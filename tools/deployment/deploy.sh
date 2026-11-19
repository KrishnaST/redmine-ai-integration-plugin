#!/usr/bin/env bash
# Run through with_service_environment.py while the old Redmine process is alive.
set -Eeuo pipefail
umask 077

EXPECTED_SHA256="${1:?Pass the reviewed package SHA256}"
APPLICATION="${2:?Pass the absolute Redmine application directory}"
STAGING="${3:?Pass the absolute deployment staging directory}"
SERVICE="${4:?Pass the existing Redmine service name}"
PG_DUMP="${5:-pg_dump}"
PG_RESTORE="${6:-pg_restore}"
ENVIRONMENT_FILE="${7:?Pass the existing service environment file for the private rollback archive}"
HEALTH_URL="${8:-http://127.0.0.1:3000/login}"
PACKAGE="$STAGING/redmine_ai_integration-1.0.0.tar.gz"
PLUGIN="$APPLICATION/plugins/redmine_ai_integration"
RUN="$STAGING/$(date -u +%Y%m%dT%H%M%SZ)"
STOPPED=0
INSTALLED=0

mkdir -p "$RUN/release" "$RUN/backup"
chmod 700 "$RUN" "$RUN/backup"
cd "$APPLICATION"

recover() {
    result=$?
    trap - ERR
    printf 'Deployment failed; see private diagnostics under %s.\n' "$RUN"
    if [[ "$INSTALLED" == 1 && -d "$PLUGIN" && ! -L "$PLUGIN" ]]; then
        sudo -n systemctl stop "$SERVICE" || true
        mv -- "$PLUGIN" "$RUN/rejected-plugin"
        sudo -n systemctl start "$SERVICE" || true
    elif [[ "$STOPPED" == 1 ]]; then
        sudo -n systemctl start "$SERVICE" || true
    fi
    exit "$result"
}
trap recover ERR

[[ ! -e "$PLUGIN" && ! -L "$PLUGIN" ]]
[[ -f "$ENVIRONMENT_FILE" ]]
[[ "$EXPECTED_SHA256" =~ ^[a-fA-F0-9]{64}$ ]]
printf '%s  %s\n' "$EXPECTED_SHA256" "$PACKAGE" | sha256sum --check
tar -xzf "$PACKAGE" -C "$RUN/release"
[[ -f "$RUN/release/redmine_ai_integration/init.rb" ]]
while IFS= read -r -d '' source; do
    ruby -c "$source" >> "$RUN/syntax.log" 2>&1
done < <(find "$RUN/release/redmine_ai_integration" -name '*.rb' -print0)
bundle check > "$RUN/bundle.log" 2>&1
sudo -n true
printf 'Preflight passed. Backup/deployment directory: %s\n' "$RUN"

sudo -n systemctl stop "$SERVICE"
STOPPED=1
bundle exec rails runner "$STAGING/backup_database.rb" "$RUN/backup/database.dump" "$PG_DUMP" > "$RUN/database-backup.log" 2>&1
"$PG_RESTORE" --list "$RUN/backup/database.dump" > "$RUN/backup/database-contents.txt"
tar -I 'gzip -1' -cf "$RUN/backup/config-plugins-attachments.tar.gz" -C "$APPLICATION" config plugins files Gemfile Gemfile.lock -C "$(dirname "$ENVIRONMENT_FILE")" "$(basename "$ENVIRONMENT_FILE")"
printf 'Database and application rollback backups completed.\n'

cp -a "$RUN/release/redmine_ai_integration" "$APPLICATION/plugins/"
INSTALLED=1
bundle exec rake redmine:plugins:migrate NAME=redmine_ai_integration > "$RUN/migration.log" 2>&1
bundle exec rails runner "$STAGING/inspect.rb" > "$RUN/inspection.json" 2> "$RUN/inspection-error.log"
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
printf 'Deployment completed. Evidence: %s\n' "$RUN"
cat "$RUN/inspection.json"
