# frozen_string_literal: true
require 'json'

information = {}
ActiveRecord::Base.transaction(requires_new: true) do
  ActiveRecord::Base.connection.execute('SET TRANSACTION READ ONLY')
  information[:version] = Redmine::Plugin.find(:redmine_ai_integration).version
  projects = EnabledModule.where(name: 'redmine_ai_integration').select(:project_id)
  information[:enabled_projects] = projects.count
  information[:roles_with_ai_permission] = Role.all.count { |role| role.permissions.include?(:enhance_issues_with_ai) }
  previous_user = User.current
  begin
    User.current = User.where(admin: true, status: 1).first!
    issue = Issue.where(project_id: projects).limit(100).detect { |record| RedmineAi::Policy.allowed?(record, User.current) }
    if issue && RedmineAi::Configuration.values['enabled'] == '1'
      rendered = AiEnhancementsController.renderer.render(partial: 'ai_enhancements/buttons', locals: {issue: issue})
      raise 'Edit with AI action missing' unless rendered.include?('>Edit with AI</a>') && rendered.include?('data-ai-edit-action="true"')
      raise 'Interactive action must POST' unless rendered.include?('mode=interactive') && rendered.include?('data-method="post"')
      raise 'Edit target missing' unless rendered.include?('data-edit-path=')
      information[:issue_actions_rendered] = true
    else
      information[:issue_actions_rendered] = false
      information[:message] = 'No enabled, permitted issue available; project module and user permissions are required.'
    end
    asset = AiEnhancementsController.renderer.render(inline: "<%= javascript_include_tag 'issue_actions', plugin: 'redmine_ai_integration', defer: true %>", layout: false)
    information[:issue_actions_asset_path] = asset.scan(/src="([^"]+)"/).flatten.first
    raise 'Issue action asset missing' unless information[:issue_actions_asset_path]
  ensure
    User.current = previous_user
  end
end
puts JSON.generate(information)
