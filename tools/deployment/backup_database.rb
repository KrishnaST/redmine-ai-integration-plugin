# frozen_string_literal: true
require 'fileutils'

# pg_dump runs its own consistent read-only database snapshot. Credentials stay in
# the child environment, never arguments, output or a generated configuration file.
target = ARGV.fetch(0)
executable = ARGV[1] || 'pg_dump'
configuration = ActiveRecord::Base.connection_db_config.configuration_hash
abort 'This deployment backup requires PostgreSQL.' unless configuration[:adapter] == 'postgresql'
environment = {'PGAPPNAME' => 'redmine-ai-deployment-backup', 'PGCONNECT_TIMEOUT' => '10',
               'PGOPTIONS' => '-c default_transaction_read_only=on'}
{database: 'PGDATABASE', username: 'PGUSER', password: 'PGPASSWORD', host: 'PGHOST', port: 'PGPORT',
 sslmode: 'PGSSLMODE', sslrootcert: 'PGSSLROOTCERT', sslcert: 'PGSSLCERT', sslkey: 'PGSSLKEY'}.each do |key, variable|
  environment[variable] = configuration[key].to_s unless configuration[key].nil?
end
FileUtils.mkdir_p(File.dirname(target), mode: 0o700)
success = system(environment, executable, '--format=custom', '--no-owner',
                 '--no-privileges', '--file', target, out: File::NULL, err: File::NULL)
abort 'Database backup failed; deployment must not proceed.' unless success && File.size?(target)
File.chmod(0o600, target)
puts "Database backup verified: #{File.size(target)} bytes."
