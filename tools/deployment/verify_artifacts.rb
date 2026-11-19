# frozen_string_literal: true
require 'json'

fixture = JSON.parse(File.read(ARGV.fetch(0)))
information = {}
ActiveRecord::Base.transaction(requires_new: true) do
  ActiveRecord::Base.connection.execute('SET TRANSACTION READ ONLY')
  previous_user = User.current
  upload = nil
  begin
    administrator = User.where(admin: true, status: 1).first!
    User.current = administrator
    projects = EnabledModule.where(name: 'redmine_ai_integration').select(:project_id)
    issue = Issue.where(project_id: projects).first!
    RedmineAi::Artifacts.validate!([fixture])
    file = RedmineAi::Artifacts.file(fixture, 0, 0)
    upload = RedmineAi::AttachmentService::Upload.new(file)
    attachment = Attachment.new(file: upload, author: administrator, container: issue, description: 'Synthetic verification only; never saved.')
    raise 'Native attachment validation failed; check site file limits/extensions.' unless attachment.valid?
    information[:native_attachment_valid] = true
    information[:filename] = file.filename
    information[:byte_size] = file.content.bytesize
    draft = AiEnhancement.new(id: 0, issue: issue, user: administrator, mode: 'interactive', state: 'draft')
    draft.define_singleton_method(:to_param) { '0' }
    fields = {'subject' => 'Synthetic verification', 'description' => 'Synthetic verification'}
    document = {'result' => {'fields' => fields.map { |name, value| {'name' => name, 'value' => value} }, 'questions' => [], 'source_ids' => [], 'attachments' => [fixture]},
                'sources' => [], 'messages' => [], 'warnings' => []}
    rendered = AiEnhancementsController.renderer.render(template: 'ai_enhancements/show', layout: false,
      assigns: {issue: issue, enhancement: draft, fields: fields, document: document, attachments: [fixture]})
    raise 'Artifact preview controls missing' unless rendered.include?('Proposed attachments') && rendered.include?('preview=1') && rendered.include?('>Download</a>')
    information[:preview_rendered] = true
    route = Rails.application.routes.recognize_path("/issues/#{issue.id}/ai_enhancements/0/attachments/0", method: :get)
    raise 'Artifact download route missing' unless route[:action] == 'attachment'
    information[:download_route] = true
    information[:persisted_attachment] = attachment.persisted?
  ensure
    upload&.close
    User.current = previous_user
  end
end
puts JSON.generate(information)
