# frozen_string_literal: true
require 'json'
require 'timeout'

class RedmineAiDeploymentProbeJob < ActiveJob::Base
  queue_as :default

  def self.completed
    @completed ||= Queue.new
  end

  def perform
    self.class.completed << true
  end
end

# Execute with Rails runner. All database diagnostics are explicitly read-only.
information = {
  ruby: RUBY_VERSION,
  rails: Rails.version,
  redmine: Redmine::VERSION.to_s,
  job_adapter: ActiveJob::Base.queue_adapter.class.name,
  plugins: Redmine::Plugin.all.map { |plugin| {id: plugin.id, version: plugin.version} }
}
ActiveRecord::Base.transaction(requires_new: true) do
  connection = ActiveRecord::Base.connection
  connection.execute('SET TRANSACTION READ ONLY')
  information[:database_adapter] = connection.adapter_name
  information[:database_version] = connection.select_value("SELECT current_setting('server_version')")
  information[:database_size_bytes] = connection.select_value('SELECT pg_database_size(current_database())').to_i
  information[:ai_table_exists] = connection.data_source_exists?('ai_enhancements')
  if defined?(RedmineAi::Configuration)
    information[:ai_enabled] = RedmineAi::Configuration.values['enabled'] == '1'
    information[:ai_key_configured] = !RedmineAi::Configuration.secret.to_s.empty?
    information[:ai_sources_count] = RedmineAi::Configuration.sources.size
    information[:ai_columns] = connection.columns('ai_enhancements').map { |column| {name: column.name, type: column.sql_type, null: column.null} }
    information[:ai_foreign_keys] = connection.foreign_keys('ai_enhancements').map { |key| {column: key.column, target_table: key.to_table} }
    information[:ai_session_count] = AiEnhancement.count
    encryptor = RedmineAi::Configuration.encryptor
    information[:encryption_roundtrip] = encryptor.decrypt_and_verify(encryptor.encrypt_and_sign({'probe' => true})) == {'probe' => true}
    information[:plugin_job_queue] = AiEnhancementJob.queue_name
    information[:issue_controller_loads] = AiEnhancementsController < ApplicationController
    information[:settings_controller_loads] = AiSettingsController < ApplicationController
  end
end
if ActiveJob::Base.queue_adapter.is_a?(ActiveJob::QueueAdapters::AsyncAdapter)
  RedmineAiDeploymentProbeJob.perform_later
  information[:default_queue_probe] = Timeout.timeout(10) { RedmineAiDeploymentProbeJob.completed.pop }
end
puts JSON.generate(information)
