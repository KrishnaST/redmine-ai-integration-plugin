# frozen_string_literal: true
require 'json'
require_relative 'source_configuration'

module RedmineAi
  class Error < StandardError; end
  class Configuration
    DEFAULTS = {'enabled' => '0', 'model' => 'gpt-6.2-astra', 'reasoning_effort' => '', 'sources_json' => '[]'}.freeze
    REASONING_EFFORT_OPTIONS = [['Model default', ''], ['Light', 'low'], ['Medium', 'medium'],
                              ['High', 'high'], ['Extra High', 'xhigh'], ['Ultra', 'max']].map(&:freeze).freeze

    def self.values
      DEFAULTS.merge(Setting.plugin_redmine_ai_integration || {}).except('instructions')
    end

    def self.reasoning_effort(value = values['reasoning_effort'])
      raise Error, 'Choose a reasoning effort from the dropdown.' unless REASONING_EFFORT_OPTIONS.any? { |option| option.last == value }
      value.empty? ? nil : value
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
      SourceConfiguration.parse(raw)
    end
  end
end
