# frozen_string_literal: true
module RedmineAi
  module DatabaseAdapters
    class Postgresql
      def initialize(source)
        require 'pg'
        @connection = if source['type'] == 'postgres_schema'
          PG.connect(ENV.fetch(source.fetch('url_env')), connect_timeout: 5)
        else
          PG.connect(host: source.fetch('host'), port: source.fetch('port'), dbname: source.fetch('database'),
                     user: source.fetch('username'), password: SourceConfiguration.password(source), connect_timeout: 5)
        end
        @connection.exec('BEGIN READ ONLY')
        @connection.exec("SET LOCAL statement_timeout = '3000ms'")
      rescue StandardError
        close
        raise
      end

      def columns(schema)
        @connection.exec_params("SELECT #{COLUMNS} FROM information_schema.columns WHERE table_schema = $1 ORDER BY table_name, ordinal_position LIMIT 2001", [schema]).to_a
      end

      def constraints(schema)
        @connection.exec_params(<<~SQL, [schema]).to_a
          SELECT c.relname AS table_name, k.conname AS name, k.contype AS kind,
                 pg_get_constraintdef(k.oid, true) AS definition
          FROM pg_catalog.pg_constraint k
          JOIN pg_catalog.pg_class c ON c.oid = k.conrelid
          JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = $1 AND k.contype IN ('p', 'u', 'f')
          ORDER BY c.relname, k.conname LIMIT 2001
        SQL
      end

      def sample(schema, table, columns, limit)
        names = [schema, table, *columns].map { |name| '"' + DatabaseAdapters.identifier(name) + '"' }
        selections = names.drop(2).map { |name| "LEFT(CAST(#{name} AS text), 500) AS #{name}" }
        @connection.exec("SELECT #{selections.join(', ')} FROM #{names[0]}.#{names[1]} LIMIT #{DatabaseAdapters.row_limit(limit)}").to_a
      end

      def close
        return unless @connection
        begin
          @connection.exec('ROLLBACK')
        ensure
          @connection.close
          @connection = nil
        end
      end
    end
  end
end
