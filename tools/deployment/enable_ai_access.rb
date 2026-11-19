# frozen_string_literal: true
require 'json'
require 'time'

# Mutating operator action: run only with explicit authorization to enable all current users/projects.
backup = ARGV.fetch(0)
result = {}
ActiveRecord::Base.transaction do
  roles = Role.where.not(builtin: Role::BUILTIN_ANONYMOUS).lock.to_a
  projects = Project.active.lock.to_a
  previous = {recorded_at: Time.now.utc.iso8601,
              roles: roles.map { |role| {id: role.id, permissions: role.permissions} },
              projects: projects.map { |project| {id: project.id, ai_enabled: project.module_enabled?(:redmine_ai_integration)} }}
  File.open(backup, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(JSON.pretty_generate(previous)) }
  result[:roles_updated] = roles.count do |role|
    next false if role.permissions.include?(:enhance_issues_with_ai)
    role.add_permission!(:enhance_issues_with_ai)
    true
  end
  result[:projects_updated] = projects.count do |project|
    next false if project.module_enabled?(:redmine_ai_integration)
    project.enable_module!(:redmine_ai_integration)
    true
  end
  result[:active_projects] = projects.size
  result[:signed_in_roles] = roles.size
end
puts JSON.generate(result)
