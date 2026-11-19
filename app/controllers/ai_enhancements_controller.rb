# frozen_string_literal: true
class AiEnhancementsController < ApplicationController
  before_action :require_login
  before_action :find_ai_issue
  before_action :authorize_ai
  before_action :find_enhancement, except: :create

  def create
    mode = params[:mode].to_s
    raise RedmineAi::Error, 'Invalid mode.' unless %w[automatic interactive].include?(mode)
    enhancement = nil
    @issue.with_lock do
      pending = AiEnhancement.where(issue_id: @issue.id, state: %w[queued processing]).where('created_at > ?', 10.minutes.ago).exists?
      raise RedmineAi::Error, 'An enhancement is already running for this ticket.' if pending
      raise RedmineAi::Error, 'No editable text fields.' if RedmineAi::Policy.text_fields(@issue, User.current).empty?
      enhancement = AiEnhancement.new(issue: @issue, user: User.current, mode: mode,
        baseline: RedmineAi::Policy.fingerprint(@issue), state: 'queued')
      enhancement.data = {'messages' => [], 'sources' => [], 'warnings' => []}
      enhancement.save!
    end
    enqueue(enhancement)
    redirect_to issue_ai_enhancement_path(@issue, enhancement)
  rescue RedmineAi::Error => exception
    flash[:error] = exception.message
    redirect_to issue_path(@issue)
  end

  def show
    @document = @enhancement.data
    @fields = RedmineAi::Policy.text_fields(@issue, User.current)
  end

  def reply
    @enhancement.with_lock do
      raise RedmineAi::Error, 'This interaction is not ready for another reply.' unless @enhancement.mode == 'interactive' && @enhancement.state == 'draft'
      text = params[:reply].to_s.strip
      raise RedmineAi::Error, 'Enter up to 8,000 characters.' unless text.length.between?(1, 8000)
      document = @enhancement.data
      raise RedmineAi::Error, 'Conversation limit reached. Apply the draft or start again.' if document['messages'].size >= 20
      document['messages'] << {'role' => 'assistant', 'text' => JSON.generate(document['result'])}
      document['messages'] << {'role' => 'user', 'text' => text}
      @enhancement.data = document
      @enhancement.state = 'queued'
      @enhancement.save!
    end
    enqueue(@enhancement)
    redirect_to issue_ai_enhancement_path(@issue, @enhancement)
  rescue RedmineAi::Error => exception
    flash[:error] = exception.message
    redirect_to issue_ai_enhancement_path(@issue, @enhancement)
  end

  def apply
    raise RedmineAi::Error, 'Automatic enhancement applies through its job.' unless @enhancement.mode == 'interactive'
    @enhancement.apply_draft!
    flash[:notice] = 'AI enhancement applied.'
    redirect_to issue_path(@issue)
  rescue RedmineAi::Error, ActiveRecord::RecordInvalid => exception
    flash[:error] = exception.is_a?(RedmineAi::Error) ? exception.message : 'Draft does not pass ticket validation.'
    redirect_to issue_ai_enhancement_path(@issue, @enhancement)
  end

  private

  def find_ai_issue
    @issue = Issue.find(params[:issue_id])
    @project = @issue.project
  end

  def authorize_ai
    unless RedmineAi::Policy.allowed?(@issue, User.current)
      render_403
      return
    end
    render_403 unless RedmineAi::Configuration.values['enabled'] == '1'
  end

  def find_enhancement
    # Sessions are private to the requesting user, even when another user can view the issue.
    @enhancement = AiEnhancement.where(issue_id: @issue.id, user_id: User.current.id).find(params[:id])
  end

  def enqueue(enhancement)
    AiEnhancementJob.perform_later(enhancement.id)
  rescue StandardError
    document = enhancement.data
    document['error'] = 'Background job could not be queued. Check the Redmine job backend.'
    enhancement.data = document
    enhancement.state = 'failed'
    enhancement.save!
  end
end
