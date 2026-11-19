# frozen_string_literal: true
require_relative 'diagram_renderer'

module RedmineAi
  class Artifacts
    FORMATS = %w[svg md txt csv json sql mmd].freeze
    FileData = Struct.new(:filename, :content_type, :content, keyword_init: true)

    def self.schema
      node = {type: 'object', additionalProperties: false, properties: {id: {type: 'string'}, label: {type: 'string'}}, required: %w[id label]}
      edge = {type: 'object', additionalProperties: false, properties: {from: {type: 'string'}, to: {type: 'string'}, label: {type: 'string'}}, required: %w[from to label]}
      diagram = {type: 'object', additionalProperties: false, properties: {title: {type: 'string'}, nodes: {type: 'array', items: node}, edges: {type: 'array', items: edge}}, required: %w[title nodes edges]}
      {type: 'array', items: {type: 'object', additionalProperties: false,
        properties: {name: {type: 'string'}, format: {type: 'string', enum: FORMATS}, content: {type: 'string'}, diagram: diagram}, required: %w[name format content diagram]}}
    end

    def self.validate!(attachments)
      raise Error, 'AI may propose at most three attachments.' unless attachments.is_a?(Array) && attachments.size <= 3
      total = 0
      attachments.each do |attachment|
        raise Error, 'Invalid AI attachment.' unless attachment.is_a?(Hash) && attachment.keys.sort == %w[content diagram format name]
        validate_text!(attachment['name'], 120, allow_empty: false)
        raise Error, 'Unsupported AI attachment format.' unless FORMATS.include?(attachment['format'])
        validate_text!(attachment['content'], 40_000)
        diagram = attachment['diagram']
        raise Error, 'Invalid AI diagram.' unless diagram.is_a?(Hash) && diagram.keys.sort == %w[edges nodes title]
        validate_text!(diagram['title'], 120)
        nodes = diagram['nodes']
        edges = diagram['edges']
        raise Error, 'Invalid AI diagram nodes or edges.' unless nodes.is_a?(Array) && edges.is_a?(Array)
        if attachment['format'] == 'svg'
          raise Error, 'SVG diagrams require a title, 1–18 nodes and at most 36 edges; raw SVG is not accepted.' unless attachment['content'].empty? && !diagram['title'].strip.empty? && nodes.size.between?(1, 18) && edges.size <= 36
          ids = nodes.map do |node|
            raise Error, 'Invalid AI diagram node.' unless node.is_a?(Hash) && node.keys.sort == %w[id label] && node['id'].is_a?(String) && node['id'].match?(/\A[a-zA-Z][a-zA-Z0-9_]{0,29}\z/)
            validate_text!(node['label'], 160, allow_empty: false)
            node['id']
          end
          raise Error, 'Duplicate AI diagram node IDs.' unless ids.uniq.size == ids.size
          edges.each do |edge|
            raise Error, 'Invalid AI diagram edge.' unless edge.is_a?(Hash) && edge.keys.sort == %w[from label to] && ids.include?(edge['from']) && ids.include?(edge['to'])
            validate_text!(edge['label'], 60)
          end
        else
          raise Error, 'Text attachments require content and an empty diagram.' unless !attachment['content'].strip.empty? && diagram['title'].empty? && nodes.empty? && edges.empty?
        end
        total += attachment['content'].bytesize
      end
      raise Error, 'AI text attachments exceed the 80 KB total limit.' if total > 80_000
      attachments
    end

    def self.citation_texts(attachments)
      attachments.flat_map do |attachment|
        diagram = attachment.fetch('diagram')
        [attachment['name'], attachment['content'], diagram['title']] + diagram['nodes'].map { |node| node['label'] } + diagram['edges'].map { |edge| edge['label'] }
      end
    end

    def self.file(attachment, session_id, index)
      validate!([attachment])
      extension = attachment.fetch('format')
      diagram = extension == 'svg'
      filename = "ai-#{diagram ? 'diagram' : 'document'}-#{Integer(session_id)}-#{Integer(index) + 1}.#{extension}"
      FileData.new(filename: filename, content_type: diagram ? 'image/svg+xml' : 'text/plain; charset=utf-8',
                   content: diagram ? DiagramRenderer.render(attachment.fetch('diagram')) : attachment.fetch('content'))
    end

    def self.validate_text!(value, limit, allow_empty: true)
      raise Error, 'Invalid AI attachment text.' unless value.is_a?(String) && value.valid_encoding? && value.bytesize <= limit && !value.match?(/[\x00-\x08\x0b\x0c\x0e-\x1f]/) && (allow_empty || !value.strip.empty?)
    end
    private_class_method :validate_text!
  end
end
