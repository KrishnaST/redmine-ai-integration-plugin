# frozen_string_literal: true
require_relative 'test_plugin'
require 'action_controller'
require 'action_view'
require 'action_dispatch/middleware/flash'
require 'rack/test'
class ApplicationController < ActionController::Base
  def require_login
    head :unauthorized unless User.current
  end
  def require_admin
    head :forbidden unless User.current&.permitted
  end
  def render_403
    head :forbidden
  end
end
require_relative '../app/controllers/ai_enhancements_controller'
require_relative '../app/controllers/ai_settings_controller'
ROUTES = ActionDispatch::Routing::RouteSet.new
ROUTES.draw do
  get 'issues/:id', to: 'issues#show', as: :issue
  instance_eval(File.read(File.expand_path('../config/routes.rb', __dir__)))
end
AiEnhancementsController.include ROUTES.url_helpers
AiSettingsController.include ROUTES.url_helpers
AiEnhancementsController.prepend_view_path File.expand_path('../app/views', __dir__)
AiSettingsController.prepend_view_path File.expand_path('../app/views', __dir__)

class ControllerTest < PluginTest
  include Rack::Test::Methods
  def app; ROUTES; end

  def test_both_modes_enqueue_for_existing_ticket
    AiEnhancementJob.stub(:perform_later, true) do
      post "/issues/#{@issue.id}/ai_enhancements", {mode: 'automatic'}
      assert_equal 302, last_response.status
      assert_equal 'automatic', AiEnhancement.last.mode
      AiEnhancement.last.update!(state: 'failed')
      post "/issues/#{@issue.id}/ai_enhancements", {mode: 'interactive'}
      assert_equal 302, last_response.status
      assert_equal 'interactive', AiEnhancement.last.mode
    end
  end

  def test_non_owner_cannot_view_or_reply
    record = enhancement
    User.current = User.create!
    assert_raises(ActiveRecord::RecordNotFound) { get "/issues/#{@issue.id}/ai_enhancements/#{record.id}" }
    assert_raises(ActiveRecord::RecordNotFound) { post "/issues/#{@issue.id}/ai_enhancements/#{record.id}/reply", {reply: 'new facts'} }
  end

  def test_interactive_page_and_reply
    record = enhancement
    get "/issues/#{@issue.id}/ai_enhancements/#{record.id}"
    assert_equal 200, last_response.status
    assert_includes last_response.body, 'Apply enhanced ticket'
    assert_includes last_response.body, 'Revise with AI'
    AiEnhancementJob.stub(:perform_later, true) do
      post "/issues/#{@issue.id}/ai_enhancements/#{record.id}/reply", {reply: 'It happens only after OTP confirmation.'}
    end
    assert_equal 'queued', record.reload.state
    assert_includes record.data['messages'].last['text'], 'OTP confirmation'
    assert_equal 'payment error', @issue.reload.subject
  end

  def test_disabled_or_unauthorized_access
    @user.update!(permitted: false)
    post "/issues/#{@issue.id}/ai_enhancements", {mode: 'automatic'}
    assert_equal 403, last_response.status
    @user.update!(permitted: true)
    Setting.plugin_redmine_ai_integration['enabled'] = '0'
    post "/issues/#{@issue.id}/ai_enhancements", {mode: 'automatic'}
    assert_equal 403, last_response.status
    assert_equal 0, AiEnhancement.count
  end

  def test_apply_is_post_only_and_preserves_conflicting_edit
    record = enhancement
    @issue.update!(description: 'Someone else changed the ticket')
    post "/issues/#{@issue.id}/ai_enhancements/#{record.id}/apply"
    assert_equal 302, last_response.status
    assert_equal 'draft', record.reload.state
    assert_equal 'Someone else changed the ticket', @issue.reload.description
    get "/issues/#{@issue.id}/ai_enhancements/#{record.id}/apply"
    assert_equal 404, last_response.status
  end

  def test_admin_settings_encrypt_and_do_not_echo_key
    post '/admin/ai_enhancement', {settings: {enabled: '1', model: 'test-model', sources_json: '[]', instructions: ''}, api_key: 'private-test-key'}
    assert_equal 302, last_response.status
    assert_equal 'private-test-key', RedmineAi::Configuration.secret
    get '/admin/ai_enhancement'
    assert_equal 200, last_response.status
    refute_includes last_response.body, 'private-test-key'
    @user.update!(permitted: false)
    get '/admin/ai_enhancement'
    assert_equal 403, last_response.status
  end
end
