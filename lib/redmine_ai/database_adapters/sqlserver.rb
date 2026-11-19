# frozen_string_literal: true
module RedmineAi
  module DatabaseAdapters
    class Sqlserver
      def initialize(source)
        require 'tiny_tds'
        @connection = TinyTds::Client.new(host: source.fetch('host'), port: source.fetch('port'),
          database: source.fetch('database'), username: source.fetch('username'),
          password: SourceConfiguration.password(source), login_timeout: 5, timeout: 5, encoding: 'UTF-8')
      end

      def query(sql)
        result = @connection.execute(sql)
        result.each(as: :hash).to_a
      ensure
        result.cancel if result && result.respond_to?(:cancel)
      end

      def columns(schema)
        literal = "N'#{DatabaseAdapters.identifier(schema)}'"
        query("SELECT TOP (2001) #{COLUMNS} FROM information_schema.columns WHERE table_schema = #{literal} ORDER BY table_name, ordinal_position")
      end

      def constraints(schema)
        literal = "N'#{DatabaseAdapters.identifier(schema)}'"
        query(<<~SQL)
          SELECT TOP (2001) * FROM (
            SELECT t.name AS table_name, i.name AS name,
                   CASE WHEN i.is_primary_key = 1 THEN 'PRIMARY KEY' ELSE 'UNIQUE' END AS kind,
                   c.name AS column_name, ic.key_ordinal AS ordinal_position,
                   CAST(NULL AS nvarchar(128)) AS referenced_schema,
                   CAST(NULL AS nvarchar(128)) AS referenced_table,
                   CAST(NULL AS nvarchar(128)) AS referenced_column
            FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
            JOIN sys.indexes i ON i.object_id = t.object_id AND i.is_unique = 1
            JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
            JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
            WHERE s.name = #{literal} AND ic.key_ordinal > 0 AND i.is_hypothetical = 0
            UNION ALL
            SELECT t.name, fk.name, 'FOREIGN KEY', c.name, fc.constraint_column_id,
                   rs.name, rt.name, rc.name
            FROM sys.foreign_keys fk JOIN sys.foreign_key_columns fc ON fc.constraint_object_id = fk.object_id
            JOIN sys.tables t ON t.object_id = fk.parent_object_id
            JOIN sys.schemas s ON s.schema_id = t.schema_id
            JOIN sys.columns c ON c.object_id = t.object_id AND c.column_id = fc.parent_column_id
            JOIN sys.tables rt ON rt.object_id = fk.referenced_object_id
            JOIN sys.schemas rs ON rs.schema_id = rt.schema_id
            JOIN sys.columns rc ON rc.object_id = rt.object_id AND rc.column_id = fc.referenced_column_id
            WHERE s.name = #{literal}
          ) metadata_keys ORDER BY table_name, name, ordinal_position
        SQL
      end

      def sample(schema, table, columns, limit)
        names = [schema, table, *columns].map { |name| '[' + DatabaseAdapters.identifier(name) + ']' }
        selections = names.drop(2).map { |name| "LEFT(CONVERT(nvarchar(max), #{name}), 500) AS #{name}" }
        query("SELECT TOP (#{DatabaseAdapters.row_limit(limit)}) #{selections.join(', ')} FROM #{names[0]}.#{names[1]}")
      end

      def close
        @connection.close if @connection
        @connection = nil
      end
    end
  end
end
