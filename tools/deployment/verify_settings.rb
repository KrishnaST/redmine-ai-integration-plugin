# frozen_string_literal: true
require 'json'

information = {}
ActiveRecord::Base.transaction(requires_new: true) do
  connection = ActiveRecord::Base.connection
  connection.execute('SET TRANSACTION READ ONLY')
  configuration = RedmineAi::Configuration.values
  information[:version] = Redmine::Plugin.find(:redmine_ai_integration).version
  information[:enabled] = configuration['enabled'] == '1'
  information[:key_configured] = !RedmineAi::Configuration.secret.to_s.empty?
  information[:sources_count] = RedmineAi::Configuration.sources.size
  information[:instructions_removed] = !configuration.key?('instructions')
  information[:model_choices] = RedmineAi::Models.options
  information[:drivers] = {'pg' => 'pg', 'ruby-oci8' => 'oci8', 'tiny_tds' => 'tiny_tds', 'mysql2' => 'mysql2'}.to_h do |name, feature|
    require feature
    [name, Gem.loaded_specs.fetch(name).version.to_s]
  end
  administrator = User.where(admin: true, status: 1).first!
  previous_user = User.current
  begin
    User.current = administrator
    rendered = AiSettingsController.renderer.render(template: 'ai_settings/edit', layout: false,
      assigns: {settings: configuration, sources: [], models: RedmineAi::Models.options,
                code_roles: Role.where(builtin: 0).order(:name).pluck(:name, :id),
                projects: Project.order(:name).pluck(:name, :id), source_check: configuration['source_check'] || {}})
    raise 'Model dropdown was not rendered' unless rendered.include?('name="settings[model]"') && rendered.include?('<select')
    raise 'Reasoning effort dropdown was not rendered' unless rendered.include?('name="settings[reasoning_effort]"') && rendered.include?('value="max">Ultra</option>')
    raise 'Code role/source controls missing' unless rendered.include?('settings[code_role_ids][]') && rendered.include?('Allow reviewed code changes')
    information[:reasoning_effort] = configuration['reasoning_effort'].presence || 'model_default'
    raise 'Structured sources were not rendered' unless rendered.include?('IP / hostname') && rendered.include?('Include table samples') && rendered.include?('Test/reload sources')
    raise 'Obsolete controls still rendered' if rendered.include?('settings[instructions]') || rendered.include?('settings[sources_json]')
    information[:settings_rendered] = true
    information[:settings_asset_path] = rendered.scan(/<script[^>]+src="([^"]+)"/).flatten.find { |path| path.include?('settings') }
    raise 'Settings JavaScript asset missing' unless information[:settings_asset_path]
  ensure
    User.current = previous_user
  end
end
puts JSON.generate(information)
