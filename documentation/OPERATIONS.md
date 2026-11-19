# Operations

Plugin 1.1.3 is deployed to server 215 as of 19 November 2026. Verified stack: Redmine 7.0.2.stable / Ruby 4.0.9 / Rails 8.1.4 / PostgreSQL 18.7. All four source drivers load, the structured settings page renders, and its JavaScript is served. The existing async backend is unchanged. Enhancement is enabled with a saved API key and zero sources. At the latest inspection the model was gpt-6.2-sol with low reasoning effort. At the user's explicit request, the AI module is enabled in all 34 active projects and the AI permission in all five signed-in roles; Anonymous is excluded and existing issue visibility/edit requirements remain. Review the [deployment record](DEPLOYMENT-2026-11-19.md) and reverify versions before future deployments.

## Endpoints

All paths are relative to Redmine's configured sub-URI (if any):

| Endpoint | Method | Access |
|---|---|---|
| /admin/ai_enhancement | GET / POST | Administrator settings |
| /admin/ai_enhancement/refresh_models | POST | Administrator model-list refresh |
| /admin/ai_enhancement/reload_sources | POST | Administrator background source test/reload |
| /issues/:issue_id/ai_enhancements | POST | Create automatic or interactive enhancement |
| /issues/:issue_id/ai_enhancements/:id | GET | Owner's private session |
| /issues/:issue_id/ai_enhancements/:id/reply | POST | Owner's interactive revision |
| /issues/:issue_id/ai_enhancements/:id/apply | POST | Owner's interactive apply |

Ticket access and enhancement/edit permissions are required at each issue endpoint. No public API or database endpoint is exposed.

## Environment and dependencies

- REDMINE_AI_OPENAI_API_KEY: optional alternative to the encrypted admin key. A saved admin key takes precedence.
- Administrator-selected URL variables, for example REDMINE_AI_PAYMENTS_DATABASE_URL: PostgreSQL metadata sources only. Use protected existing service environment; never commit values.
- Existing Rails secret/key generator: encryption for credentials and sessions.
- Existing ActiveJob backend with default-queue workers: background enhancement.
- Existing pg gem: required only for live PostgreSQL metadata sources. Redmine on PostgreSQL already supplies it.
- Optional ruby-oci8, tiny_tds and mysql2 client gems for the matching source types; they must be available in Redmine's bundle. See [driver setup](SETTINGS.md).
- Oracle client ORACLE_HOME / LD_LIBRARY_PATH in the existing service environment if required by its native client. These are library paths, not connection credentials.
- OpenAI Responses API HTTPS connectivity and funded API account with selected-model access.
- Readable curated source roots on the server. Content is not fetched from workstation paths.

No additional production gems are installed by the plugin. The root Gemfile is for its isolated tests.

Version 1.1.0 uses structured source forms, a model dropdown and explicit Test/reload rather than startup scanning. Database credentials are encrypted in plugin settings. Optional table samples default off and require explicit tables/columns/row limits. PostgreSQL/Oracle/MySQL use read-only transaction controls; SQL Server executes SELECT-only queries with no role/replica restrictions. The operator installs any required optional native client gems; the plugin does not install them from web requests.

AiSourceCheckJob uses the default queue and does not call OpenAI. It records only statuses/counts, not source contents or sample rows. Changing source settings invalidates old results; token/fingerprint checks plus a settings-row lock prevent late results from replacing newer configuration. A lost async job can leave a queued check; use Test/reload again. Enhancement instructions have been removed from configuration and older saved guidance is ignored.

## Jobs and retention

Run from Redmine with its production environment loaded:

```sh
RAILS_ENV=production bundle exec rake redmine_ai:expire_stuck
RAILS_ENV=production bundle exec rake redmine_ai:purge
```

expire_stuck marks queued/processing sessions older than ten minutes failed. Only run after confirming their worker is no longer processing; the task is maintenance, not an automatic retry. purge deletes non-running sessions older than 30 days, including encrypted conversations; issue journals remain. Schedule these through existing operations tooling if desired. No schedule is installed automatically.

Database source failure does not stop wording enhancement, but warnings identify incomplete context. API/network/model/billing errors produce a failed session and no issue update. A missing worker leaves work queued. A concurrent issue edit produces conflict. Restart enhancement from the issue after correcting the cause.

### OpenAI HTTP 429

Version 1.1.3 classifies allowlisted OpenAI error.code/error.type values into fixed messages for exhausted credits, insufficient quota, organization/project spend limits, approved usage limits, request/token rate limits and slow ramp-up. Unknown/malformed responses produce a generic credits/limits message. Remote error messages, raw response bodies, headers and credentials are never displayed or logged. There is no automatic retry; a failed request does not apply a draft.

Check API organization billing/credit balance and the key's project/organization limits. A ChatGPT subscription and an authenticated models-list request do not establish that inference quota is funded or available. Model rate limits can also include token limits, even for a single request. Billing/quota errors require correcting the account limit/balance rather than repeated retries. For genuine temporary rate limits, wait before starting another enhancement. See [official error guidance](https://developers.openai.com/api/docs/guides/error-codes) and [API billing](https://platform.openai.com/settings/organization/billing/overview).

Old failed sessions retain their original message; response bodies were deliberately not persisted, so their exact remote cause cannot be reconstructed. After correcting the cause, start a new enhancement. Never paste API keys into tickets, logs or documentation; replace exposed keys through the protected settings form.

## Rollback

Disable the plugin in Administration first. Drain/stop its default-queue work through the site's existing job operations. Remove its plugin directory and restart Redmine to remove UI/actions. Keep its table and Rails secret to preserve encrypted sessions. Reversing its migration deletes session data; do so only after backup and an explicit decision to remove that data. Applied issue changes remain in ordinary Redmine journal history and can be reviewed/restored through normal issue editing.
