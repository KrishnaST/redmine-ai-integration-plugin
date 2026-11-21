# frozen_string_literal: true
require_relative 'test_plugin'
require_relative '../lib/redmine_ai/code_apply_service'

module CodeFixtures
  def with_code_workspace
    Dir.mktmpdir('code-test-') do |directory|
      @code_root = File.join(directory, 'checkout')
      Dir.mkdir(@code_root)
      Attachment.storage_path = File.join(directory, 'files')
      Dir.mkdir(Attachment.storage_path)
      @original_code = "class Payment\n  def valid?\n    false\n  end\nend\n"
      File.binwrite(File.join(@code_root, 'payment.rb'), @original_code)
      @code_source = {'id' => 'code-test', 'name' => 'payments', 'type' => 'code_folder', 'root' => @code_root,
                      'project_ids' => [1], 'allow_code_changes' => true}
      Setting.plugin_redmine_ai_integration['sources_json'] = JSON.generate([@code_source])
      yield
    end
  end

  def code_result(files)
    {'summary' => 'Validate payment as requested. Suggested verification: run the payment tests; no tests were run.',
     'questions' => [], 'source_ids' => [],
     'changes' => [{'file_id' => files.first['id'], 'explanation' => 'Correct the payment validation result.', 'content' => @original_code.sub('false', 'true')}]}
  end

  def code_record
    files = RedmineAi::CodeFiles.collect(@issue.project_id, 'payment')
    record = AiEnhancement.new(issue: @issue, user: @user, mode: 'code', state: 'draft', baseline: RedmineAi::Policy.fingerprint(@issue))
    record.data = {'messages' => [], 'sources' => [], 'warnings' => [], 'code_files' => files, 'code_result' => code_result(files)}
    record.save!
    record
  end
end

class CodeFilesTest < Minitest::Test
  include CodeFixtures

  def setup
    Setting.plugin_redmine_ai_integration = {'enabled' => '1', 'model' => 'test-model', 'sources_json' => '[]'}
  end

  def test_discovery_requires_explicit_project_mapped_writable_code_source
    assert_raises(RedmineAi::Error) { RedmineAi::CodeFiles.collect(1, 'payment') }
    with_code_workspace do
      files = RedmineAi::CodeFiles.collect(1, 'payment')
      assert_equal 1, files.size
      assert_equal 'F1', files.first['id']
      assert_equal @original_code, files.first['content']
      assert_equal Digest::SHA256.hexdigest(@original_code), files.first['sha256']
      assert_raises(RedmineAi::Error) { RedmineAi::CodeFiles.collect(2, 'payment') }
      @code_source['allow_code_changes'] = false
      Setting.plugin_redmine_ai_integration['sources_json'] = JSON.generate([@code_source])
      assert_raises(RedmineAi::Error) { RedmineAi::CodeFiles.collect(1, 'payment') }
    end
  end

  def test_code_paths_reject_traversal_credential_and_build_files
    with_code_workspace do
      %w[../payment.rb /payment.rb sub/../../payment.rb .git/config application.yml passwords.txt target/payment.rb bad:payment.rb].each do |path|
        assert_raises(RedmineAi::Error) { RedmineAi::CodeFiles.path(@code_source, path) }
      end
      assert_equal @original_code, RedmineAi::CodeFiles.read(@code_source, 'payment.rb')
      File.binwrite(File.join(@code_root, 'payment.rb'), "\xff\x00".b)
      assert_raises(RedmineAi::Error) { RedmineAi::CodeFiles.read(@code_source, 'payment.rb') }
    end
  end

  def test_code_targets_reject_symlinks_and_hardlinks
    skip 'Windows developer account cannot reliably create symlinks' if Gem.win_platform?
    with_code_workspace do
      File.symlink(File.join(@code_root, 'payment.rb'), File.join(@code_root, 'linked.rb'))
      assert_raises(RedmineAi::Error) { RedmineAi::CodeFiles.path(@code_source, 'linked.rb') }
      File.link(File.join(@code_root, 'payment.rb'), File.join(@code_root, 'hardlink.rb'))
      assert_raises(RedmineAi::Error) { RedmineAi::CodeFiles.path(@code_source, 'hardlink.rb') }
    end
  end

  def test_proposals_validate_file_ids_sizes_and_citations
    with_code_workspace do
      files = RedmineAi::CodeFiles.collect(1, 'payment')
      valid = code_result(files)
      assert_equal valid, RedmineAi::CodeDraft.validate!(valid, files, [])
      invalid = valid.deep_dup
      invalid['changes'][0]['file_id'] = '../unlisted.rb'
      assert_raises(RedmineAi::Error) { RedmineAi::CodeDraft.validate!(invalid, files, []) }
      invalid = valid.deep_dup
      invalid['changes'] *= 2
      assert_raises(RedmineAi::Error) { RedmineAi::CodeDraft.validate!(invalid, files, []) }
      invalid = valid.deep_dup
      invalid['changes'][0]['content'] = ''
      assert_raises(RedmineAi::Error) { RedmineAi::CodeDraft.validate!(invalid, files, []) }
      invalid['changes'][0]['content'] = 'a' * 32_001
      assert_raises(RedmineAi::Error) { RedmineAi::CodeDraft.validate!(invalid, files, []) }
      invalid = valid.deep_dup
      invalid['summary'] = 'Supported by [S7]'
      assert_raises(RedmineAi::Error) { RedmineAi::CodeDraft.validate!(invalid, files, []) }
      patch = RedmineAi::CodeDraft.patch(valid, files)
      assert_includes patch, '--- a/payments/payment.rb'
      assert_includes patch, '-    false'
      assert_includes patch, '+    true'
    end
  end

  def test_role_and_source_form_options_are_validated
    with_code_workspace do
      row = {'name' => 'payments', 'type' => 'code_folder', 'root' => @code_root, 'project_ids' => ['1'], 'allow_code_changes' => '1'}
      saved = RedmineAi::SourceConfiguration.from_form([row], []).first
      assert_equal true, saved['allow_code_changes']
      row.delete('allow_code_changes')
      assert_equal false, RedmineAi::SourceConfiguration.from_form([row], []).first['allow_code_changes']
      role = Role.create!(name: 'Developer')
      RedmineAi::SettingsService.save({'model' => 'test-model', 'code_role_ids' => ['', role.id.to_s]}, source_rows: nil, api_key: '', clear_api_key: false)
      assert_equal [role.id], RedmineAi::Configuration.values['code_role_ids']
      assert_raises(RedmineAi::Error) { RedmineAi::SettingsService.save({'model' => 'test-model', 'code_role_ids' => ['999999']}, source_rows: nil, api_key: '', clear_api_key: false) }
    end
  end
end
