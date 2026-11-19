# frozen_string_literal: true
class AiEnhancement < ApplicationRecord
  belongs_to :issue
  belongs_to :user
  validates :mode, inclusion: {in: %w[automatic interactive]}
  validates :state, inclusion: {in: %w[queued processing draft applied failed conflict]}

  def data
    RedmineAi::Configuration.encryptor.decrypt_and_verify(payload)
  end

  def data=(value)
    self.payload = RedmineAi::Configuration.encryptor.encrypt_and_sign(value)
  end

  def apply_draft!
    with_lock do
      raise RedmineAi::Error, 'Draft is not ready.' unless state == 'draft'
      issue.with_lock do
        raise RedmineAi::Error, 'Permission to edit this ticket was revoked.' unless RedmineAi::Policy.allowed?(issue, user)
        raise RedmineAi::Error, 'Ticket changed. Start a new enhancement to preserve the latest edits.' unless baseline == RedmineAi::Policy.fingerprint(issue)
        fields = RedmineAi::Policy.text_fields(issue, user)
        document = data
        result = RedmineAi::Policy.validate!(document.fetch('result'), fields, document.fetch('sources').map { |source| source['id'] })
        attributes = {}
        custom = {}
        result['fields'].each do |field|
          if field['name'].start_with?('custom_field_')
            custom[field['name'].delete_prefix('custom_field_')] = field['value']
          else
            attributes[field['name']] = field['value']
          end
        end
        attributes['custom_field_values'] = custom unless custom.empty?
        citations = document['sources'].select { |source| result['source_ids'].include?(source['id']) }
        notes = "AI enhancement (#{mode}); requested by user ##{user_id}."
        Array(document['warnings']).each { |warning| notes << "\n#{warning}" }
        citations.each { |source| notes << "\n[#{source['id']}] #{source['reference']} revision=#{source['revision']} sha256=#{source['sha256']}" }
        issue.init_journal(user, notes)
        issue.send(:safe_attributes=, attributes, user)
        issue.save!
        update!(state: 'applied')
      end
    end
  end
end
