# frozen_string_literal: true
require_relative 'lib/redmine_ai/configuration'
require_relative 'lib/redmine_ai/policy'
require_relative 'lib/redmine_ai/sources'
require_relative 'lib/redmine_ai/client'
require_relative 'lib/redmine_ai/hooks'

Redmine::Plugin.register :redmine_ai_integration do
  name 'Redmine AI Integration'
  author 'KrishnaST'
  description 'Source-backed automatic and interactive ticket enhancement.'
  version '1.0.0'
  requires_redmine version_or_higher: '7.0.0'
  settings default: RedmineAi::Configuration::DEFAULTS, partial: 'settings/redmine_ai'
  project_module :redmine_ai_integration do
    permission :enhance_issues_with_ai, {ai_enhancements: [:create, :show, :reply, :apply]}, require: :member
  end
  menu :admin_menu, :redmine_ai_settings,
       {controller: 'ai_settings', action: 'edit'}, caption: 'AI ticket enhancement'
end

Rails.application.config.filter_parameters += [:api_key, :instructions, :sources_json, :messages, :reply]
