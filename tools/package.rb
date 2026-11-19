# frozen_string_literal: true
require 'fileutils'
require 'rubygems/package'
require 'zlib'

# Tar.gz needs only the Ruby standard library and preserves the required plugin folder name.
root = File.expand_path('..', __dir__)
FileUtils.mkdir_p(File.join(root, 'dist'))
target = File.join(root, 'dist/redmine_ai_integration-1.2.0.tar.gz')
paths = %w[init.rb app assets config db lib].flat_map { |item| Dir.glob(File.join(root, item, '**/*')) + [File.join(root, item)] }.uniq.select { |file| File.file?(file) }
Zlib::GzipWriter.open(target) do |gzip|
  Gem::Package::TarWriter.new(gzip) do |tar|
    paths.sort.each do |file|
      relative = file.delete_prefix(root + '/')
      tar.add_file_simple('redmine_ai_integration/' + relative, 0o644, File.size(file)) { |entry| entry.write(File.binread(file)) }
    end
  end
end
puts target
