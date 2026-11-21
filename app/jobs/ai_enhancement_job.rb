# frozen_string_literal: true
require_relative '../../lib/redmine_ai/code_draft'

class AiEnhancementJob < ActiveJob::Base
  queue_as :default

  def perform(id)
    enhancement = AiEnhancement.find(id)
    user = enhancement.user
    previous_user = User.current
    User.current = user
    claimed = false
    enhancement.with_lock do
      return unless enhancement.state == 'queued'
      enhancement.update!(state: 'processing')
      claimed = true
    end
    raise RedmineAi::Error, 'AI enhancement is disabled.' unless RedmineAi::Configuration.values['enabled'] == '1'
    raise RedmineAi::Error, 'Permission to enhance this ticket was revoked.' unless RedmineAi::Policy.allowed?(enhancement.issue, user)
    raise RedmineAi::Error, 'Permission to use Code with AI was revoked.' if enhancement.mode == 'code' && !RedmineAi::Policy.code_allowed?(enhancement.issue, user)
    document = enhancement.data
    fields = RedmineAi::Policy.text_fields(enhancement.issue, user)
    raise RedmineAi::Error, 'No editable text fields.' if fields.empty?
    query = (fields.values + document['messages'].map { |message| message['text'] }).join(' ')[0, 40_000]
    sources, warnings = RedmineAi::Sources.collect(enhancement.issue.project_id, query)
    if enhancement.mode == 'code'
      files = RedmineAi::CodeFiles.collect(enhancement.issue.project_id, query)
      result = RedmineAi::CodeDraft.generate(fields: fields, evidence: sources, messages: document['messages'], files: files)
      document.merge!('code_result' => result, 'code_files' => files)
    else
      result = RedmineAi::Client.generate(fields: fields, evidence: sources, messages: document['messages'], mode: enhancement.mode)
      document['result'] = result
    end
    document.merge!('sources' => sources.map { |source| source.except('content') }, 'warnings' => warnings)
    enhancement.with_lock do
      enhancement.data = document
      enhancement.state = 'draft'
      enhancement.save!
    end
    enhancement.apply_draft! if enhancement.mode == 'automatic'
  rescue StandardError => exception
    if enhancement && claimed
      # Never log remote response, ticket text, file contents or database exception messages.
      Rails.logger.warn("RedmineAI enhancement=#{id} error=#{exception.class.name}")
      enhancement.reload
      document = enhancement.data
      document['error'] = exception.is_a?(RedmineAi::Error) ? exception.message : 'Enhancement failed. Check source availability and server diagnostics, then start a new enhancement.'
      enhancement.data = document
      enhancement.state = exception.is_a?(RedmineAi::Error) && exception.message.start_with?('Ticket changed') ? 'conflict' : 'failed'
      enhancement.save!
    end
  ensure
    User.current = previous_user
  end
end
