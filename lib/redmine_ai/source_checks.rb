# frozen_string_literal: true
require 'digest'
require 'json'
require 'securerandom'
require 'time'

module RedmineAi
  class SourceChecks
    def self.signature
      Digest::SHA256.hexdigest(Configuration.values['sources_json'])
    end

    def self.run
      budget = {bytes: 10_000_000}
      Configuration.sources.map do |source|
        result = {'name' => source['name'], 'type' => source['type']}
        begin
          if %w[database postgres_schema].include?(source['type'])
            tables = DatabaseSources.snapshot(source)
            raise Error, 'Connected, but no table columns are visible. Check the schema/owner and metadata access.' if tables.empty?
            result.merge!('status' => 'ok', 'message' => "#{tables.size} tables; #{tables.sum { |table| table['columns'].size }} columns; #{tables.sum { |table| table['sample_rows'].size }} approved sample rows checked.")
          else
            if source['type'] == 'code_folder' && source['allow_code_changes'] == true
              code_root = CodeFiles.root(source)
              raise Error, 'Reviewed code folder is not writable by Redmine.' unless code_root.writable?
            end
            files = source['type'] == 'files' ? source['files'] : FolderInventory.discover(source)
            raise Error, 'No eligible text/code files were found.' if files.empty?
            readable = 0
            Sources.files(source.merge('files' => files), [], budget) { readable += 1 }
            raise Error, 'No readable text/code files were found.' if readable.zero?
            result.merge!('status' => 'ok', 'message' => "#{readable} text/code files checked.")
          end
        rescue Error => exception
          result.merge!('status' => 'failed', 'message' => exception.message)
        rescue StandardError, LoadError
          result.merge!('status' => 'failed', 'message' => 'Source could not be read. Check driver availability, access, schema and connection settings.')
        end
        result
      end
    end

    def self.enqueue(user)
      token = SecureRandom.uuid
      fingerprint = signature
      state = {'state' => 'queued', 'token' => token, 'signature' => fingerprint, 'results' => []}
      Setting.plugin_redmine_ai_integration = Configuration.values.merge('source_check' => state)
      AiSourceCheckJob.perform_later(token, fingerprint, user.id)
    end

    def self.finish(token, fingerprint, state)
      # Lock the settings row so a late worker cannot overwrite reconfigured sources.
      Setting.transaction do
        record = Setting.where(name: 'plugin_redmine_ai_integration').lock.first!
        settings = record.value
        check = settings['source_check'] || {}
        return unless check['token'] == token && check['signature'] == fingerprint && Digest::SHA256.hexdigest(settings['sources_json']) == fingerprint
        record.value = settings.merge('source_check' => check.merge(state).merge('checked_at' => Time.now.utc.iso8601))
        record.save!
      end
      Setting.clear_cache
    end
  end
end
