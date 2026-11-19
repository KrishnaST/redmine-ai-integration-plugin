# Server 215 deployment — 19 November 2026

## Initial 1.0.0 installation (superseded by 1.1.0 below)

- Server: 13.127.209.215; portal: https://redmine.dynamicbanksoft.com/.
- Application: `/home/idsspl/redmine/native`; service: `redmine-native.service`, running as idsspl.
- Plugin folder: `plugins/redmine_ai_integration`; version 1.0.0, production files from commit ca01107.
- Package SHA-256: `096f53daf4932ef295f8a5560986eed8b4eef0966ebc715a465b04ad7932d30d`.
- Verified stack: Rocky Linux 9.8, Redmine 7.0.2.stable, Ruby 4.0.9, Rails 8.1.4, PostgreSQL 18.7.
- Service restarted successfully at **2026-11-19T12:38:26+05:30**.
- Existing plugins unchanged: redmine_backup_plugin 0.5.0 and redmine_microsoft365_smtp 2.0.3.

## Backups and evidence

Private server directory:

`/home/idsspl/redmine/ai-integration-deployment/20261119T070724Z/`

It contains the pre-deployment database dump (about 281 KiB), validated database table-of-contents listing, and config/plugins/attachments/Gemfiles/service-environment archive (about 607 MiB). The existing Rails secret is included in the private environment-file archive; no secret values are in this repository. It also retains migration output, read-only inspection JSON, bundle/syntax checks and the executed deployment script. The generic reusable helper now takes deployment paths as arguments; its original executed copy remains in the private evidence directory.

## Verified

- Local plugin tests: 32 tests / 130 assertions, no failures/errors/skips. Deployment environment parser: four tests passed.
- Package integrity and all package entry paths checked before installation.
- Database session-table migration completed, including issue/user foreign keys and the ownership index.
- Service active; local and public login HTTP 200; unauthenticated AI admin route HTTP 302.
- Both plugin controllers load under the actual production Rails stack.
- Encryption roundtrip succeeds with the existing Rails secret.
- Plugin jobs use the default queue. A harmless in-memory queue probe ran in the production Rails runner process.
- Zero enhancement sessions; no paid OpenAI request, source-database connection or live issue enhancement was performed.

## Remaining setup

Integration is **disabled**, API key is absent, and sources count is zero. Configure these at `/admin/ai_enhancement`, then explicitly enable selected project modules and grant the enhancement role permission. No project memberships, roles, notification settings, gateway configuration or workflow values were changed during deployment.

The existing backend remains `ActiveJob::QueueAdapters::AsyncAdapter`. Its in-memory jobs are not durable across process restarts. Production durable-worker adoption is a separate infrastructure change. A real browser-driven enhancement, real OpenAI response and real source retrieval remain unverified until credentials and project sources are configured.

## Structured settings upgrade to 1.1.0

The configuration update was deployed and the service restarted at **2026-11-19T13:44:01+05:30**. Rollback material is under:

`/home/idsspl/redmine/ai-integration-deployment/settings-upgrade-20261119T081252Z/`

It includes the previous plugin, database/config/plugin/bundle/environment backup, migration and asset-build logs, and private verification JSON. No additional plugin migration was needed. The settings page renders a model dropdown, structured code/document/database sources and table-sample controls; enhancement instructions and raw source JSON controls are absent. Its fingerprinted settings JavaScript and public login both return HTTP 200.

Installed optional drivers load on Ruby 4.0.9: pg 1.6.3, ruby-oci8 2.2.14, tiny_tds 3.4.1 and mysql2 0.5.7. Six new small FreeTDS/MariaDB client packages were installed without upgrading existing OS packages. Gemfile.local contains optional require:false declarations. Oracle client libraries/headers plus timezone/NLS resources are copied into the app's private vendor/redmine-ai-oracle-client-19 directory because the Oracle database home's client libraries are owner-readable only. The original Oracle home permissions/files are unchanged. ORACLE_HOME and LD_LIBRARY_PATH are scoped to Redmine's existing private service environment. Native dependency setup backups/logs are in sibling source-drivers-* directories; they contain protected configuration and are not committed.

