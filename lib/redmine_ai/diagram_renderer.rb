# frozen_string_literal: true
require 'erb'

module RedmineAi
  class DiagramRenderer
    WIDTH = 1020
    BOX_WIDTH = 260
    BOX_HEIGHT = 120
    ROW_HEIGHT = 192

    def self.render(diagram)
      nodes = diagram.fetch('nodes')
      edges = diagram.fetch('edges')
      remaining = nodes.map { |node| node.fetch('id') }
      levels = []
      until remaining.empty?
        ready = remaining.reject { |id| edges.any? { |edge| edge['to'] == id && remaining.include?(edge['from']) } }
        ready = [remaining.first] if ready.empty?
        ready.each_slice(3) { |row| levels << row }
        remaining -= ready
      end
      positions = {}
      levels.each_with_index do |row, level|
        row.each_with_index do |id, column|
          positions[id] = {x: (WIDTH - (row.size * BOX_WIDTH + (row.size - 1) * 36)) / 2 + column * (BOX_WIDTH + 36),
                           y: 112 + level * ROW_HEIGHT, row: level}
        end
      end
      height = 112 + levels.size * ROW_HEIGHT + 30
      parts = [%(<?xml version="1.0" encoding="UTF-8"?>),
               %(<svg xmlns="http://www.w3.org/2000/svg" width="#{WIDTH}" height="#{height}" viewBox="0 0 #{WIDTH} #{height}" role="img" aria-labelledby="diagram-title">),
               %(<title id="diagram-title">#{escape(diagram.fetch('title'))}</title>),
               %(<rect width="#{WIDTH}" height="#{height}" fill="#ffffff"/>),
               %(<defs><marker id="arrow" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto"><path d="M 0 0 L 10 5 L 0 10 z" fill="#64748b"/></marker></defs>)]
      wrap(diagram.fetch('title'), 90).each_with_index { |line, index| parts << text(WIDTH / 2, 30 + index * 24, line, 20, '#0f172a') }
      parts << text(WIDTH / 2, 86, 'AI-generated proposal — review before implementation', 13, '#64748b')
      edges.each_with_index do |edge, index|
        from = positions.fetch(edge.fetch('from'))
        to = positions.fetch(edge.fetch('to'))
        if to[:row] > from[:row]
          x1 = from[:x] + BOX_WIDTH / 2
          y1 = from[:y] + BOX_HEIGHT
          x2 = to[:x] + BOX_WIDTH / 2
          y2 = to[:y]
          middle = (y1 + y2) / 2
          path = "M #{x1} #{y1} C #{x1} #{middle}, #{x2} #{middle}, #{x2} #{y2 - 3}"
          label_x = (x1 + x2) / 2
          label_y = middle
        else
          x1 = from[:x] + BOX_WIDTH
          y1 = from[:y] + BOX_HEIGHT / 2
          x2 = to[:x] + BOX_WIDTH
          y2 = to[:y] + BOX_HEIGHT / 2
          channel = WIDTH - 24 - (index % 3) * 12
          path = "M #{x1} #{y1} C #{channel} #{y1 - 38}, #{channel} #{y2 + 38}, #{x2 + 3} #{y2}"
          label_x = channel - 48
          label_y = (y1 + y2) / 2
        end
        parts << %(<path d="#{path}" fill="none" stroke="#64748b" stroke-width="2" marker-end="url(#arrow)"/>)
        unless edge.fetch('label').empty?
          wrap(edge.fetch('label'), 32).each_with_index { |line, offset| parts << text(label_x, label_y + offset * 15, line, 12, '#334155', halo: true) }
        end
      end
      nodes.each do |node|
        point = positions.fetch(node.fetch('id'))
        parts << %(<rect x="#{point[:x]}" y="#{point[:y]}" width="#{BOX_WIDTH}" height="#{BOX_HEIGHT}" rx="12" fill="#f1f5f9" stroke="#94a3b8"/>)
        lines = wrap(node.fetch('label'), 29)
        first_y = point[:y] + BOX_HEIGHT / 2 - (lines.size - 1) * 9 + 5
        lines.each_with_index { |line, offset| parts << text(point[:x] + BOX_WIDTH / 2, first_y + offset * 18, line, 14, '#0f172a') }
      end
      parts << '</svg>'
      parts.join("\n")
    end

    def self.wrap(value, width)
      value.split.flat_map { |word| word.scan(/.{1,#{width}}/) }.each_with_object([]) do |word, lines|
        if lines.any? && lines.last.size + word.size + 1 <= width
          lines[-1] += ' ' + word
        else
          lines << word
        end
      end
    end

    def self.escape(value)
      ERB::Util.html_escape(value.to_s)
    end

    def self.text(x, y, value, size, color, halo: false)
      outline = halo ? ' stroke="#ffffff" stroke-width="5" paint-order="stroke" stroke-linejoin="round"' : ''
      %(<text x="#{x}" y="#{y}" text-anchor="middle" font-family="Arial, sans-serif" font-size="#{size}" fill="#{color}"#{outline}>#{escape(value)}</text>)
    end
    private_class_method :wrap, :escape, :text
  end
end
