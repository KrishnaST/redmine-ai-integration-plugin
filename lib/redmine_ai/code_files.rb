# frozen_string_literal: true
require 'digest'
require 'pathname'
require_relative 'sources'

module RedmineAi
  class CodeFiles
    MAX_FILE_BYTES = 32_000
    MAX_TOTAL_BYTES = 96_000
    MAX_FILES = 8

    def self.sources(project_id)
      Configuration.sources.select { |source| source['type'] == 'code_folder' && source['allow_code_changes'] == true && source['project_ids'].include?(project_id) }
    end

    def self.source_signature(source)
      Digest::SHA256.hexdigest(JSON.generate(source.slice('id', 'name', 'type', 'root', 'project_ids', 'allow_code_changes')))
    end

    def self.root(source)
      configured = Pathname.new(source.fetch('root')).expand_path
      resolved = configured.realpath
      raise Error, 'Code roots cannot use symlinks or filesystem/system roots.' unless configured == resolved && configured.parent != configured
      if File::ALT_SEPARATOR.nil? && %w[/etc /proc /sys /dev /bin /sbin /usr /boot].any? { |base| resolved.to_s == base || resolved.to_s.start_with?(base + '/') }
        raise Error, 'System directories cannot be code targets.'
      end
      if Rails.respond_to?(:root) && Rails.root
        application = Pathname.new(Rails.root).realpath
        if resolved == application || resolved.to_s.start_with?(application.to_s + File::SEPARATOR) || application.to_s.start_with?(resolved.to_s + File::SEPARATOR)
          raise Error, 'Redmine application directories and their ancestors cannot be code targets.'
        end
      end
      raise Error, 'Code root must be a readable directory.' unless resolved.directory? && resolved.readable?
      resolved
    end

    def self.path(source, relative)
      raise Error, 'Invalid code file path.' unless relative.is_a?(String) && relative.bytesize.between?(1, 300) && relative.match?(/\A[a-zA-Z0-9_.\/-]+\z/) && !relative.start_with?('/') && !relative.split('/').any? { |part| part.empty? || part.start_with?('.') || FolderInventory::SKIPPED.include?(part) }
      raise Error, 'This code file type/path is excluded.' if relative.match?(Sources::BLOCKED) || !Sources::EXTENSIONS.include?(File.extname(relative).downcase)
      directory = root(source)
      current = directory
      relative.split('/').each do |part|
        current = current.join(part)
        raise Error, 'Code targets cannot contain symlinks.' if current.symlink?
      end
      stats = current.lstat
      raise Error, 'Code target must be an existing regular file without hard links.' unless stats.file? && stats.nlink == 1 && current.realpath == current
      current
    rescue Errno::ENOENT, Errno::EACCES
      raise Error, 'A code target is unavailable. Reload the draft.'
    end

    def self.read(source, relative)
      file = path(source, relative)
      bytes = file.open('rb') { |handle| handle.read(MAX_FILE_BYTES + 1) }
      raise Error, 'Code files must be UTF-8 text no larger than 32 KB.' unless bytes && bytes.bytesize <= MAX_FILE_BYTES && bytes.dup.force_encoding(Encoding::UTF_8).valid_encoding? && !bytes.include?("\x00")
      bytes.force_encoding(Encoding::UTF_8)
    end

    def self.collect(project_id, query)
      configured = sources(project_id)
      raise Error, 'Configure a project-mapped Code folder and enable Allow reviewed code changes before using Code with AI.' if configured.empty?
      terms = query.downcase.scan(/[a-z][a-z0-9_]{2,}/).uniq.first(80)
      candidates = []
      budget = 10_000_000
      configured.each do |source|
        root(source)
        FolderInventory.discover(source).each do |relative|
          next if File.size(path(source, relative)) > MAX_FILE_BYTES
          content = read(source, relative)
          budget -= content.bytesize
          raise Error, 'Code discovery exceeds its read budget.' if budget.negative?
          score = terms.count { |term| relative.downcase.include?(term) || content.downcase.include?(term) }
          next if score.zero?
          candidates << {'source_id' => SourceConfiguration.id(source), 'source_name' => source['name'], 'source_signature' => source_signature(source),
                         'path' => relative.tr('\\', '/'), 'content' => content, 'sha256' => Digest::SHA256.hexdigest(content), 'score' => score}
        end
      end
      remaining = MAX_TOTAL_BYTES
      selected = candidates.sort_by { |file| [-file['score'], file['source_name'], file['path']] }.first(MAX_FILES).filter_map do |file|
        next if file['content'].bytesize > remaining
        remaining -= file['content'].bytesize
        file.except('score')
      end
      raise Error, 'No matching eligible code files were found. Add filenames or identifiers to the ticket and check the configured folder.' if selected.empty?
      selected.each_with_index.map { |file, index| file.merge('id' => "F#{index + 1}") }
    end
  end
end
