# frozen_string_literal: true
require 'json'
require 'pathname'

module RedmineAi
  class Error < StandardError; end
  class Configuration
    DEFAULTS = {'enabled' => '0', 'model' => 'gpt-6.2-astra', 'instructions' => '', 'sources_json' => '[]'}.freeze

    def self.values
      DEFAULTS.merge(Setting.plugin_redmine_ai_integration || {})
    end

    def self.encryptor
      key = Rails.application.key_generator.generate_key('redmine-ai-integration/v1', 32)
      ActiveSupport::MessageEncryptor.new(key, cipher: 'aes-256-gcm', serializer: JSON)
    end

    def self.secret
      value = values['api_key_encrypted']
      value.present? ? encryptor.decrypt_and_verify(value) : ENV['REDMINE_AI_OPENAI_API_KEY']
    end

    def self.sources(raw = values['sources_json'])
      sources = JSON.parse(raw)
      raise Error, 'Sources must be an array of at most 20 objects.' unless sources.is_a?(Array) && sources.size <= 20
      names = []
      sources.each do |source|
        raise Error, 'Invalid source object.' unless source.is_a?(Hash)
        raise Error, 'Each source requires a unique name.' unless source['name'].is_a?(String) && source['name'].match?(/\A[a-zA-Z0-9_-]{1,50}\z/) && !names.include?(source['name'])
        names << source['name']
        ids = source['project_ids']
        raise Error, 'Each source requires explicit numeric project_ids.' unless ids.is_a?(Array) && !ids.empty? && ids.all? { |id| id.is_a?(Integer) && id.positive? }
        case source['type']
        when 'files'
          raise Error, 'File source requires an absolute root.' unless source['root'].is_a?(String) && Pathname.new(source['root']).absolute?
          raise Error, 'File source requires an explicit file list (max 500).' unless source['files'].is_a?(Array) && source['files'].size.between?(1, 500) && source['files'].all? { |file| file.is_a?(String) && !Pathname.new(file).absolute? && !file.split(/[\\\/]/).include?('..') }
        when 'postgres_schema'
          raise Error, 'Database URL must reference an environment variable.' unless source['url_env'].to_s.match?(/\A[A-Z][A-Z0-9_]+\z/)
          raise Error, 'Database schema must be explicit.' unless source['schema'].to_s.match?(/\A[a-zA-Z_][a-zA-Z0-9_]{0,62}\z/)
        else
          raise Error, 'Supported source types: files, postgres_schema.'
        end
      end
      sources
    rescue JSON::ParserError
      raise Error, 'Sources JSON is invalid.'
    end
  end
end
