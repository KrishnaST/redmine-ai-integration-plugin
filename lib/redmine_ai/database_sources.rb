# frozen_string_literal: true
require 'digest'
require 'json'
require 'time'
require_relative 'database_adapters'

module RedmineAi
  class DatabaseSources
    LIMIT = 2000
    DRIVERS = {'postgresql' => 'pg', 'oracle' => 'ruby-oci8', 'sqlserver' => 'tiny_tds', 'mysql' => 'mysql2'}.freeze

    def self.snapshot(source)
      engine = source['type'] == 'postgres_schema' ? 'postgresql' : source.fetch('db_type')
      adapter = DatabaseAdapters.open(engine, source)
      begin
        columns = adapter.columns(source.fetch('schema'))
        constraints = adapter.constraints(source.fetch('schema'))
        raise Error, 'Schema exceeds the metadata limit.' if columns.size > LIMIT || constraints.size > LIMIT
        grouped = columns.group_by { |row| row.fetch('table_name') }
        samples = {}
        if source['include_table_data']
          source.fetch('sample_tables').each do |selection|
            table = selection.fetch('table')
            available = grouped.fetch(table) { raise Error, 'A sample table is absent or not visible in metadata.' }.map { |column| column.fetch('column_name') }
            raise Error, 'A configured sample column is absent or not visible in metadata.' unless (selection.fetch('columns') - available).empty?
            rows = adapter.sample(source.fetch('schema'), table, selection.fetch('columns'), selection.fetch('limit'))
            samples[table] = rows.map do |row|
              row.to_h.transform_values { |value| value.nil? ? nil : value.to_s.encode('UTF-8', invalid: :replace, undef: :replace)[0, 500] }
            end
          end
        end
        keys = constraints.group_by { |row| row.fetch('table_name') }
        grouped.map { |table, fields| {'table_name' => table, 'columns' => fields, 'constraints' => keys.fetch(table, []), 'sample_rows' => samples.fetch(table, [])} }
      ensure
        adapter.close
      end
    end

    def self.snippets(source, terms)
      snapshot(source).filter_map do |table|
        content = JSON.generate(table)
        score = terms.count { |term| content.downcase.include?(term) }
        next if score.zero?
        {score: score, reference: "#{source['name']}:#{source['schema']}.#{table['table_name']}",
         revision: Time.now.utc.iso8601, sha256: Digest::SHA256.hexdigest(content), content: content}
      end
    end
  end
end