A live PostgreSQL adapter probe retrieved **61 tables / 462 columns**, with read-only metadata queries and **zero sample rows**. A real empty-source Test/reload job completed and persisted its completed state. Other engine drivers were loaded, but no Oracle/SQL Server/MySQL source connection or sample-data query was attempted because no source credentials/configuration were supplied. API calls remain untested and no paid generation was requested. No live tickets, project access or issue workflow values were changed.

## Reasoning dropdown upgrade to 1.1.1

Deployed on 19 November 2026. The native configuration view renders the reasoning dropdown with Model default, Light, Medium, High, Extra High and Ultra. Service health returned active and the local login returned HTTP 200. Model default omits reasoning.effort; selected levels map to low, medium, high, xhigh and max for both enhancement modes.

Package SHA-256: `13acbc2186c2bf813acfa2577f2e6650ffae06515fb88197d064fbc9abdc94f8`. Private rollback material, migration/asset logs and native verification are under `/home/idsspl/redmine/ai-integration-deployment/settings-upgrade-20261119T083815Z/`.

By this upgrade the operator had saved an API key and enabled the integration. Both settings were preserved, along with project access and zero configured sources. All four driver versions remain unchanged. No additional database migration was needed and no live ticket or OpenAI request was used for verification. Local checks passed 65 Ruby tests / 332 assertions, 13 JavaScript assertions and four deployment-helper tests.

## Edit with AI action upgrade to 1.1.2

Deployed on 19 November 2026, with rollback material and native verification under `/home/idsspl/redmine/ai-integration-deployment/settings-upgrade-20261119T084707Z/`. Package SHA-256: `4ef2953b4c237c7a4cab6dd67bd3317759756fe6932c2d112073b7d5cad3df22`.

The interactive action is named Edit with AI and is placed immediately after the normal Edit link by the plugin's own issue_actions asset. Automatic Enhance with AI remains below the issue details. No Redmine core view is overwritten; a missing toolbar or disabled JavaScript leaves the interactive link below the details. The link keeps its interactive POST behavior and original authorization.

Read-only inspection found zero projects/roles enabled for AI, explaining the hidden buttons. The user then explicitly requested access for all users. A separate authorized transaction enabled the AI module in all **34 active projects** and added only the AI permission to all **five signed-in roles**, including Non member. Anonymous was excluded. The permission registration now allows signed-in users, while the policy still requires existing issue visibility/edit access. No issue-edit privileges, memberships or issue records were changed. A private pre-change role/module inventory is in `ai-access-before.json` in that rollback directory. Future projects/roles are not automatically enrolled.

The service restarted successfully, and local/public login and the fingerprinted issue-action asset returned HTTP 200. Native rendering after the access change verified the interactive POST action on an actual permitted issue in a read-only transaction. Local checks passed **68 Ruby tests / 357 assertions**, **13 settings-form assertions**, **nine issue-action DOM assertions** and **four deployment-helper tests**. No paid OpenAI request was used for verification.

## Safe HTTP 429 diagnostics upgrade to 1.1.3

Deployed on 19 November 2026. Private rollback/config/database backup and native verification: `/home/idsspl/redmine/ai-integration-deployment/settings-upgrade-20261119T090016Z/`. Package SHA-256: `9c0090ff7a356c5f578d689dc4510da3ebb5450e7cfe4a6c5d9a135bc2e750c2`.

Read-only inspection found one enhancement attempt in the preceding hour, failed with HTTP 429. Its raw error body was never persisted, so the specific historical quota/rate-limit cause could not be recovered. A single non-generating GET /v1/models check authenticated successfully and confirmed the selected model is listed. The supplied credential matched the encrypted saved credential; no credential values were logged, committed or added to files by the check. A successful models-list request does not verify inference credits or rate-limit capacity.

New failures are classified using only allowlisted error codes/types and fixed messages. No raw remote message/body/header is displayed or logged; no automatic retry was added. Existing failed-session messages remain unchanged. Native version/settings/action rendering and all four driver loads passed; the service is active and local/public login returned HTTP 200. Existing model, low reasoning effort, saved key and 34-project/five-role access settings were preserved. No paid inference or live ticket modification was performed. Local verification passed **73 Ruby tests / 436 assertions**, **22 JavaScript assertions** and **four deployment-helper tests**.
