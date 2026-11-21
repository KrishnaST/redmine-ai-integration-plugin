# frozen_string_literal: true
require 'securerandom'
require_relative 'code_draft'

module RedmineAi
  class CodeApplyService
    def self.targets(issue, document)
      files = document.fetch('code_files')
      result = CodeDraft.validate!(document.fetch('code_result'), files, document.fetch('sources').map { |source| source['id'] })
      sources = CodeFiles.sources(issue.project_id)
      targets = result['changes'].map do |change|
        original = files.find { |file| file['id'] == change['file_id'] }
        source = sources.find { |entry| SourceConfiguration.id(entry) == original['source_id'] }
        raise Error, 'Code source configuration changed or access was removed. Generate a new proposal.' unless source && CodeFiles.source_signature(source) == original['source_signature']
        path = CodeFiles.path(source, original['path'])
        current = CodeFiles.read(source, original['path'])
        raise Error, 'Code file changed. Generate a new proposal to preserve other edits.' unless Digest::SHA256.hexdigest(current) == original['sha256'] && current == original['content']
        stat = File.stat(path)
        raise Error, 'Code file must be an owned, writable, single-link file in a writable directory.' unless stat.nlink == 1 && stat.uid == Process.uid && File.writable?(path) && File.writable?(path.dirname)
        {path: path, source: source, relative: original['path'], before: current, after: change['content'], mode: stat.mode & 0o777}
      end
      raise Error, 'Code sources resolve to duplicate target files.' unless targets.map { |target| target[:path].to_s }.uniq.size == targets.size
      targets
    end

    def self.apply!(enhancement)
      token = SecureRandom.uuid
      enhancement.with_lock do
        check_access!(enhancement)
        raise Error, 'Code draft is not ready to apply.' unless enhancement.mode == 'code' && enhancement.state == 'draft'
        document = enhancement.data
        raise Error, 'There are no proposed code changes to apply.' if document.fetch('code_result').fetch('changes').empty?
        # Persist an intent before touching files; interrupted writes remain explicitly applying.
        document['code_apply_token'] = token
        enhancement.data = document
        enhancement.update!(state: 'applying')
      end
      written = []
      locks = []
      begin
        document = enhancement.data
        directory = recovery_directory
        planned = targets(enhancement.issue, document)
        planned.sort_by { |target| target[:path].to_s }.each do |target|
          lock_path = directory.join("#{Digest::SHA256.hexdigest(target[:path].to_s)}.lock")
          raise Error, 'Unsafe code lock file.' if lock_path.symlink?
          handle = File.open(lock_path, File::RDWR | File::CREAT, 0o600)
          locks << handle
          raise Error, 'Another code apply is using one of these files. Try later.' unless handle.flock(File::LOCK_EX | File::LOCK_NB)
        end
        # Recheck after obtaining the cooperating writers' locks.
        planned = targets(enhancement.issue, document)
        recovery = {'session_id' => enhancement.id, 'token' => token, 'files' => planned.map { |target| {path: target[:path].to_s, before: target[:before], after: target[:after], mode: target[:mode]} }}
        recovery_path = directory.join("#{enhancement.id}-#{token}.encrypted")
        File.open(recovery_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.write(Configuration.encryptor.encrypt_and_sign(recovery))
          file.flush
          file.fsync
        end
        planned.each do |target|
          raise Error, 'Code file changed during Apply.' unless CodeFiles.read(target[:source], target[:relative]) == target[:before]
          replace!(target, target[:after], expected: target[:before])
          written << target
        end
        enhancement.with_lock do
          check_access!(enhancement)
          raise Error, 'Code apply state changed; operator review required.' unless enhancement.state == 'applying' && enhancement.data['code_apply_token'] == token
          enhancement.issue.with_lock do
            raise Error, 'Ticket changed. Generate a new code proposal.' unless enhancement.baseline == Policy.fingerprint(enhancement.issue)
            # Access/source settings and disk bytes are checked immediately before the journal commit.
            planned.each do |target|
              source = CodeFiles.sources(enhancement.issue.project_id).find { |entry| SourceConfiguration.id(entry) == SourceConfiguration.id(target[:source]) }
              raise Error, 'Code source configuration changed during Apply.' unless source && CodeFiles.source_signature(source) == CodeFiles.source_signature(target[:source]) && CodeFiles.read(source, target[:relative]) == target[:after]
            end
            notes = "AI code changes reviewed and applied by user ##{enhancement.user_id}; session ##{enhancement.id}. No build, test, commit or deployment was run."
            planned.each { |target| notes << "\n#{target[:source]['name']}:#{target[:relative]} sha256=#{Digest::SHA256.hexdigest(target[:after])}" }
            enhancement.issue.init_journal(enhancement.user, notes)
            enhancement.issue.save!
            document['code_recovery_file'] = recovery_path.basename.to_s
            document['code_applied_files'] = planned.map { |target| {'path' => target[:relative], 'sha256' => Digest::SHA256.hexdigest(target[:after])} }
            enhancement.data = document
            enhancement.update!(state: 'applied')
          end
        end
      rescue StandardError
        rollback_ok = true
        written.reverse_each do |target|
          begin
            current = CodeFiles.read(target[:source], target[:relative])
            raise Error, 'Concurrent file edit during rollback.' unless current == target[:after]
            replace!(target, target[:before], expected: target[:after])
          rescue StandardError
            rollback_ok = false
          end
        end
        enhancement.reload
        if enhancement.state == 'applying' && enhancement.data['code_apply_token'] == token
          failed = enhancement.data
          failed['error'] = rollback_ok ? 'Code Apply failed. Any files written by this attempt were restored; review source access, permissions and concurrent edits before generating a new draft.' : 'Code Apply needs operator recovery. An external edit or filesystem error prevented full rollback. Do not retry; use the private encrypted code recovery inventory.'
          enhancement.data = failed
          enhancement.update!(state: rollback_ok ? 'failed' : 'applying')
        end
        raise Error, rollback_ok ? 'Code Apply failed; no code changes from this attempt remain.' : 'Code Apply requires operator recovery; do not retry.'
      ensure
        locks.reverse_each(&:close)
      end
    end

    def self.check_access!(enhancement)
      raise Error, 'Permission to use Code with AI was revoked.' unless Configuration.values['enabled'] == '1' && Policy.code_allowed?(enhancement.issue, enhancement.user)
      raise Error, 'Ticket changed. Generate a new code proposal.' unless enhancement.baseline == Policy.fingerprint(enhancement.issue)
    end

    def self.recovery_directory
      root = Pathname.new(Attachment.storage_path).realpath
      directory = root.join('ai-code-recovery')
      raise Error, 'Unsafe code recovery directory.' if directory.symlink?
      Dir.mkdir(directory, 0o700) unless directory.exist?
      raise Error, 'Private code recovery storage is unavailable.' unless directory.directory? && directory.realpath.dirname == root && File.stat(directory).uid == Process.uid
      File.chmod(0o700, directory)
      directory
    end

    def self.replace!(target, content, expected:)
      path = CodeFiles.path(target[:source], target[:relative])
      temporary = path.dirname.join(".redmine-ai-#{SecureRandom.hex(16)}.tmp")
      begin
        File.open(temporary, File::WRONLY | File::CREAT | File::EXCL | File::BINARY, 0o600) do |file|
          file.write(content.b)
          file.flush
          file.fsync
          file.chmod(target[:mode])
        end
        raise Error, 'Code target changed during file preparation.' unless CodeFiles.path(target[:source], target[:relative]) == path && CodeFiles.read(target[:source], target[:relative]) == expected
        File.rename(temporary, path)
      ensure
        File.unlink(temporary) if temporary.exist?
      end
    end
    private_class_method :check_access!, :recovery_directory
  end
end
