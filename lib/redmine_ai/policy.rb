# frozen_string_literal: true
require 'digest'
require 'json'
require_relative 'artifacts'

module RedmineAi
  module Policy
    def self.allowed?(issue, user)
      user&.active? && issue.visible?(user) && issue.editable?(user) &&
        user.allowed_to?(:enhance_issues_with_ai, issue.project) &&
        user.allowed_to?(:edit_issues, issue.project)
    end

    def self.fingerprint(issue)
      Digest::SHA256.hexdigest(JSON.generate([issue.attributes.sort, issue.custom_field_values.map { |field| [field.custom_field_id, field.value] }]))
    end

    def self.text_fields(issue, user)
      editable = issue.safe_attribute_names(user)
      fields = {}
      fields['subject'] = issue.subject if editable.include?('subject')
      fields['description'] = issue.description.to_s if editable.include?('description')
      if editable.include?('custom_field_values')
        issue.editable_custom_field_values(user).each do |field|
          next unless %w[string text].include?(field.custom_field.field_format)
          next if field.custom_field.multiple?
          fields["custom_field_#{field.custom_field_id}"] = field.value.to_s
        end
      end
      fields
    end

    def self.validate!(result, fields, source_ids)
      raise Error, 'Invalid AI response.' unless result.is_a?(Hash) && result['fields'].is_a?(Array) && result['questions'].is_a?(Array) && result['source_ids'].is_a?(Array)
      names = result['fields'].map { |field| field['name'] }
      raise Error, 'AI response changed unsupported fields.' unless names.sort == fields.keys.sort
      result['fields'].each do |field|
        value = field['value']
        raise Error, 'Invalid field content.' unless value.is_a?(String) && value.length <= 40_000
        raise Error, 'Invalid subject.' if field['name'] == 'subject' && (value.strip.empty? || value.length > 255)
      end
      raise Error, 'Invalid questions.' unless result['questions'].size <= 8 && result['questions'].all? { |question| question.is_a?(String) && question.size <= 2000 }
      raise Error, 'Unknown source citation.' unless (result['source_ids'] - source_ids).empty?
      attachments = Artifacts.validate!(result.fetch('attachments', []))
      citation_texts = result['fields'].map { |field| field['value'] } + Artifacts.citation_texts(attachments)
      citations = citation_texts.flat_map { |value| value.scan(/\[(S\d+)\]/).flatten }.uniq
      raise Error, 'Unknown inline citation.' unless (citations - source_ids).empty?
      raise Error, 'Inline citations and source list disagree.' unless citations.sort == result['source_ids'].uniq.sort
      result
    end
  end
end
