# Deployment tooling

These tools are optional operator helpers, excluded from the deployable plugin archive. They require the existing server Python 3, Bash, Ruby/Bundler, tar/gzip, curl, PostgreSQL client tools and authorized sudo service-control access. No new plugin runtime dependency or external worker is added.

## Prepare and inspect

1. Run the plugin tests, build `ruby tools/package.rb`, review archive paths and record its SHA-256.
2. Choose a private staging directory owned by the Redmine service user (`0700`). Copy the archive and `tools/deployment/` helpers there using the site's authorized transfer mechanism.
3. Confirm application/service paths, service account, free space, existing plugins, Ruby/Rails/Redmine versions and the actual job backend. Run the deployment as the service's OS user. Do not replace an existing plugin without separately reviewing an upgrade plan; deploy.sh is an initial-install helper and refuses an existing plugin path.
4. The environment wrapper reads `/proc/PID/environ` plus an explicitly supplied systemd EnvironmentFile. Puma can erase its original process environment when changing its title, so the file is necessary for this installation. It accepts reviewed one-assignment-per-line values with shell-style quotes, without executing shell expressions or printing values. Unsupported multiline/unquoted-space syntax is rejected. It does not edit the existing environment file.

From the application directory, using reviewed values:

```sh
python3 "$STAGING/with_service_environment.py" \
    --environment-file "$SERVICE_ENVIRONMENT_FILE" "$MAIN_PID" \
    bundle exec rails runner "$STAGING/inspect.rb"
```

All database diagnostics in inspect.rb use an explicit read-only transaction. It reports versions/schema/state and booleans, not credentials or business records. Its harmless queue probe is only used for the in-memory AsyncAdapter; it makes no API request and does not change tickets.

## Initial installation

Refresh sudo authorization interactively before running the helper. Run it through the wrapper **while the existing Redmine service is alive**, so the command environment is retained while Redmine is stopped:

```sh
python3 "$STAGING/with_service_environment.py" \
    --environment-file "$SERVICE_ENVIRONMENT_FILE" "$MAIN_PID" \
    bash "$STAGING/deploy.sh" "$PACKAGE_SHA256" "$APPLICATION" "$STAGING" \
    "$SERVICE" "$PG_DUMP" "$PG_RESTORE" "$SERVICE_ENVIRONMENT_FILE" "$HEALTH_URL"
```

The deployment script's positional arguments are: reviewed package SHA-256; absolute application directory; private staging directory; existing service name; pg_dump executable; pg_restore executable; existing service EnvironmentFile; local login health URL. The archive must be named `redmine_ai_integration-1.0.0.tar.gz` under staging. PostgreSQL tools must match the database major version. The normal command should pass every argument; optional tool defaults are pg_dump/pg_restore, and the optional health default is localhost port 3000.

Before service downtime it checks package integrity, Ruby syntax, installed bundle and sudo availability. After stopping Redmine it creates a full custom-format database dump, validates its table of contents, and archives config/plugins/attachments/Gemfiles plus the existing service environment file. Backups are private; the environment file contains the Rails secret required for encrypted plugin state. pg_dump uses a consistent read-only snapshot and receives credentials only through its child environment. The credentials are never included in command arguments or generated scripts.

The script copies only the new plugin, runs only its migration, verifies loading, restarts the existing service and checks the local login endpoint. API credentials, project modules and role permissions are not changed. Inspect the public HTTPS endpoint and run the read-only verifier afterward. The helper does not replace the site's backup process or automatically prune backups.

## Failure and rollback

If a step fails, inspect the private run directory. The helper attempts to remove the newly added plugin from the app and restart Redmine. It retains any plugin migration table/registration already created; it never automatically drops tables or restores the entire database. Applied backups and diagnostic files remain private. If that automatic service recovery also fails, use the site's recovery process.

For a later manual rollback, first disable enhancement and drain jobs; stop Redmine, move only `plugins/redmine_ai_integration` to a reviewed private holding directory, and restart. Retain the plugin table and Rails secret. Restoring the full database is a separate explicit operation, since it would replace subsequent Redmine changes. Never delete another plugin or attachment directory as part of rollback.

`test/test_deployment_environment.py` tests the wrapper with synthetic inputs. Repository CI also checks the deployment shell syntax. The recorded production deployment was performed with reviewed server paths; the generic helper now takes these as arguments so environment-specific settings remain outside source code.
