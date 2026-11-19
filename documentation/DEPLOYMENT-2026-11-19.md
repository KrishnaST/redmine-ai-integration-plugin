# Server 215 deployment — 19 November 2026

## Installed state

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
