# frozen_string_literal: true
require 'digest'
require 'pathname'
require 'time'

module RedmineAi
  class Sources
    EXTENSIONS = %w[.md .txt .rst .java .rb .py .js .ts .tsx .jsx .cs .sql .xml .xsd .html .css .properties .yml .yaml].freeze
    BLOCKED = /(?:password|secret|credential|token|database\.yml|\.env|private.key)/i
    MAX_BYTES = 2_000_000
    MAX_CONTEXT = 32_000

    def self.collect(project_id, query)
      terms = query.downcase.scan(/[a-z][a-z0-9_]{2,}/).uniq.first(80)
      candidates = []
      warnings = []
      budget = {bytes: 10_000_000}
      Configuration.sources.each do |source|
        next unless source['project_ids'].include?(project_id)
        begin
          snippets = source['type'] == 'files' ? files(source, terms, budget) : database(source, terms)
          candidates.concat(snippets)
        rescue StandardError
          # No paths, credentials, connection strings or database error messages in logs/UI.
          warnings << "Source #{source['name']} could not be read; technical context may be incomplete."
        end
      end
      remaining = MAX_CONTEXT
      selected = candidates.sort_by { |snippet| [-snippet.delete(:score), snippet[:reference]] }.filter_map do |snippet|
        next if remaining <= 0
        snippet[:content] = snippet[:content][0, [remaining, 4000].min]
        remaining -= snippet[:content].length
        snippet.transform_keys(&:to_s)
      end
      [selected.each_with_index.map { |snippet, index| snippet.merge('id' => "S#{index + 1}") }, warnings]
    end

    def self.files(source, terms, budget = {bytes: 10_000_000})
      root = Pathname.new(source.fetch('root')).realpath
      source.fetch('files').flat_map do |relative|
        next [] if relative.match?(BLOCKED) || !EXTENSIONS.include?(File.extname(relative).downcase)
        file = root.join(relative).realpath
        next [] unless file.to_s.start_with?(root.to_s + File::SEPARATOR) && file.file? && file.size <= MAX_BYTES
        raise Error, 'File scan budget exceeded.' if file.size > budget[:bytes]
        budget[:bytes] -= file.size
        bytes = file.binread
        next [] if bytes.include?("\x00")
        text = bytes.force_encoding('UTF-8').scrub
        digest = Digest::SHA256.hexdigest(bytes)
        text.lines.each_slice(40).with_index.filter_map do |chunk, index|
          content = chunk.join
          score = terms.count { |term| content.downcase.include?(term) }
          next if score.zero?
          {score: score, reference: "#{source['name']}:#{relative}:#{index * 40 + 1}-#{index * 40 + chunk.size}",
           revision: source['revision'].to_s, sha256: digest, content: content}
        end.sort_by { |snippet| -snippet[:score] }.first(4)
      end
    end

    def self.database(source, terms)
      require 'pg'
      url = ENV.fetch(source.fetch('url_env'))
      connection = PG.connect(url, connect_timeout: 5)
      begin
        connection.exec('BEGIN READ ONLY')
        connection.exec("SET LOCAL statement_timeout = '3000ms'")
        # Only schema metadata, never business records or model-generated SQL.
        result = connection.exec_params(<<~SQL, [source.fetch('schema')])
          SELECT table_schema, table_name, column_name, data_type,
                 is_nullable, character_maximum_length, numeric_precision, numeric_scale
          FROM information_schema.columns
          WHERE table_schema = $1
          ORDER BY table_name, ordinal_position
          LIMIT 2001
        SQL
        raise Error, 'Schema exceeds metadata limit.' if result.ntuples > 2000
        constraints = connection.exec_params(<<~SQL, [source.fetch('schema')]).to_a.group_by { |row| row['table_name'] }
          SELECT c.relname AS table_name, k.conname AS name, k.contype AS kind,
                 pg_get_constraintdef(k.oid, true) AS definition
          FROM pg_catalog.pg_constraint k
          JOIN pg_catalog.pg_class c ON c.oid = k.conrelid
          JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = $1 AND k.contype IN ('p', 'u', 'f')
          ORDER BY c.relname, k.conname LIMIT 2000
        SQL
        result.to_a.group_by { |row| row['table_name'] }.filter_map do |table, columns|
          content = JSON.generate(columns: columns, constraints: constraints.fetch(table, []))
          score = terms.count { |term| content.downcase.include?(term) }
          next if score.zero?
          {score: score, reference: "#{source['name']}:#{source['schema']}.#{table}",
           revision: Time.now.utc.iso8601, content: content}
        end
      ensure
        connection.exec('ROLLBACK') rescue nil
        connection.close
      end
    end
  end
end
