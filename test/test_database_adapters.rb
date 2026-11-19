# frozen_string_literal: true
require_relative 'test_plugin'

class DatabaseAdaptersTest < Minitest::Test
  class Result
    def initialize(rows); @rows = rows; end
    def to_a; @rows; end
    def each(**); @rows; end
    def cancel; end
  end

  class Cursor
    def initialize(connection, sql)
      @connection = connection
      @sql = sql
      @rows = connection.rows(sql)
    end
    def bind_param(*); end
    def exec; @connection.queries << @sql; end
    def get_col_names; @rows.first&.keys || []; end
    def fetch; @rows.shift&.values; end
    def close; end
    def execute(*)
      @connection.queries << @sql
      Result.new(@rows)
    end
  end

  class Connection
    attr_reader :queries, :closed
    attr_accessor :fail_metadata, :send_timeout, :recv_timeout
    def initialize; @queries = []; end
    def rows(sql)
      raise IOError, 'synthetic connection failure' if fail_metadata && sql.match?(/information_schema|all_tab_columns/)
      if sql.match?(/information_schema.columns|all_tab_columns/)
        [{'table_name' => 'codes', 'column_name' => 'code', 'data_type' => 'text'}]
      elsif sql.match?(/pg_catalog|all_constraints|sys.tables|table_constraints/)
        [{'table_name' => 'codes', 'name' => 'codes_pk', 'kind' => 'PRIMARY KEY'}]
      else
        [{'code' => 'approved example'}]
      end
    end
    def exec(sql); @queries << sql; Result.new(sql.start_with?('SELECT') ? rows(sql) : []); end
    def exec_params(sql, _bindings); @queries << sql; Result.new(rows(sql)); end
    def execute(sql); @queries << sql; Result.new(rows(sql)); end
    def query(sql); exec(sql); end
    def parse(sql); Cursor.new(self, sql); end
    def prepare(sql); Cursor.new(self, sql); end
    def rollback; @queries << 'ROLLBACK'; end
    def logoff; close; end
    def close; @closed = true; end
  end

  def source(engine, samples: false)
    {'name' => 'db', 'type' => 'database', 'db_type' => engine, 'host' => '127.0.0.1', 'port' => 1234,
     'database' => 'example', 'schema' => 'public', 'username' => 'unrestricted_example', 'project_ids' => [1],
     'include_table_data' => samples, 'sample_tables' => [{'table' => 'codes', 'columns' => ['code'], 'limit' => 5}]}
  end

  def with_driver(engine, connection)
    name, feature = {'postgresql' => [:PG, 'pg.rb'], 'oracle' => [:OCI8, 'oci8.rb'],
                     'sqlserver' => [:TinyTds, 'tiny_tds.rb'], 'mysql' => [:Mysql2, 'mysql2.rb']}.fetch(engine)
    previous = Object.const_get(name) if Object.const_defined?(name)
    Object.send(:remove_const, name) if previous
    driver = Module.new
    if engine == 'postgresql'
      driver.define_singleton_method(:connect) { |*_arguments, **_options| connection }
    elsif engine == 'oracle'
      driver.define_singleton_method(:new) { |*_arguments| connection }
    else
      client = Class.new
      client.define_singleton_method(:new) { |**_options| connection }
      driver.const_set(:Client, client)
    end
    Object.const_set(name, driver)
    $LOADED_FEATURES << feature
    yield
  ensure
    $LOADED_FEATURES.delete(feature)
    Object.send(:remove_const, name) if Object.const_defined?(name)
    Object.const_set(name, previous) if previous
  end

  %w[postgresql oracle sqlserver mysql].each do |engine|
    define_method("test_#{engine}_metadata_and_opted_in_samples") do
      connection = Connection.new
      with_driver(engine, connection) do
        tables = RedmineAi::DatabaseSources.snapshot(source(engine, samples: true))
        assert_equal 'codes', tables.first['table_name']
        assert_equal 'approved example', tables.first['sample_rows'].first['code']
        assert_equal 1, tables.first['constraints'].size
        assert connection.closed
        sample = connection.queries.find { |sql| sql.include?('500) AS') || sql.include?('1, 500)') }
        refute_nil sample
        assert_match(/SELECT/, sample)
        assert_match(/LIMIT 5|FIRST 5|TOP \(5\)/, sample)
        if engine == 'sqlserver'
          assert connection.queries.all? { |sql| sql.lstrip.start_with?('SELECT') }, 'SQL Server must execute SELECT statements only'
        else
          assert_match(/READ ONLY/, connection.queries.first)
          assert_equal 'ROLLBACK', connection.queries.last
        end
      end
    end

    define_method("test_#{engine}_always_closes_on_metadata_error") do
      connection = Connection.new
      connection.fail_metadata = true
      with_driver(engine, connection) do
        assert_raises(IOError) { RedmineAi::DatabaseSources.snapshot(source(engine)) }
        assert connection.closed
      end
    end
  end

  def test_identifier_and_limit_injection_are_rejected
    assert_raises(RedmineAi::Error) { RedmineAi::DatabaseAdapters.identifier('codes; DELETE') }
    assert_raises(RedmineAi::Error) { RedmineAi::DatabaseAdapters.row_limit(21) }
    assert_raises(RedmineAi::Error) { RedmineAi::DatabaseAdapters.row_limit('5;DROP') }
  end
end
