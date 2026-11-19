# frozen_string_literal: true
gem 'minitest', '~> 5.0'
# Avoid loading incompatible plugins from other globally installed Minitest versions.
ENV['MT_NO_PLUGINS'] = '1'
require 'minitest/autorun'
require 'minitest/mock'
require 'active_record'
require 'active_job'
require 'active_support/message_encryptor'
require 'active_support/key_generator'
require 'tmpdir'
require 'fileutils'
require 'logger'
require_relative '../lib/redmine_ai/configuration'
require_relative '../lib/redmine_ai/policy'
require_relative '../lib/redmine_ai/sources'
require_relative '../lib/redmine_ai/client'
require_relative '../lib/redmine_ai/models'
require_relative '../lib/redmine_ai/source_checks'
require_relative '../lib/redmine_ai/settings_service'

# Real Rails persistence/job machinery with small doubles for Redmine-specific interfaces.
module Rails
  def self.application
    @application ||= Struct.new(:key_generator).new(ActiveSupport::KeyGenerator.new('test-only-key'))
  end
  def self.logger
    @logger ||= Logger.new(File::NULL)
  end
end
class Setting
  class << self
    attr_accessor :plugin_redmine_ai_integration
    def transaction; yield; end
    def where(*); self; end
    def lock; self; end
    def first!; new; end
    def clear_cache; end
  end
  def value; self.class.plugin_redmine_ai_integration; end
  def value=(value); @value = value; end
  def save!; self.class.plugin_redmine_ai_integration = @value; end
end
class Project
  def self.order(*)
    self
  end

  def self.pluck(*)
    [['Test project', 1]]
  end
end
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Schema.define do
  create_table(:users) { |table| table.boolean :active, default: true; table.boolean :permitted, default: true }
  create_table(:issues) do |table|
    table.string :subject
    table.text :description
    table.integer :project_id, default: 1
    table.timestamps
  end
end
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
class User < ApplicationRecord
  class << self
    attr_accessor :current
  end
  def allowed_to?(*); permitted; end
  def admin?; permitted; end
end
class Issue < ApplicationRecord
  attr_reader :journal
  def project; project_id; end
  def visible?(*); true; end
  def editable?(*); true; end
  def safe_attribute_names(*); %w[subject description custom_field_values]; end
  def editable_custom_field_values(*); []; end
  def custom_field_values; []; end
  def init_journal(user, notes); @journal = [user.id, notes]; end
  def safe_attributes=(attributes, _user = nil); assign_attributes(attributes); end
end
require_relative '../db/migrate/001_create_ai_enhancements'
CreateAiEnhancements.new.migrate(:up)
require_relative '../app/models/ai_enhancement'
require_relative '../app/jobs/ai_enhancement_job'
require_relative '../app/jobs/ai_source_check_job'
ActiveJob::Base.logger = Logger.new(File::NULL)

