# Operations

Plugin 1.0.0 was deployed to server 215 on 19 November 2026. Verified stack: Redmine 7.0.2.stable / Ruby 4.0.9 / Rails 8.1.4 / PostgreSQL 18.7. The existing ActiveJob async backend is unchanged; enhancement remains disabled with no API key or sources configured. Review the [deployment record](DEPLOYMENT-2026-11-19.md) and reverify versions before future deployments.

## Endpoints

All paths are relative to Redmine's configured sub-URI (if any):

| Endpoint | Method | Access |
|---|---|---|
| /admin/ai_enhancement | GET / POST | Administrator settings |
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
- OpenAI Responses API HTTPS connectivity and funded API account with selected-model access.
- Readable curated source roots on the server. Content is not fetched from workstation paths.

No additional production gems are installed by the plugin. The root Gemfile is for its isolated tests.

## Jobs and retention

Run from Redmine with its production environment loaded:

```sh
RAILS_ENV=production bundle exec rake redmine_ai:expire_stuck
RAILS_ENV=production bundle exec rake redmine_ai:purge
```

expire_stuck marks queued/processing sessions older than ten minutes failed. Only run after confirming their worker is no longer processing; the task is maintenance, not an automatic retry. purge deletes non-running sessions older than 30 days, including encrypted conversations; issue journals remain. Schedule these through existing operations tooling if desired. No schedule is installed automatically.

Database source failure does not stop wording enhancement, but warnings identify incomplete context. API/network/model/billing errors produce a failed session and no issue update. A missing worker leaves work queued. A concurrent issue edit produces conflict. Restart enhancement from the issue after correcting the cause.

## Rollback

Disable the plugin in Administration first. Drain/stop its default-queue work through the site's existing job operations. Remove its plugin directory and restart Redmine to remove UI/actions. Keep its table and Rails secret to preserve encrypted sessions. Reversing its migration deletes session data; do so only after backup and an explicit decision to remove that data. Applied issue changes remain in ordinary Redmine journal history and can be reviewed/restored through normal issue editing.
