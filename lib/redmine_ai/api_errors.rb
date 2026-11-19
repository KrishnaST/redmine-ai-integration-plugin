# frozen_string_literal: true
require 'json'

module RedmineAi
  class ApiErrors
    QUOTA_MESSAGES = {
      'credit_balance_exhausted' => 'OpenAI API credits are exhausted (HTTP 429). Add or claim API credits in the key\'s API organization billing settings.',
      'insufficient_quota' => 'OpenAI API quota is unavailable (HTTP 429). Check API credit balance and billing/usage limits for the key\'s organization and project. ChatGPT billing is separate.',
      'organization_spend_limit_exceeded' => 'OpenAI organization spend limit reached (HTTP 429). Review the enforced organization spend limit in API settings.',
      'project_spend_limit_exceeded' => 'OpenAI project spend limit reached (HTTP 429). Review the enforced spend limit for the API key\'s project.',
      'organization_usage_limit_exceeded' => 'OpenAI organization usage limit reached (HTTP 429). Review the approved API usage limit and request an increase if needed.',
      'billing_hard_limit_reached' => 'OpenAI API billing limit reached (HTTP 429). Review API billing and usage limits before retrying.',
      'rate_limit_exceeded' => 'OpenAI request/token rate limit reached (HTTP 429). Wait before starting another enhancement and review the selected model\'s API rate limits.',
      'slow_down' => 'OpenAI request rate increased too quickly (HTTP 429). Wait before starting another enhancement and reduce simultaneous requests.',
      'rate_limit_error' => 'OpenAI request/token rate limit reached (HTTP 429). Wait before starting another enhancement and review the selected model\'s API rate limits.'
    }.freeze
    UNKNOWN_QUOTA = 'OpenAI rejected the request (HTTP 429). Check API credits, organization/project spend limits and the selected model\'s rate limits.'

    def self.message(status, body)
      return "OpenAI request failed (HTTP #{status.to_i}); check API access, model and billing." unless status.to_s == '429'
      parsed = JSON.parse(body)
      error = parsed.is_a?(Hash) ? parsed['error'] : nil
      return UNKNOWN_QUOTA unless error.is_a?(Hash)
      # Use only allowlisted codes and fixed text. Never expose remote messages, headers or bodies.
      [error['code'], error['type']].each do |code|
        return QUOTA_MESSAGES.fetch(code) if code.is_a?(String) && QUOTA_MESSAGES.key?(code)
      end
      UNKNOWN_QUOTA
    rescue JSON::ParserError, TypeError
      UNKNOWN_QUOTA
    end
  end
end
