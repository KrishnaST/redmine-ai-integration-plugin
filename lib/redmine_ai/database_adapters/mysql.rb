# frozen_string_literal: true
module RedmineAi
  module DatabaseAdapters
    class Mysql
      def initialize(source)
        require 'mysql2'
        @connection = Mysql2::Client.new(host: source.fetch('host'), port: source.fetch('port'), database: source.fetch('database'),
          username: source.fetch('username'), password: SourceConfiguration.password(source),
          connect_timeout: 5, read_timeout: 5, write_timeout: 5, encoding: 'utf8mb4')
        @connection.query('START TRANSACTION READ ONLY')
      rescue StandardError
        close
        raise
      end

      def prepared(sql, schema)
        statement = @connection.prepare(sql)
        begin
          statement.execute(schema).to_a
        ensure
          statement.close
        end
      end

      def columns(schema)
        prepared("SELECT #{COLUMNS} FROM information_schema.columns WHERE table_schema = ? ORDER BY table_name, ordinal_position LIMIT 2001", schema)
      end

      def constraints(schema)
        prepared(<<~SQL, schema)
          SELECT tc.table_name, tc.constraint_name AS name, tc.constraint_type AS kind,
                 k.column_name, k.ordinal_position, k.referenced_table_schema AS referenced_schema,
                 k.referenced_table_name AS referenced_table, k.referenced_column_name AS referenced_column
          FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage k
            ON k.constraint_schema = tc.constraint_schema AND k.constraint_name = tc.constraint_name AND k.table_name = tc.table_name
          WHERE tc.table_schema = ? AND tc.constraint_type IN ('PRIMARY KEY', 'UNIQUE', 'FOREIGN KEY')
          ORDER BY tc.table_name, tc.constraint_name, k.ordinal_position LIMIT 2001
        SQL
      end

      def sample(schema, table, columns, limit)
        names = [schema, table, *columns].map { |name| '`' + DatabaseAdapters.identifier(name) + '`' }
        selections = names.drop(2).map { |name| "LEFT(CAST(#{name} AS CHAR), 500) AS #{name}" }
        @connection.query("SELECT #{selections.join(', ')} FROM #{names[0]}.#{names[1]} LIMIT #{DatabaseAdapters.row_limit(limit)}").to_a
      end

      def close
        return unless @connection
        begin
          @connection.query('ROLLBACK')
        ensure
          @connection.close
          @connection = nil
        end
      end
    end
  end
end
