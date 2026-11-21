#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
APPLICATION="${1:?Application directory required}"
STAGING="${2:?Private staging directory required}"
SERVICE="${3:?Service name required}"
ENVIRONMENT_FILE="${4:?Existing service environment file required}"
EXPECTED_SHA256="${5:?Reviewed package SHA256 required}"
HEALTH_URL="${6:-http://127.0.0.1:3000/login}"
PG_DUMP="${7:-pg_dump}"
PACKAGE="$STAGING/redmine_ai_integration-1.3.0.tar.gz"
PLUGIN="$APPLICATION/plugins/redmine_ai_integration"
RUN="$STAGING/settings-upgrade-$(date -u +%Y%m%dT%H%M%SZ)"
STOPPED=0
REPLACED=0
mkdir -p "$RUN/release" "$RUN/backup"
cd "$APPLICATION"
recover() {
    result=$?
    trap - ERR
    if [[ "$REPLACED" == 1 ]]; then
        sudo -n systemctl stop "$SERVICE" || true
        [[ ! -e "$PLUGIN" ]] || mv "$PLUGIN" "$RUN/failed-plugin"
        mv "$RUN/previous-plugin" "$PLUGIN"
        sudo -n systemctl start "$SERVICE" || true
    elif [[ "$STOPPED" == 1 ]]; then
        sudo -n systemctl start "$SERVICE" || true
    fi
    printf 'Upgrade failed; application recovery attempted. Evidence: %s\n' "$RUN"
    exit "$result"
}
trap recover ERR
[[ -d "$PLUGIN" && ! -L "$PLUGIN" ]]
[[ "$EXPECTED_SHA256" =~ ^[a-fA-F0-9]{64}$ ]]
printf '%s  %s\n' "$EXPECTED_SHA256" "$PACKAGE" | sha256sum --check
tar -xzf "$PACKAGE" -C "$RUN/release"
while IFS= read -r -d '' source; do ruby -c "$source" >> "$RUN/syntax.log" 2>&1; done < <(find "$RUN/release" -name '*.rb' -print0)
bundle check > "$RUN/bundle.log" 2>&1
sudo -n true
sudo -n systemctl stop "$SERVICE"
STOPPED=1
bundle exec rails runner "$STAGING/backup_database.rb" "$RUN/backup/database.dump" "$PG_DUMP" > "$RUN/database-backup.log" 2>&1
tar -I 'gzip -1' -cf "$RUN/backup/config-plugin-bundle.tar.gz" config plugins/redmine_ai_integration Gemfile Gemfile.local Gemfile.lock .bundle/config -C "$(dirname "$ENVIRONMENT_FILE")" "$(basename "$ENVIRONMENT_FILE")"
mv "$PLUGIN" "$RUN/previous-plugin"
REPLACED=1
cp -a "$RUN/release/redmine_ai_integration" "$APPLICATION/plugins/"
bundle exec rake redmine:plugins:migrate NAME=redmine_ai_integration > "$RUN/migration.log" 2>&1
bundle exec rake assets:precompile > "$RUN/assets.log" 2>&1
bundle exec rails runner "$STAGING/verify_settings.rb" > "$RUN/verification.json" 2> "$RUN/verification-errors.log"
bundle exec rails runner "$STAGING/verify_issue_actions.rb" > "$RUN/issue-actions-verification.json" 2> "$RUN/issue-actions-errors.log"
bundle exec rails runner "$STAGING/verify_artifacts.rb" "$STAGING/diagram-fixture.json" > "$RUN/artifacts-verification.json" 2> "$RUN/artifacts-errors.log"
bundle exec rails runner "$STAGING/verify_code.rb" > "$RUN/code-verification.json" 2> "$RUN/code-errors.log"
sudo -n systemctl start "$SERVICE"
STOPPED=0
healthy=0
for attempt in $(seq 1 30); do
    code=$(curl --connect-timeout 2 --max-time 5 -s -o /dev/null -w '%{http_code}' "$HEALTH_URL" || true)
    if [[ "$code" == 200 ]]; then healthy=1; break; fi
    sleep 2
done
[[ "$healthy" == 1 ]]
systemctl is-active "$SERVICE"
printf 'Settings upgrade completed. Evidence: %s\n' "$RUN"
cat "$RUN/verification.json"
cat "$RUN/issue-actions-verification.json"
cat "$RUN/artifacts-verification.json"
cat "$RUN/code-verification.json"
