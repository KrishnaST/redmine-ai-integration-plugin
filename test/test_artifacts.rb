# frozen_string_literal: true
require_relative 'test_plugin'

module ArtifactFixtures
  def diagram_attachment
    JSON.parse(File.read(File.join(__dir__, 'fixtures/diagram.json')))
  end

  def text_attachment(content = 'Proposed test cases')
    {'name' => 'Test cases', 'format' => 'md', 'content' => content, 'diagram' => {'title' => '', 'nodes' => [], 'edges' => []}}
  end

  def attachment_draft
    record = enhancement
    document = record.data
    document['result']['attachments'] = [diagram_attachment, text_attachment]
    record.data = document
    record.save!
    record
  end
end

class ArtifactsTest < Minitest::Test
  include ArtifactFixtures

  def test_diagram_is_rendered_as_static_svg_with_owned_filename
    file = RedmineAi::Artifacts.file(diagram_attachment, 7, 0)
    assert_equal 'ai-diagram-7-1.svg', file.filename
    assert_equal 'image/svg+xml', file.content_type
    assert_includes file.content, 'AI-generated proposal'
    assert_includes file.content, 'Primary endpoint'
    assert_includes file.content, 'marker-end="url(#arrow)"'
    refute_match(/<(script|foreignObject|image)\b|\bonload=|\bhref=/i, file.content)
    FileUtils.mkdir_p(File.expand_path('../tmp', __dir__))
    File.write(File.expand_path('../tmp/proposed-dns-failover.svg', __dir__), file.content)
  end

  def test_diagram_labels_are_escaped_and_cycles_are_bounded
    attachment = diagram_attachment
    attachment['diagram']['nodes'][0]['label'] = '<script>alert("test")</script> & external'
    attachment['diagram']['edges'] << {'from' => 'primary', 'to' => 'app', 'label' => 'Review loop'}
    file = RedmineAi::Artifacts.file(attachment, 7, 0)
    refute_includes file.content, '<script>'
    assert_includes file.content, '&lt;script&gt;'
    assert_operator file.content.bytesize, :<, 40_000
  end

  def test_rejects_raw_svg_unsupported_formats_and_invalid_graph_references
    invalid = diagram_attachment
    invalid['content'] = '<svg onload="alert(1)"/>'
    assert_raises(RedmineAi::Error) { RedmineAi::Artifacts.validate!([invalid]) }
    invalid = diagram_attachment
    invalid['diagram']['edges'][0]['to'] = 'absent'
    assert_raises(RedmineAi::Error) { RedmineAi::Artifacts.validate!([invalid]) }
    invalid = diagram_attachment
    invalid['diagram']['nodes'][1]['id'] = 'app'
    assert_raises(RedmineAi::Error) { RedmineAi::Artifacts.validate!([invalid]) }
    %w[html exe ../svg].each do |format|
      assert_raises(RedmineAi::Error) { RedmineAi::Artifacts.file(text_attachment.merge('format' => format), 7, 0) }
    end
  end

  def test_text_limits_and_binary_controls_are_rejected
    assert_raises(RedmineAi::Error) { RedmineAi::Artifacts.validate!(Array.new(4) { text_attachment }) }
    assert_raises(RedmineAi::Error) { RedmineAi::Artifacts.validate!([text_attachment('a' * 40_001)]) }
    assert_raises(RedmineAi::Error) { RedmineAi::Artifacts.validate!(Array.new(3) { text_attachment('a' * 30_000) }) }
    assert_raises(RedmineAi::Error) { RedmineAi::Artifacts.validate!([text_attachment("binary\0value")]) }
    file = RedmineAi::Artifacts.file(text_attachment('Café'), 7, 1)
    assert_equal 'ai-document-7-2.md', file.filename
    assert_equal 'Café', file.content
  end

  def test_all_diagram_limits_and_extra_properties_are_rejected
    invalid = diagram_attachment
    invalid['diagram']['nodes'] = Array.new(19) { |index| {'id' => "n#{index}", 'label' => 'Node'} }
    assert_raises(RedmineAi::Error) { RedmineAi::Artifacts.validate!([invalid]) }
    invalid = diagram_attachment
    invalid['diagram']['edges'] *= 10
    assert_raises(RedmineAi::Error) { RedmineAi::Artifacts.validate!([invalid]) }
    assert_raises(RedmineAi::Error) { RedmineAi::Artifacts.validate!([diagram_attachment.merge('url' => 'https://example.invalid')]) }
  end
end
