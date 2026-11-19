# frozen_string_literal: true
require 'find'
require 'pathname'

module RedmineAi
  class FolderInventory
    SKIPPED = %w[.git .svn node_modules vendor target build dist log logs tmp coverage .bundle].freeze
    MAX_ENTRIES = 20_000
    MAX_FILES = 500

    def self.discover(source)
      root = Pathname.new(source.fetch('root')).realpath
      raise Error, 'Source folder is not readable.' unless root.directory? && root.readable?
      files = []
      entries = 0
      Find.find(root.to_s) do |path|
        entries += 1
        raise Error, 'Folder scan exceeds the entry limit.' if entries > MAX_ENTRIES
        entry = Pathname.new(path)
        if entry.symlink?
          Find.prune
        elsif entry.directory?
          Find.prune if path != root.to_s && (entry.basename.to_s.start_with?('.') || SKIPPED.include?(entry.basename.to_s))
        else
          relative = entry.relative_path_from(root).to_s
          next if relative.match?(Sources::BLOCKED) || !Sources::EXTENSIONS.include?(entry.extname.downcase)
          next unless entry.file? && entry.size <= Sources::MAX_BYTES
          raise Error, 'Folder contains too many eligible files.' if files.size >= MAX_FILES
          files << relative
        end
      end
      files.sort
    end
  end
end
