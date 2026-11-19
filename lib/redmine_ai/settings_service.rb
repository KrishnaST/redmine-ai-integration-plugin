# frozen_string_literal: true
require 'json'

module RedmineAi
  class SettingsService
    def self.save(values, source_rows:, api_key:, clear_api_key:)
      current = Configuration.values
      raise Error, 'Choose a model from the dropdown; refresh available models if needed.' unless Models.options.include?(values['model'])
      sources = source_rows.nil? ? Configuration.sources : SourceConfiguration.from_form(source_rows, Configuration.sources)
      values = values.merge('sources_json' => JSON.generate(sources))
      raise Error, 'Technical source configuration exceeds 100 KB.' if values['sources_json'].bytesize > 100_000
      key = api_key.to_s.strip
      raise Error, 'Invalid API key length.' if key.bytesize > 1000
      encrypted = clear_api_key ? nil : current['api_key_encrypted']
      encrypted = Configuration.encryptor.encrypt_and_sign(key) unless key.empty?
      saved = current.merge(values).merge('api_key_encrypted' => encrypted)
      saved.delete('source_check') if values['sources_json'] != current['sources_json']
      saved.delete('available_models') if encrypted != current['api_key_encrypted']
      Setting.plugin_redmine_ai_integration = saved.except('instructions')
    end
  end
end
