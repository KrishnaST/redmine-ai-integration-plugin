# frozen_string_literal: true
require 'json'

information = {}
ActiveRecord::Base.transaction(requires_new: true) do
  ActiveRecord::Base.connection.execute('SET TRANSACTION READ ONLY')
  previous_user = User.current
  begin
    administrator = User.where(admin: true, status: 1).first!
    User.current = administrator
    projects = EnabledModule.where(name: 'redmine_ai_integration').select(:project_id)
    issue = Issue.where(project_id: projects).first!
    draft = AiEnhancement.new(id: 0, issue: issue, user: administrator, mode: 'code', state: 'draft')
    draft.define_singleton_method(:to_param) { '0' }
    files = [{'id' => 'F1', 'source_name' => 'synthetic', 'path' => 'example.rb', 'content' => "old_value\n"}]
    result = {'summary' => 'Synthetic preview verification only.', 'questions' => [], 'source_ids' => [],
              'changes' => [{'file_id' => 'F1', 'explanation' => 'Synthetic proposal.', 'content' => "new_value\n"}]}
    RedmineAi::CodeDraft.validate!(result, files, [])
    rendered = AiEnhancementsController.renderer.render(template: 'ai_enhancements/code', layout: false,
      assigns: {issue: issue, enhancement: draft, document: {'code_result' => result, 'code_files' => files, 'sources' => [], 'warnings' => [], 'messages' => []}})
    raise 'Code review controls missing' unless rendered.include?('Apply code changes') && rendered.include?('Download proposed patch') && rendered.include?('Revise code with AI')
    controls = AiEnhancementsController.renderer.render(partial: 'ai_enhancements/buttons', locals: {issue: issue})
    raise 'Code action missing for administrator' unless controls.include?('>Code with AI</a>') && controls.include?('mode=code')
    configuration = RedmineAi::Configuration.values
    settings = AiSettingsController.renderer.render(template: 'ai_settings/edit', layout: false,
      assigns: {settings: configuration, sources: [], models: RedmineAi::Models.options,
                code_roles: Role.where(builtin: 0).order(:name).pluck(:name, :id), projects: Project.order(:name).pluck(:name, :id), source_check: {}})
    raise 'Code access/source configuration missing' unless settings.include?('settings[code_role_ids][]') && settings.include?('Allow reviewed code changes')
    route = Rails.application.routes.recognize_path("/issues/#{issue.id}/ai_enhancements/0/code.patch", method: :get)
    raise 'Code download route missing' unless route[:action] == 'code_patch'
    information = {version: Redmine::Plugin.find(:redmine_ai_integration).version, code_view_rendered: true, code_button_rendered: true,
                   code_settings_rendered: true, selected_code_roles: Array(configuration['code_role_ids']).size,
                   writable_code_sources: RedmineAi::Configuration.sources.count { |source| source['type'] == 'code_folder' && source['allow_code_changes'] == true },
                   persisted_session: draft.persisted?, generated_code_written: false}
  ensure
    User.current = previous_user
  end
end
puts JSON.generate(information)
