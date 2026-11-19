# Redmine AI Integration

Source-backed automatic and interactive ticket enhancement for Redmine 7.0 / Ruby 4 / Rails 8.1. Version 1.0.0.

After a ticket is created, permitted users see **Enhance with AI** and **Enhance with AI Interactively** in the issue details.

- **Enhance with AI** retrieves configured context, improves every editable textual ticket field, and saves automatically with a Redmine journal. No confirmation or answers are needed after clicking.
- **Enhance with AI Interactively** generates a draft and targeted questions. Users supply answers, facts and instructions, request revisions, then apply the draft.
- Subject, description and editable single-value string/text custom fields are supported. Workflow-controlled values such as status, priority, assignee, dates and numeric/list custom fields retain their values; an AI wording change does not imply authorization to change workflow or ownership. Existing journal history is retained.
- Administration → **AI ticket enhancement** configures the model, encrypted API key, enhancement instructions and project-scoped sources.

The Ruby plugin calls the OpenAI Responses API directly. No separate Java service is required. It uses Redmine's existing Rails/ActiveJob and PostgreSQL driver; the root Gemfile is **test tooling only**, not a production plugin Gemfile.

## Install on the existing server

Recorded target: `13.127.209.215`, application `/home/idsspl/redmine/native`, service `redmine-native.service`. Live installation has not been modified by this implementation.

1. Back up the Redmine database and attachment/configuration directories using the site's normal procedure.
2. Clone the repository **outside** Redmine's plugin folder, then copy `init.rb`, `app/`, `config/`, `db/` and `lib/` into `plugins/redmine_ai_integration/`. Alternatively extract the packaged `.tar.gz` into `plugins/`. The directory must be named `redmine_ai_integration`.
3. From the Redmine application root, with its existing production environment loaded:

   ```sh
   RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=redmine_ai_integration
   ```

4. Restart Redmine. A plugin migration creates only its encrypted enhancement-session table; it does not alter business application schemas.
5. Open Administration → AI ticket enhancement, configure an API key and available Responses API model, add source definitions, and enable the integration.
6. In each participating project enable the **Redmine AI Integration** module. Grant the **Enhance issues with AI** role permission alongside edit-issues permission.
7. Ensure Redmine's ActiveJob backend/worker processes the `default` queue. An in-process async backend is suitable for evaluation but jobs can be lost on process restart; use the site's durable job backend for production. The plugin does not change the existing backend.

Outbound HTTPS to `api.openai.com:443` is required. API usage is billed to the configured OpenAI API account. No API key is included in this repository.

## Configure sources

Sources JSON is managed in Administration. Each source requires an explicit list of numeric Redmine project IDs. Users with enhancement permission in those projects can receive source excerpts through generated tickets, so each mapping grants access to that knowledge.

```json
[
  {
    "name": "payments_docs",
    "type": "files",
    "project_ids": [1],
    "root": "/srv/redmine-ai/docs",
    "files": ["payments.md", "operations.txt"],
    "revision": "2026-11-19"
  },
  {
    "name": "payments_code",
    "type": "files",
    "project_ids": [1],
    "root": "/srv/redmine-ai/code",
    "files": ["src/PaymentService.java"],
    "revision": "verified-git-commit-sha"
  },
  {
    "name": "payments_schema",
    "type": "postgres_schema",
    "project_ids": [1],
    "url_env": "REDMINE_AI_PAYMENTS_DATABASE_URL",
    "schema": "payments"
  }
]
```

File roots refer to the **Redmine server**, not the administrator's workstation. Use reviewed UTF-8 documentation, code and DDL exports. Files are explicitly listed; traversal/symlink escapes, binary files, files over 2 MB and credential-related filenames are excluded. PDF/Word inputs require reviewed text exports. No automatic repository clone, arbitrary URL fetching, recursive crawling or private repository credentials are used. Update the server-side checkout/files and revision when a release changes. References include file/line ranges and SHA-256 hashes.

File scanning is bounded to 10 MB per enhancement across all file sources; exceeding the budget produces a source warning. Retrieval ranks 40-line passages by ticket/conversation keyword overlap, then supplies at most 32,000 characters, with at most 4,000 characters per passage. It is a bounded lexical retrieval implementation, not an exhaustive code analyzer or semantic index. No matching sources means wording enhancement uses the ticket facts alone; an unreadable configured source produces a warning. Automatic updates record these warnings in the issue journal.

PostgreSQL live sources retrieve columns/types/nullability/size and primary/unique/foreign-key definitions in an explicit read-only transaction with connection and statement timeouts. Use a dedicated metadata-only login in the configured URL environment variable. Business records, generated SQL and database writes are unsupported. Oracle/MSSQL can supply authoritative schema exports as file sources; native live adapters are not included in 1.0. No operational database access is required to improve wording alone.

## Credentials and storage

API keys entered through the administrator form are encrypted using a key derived from Redmine's existing secret. Blank input retains the saved key; removal clears it. Alternatively use `REDMINE_AI_OPENAI_API_KEY` in the existing protected service environment. Database URLs are referenced through administrator-selected environment variable names; do not put credentials in Sources JSON.

Enhancement conversations, draft output and source references are encrypted at rest in `ai_enhancements.payload`. Losing/changing the Rails secret prevents decryption. Successful applied ticket content and journal evidence are normal Redmine data with the issue's existing access rules. Selected ticket fields, conversation and retrieved excerpts are sent to OpenAI with `store:false`; that flag does not override the API account's applicable data-retention policy.

Sessions are visible only to the initiating user and require current issue visibility/edit rights. Authorization is checked on requests, job execution and apply. CSRF protection is inherited from Redmine; all mutations use POST. The API endpoint is fixed HTTPS. No remote response bodies, source contents, API keys or raw database error messages are written to plugin diagnostic logs.

## Reliability and behaviour

Jobs call OpenAI outside database transactions. Apply locks the enhancement and issue, validates output field names and source IDs, rechecks permissions and the original issue fingerprint, and uses Redmine's safe attributes and journal APIs. If the issue changed, the enhancement is blocked instead of overwriting newer edits. A successfully applied job cannot apply again.

Output uses strict JSON Schema and application validation; refused, incomplete, oversized or invalid API responses fail without changing the ticket. Evidence is untrusted data. Prompts instruct the model to distinguish facts, hypotheses and unknowns, and prevent unsupported technical claims. Citations identify supporting excerpts but are not proof that every generated statement is correct. Interactive enhancement is appropriate when missing facts require reporter input.

The status page refreshes while work is queued/processing. A failed/conflicting enhancement can be restarted from the issue buttons. Concurrent active enhancements are rejected for ten minutes. Jobs interrupted by process termination can remain queued/processing; they are not automatically replayed. Review/clean them using the maintenance tasks in [operations](documentation/OPERATIONS.md).

## Development and verification

```sh
bundle install
bundle exec ruby test/test_controllers.rb
```

The standalone harness exercises real Rails 8.1.4 persistence, migration, encryption, jobs, routes/controllers and ERB views with in-memory SQLite and Redmine interface doubles. OpenAI calls are simulated; tests make no paid API request or live database connection. Native Redmine deployment, theme rendering, installed job-backend behaviour and real API/database connectivity require staging verification. See [documentation index](documentation/README.md).

Use `ruby tools/package.rb` to create a deployable `.tar.gz` from production files only. A GitHub Actions workflow runs tests on pushes/PRs. The user has authorized commits/pushes for this repository; deployment remains a separate operation.
