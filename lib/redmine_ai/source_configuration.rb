# frozen_string_literal: true
require 'digest'
require 'json'
require 'pathname'
require 'securerandom'

module RedmineAi
  class SourceConfiguration
    TYPES = %w[code_folder documents_folder database files postgres_schema].freeze
    ENGINES = %w[postgresql oracle sqlserver mysql].freeze
    CONNECTION_FIELDS = %w[db_type host port database username].freeze

    def self.parse(raw)
      sources = JSON.parse(raw)
      raise Error, 'Configure at most 20 technical sources.' unless sources.is_a?(Array) && sources.size <= 20
      names = []
      sources.each do |source|
        raise Error, 'Invalid technical source.' unless source.is_a?(Hash) && TYPES.include?(source['type'])
        name = source['name']
        raise Error, 'Each source needs a unique name using letters, numbers, underscores or hyphens.' unless name.is_a?(String) && name.match?(/\A[a-zA-Z0-9_-]{1,50}\z/) && !names.include?(name)
        names << name
        ids = source['project_ids']
        raise Error, 'Select at least one project for each source.' unless ids.is_a?(Array) && ids.any? && ids.all? { |id| id.is_a?(Integer) && id.positive? }
        case source['type']
        when 'files', 'code_folder', 'documents_folder'
          raise Error, 'Source path must be an absolute server-side folder.' unless source['root'].is_a?(String) && Pathname.new(source['root']).absolute?
          if source['type'] == 'files'
            raise Error, 'File source needs an explicit safe file list (max 500).' unless source['files'].is_a?(Array) && source['files'].size.between?(1, 500) && source['files'].all? { |file| file.is_a?(String) && !Pathname.new(file).absolute? && !file.split(/[\\\/]/).include?('..') }
          end
        when 'postgres_schema'
          raise Error, 'Legacy database URL must reference an environment variable.' unless source['url_env'].to_s.match?(/\A[A-Z][A-Z0-9_]+\z/)
          validate_schema(source['schema'])
        when 'database'
          raise Error, 'Choose a supported database type.' unless ENGINES.include?(source['db_type'])
          raise Error, 'Enter a host name or IP address.' unless source['host'].to_s.match?(/\A[a-zA-Z0-9_.:\-\[\]]{1,253}\z/)
          raise Error, 'Database port must be between 1 and 65535.' unless source['port'].is_a?(Integer) && source['port'].between?(1, 65535)
          %w[database username].each { |key| raise Error, 'Enter the database/service name and username.' unless source[key].is_a?(String) && source[key].size.between?(1, 128) && !source[key].match?(/[\x00-\x1f]/) }
          validate_schema(source['schema'])
          raise Error, 'Database passwords must be encrypted.' if source.key?('password')
          validate_samples(source)
        end
      end
      sources
    rescue JSON::ParserError
      raise Error, 'Technical source configuration is invalid.'
    end

    def self.validate_schema(schema)
      raise Error, 'Enter an explicit schema/owner using letters, numbers and underscores.' unless schema.to_s.match?(/\A[a-zA-Z_][a-zA-Z0-9_$#]{0,127}\z/)
    end

    def self.validate_samples(source)
      return unless source['include_table_data']
      tables = source['sample_tables']
      raise Error, 'Choose 1-10 sample tables with explicit columns.' unless tables.is_a?(Array) && tables.size.between?(1, 10)
      names = []
      tables.each do |selection|
        raise Error, 'Invalid sample table definition.' unless selection.is_a?(Hash)
        validate_schema(selection['table'])
        raise Error, 'Sample tables must be unique.' if names.include?(selection['table'])
        names << selection['table']
        columns = selection['columns']
        raise Error, 'Choose 1-20 unique columns for each sample table.' unless columns.is_a?(Array) && columns.size.between?(1, 20) && columns.uniq.size == columns.size
        columns.each { |column| validate_schema(column) }
        raise Error, 'Sample row limit must be 1-20.' unless selection['limit'].is_a?(Integer) && selection['limit'].between?(1, 20)
      end
    end

    def self.id(source)
      source['id'] || Digest::SHA256.hexdigest(source['name'].to_s + ':' + source['type'].to_s)[0, 32]
    end

    def self.from_form(rows, previous)
      raise Error, 'Configure at most 20 technical sources.' unless rows.is_a?(Array) && rows.size <= 20
      sources = rows.map do |row|
        id = row['id'].to_s
        old = previous.find { |source| self.id(source) == id && !id.empty? } || {}
        source = {'id' => old.empty? ? SecureRandom.uuid : self.id(old), 'name' => row['name'].to_s.strip,
                  'type' => row['type'].to_s, 'project_ids' => Array(row['project_ids']).reject(&:blank?).map { |value| Integer(value, 10) },
                  'revision' => row['revision'].to_s.strip[0, 200]}
        if source['type'] == 'database'
          CONNECTION_FIELDS.each { |field| source[field] = row[field].to_s.strip }
          source['port'] = Integer(source['port'], 10)
          source['schema'] = row['schema'].to_s.strip
          password = row['password'].to_s
          raise Error, 'Database password is too long.' if password.bytesize > 4096
          same_connection = CONNECTION_FIELDS.all? { |field| source[field].to_s == old[field].to_s }
          encrypted = same_connection && row['clear_password'] != '1' ? old['password_encrypted'] : nil
          encrypted = Configuration.encryptor.encrypt_and_sign(password) unless password.empty?
          source['password_encrypted'] = encrypted if encrypted
          source['include_table_data'] = row['include_table_data'] == '1'
          if source['include_table_data']
            source['sample_tables'] = Array(row['sample_tables']).reject { |table| table['table'].to_s.strip.empty? }.map do |table|
              {'table' => table['table'].to_s.strip, 'columns' => table['columns'].to_s.split(',').map(&:strip).reject(&:empty?), 'limit' => Integer(table['limit'].to_s, 10)}
            end
          end
        elsif %w[files postgres_schema].include?(source['type'])
          # Existing explicit-file/environment-URL definitions remain usable without JSON editing.
          raise Error, 'A legacy source cannot be created through this form.' if old.empty?
          source.merge!(old.except('name', 'project_ids', 'revision'))
        else
          source['root'] = row['root'].to_s.strip
        end
        source
      end
      parse(JSON.generate(sources))
    rescue ArgumentError, TypeError
      raise Error, 'Project IDs and database ports must be valid numbers.'
    end

    def self.password(source)
      encrypted = source['password_encrypted']
      encrypted.present? ? Configuration.encryptor.decrypt_and_verify(encrypted) : ''
    end
  end
end
