# frozen_string_literal: true
require_relative 'test_plugin'
require 'action_controller'
require 'action_dispatch/middleware/flash'
require 'action_view'
require 'rack/test'
require_relative 'test_api_errors'
require_relative 'test_artifacts'
require_relative 'test_database_adapters'
require_relative 'test_technical_sources'
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
  get 'issues/:id/edit', to: 'issues#edit', as: :edit_issue
  instance_eval(File.read(File.expand_path('../config/routes.rb', __dir__)))
end
AiEnhancementsController.include ROUTES.url_helpers
AiSettingsController.include ROUTES.url_helpers
AiEnhancementsController.prepend_view_path File.expand_path('../app/views', __dir__)
AiSettingsController.prepend_view_path File.expand_path('../app/views', __dir__)

class ControllerTest < PluginTest
  include ArtifactFixtures
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

  def test_issue_actions_render_interactive_post_link_with_edit_target
    rendered = AiEnhancementsController.renderer.render(partial: 'ai_enhancements/buttons', locals: {issue: @issue})
    assert_includes rendered, '>Edit with AI</a>'
    assert_includes rendered, "data-edit-path=\"/issues/#{@issue.id}/edit\""
    assert_includes rendered, 'mode=interactive'
    assert_includes rendered, 'data-method="post"'
    assert_includes rendered, 'data-ai-edit-action="true"'
    assert_includes rendered, 'issue_actions.js'
    assert_includes rendered, '>Enhance with AI</a>'
    FileUtils.mkdir_p(File.expand_path('../tmp', __dir__))
    File.write(File.expand_path('../tmp/issue-actions.html', __dir__), rendered)
  end

  def test_issue_actions_hidden_when_disabled_or_not_allowed
    Setting.plugin_redmine_ai_integration['enabled'] = '0'
    rendered = AiEnhancementsController.renderer.render(partial: 'ai_enhancements/buttons', locals: {issue: @issue})
    refute_includes rendered, 'Edit with AI'
    Setting.plugin_redmine_ai_integration['enabled'] = '1'
    @user.update!(permitted: false)
    rendered = AiEnhancementsController.renderer.render(partial: 'ai_enhancements/buttons', locals: {issue: @issue})
    refute_includes rendered, 'Edit with AI'
    User.current = nil
    rendered = AiEnhancementsController.renderer.render(partial: 'ai_enhancements/buttons', locals: {issue: @issue})
    refute_includes rendered, 'Edit with AI'
  end

  def test_ai_permission_does_not_bypass_existing_edit_access_or_login
    @user.define_singleton_method(:allowed_to?) { |permission, *_arguments| permission == :enhance_issues_with_ai }
    rendered = AiEnhancementsController.renderer.render(partial: 'ai_enhancements/buttons', locals: {issue: @issue})
    refute_includes rendered, 'Edit with AI'
    post "/issues/#{@issue.id}/ai_enhancements", {mode: 'interactive'}
    assert_equal 403, last_response.status
    User.current = nil
    post "/issues/#{@issue.id}/ai_enhancements", {mode: 'interactive'}
    assert_equal 401, last_response.status
    assert_equal 0, AiEnhancement.count
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

  def test_attachment_preview_download_are_private_and_do_not_attach_until_apply
    record = attachment_draft
    get "/issues/#{@issue.id}/ai_enhancements/#{record.id}"
    assert_includes last_response.body, 'Proposed attachments'
    assert_includes last_response.body, 'preview=1'
    get "/issues/#{@issue.id}/ai_enhancements/#{record.id}/attachments/0", {preview: '1'}
    assert_equal 200, last_response.status
    assert_includes last_response.headers['content-type'], 'image/svg+xml'
    assert_includes last_response.headers['content-disposition'], 'inline'
    assert_equal "sandbox; default-src 'none'", last_response.headers['content-security-policy']
    assert_includes last_response.body, '<svg'
    get "/issues/#{@issue.id}/ai_enhancements/#{record.id}/attachments/1", {preview: '1'}
    assert_includes last_response.headers['content-disposition'], 'attachment'
    assert_equal 'Proposed test cases', last_response.body
    assert_equal 0, Attachment.count
    User.current = User.create!
    assert_raises(ActiveRecord::RecordNotFound) { get "/issues/#{@issue.id}/ai_enhancements/#{record.id}/attachments/0" }
  end

  def test_attachment_routes_reject_invalid_states_indices_and_revoked_permissions
    record = attachment_draft
    %w[-1 3 invalid].each do |index|
      get "/issues/#{@issue.id}/ai_enhancements/#{record.id}/attachments/#{index}"
      assert_equal 404, last_response.status
    end
    record.update!(state: 'failed')
    get "/issues/#{@issue.id}/ai_enhancements/#{record.id}/attachments/0"
    assert_equal 404, last_response.status
    @user.update!(permitted: false)
    get "/issues/#{@issue.id}/ai_enhancements/#{record.id}/attachments/0"
    assert_equal 403, last_response.status
  end

  def test_apply_attaches_files_once_with_author_and_journal
    record = attachment_draft
    record.apply_draft!
    assert_equal 'applied', record.reload.state
    assert_equal 2, @issue.attachments.count
    assert_equal [@user.id], @issue.attachments.distinct.pluck(:author_id)
    assert_equal record.data['attachment_ids'].sort, @issue.attachments.pluck(:id).sort
    assert_includes @issue.attachments.find_by!(content_type: 'image/svg+xml').body, 'Proposed DNS failover design'
    assert_raises(RedmineAi::Error) { record.apply_draft! }
    assert_equal 2, Attachment.count
  end

  def test_attachment_apply_rolls_back_when_ticket_save_fails
    record = attachment_draft
    document = record.data
    document['result']['fields'].find { |field| field['name'] == 'subject' }['value'] = 'Rejected by validation'
    record.data = document
    record.save!
    assert_raises(ActiveRecord::RecordInvalid) { record.apply_draft! }
    assert_equal 0, Attachment.count
    assert_equal 'payment error', @issue.reload.subject
    assert_equal 'draft', record.reload.state
  end

  def test_attachment_permission_and_concurrent_edit_are_rechecked_on_apply
    record = attachment_draft
    @user.update!(attachment_access: false)
    assert_raises(RedmineAi::Error) { record.apply_draft! }
    assert_equal 0, Attachment.count
    @user.update!(attachment_access: true)
    record = record.reload
    @issue.update!(subject: 'Changed elsewhere')
    assert_raises(RedmineAi::Error) { record.apply_draft! }
    assert_equal 0, Attachment.count
  end

  def test_old_drafts_without_attachment_fields_still_apply
    record = enhancement
    document = record.data
    document['result'].delete('attachments')
    record.data = document
    record.save!
    record.apply_draft!
    assert_equal 'applied', record.reload.state
    assert_equal 0, Attachment.count
  end

  def test_attachment_validation_failure_closes_uploads_and_preserves_ticket
    record = attachment_draft
    uploads = []
    invalid = Object.new
    invalid.define_singleton_method(:valid?) { false }
    Attachment.stub(:new, ->(**attributes) { uploads << attributes.fetch(:file); invalid }) do
      error = assert_raises(RedmineAi::Error) { record.apply_draft! }
      assert_includes error.message, 'Redmine file-size and extension settings'
    end
    assert uploads.all?(&:closed?)
    assert_equal 0, Attachment.count
    assert_equal 'payment error', @issue.reload.subject
  end

  def test_attachment_citations_are_validated_with_ticket_citations
    draft = result
    draft['attachments'] = [text_attachment('Evidence [S1]')]
    fields = RedmineAi::Policy.text_fields(@issue, @user)
    assert_raises(RedmineAi::Error) { RedmineAi::Policy.validate!(draft, fields, []) }
    draft['source_ids'] = ['S1']
    assert_equal draft, RedmineAi::Policy.validate!(draft, fields, ['S1'])
  end

  def test_api_generates_artifacts_only_for_interactive_review
    draft = result
    draft['attachments'] = [diagram_attachment]
    body = {'status' => 'completed', 'output' => [{'content' => [{'type' => 'output_text', 'text' => JSON.generate(draft)}]}]}
    with_api(body) do
      assert_equal draft, RedmineAi::Client.generate(fields: RedmineAi::Policy.text_fields(@issue, @user), evidence: [], messages: [], mode: 'interactive')
    end
    with_api(body) do
      error = assert_raises(RedmineAi::Error) do
        RedmineAi::Client.generate(fields: RedmineAi::Policy.text_fields(@issue, @user), evidence: [], messages: [], mode: 'automatic')
      end
      assert_includes error.message, 'interactive preview and Apply'
    end
    assert_equal 0, Attachment.count
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

  def test_structured_settings_controls_and_database_password_secrecy
    get '/admin/ai_enhancement'
    assert_equal 200, last_response.status
    assert_includes last_response.body, '<select name="settings[model]"'
    assert_includes last_response.body, '<select name="settings[reasoning_effort]"'
    refute_includes last_response.body, 'settings[instructions]'
    refute_includes last_response.body, 'settings[sources_json]'
    assert_includes last_response.body, 'Code folder'
    assert_includes last_response.body, 'Documents folder'
    assert_includes last_response.body, 'Microsoft SQL Server'
    assert_includes last_response.body, 'Include table samples'
    assert_includes last_response.body, 'Test/reload sources'
    fields = {'name' => 'db', 'type' => 'database', 'project_ids' => ['1'], 'db_type' => 'postgresql',
              'host' => '127.0.0.1', 'port' => '5432', 'database' => 'example', 'schema' => 'public',
              'username' => 'example', 'password' => 'synthetic-private-password',
              'include_table_data' => '1', 'sample_tables' => {'0' => {'table' => 'codes', 'columns' => 'code, description', 'limit' => '5'}}}
    post '/admin/ai_enhancement', {settings: {enabled: '0', model: 'test-model'}, sources_present: '1', sources: {'0' => fields}}
    assert_equal 302, last_response.status
    source = RedmineAi::Configuration.sources.first
    assert_equal 'synthetic-private-password', RedmineAi::SourceConfiguration.password(source)
    assert_equal %w[code description], source['sample_tables'].first['columns']
    get '/admin/ai_enhancement'
    assert_equal 200, last_response.status
    refute_includes last_response.body, 'synthetic-private-password'
    refute_includes last_response.body, source['password_encrypted']
    FileUtils.mkdir_p(File.expand_path('../tmp', __dir__))
    File.write(File.expand_path('../tmp/settings-form.html', __dir__), last_response.body)
  end

  def test_source_reload_is_admin_only_and_post_only
    AiSourceCheckJob.stub(:perform_later, true) do
      post '/admin/ai_enhancement/reload_sources'
      assert_equal 302, last_response.status
    end
    @user.update!(permitted: false)
    post '/admin/ai_enhancement/reload_sources'
    assert_equal 403, last_response.status
    get '/admin/ai_enhancement/reload_sources'
    assert_equal 404, last_response.status
  end

  def test_reasoning_effort_saves_renders_and_rejects_invalid_values
    %w[low medium high xhigh max].each do |effort|
      post '/admin/ai_enhancement', {settings: {enabled: '1', model: 'test-model', reasoning_effort: effort}}
      assert_equal 302, last_response.status
      assert_equal effort, RedmineAi::Configuration.values['reasoning_effort']
    end
    get '/admin/ai_enhancement'
    assert_includes last_response.body, '<option selected="selected" value="max">Ultra</option>'
    post '/admin/ai_enhancement', {settings: {enabled: '1', model: 'test-model', reasoning_effort: 'ultra'}}
    assert_equal 200, last_response.status
    assert_equal 'max', RedmineAi::Configuration.values['reasoning_effort']
    post '/admin/ai_enhancement', {settings: {enabled: '1', model: 'test-model', reasoning_effort: ''}}
    assert_equal 302, last_response.status
    assert_nil RedmineAi::Configuration.reasoning_effort
  end
end
