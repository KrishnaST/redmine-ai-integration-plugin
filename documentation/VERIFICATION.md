# Verification — 19 November 2026

Tested locally with portable Ruby 4.0.9, Rails ActiveRecord/ActiveJob/ActionPack 8.1.4 and in-memory SQLite. Standalone test command: `bundle exec ruby test/test_controllers.rb`.

Latest passing run: **32 tests, 130 assertions, zero failures/errors/skips**. Controller tests inherit model/job cases and also run the independent base test class; the count includes those repeated model cases. Tests exercise migration and foreign keys, encrypted payload/API-key roundtrip, automatic apply, interactive draft-only behaviour, repeated-job guards, permission revocation, concurrent-edit rejection, output schema/field/citation validation, file retrieval and project scoping, blocked credential filenames, mocked PostgreSQL read-only transaction/rollback/disconnect, inline citation validation, HTTP response-body handling, incomplete model output, owner-only sessions, routes, settings forms and rendered interactive ERB.

OpenAI HTTP calls are simulated. No real API key or paid request is used. Redmine-specific permission/custom-field APIs use small interface doubles. A production bundle, theme and real Redmine request lifecycle have not been exercised by this harness. PostgreSQL metadata connectivity and SSL settings require testing against the configured metadata account. The plugin uses read-only fixed metadata queries, with no generated SQL or application data reads.

## Staging acceptance

1. Verify Redmine/Ruby/Rails versions and install the plugin under the exact registered folder name. Apply only its session-table migration to the staging Redmine database.
2. Enable the module on a test project, give one role edit/enhance access, and verify other users/projects cannot access the actions or another user's session.
3. Configure a funded API key and an available model. Confirm a valid response using a non-sensitive example ticket.
4. Add one reviewed document/code file and verify the generated citations identify the correct revision and lines. Verify a project without the mapping cannot retrieve it.
5. Configure a dedicated PostgreSQL metadata role. Verify read-only transaction execution, query timeouts, schema scoping and connection cleanup. Use DDL exports for other engines.
6. Click automatic enhancement and verify all permitted text fields update and the issue journal records the change. Check read-only workflow/custom fields retain their values.
7. Click interactive enhancement, answer questions through two revisions, and apply. Test CSRF rejection, invalid API key, source outage, an intervening issue edit and lost permission.
8. Confirm the real job worker, error handling and maintenance tasks. Test both the configured root and any reverse-proxy sub-URI. Verify backup/restore includes the Rails secret for encrypted drafts.

No deployment, server migration, Redmine restart or live ticket modification was performed during this implementation.
