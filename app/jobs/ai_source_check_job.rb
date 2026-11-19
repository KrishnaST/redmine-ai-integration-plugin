# frozen_string_literal: true
class AiSourceCheckJob < ActiveJob::Base
  queue_as :default
  self.log_arguments = false

  def perform(token, fingerprint, user_id)
    user = User.find(user_id)
    raise RedmineAi::Error, 'Source test requires an active administrator.' unless user.active? && user.admin?
    return unless RedmineAi::SourceChecks.signature == fingerprint
    results = RedmineAi::SourceChecks.run
    state = results.any? { |result| result['status'] != 'ok' } ? 'needs_attention' : 'completed'
    RedmineAi::SourceChecks.finish(token, fingerprint, {'state' => state, 'results' => results})
  rescue StandardError
    RedmineAi::SourceChecks.finish(token, fingerprint, {'state' => 'failed', 'results' => [], 'error' => 'Source testing failed. Check the job backend and administrator access.'})
  end
end
