# frozen_string_literal: true
require 'json'
require 'net/http'
require 'uri'

module RedmineAi
  class Models
    DEFAULTS = %w[gpt-6.2-astra gpt-6.2-sol gpt-6.1-terra gpt-6-luna].freeze
    ENDPOINT = URI('https://api.openai.com/v1/models')

    def self.options
      values = Configuration.values
      cached = Array(values['available_models'])
      ((cached.empty? ? DEFAULTS : cached) + [values['model']]).compact.uniq.sort
    end

    def self.refresh
      key = Configuration.secret
      raise Error, 'Save an OpenAI API key before refreshing models.' if key.to_s.empty?
      request = Net::HTTP::Get.new(ENDPOINT)
      request['Authorization'] = "Bearer #{key}"
      body = +''
      Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true, open_timeout: 10, read_timeout: 15) do |http|
        http.request(request) do |response|
          response.read_body do |chunk|
            raise Error, 'Model list exceeds the response limit.' if body.bytesize + chunk.bytesize > 1_000_000
            body << chunk
          end
          raise Error, "Model refresh failed (HTTP #{response.code}). Check the API key and its model-list permission." unless response.is_a?(Net::HTTPSuccess)
        end
      end
      ids = JSON.parse(body).fetch('data').filter_map do |model|
        id = model['id']
        next unless id.is_a?(String) && id.match?(/\A(?:gpt-[0-9]|o[3-9])[-a-zA-Z0-9_.]*\z/)
        next if id.match?(/audio|realtime|transcri|image|search|codex|instruct/i)
        id
      end.uniq.sort.first(200)
      raise Error, 'No text models were returned for this key.' if ids.empty?
      Setting.plugin_redmine_ai_integration = Configuration.values.merge('available_models' => ids)
      ids
    rescue JSON::ParserError, KeyError, TypeError
      raise Error, 'OpenAI returned an invalid model list.'
    end
  end
end
