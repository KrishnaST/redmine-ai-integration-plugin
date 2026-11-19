# frozen_string_literal: true
require_relative 'database_adapters/postgresql'
require_relative 'database_adapters/oracle'
require_relative 'database_adapters/sqlserver'
require_relative 'database_adapters/mysql'

module RedmineAi
  module DatabaseAdapters
    COLUMNS = 'table_schema, table_name, column_name, data_type, is_nullable, character_maximum_length, numeric_precision, numeric_scale'

    def self.identifier(value)
      raise Error, 'Invalid database identifier.' unless value.is_a?(String) && value.match?(/\A[a-zA-Z_][a-zA-Z0-9_$#]{0,127}\z/)
      value
    end

    def self.row_limit(value)
      raise Error, 'Sample row limit must be between 1 and 20.' unless value.is_a?(Integer) && value.between?(1, 20)
      value
    end

    def self.open(engine, source)
      adapter = {'postgresql' => Postgresql, 'oracle' => Oracle, 'sqlserver' => Sqlserver, 'mysql' => Mysql}.fetch(engine) { raise Error, 'Unknown database type.' }
      adapter.new(source)
    rescue LoadError
      raise Error, "Database driver #{DatabaseSources::DRIVERS.fetch(engine)} is not available in Redmine's bundle."
    end
  end
end
