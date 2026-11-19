# frozen_string_literal: true
require_relative 'test_plugin'

class ApiErrorsTest < Minitest::Test
  def test_known_429_codes_have_specific_safe_messages
    expected = {'credit_balance_exhausted' => 'credits are exhausted', 'insufficient_quota' => 'quota is unavailable',
                'organization_spend_limit_exceeded' => 'organization spend limit', 'project_spend_limit_exceeded' => 'project spend limit',
                'organization_usage_limit_exceeded' => 'organization usage limit', 'billing_hard_limit_reached' => 'billing limit',
                'rate_limit_exceeded' => 'request/token rate limit', 'slow_down' => 'increased too quickly', 'rate_limit_error' => 'request/token rate limit'}
    expected.each do |code, description|
      message = RedmineAi::ApiErrors.message('429', JSON.generate(error: {code: code, type: 'other', message: 'synthetic-secret'}))
      assert_includes message, description
      assert_includes message, 'HTTP 429'
      refute_includes message, 'synthetic-secret'
    end
  end

  def test_quota_type_fallback_and_code_precedence
    message = RedmineAi::ApiErrors.message('429', JSON.generate(error: {code: nil, type: 'insufficient_quota'}))
    assert_includes message, 'quota is unavailable'
    message = RedmineAi::ApiErrors.message('429', JSON.generate(error: {code: 'project_spend_limit_exceeded', type: 'insufficient_quota'}))
    assert_includes message, 'project spend limit'
  end

  def test_unclassified_or_malformed_responses_do_not_expose_remote_content
    ['not-json synthetic-secret', '[]', 'null', '{"error":[]}',
     JSON.generate(error: {code: ['synthetic-secret'], type: 'synthetic-secret', message: 'synthetic-secret'})].each do |body|
      assert_equal RedmineAi::ApiErrors::UNKNOWN_QUOTA, RedmineAi::ApiErrors.message('429', body)
    end
    refute_includes RedmineAi::ApiErrors.message('401', '{"error":"synthetic-secret"}'), 'synthetic-secret'
    assert_includes RedmineAi::ApiErrors.message('401', '{}'), 'HTTP 401'
  end
end
