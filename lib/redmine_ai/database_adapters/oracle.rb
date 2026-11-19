# frozen_string_literal: true
module RedmineAi
  module DatabaseAdapters
    class Oracle
      def initialize(source)
        require 'oci8'
        # Identifiers in the descriptor are validated configuration, never model output.
        service = source.fetch('database')
        raise Error, 'Oracle service name has unsupported characters.' unless service.match?(/\A[a-zA-Z0-9_.-]+\z/)
        descriptor = "(DESCRIPTION=(CONNECT_TIMEOUT=5)(TRANSPORT_CONNECT_TIMEOUT=3)(ADDRESS=(PROTOCOL=TCP)(HOST=#{source.fetch('host')})(PORT=#{source.fetch('port')}))(CONNECT_DATA=(SERVICE_NAME=#{service})))"
        @connection = OCI8.new(source.fetch('username'), SourceConfiguration.password(source), descriptor)
        @connection.send_timeout = 5
        @connection.recv_timeout = 5
        @connection.exec('SET TRANSACTION READ ONLY')
      rescue StandardError
        close
        raise
      end

      def query(sql, bindings = [])
        cursor = @connection.parse(sql)
        begin
          bindings.each_with_index { |value, index| cursor.bind_param(index + 1, value) }
          cursor.exec
          names = cursor.get_col_names.map(&:downcase)
          rows = []
          while (row = cursor.fetch)
            rows << names.zip(row).to_h
          end
          rows
        ensure
          cursor.close
        end
      end

      def columns(schema)
        query(<<~SQL, [schema])
          SELECT owner AS table_schema, table_name, column_name, data_type,
                 nullable AS is_nullable, char_length AS character_maximum_length,
                 data_precision AS numeric_precision, data_scale AS numeric_scale
          FROM all_tab_columns WHERE owner = :1
          ORDER BY table_name, column_id FETCH FIRST 2001 ROWS ONLY
        SQL
      end

      def constraints(schema)
        query(<<~SQL, [schema])
          SELECT c.table_name, c.constraint_name AS name, c.constraint_type AS kind,
                 k.column_name, k.position AS ordinal_position, r.owner AS referenced_schema,
                 r.table_name AS referenced_table, rk.column_name AS referenced_column
          FROM all_constraints c JOIN all_cons_columns k
            ON k.owner = c.owner AND k.constraint_name = c.constraint_name
          LEFT JOIN all_constraints r ON r.owner = c.r_owner AND r.constraint_name = c.r_constraint_name
          LEFT JOIN all_cons_columns rk ON rk.owner = r.owner
            AND rk.constraint_name = r.constraint_name AND rk.position = k.position
          WHERE c.owner = :1 AND c.constraint_type IN ('P', 'U', 'R')
          ORDER BY c.table_name, c.constraint_name, k.position FETCH FIRST 2001 ROWS ONLY
        SQL
      end

      def sample(schema, table, columns, limit)
        names = [schema, table, *columns].map { |name| '"' + DatabaseAdapters.identifier(name) + '"' }
        selections = names.drop(2).map { |name| "SUBSTR(CAST(#{name} AS VARCHAR2(4000)), 1, 500) AS #{name}" }
        query("SELECT #{selections.join(', ')} FROM #{names[0]}.#{names[1]} FETCH FIRST #{DatabaseAdapters.row_limit(limit)} ROWS ONLY")
      end

      def close
        return unless @connection
        begin
          @connection.rollback
        ensure
          @connection.logoff
          @connection = nil
        end
      end
    end
  end
end