class PluginTest < Minitest::Test
  def setup
    AiEnhancement.delete_all
    Issue.delete_all
    User.delete_all
    @user = User.create!
    User.current = @user
    @issue = Issue.create!(subject: 'payment error', description: 'Transfer fails after confirmation')
    Setting.plugin_redmine_ai_integration = {'enabled' => '1', 'model' => 'test-model', 'sources_json' => '[]'}
  end

  def result
    {'fields' => [{'name' => 'subject', 'value' => 'Transfer fails after confirmation'},
                  {'name' => 'description', 'value' => 'Actual behaviour: transfer fails after confirmation.'}],
     'questions' => [], 'source_ids' => []}
  end

  def enhancement(mode = 'interactive')
    record = AiEnhancement.new(issue: @issue, user: @user, mode: mode, state: 'draft', baseline: RedmineAi::Policy.fingerprint(@issue))
    record.data = {'messages' => [], 'sources' => [], 'warnings' => [], 'result' => result}
    record.save!
    record
  end

  def test_payload_encryption_and_key_roundtrip
    record = enhancement
    refute_includes record.payload, 'Actual behaviour'
    assert_equal result, record.reload.data['result']
    encrypted = RedmineAi::Configuration.encryptor.encrypt_and_sign('test-key')
    Setting.plugin_redmine_ai_integration['api_key_encrypted'] = encrypted
    assert_equal 'test-key', RedmineAi::Configuration.secret
  end

  def test_apply_and_duplicate_apply
    record = enhancement
    record.apply_draft!
    assert_equal result['fields'][0]['value'], @issue.reload.subject
    assert_equal 'applied', record.reload.state
    assert_raises(RedmineAi::Error) { record.apply_draft! }
  end

  def test_conflicting_edits_are_preserved
    record = enhancement
    @issue.update!(description: 'New facts supplied by another engineer')
    assert_raises(RedmineAi::Error) { record.apply_draft! }
    assert_equal 'New facts supplied by another engineer', @issue.reload.description
    assert_equal 'draft', record.reload.state
  end

  def test_revoked_permission_blocks_save
    record = enhancement
    @user.update!(permitted: false)
    assert_raises(RedmineAi::Error) { record.reload.apply_draft! }
    assert_equal 'payment error', @issue.reload.subject
  end

  def test_output_rejects_missing_duplicate_or_unknown_fields_and_citations
    fields = RedmineAi::Policy.text_fields(@issue, @user)
    invalid = result
    invalid['fields'][0]['name'] = 'status_id'
    assert_raises(RedmineAi::Error) { RedmineAi::Policy.validate!(invalid, fields, []) }
    invalid = result
    invalid['fields'] << invalid['fields'][0]
    assert_raises(RedmineAi::Error) { RedmineAi::Policy.validate!(invalid, fields, []) }
    invalid = result
    invalid['source_ids'] = ['S999']
    assert_raises(RedmineAi::Error) { RedmineAi::Policy.validate!(invalid, fields, []) }
    invalid = result
    invalid['fields'][0]['value'] = 'x' * 256
    assert_raises(RedmineAi::Error) { RedmineAi::Policy.validate!(invalid, fields, []) }
  end

  def test_source_configuration_rejects_unsafe_or_unscoped_sources
    assert_raises(RedmineAi::Error) { RedmineAi::Configuration.sources('{}') }
    assert_raises(RedmineAi::Error) { RedmineAi::Configuration.sources('[{"name":"docs","type":"files","root":"/tmp","files":["../secret"],"project_ids":[1]}]') }
    assert_raises(RedmineAi::Error) { RedmineAi::Configuration.sources('[{"name":"db","type":"postgres_schema","schema":"public","url_env":"postgres://secret","project_ids":[1]}]') }
    assert_raises(RedmineAi::Error) { RedmineAi::Configuration.sources('[{"name":"db","type":"postgres_schema","schema":"public","url_env":"DB_URL","project_ids":[]}]') }
  end

  def test_file_retrieval_scoping_selection_and_secrets_exclusion
    Dir.mktmpdir do |root|
      File.write(File.join(root, 'payments.md'), 'Transfer confirmation requires a unique transaction reference.')
      File.write(File.join(root, 'passwords.txt'), 'Transfer secret-value')
      File.write(File.join(root, 'unrelated.md'), 'Weather forecast')
      Setting.plugin_redmine_ai_integration['sources_json'] = JSON.generate([{name: 'docs', type: 'files', root: root,
        project_ids: [1], files: %w[payments.md passwords.txt unrelated.md], revision: 'abc123'}])
      sources, warnings = RedmineAi::Sources.collect(1, 'Transfer confirmation')
      assert_empty warnings
      assert_equal 1, sources.size
      assert_equal 'S1', sources[0]['id']
      assert_includes sources[0]['reference'], 'payments.md:1'
      assert_equal 'abc123', sources[0]['revision']
      assert_empty RedmineAi::Sources.collect(2, 'Transfer')[0]
      refute_includes sources.to_s, 'secret-value'
    end
  end

  class FakeReply < Net::HTTPOK
    def initialize(body)
      super('1.1', '200', 'OK')
      @test_body = body
    end
    def read_body
      yield @test_body
    end
  end

  def with_api(body)
    reply = FakeReply.new(JSON.generate(body))
    transport = Object.new
    transport.define_singleton_method(:request) do |request, &block|
      raise 'Missing authentication' unless request['Authorization'] == 'Bearer test-key'
      payload = JSON.parse(request.body)
      raise 'Response storage enabled' unless payload['store'] == false
      raise 'No strict schema' unless payload.dig('text', 'format', 'strict')
      block.call(reply)
      reply # Net::HTTP returns the response, not the block value.
    end
    Setting.plugin_redmine_ai_integration['api_key_encrypted'] = RedmineAi::Configuration.encryptor.encrypt_and_sign('test-key')
    Net::HTTP.stub(:start, ->(*_args, **_kwargs, &block) { block.call(transport) }) { yield }
  end

  def test_actual_http_response_contract_and_structured_output
    body = {'status' => 'completed', 'output' => [{'content' => [{'type' => 'output_text', 'text' => JSON.generate(result)}]}]}
    with_api(body) do
      response = RedmineAi::Client.generate(fields: RedmineAi::Policy.text_fields(@issue, @user), evidence: [], messages: [], mode: 'automatic')
      assert_equal result, response
    end
  end

  def test_incomplete_api_response_does_not_apply
    with_api({'status' => 'incomplete', 'output' => []}) do
      assert_raises(RedmineAi::Error) do
        RedmineAi::Client.generate(fields: RedmineAi::Policy.text_fields(@issue, @user), evidence: [], messages: [], mode: 'automatic')
      end
    end
  end

  def test_unknown_inline_citations_are_rejected
    draft = result
    draft['fields'][1]['value'] += ' See [S99].'
    assert_raises(RedmineAi::Error) do
      RedmineAi::Policy.validate!(draft, RedmineAi::Policy.text_fields(@issue, @user), [])
    end
  end

  def test_database_metadata_uses_read_only_transaction_and_always_disconnects
    queries = []
    closed = false
    connection = Object.new
    connection.define_singleton_method(:exec) { |sql| queries << sql }
    connection.define_singleton_method(:close) { closed = true }
    connection.define_singleton_method(:exec_params) do |sql, values|
      queries << sql
      raise 'Unexpected schema binding' unless values == ['payments']
      if sql.include?('information_schema.columns')
        Object.new.tap do |result|
          result.define_singleton_method(:ntuples) { 1 }
          result.define_singleton_method(:to_a) { [{'table_name' => 'transfer', 'column_name' => 'id', 'data_type' => 'bigint'}] }
        end
      else
        []
      end
    end
    pg = Object.new
    pg.define_singleton_method(:connect) { |*_args, **_kwargs| connection }
    Object.const_set(:PG, pg)
    $LOADED_FEATURES << 'pg.rb'
    ENV['REDMINE_AI_TEST_DB'] = 'test-only-url'
    rows = RedmineAi::Sources.database({'url_env' => 'REDMINE_AI_TEST_DB', 'schema' => 'payments', 'name' => 'db'}, ['transfer'])
    assert_equal 'BEGIN READ ONLY', queries.first
    assert_equal 'ROLLBACK', queries.last
    assert queries.any? { |sql| sql.include?('statement_timeout') }
    assert closed
    assert_equal 1, rows.size
    assert_includes rows.first[:reference], 'payments.transfer'
    closed = false
    connection.define_singleton_method(:exec_params) { |*_args| raise IOError, 'sensitive DB failure' }
    assert_raises(IOError) do
      RedmineAi::Sources.database({'url_env' => 'REDMINE_AI_TEST_DB', 'schema' => 'payments', 'name' => 'db'}, ['transfer'])
    end
    assert closed
    assert_equal 'ROLLBACK', queries.last
  ensure
    ENV.delete('REDMINE_AI_TEST_DB')
    $LOADED_FEATURES.delete('pg.rb')
    Object.send(:remove_const, :PG) if Object.const_defined?(:PG)
  end

  def test_automatic_job_applies_and_interactive_job_only_drafts
    record = enhancement('automatic')
    record.update!(state: 'queued')
    RedmineAi::Client.stub(:generate, result) { AiEnhancementJob.perform_now(record.id) }
    assert_equal 'applied', record.reload.state
    assert_equal result['fields'][0]['value'], @issue.reload.subject
    @issue.update!(subject: 'original subject')
    interactive = enhancement
    interactive.update!(state: 'queued')
    RedmineAi::Client.stub(:generate, result) { AiEnhancementJob.perform_now(interactive.id) }
    assert_equal 'draft', interactive.reload.state
    assert_equal 'original subject', @issue.reload.subject
  end

  def test_job_rechecks_permissions_and_does_not_repeat_applied_work
    record = enhancement('automatic')
    record.update!(state: 'queued')
    @user.update!(permitted: false)
    AiEnhancementJob.perform_now(record.id)
    assert_equal 'failed', record.reload.state
    assert_equal 'payment error', @issue.reload.subject
    @user.update!(permitted: true)
    record.update!(state: 'applied')
    RedmineAi::Client.stub(:generate, ->(**) { raise 'Must not call OpenAI' }) { AiEnhancementJob.perform_now(record.id) }
    assert_equal 'applied', record.reload.state
  end
end
