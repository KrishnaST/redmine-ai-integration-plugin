#!/usr/bin/env bash
# Optional client libraries only; run through the existing service environment wrapper.
set -Eeuo pipefail
umask 077
APPLICATION="${1:?Pass the application directory}"
STAGING="${2:?Pass the private staging directory}"
ORACLE_HOME="${3:?Pass the existing Oracle client/database home}"
SERVICE_ENVIRONMENT="${4:?Pass the service environment file}"
RUN="$STAGING/source-drivers-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RUN"
cd "$APPLICATION"
cp Gemfile.local "$RUN/Gemfile.local.before"
cp Gemfile.lock "$RUN/Gemfile.lock.before"
cp "$SERVICE_ENVIRONMENT" "$RUN/service.env.before"
if [[ -f .bundle/config ]]; then cp .bundle/config "$RUN/bundle-config.before"; fi
recover() {
    result=$?
    trap - ERR
    cp "$RUN/Gemfile.local.before" Gemfile.local
    cp "$RUN/Gemfile.lock.before" Gemfile.lock
    cp "$RUN/service.env.before" "$SERVICE_ENVIRONMENT"
    if [[ -f "$RUN/bundle-config.before" ]]; then cp "$RUN/bundle-config.before" .bundle/config; fi
    printf 'Driver setup failed; original bundle declarations/environment restored. Diagnostics: %s\n' "$RUN"
    exit "$result"
}
trap recover ERR
export ORACLE_HOME
export LD_LIBRARY_PATH="$ORACLE_HOME/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
bundle config set --local build.ruby-oci8 "--with-instant-client-include=$ORACLE_HOME/include --with-instant-client-lib=$ORACLE_HOME/lib" > "$RUN/build-config.log" 2>&1
cat >> Gemfile.local <<'AI_DRIVER_GEMS'

# Redmine AI optional technical-source drivers.
gem 'tiny_tds', '3.4.1', require: false
gem 'ruby-oci8', '2.2.14', require: false
gem 'mysql2', '0.5.7', require: false
AI_DRIVER_GEMS
bundle install > "$RUN/bundle.log" 2>&1
bundle exec ruby -rjson -rpg -rtiny_tds -rmysql2 -roci8 -e 'puts JSON.generate(%w[pg tiny_tds ruby-oci8 mysql2].to_h { |name| [name, Gem.loaded_specs.fetch(name).version.to_s] })' > "$RUN/driver-load.json" 2> "$RUN/driver-load-error.log"
# These contain paths only; existing secret values are not read into output or replaced.
printf '\nORACLE_HOME=%s\nLD_LIBRARY_PATH=%s\n' "$ORACLE_HOME" "$LD_LIBRARY_PATH" >> "$SERVICE_ENVIRONMENT"
printf 'Source drivers installed and loaded. Restart Redmine with the reviewed plugin update. Evidence: %s\n' "$RUN"
cat "$RUN/driver-load.json"
