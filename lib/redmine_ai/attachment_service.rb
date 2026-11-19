# frozen_string_literal: true
require 'stringio'
require_relative 'artifacts'

module RedmineAi
  class AttachmentService
    class Upload < StringIO
      attr_reader :original_filename, :content_type

      def initialize(file)
        super(file.content.b)
        @original_filename = file.filename
        @content_type = file.content_type
      end
    end

    def self.stage!(issue, user, session_id, attachments)
      Artifacts.validate!(attachments)
      return [] if attachments.empty?
      raise Error, 'Permission to attach files was revoked.' unless issue.attachments_addable?(user)
      uploads = attachments.each_with_index.map do |attachment, index|
        {'file' => Upload.new(Artifacts.file(attachment, session_id, index)), 'description' => 'AI-generated proposal; reviewed on Apply.'}
      end
      begin
        files = uploads.map { |upload| Attachment.new(file: upload.fetch('file'), author: user, description: upload.fetch('description'), container: issue) }
        raise Error, 'Generated attachments could not be saved. Check Redmine file-size and extension settings.' unless files.all?(&:valid?)
        files.each { |file| issue.attachments << file }
        files
      ensure
        uploads.each { |upload| upload.fetch('file').close }
      end
    end
  end
end
