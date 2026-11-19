# frozen_string_literal: true
require_relative 'test_plugin'

class TechnicalSourcesTest < Minitest::Test
  def setup
    Setting.plugin_redmine_ai_integration = {'enabled' => '0', 'model' => 'gpt-6.2-astra', 'sources_json' => '[]'}
  end

  def row
    {'name' => 'schema', 'type' => 'database', 'project_ids' => ['1'], 'db_type' => 'postgresql',
     'host' => '127.0.0.1', 'port' => '5432', 'database' => 'example', 'schema' => 'public',
     'username' => 'example', 'password' => 'synthetic-password'}
  end

  def test_database_password_is_encrypted_and_never_saved_in_plaintext
    sources = RedmineAi::SourceConfiguration.from_form([row], [])
    refute_includes JSON.generate(sources), 'synthetic-password'
    assert_equal 'synthetic-password', RedmineAi::SourceConfiguration.password(sources.first)
    refute sources.first['include_table_data']
  end

  def test_blank_password_retention_clear_and_changed_target
    source = RedmineAi::SourceConfiguration.from_form([row], []).first
    update = row.merge('id' => source['id'], 'password' => '')
    kept = RedmineAi::SourceConfiguration.from_form([update], [source]).first
    assert_equal source['password_encrypted'], kept['password_encrypted']
    changed = RedmineAi::SourceConfiguration.from_form([update.merge('host' => '127.0.0.2')], [source]).first
    refute changed.key?('password_encrypted')
    cleared = RedmineAi::SourceConfiguration.from_form([update.merge('clear_password' => '1')], [source]).first
    refute cleared.key?('password_encrypted')
  end

  def test_sample_configuration_requires_explicit_tables_columns_and_bounds
    sample = row.merge('include_table_data' => '1', 'sample_tables' => [{'table' => 'reference_codes', 'columns' => 'code, description', 'limit' => '5'}])
    source = RedmineAi::SourceConfiguration.from_form([sample], []).first
    assert source['include_table_data']
    assert_equal %w[code description], source['sample_tables'].first['columns']
    sample['sample_tables'][0]['limit'] = '999'
    assert_raises(RedmineAi::Error) { RedmineAi::SourceConfiguration.from_form([sample], []) }
    sample['sample_tables'][0].merge!('limit' => '5', 'table' => 'reference_codes;DROP')
    assert_raises(RedmineAi::Error) { RedmineAi::SourceConfiguration.from_form([sample], []) }
    sample['sample_tables'] = []
    assert_raises(RedmineAi::Error) { RedmineAi::SourceConfiguration.from_form([sample], []) }
  end

  def test_all_four_engine_forms_and_invalid_parameters
    %w[postgresql oracle sqlserver mysql].each do |engine|
      assert_equal engine, RedmineAi::SourceConfiguration.from_form([row.merge('db_type' => engine)], []).first['db_type']
    end
    %w[0 65536 bogus].each { |port| assert_raises(RedmineAi::Error) { RedmineAi::SourceConfiguration.from_form([row.merge('port' => port)], []) } }
    assert_raises(RedmineAi::Error) { RedmineAi::SourceConfiguration.from_form([row.merge('project_ids' => [])], []) }
    assert_raises(RedmineAi::Error) { RedmineAi::SourceConfiguration.from_form([row.merge('host' => 'host)(injected')], []) }
  end

  def test_removed_administrator_instructions_are_ignored
    Setting.plugin_redmine_ai_integration['instructions'] = 'obsolete guidance'
    refute RedmineAi::Configuration.values.key?('instructions')
  end

  def test_recursive_folder_inventory_excludes_generated_and_sensitive_files
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, 'src'))
      FileUtils.mkdir_p(File.join(root, 'target'))
      File.write(File.join(root, 'src', 'Payment.java'), 'Payment transfer confirmation')
      File.write(File.join(root, 'target', 'Generated.java'), 'Payment generated')
      File.write(File.join(root, 'credentials.txt'), 'Payment synthetic-secret')
      File.write(File.join(root, 'application.yml'), 'Payment synthetic-connection-password')
      File.write(File.join(root, 'image.png'), 'binary')
      source = {'name' => 'code', 'type' => 'code_folder', 'root' => root, 'project_ids' => [1]}
      assert_equal [File.join('src', 'Payment.java')], RedmineAi::FolderInventory.discover(source)
      Setting.plugin_redmine_ai_integration['sources_json'] = JSON.generate([source])
      snippets, warnings = RedmineAi::Sources.collect(1, 'Payment transfer')
      assert_empty warnings
      assert_equal 1, snippets.size
      refute_includes snippets.to_s, 'synthetic-secret'
      assert_equal 'ok', RedmineAi::SourceChecks.run.first['status']
    end
  end

  def test_source_check_does_not_expose_driver_exception_or_contents
    source = RedmineAi::SourceConfiguration.from_form([row], []).first
    Setting.plugin_redmine_ai_integration['sources_json'] = JSON.generate([source])
    RedmineAi::DatabaseSources.stub(:snapshot, ->(*) { raise IOError, 'synthetic-sensitive-error' }) do
      result = RedmineAi::SourceChecks.run
      assert_equal 'failed', result.first['status']
      refute_includes result.to_s, 'synthetic-sensitive-error'
      refute_includes result.to_s, 'synthetic-password'
    end
  end

  def test_binary_only_document_folder_is_not_reported_healthy
    Dir.mktmpdir do |root|
      File.binwrite(File.join(root, 'not-text.txt'), "binary\x00content")
      Setting.plugin_redmine_ai_integration['sources_json'] = JSON.generate([{'name' => 'docs', 'type' => 'documents_folder', 'root' => root, 'project_ids' => [1]}])
      assert_equal 'failed', RedmineAi::SourceChecks.run.first['status']
    end
  end

  def test_empty_or_invisible_database_schema_requires_attention
    source = RedmineAi::SourceConfiguration.from_form([row], []).first
    Setting.plugin_redmine_ai_integration['sources_json'] = JSON.generate([source])
    RedmineAi::DatabaseSources.stub(:snapshot, []) do
      result = RedmineAi::SourceChecks.run.first
      assert_equal 'failed', result['status']
      assert_includes result['message'], 'no table columns'
    end
  end

  class FakeAdapter
    attr_reader :samples, :closed
    def initialize
      @samples = []
    end
    def columns(*)
      [{'table_name' => 'reference_codes', 'column_name' => 'code', 'data_type' => 'text'}]
    end
    def constraints(*)
      [{'table_name' => 'reference_codes', 'name' => 'codes_pk', 'kind' => 'PRIMARY KEY'}]
    end
    def sample(*arguments)
      @samples << arguments
      [{'code' => 'A' * 1000}]
    end
    def close
      @closed = true
    end
  end

  def test_samples_are_opt_in_and_verified_against_current_metadata
    source = RedmineAi::SourceConfiguration.from_form([row], []).first
    adapter = FakeAdapter.new
    RedmineAi::DatabaseAdapters.stub(:open, adapter) do
      snapshot = RedmineAi::DatabaseSources.snapshot(source)
      assert_empty snapshot.first['sample_rows']
      assert_empty adapter.samples
      assert adapter.closed
    end
    source.merge!('include_table_data' => true, 'sample_tables' => [{'table' => 'reference_codes', 'columns' => ['code'], 'limit' => 5}])
    adapter = FakeAdapter.new
    RedmineAi::DatabaseAdapters.stub(:open, adapter) do
      snapshot = RedmineAi::DatabaseSources.snapshot(source)
      assert_equal 500, snapshot.first['sample_rows'].first['code'].size
      assert_equal [['public', 'reference_codes', ['code'], 5]], adapter.samples
    end
    source['sample_tables'].first['columns'] = ['missing_column']
    adapter = FakeAdapter.new
    RedmineAi::DatabaseAdapters.stub(:open, adapter) do
      assert_raises(RedmineAi::Error) { RedmineAi::DatabaseSources.snapshot(source) }
      assert_empty adapter.samples
      assert adapter.closed
    end
  end

  def test_legacy_file_source_can_be_edited_without_losing_its_definition
    previous = {'name' => 'docs', 'type' => 'files', 'project_ids' => [1], 'root' => Dir.tmpdir, 'files' => ['guide.txt']}
    updated = RedmineAi::SourceConfiguration.from_form([{'id' => RedmineAi::SourceConfiguration.id(previous), 'name' => 'docs_updated', 'type' => 'files', 'project_ids' => ['1']}], [previous]).first
    assert_equal ['guide.txt'], updated['files']
    assert_equal 'docs_updated', updated['name']
  end

  def test_model_dropdown_and_refresh_filters_non_text_models
    assert_includes RedmineAi::Models.options, 'gpt-6.2-sol'
    response = PluginTest::FakeReply.new(JSON.generate('data' => [{'id' => 'gpt-6.2-sol'}, {'id' => 'gpt-image-2'}, {'id' => 'gpt-realtime'}, {'id' => 'gpt-6.2-sol'}]))
    transport = Object.new
    transport.define_singleton_method(:request) do |request, &block|
      raise 'Wrong metadata request' unless request.is_a?(Net::HTTP::Get) && request['Authorization'] == 'Bearer synthetic-key'
      block.call(response)
    end
    Setting.plugin_redmine_ai_integration['api_key_encrypted'] = RedmineAi::Configuration.encryptor.encrypt_and_sign('synthetic-key')
    Net::HTTP.stub(:start, ->(*_arguments, **_options, &block) { block.call(transport) }) do
      assert_equal ['gpt-6.2-sol'], RedmineAi::Models.refresh
    end
    assert_includes RedmineAi::Models.options, 'gpt-6.2-sol'
    refute_includes RedmineAi::Models.options, 'gpt-image-2'
  end

  def test_source_job_checks_current_admin_and_handles_no_sources
    user = User.create!
    fingerprint = RedmineAi::SourceChecks.signature
    calls = []
    RedmineAi::SourceChecks.stub(:finish, ->(*arguments) { calls << arguments }) do
      AiSourceCheckJob.perform_now('test-token', fingerprint, user.id)
      assert_equal 'completed', calls.last[2]['state']
      user.update!(permitted: false)
      AiSourceCheckJob.perform_now('test-token', fingerprint, user.id)
      assert_equal 'failed', calls.last[2]['state']
    end
  end

  def test_late_source_check_cannot_overwrite_new_configuration
    fingerprint = RedmineAi::SourceChecks.signature
    Setting.plugin_redmine_ai_integration['source_check'] = {'token' => 'current', 'signature' => fingerprint, 'state' => 'queued'}
    RedmineAi::SourceChecks.finish('older', fingerprint, {'state' => 'completed'})
    assert_equal 'queued', Setting.plugin_redmine_ai_integration['source_check']['state']
    RedmineAi::SourceChecks.finish('current', fingerprint, {'state' => 'completed'})
    assert_equal 'completed', Setting.plugin_redmine_ai_integration['source_check']['state']
    Setting.plugin_redmine_ai_integration['sources_json'] = '[ ]'
    RedmineAi::SourceChecks.finish('current', fingerprint, {'state' => 'failed'})
    assert_equal 'completed', Setting.plugin_redmine_ai_integration['source_check']['state']
  end
end
