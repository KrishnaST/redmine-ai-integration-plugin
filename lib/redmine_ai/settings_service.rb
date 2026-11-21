# frozen_string_literal: true
require 'json'

module RedmineAi
  class SettingsService
    def self.save(values, source_rows:, api_key:, clear_api_key:)
      current = Configuration.values
      raise Error, 'Choose a model from the dropdown; refresh available models if needed.' unless Models.options.include?(values['model'])
      Configuration.reasoning_effort(values.fetch('reasoning_effort', current['reasoning_effort']))
      if values.key?('code_role_ids')
        ids = Array(values['code_role_ids']).reject(&:blank?).map { |id| Integer(id.to_s, 10) }.uniq
        raise Error, 'Choose existing member roles for Code with AI.' unless (ids - Role.where(builtin: 0).pluck(:id)).empty?
        values = values.merge('code_role_ids' => ids)
      end
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
    rescue ArgumentError, TypeError
      raise Error, 'Invalid Code with AI role selection.'
    end
  end
end
