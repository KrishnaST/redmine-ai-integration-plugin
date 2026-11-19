# Redmine AI Integration

Version 1.1.3. Source-backed automatic and interactive ticket enhancement for Redmine 7.0 / Ruby 4 / Rails 8.1.

Existing issues expose **Edit with AI** beside the normal **Edit** action (interactive questions, revisions and Apply). **Enhance with AI** below the issue details improves and saves editable textual fields automatically with a journal. Status, assignee, priority, dates and non-text workflow fields retain their values. Users need issue-edit and enhancement permissions, and the project module must be enabled.

The plugin calls OpenAI directly from Ruby using the existing ActiveJob default queue. There is no separate AI service.

## Configure in Redmine

Open **Administration → AI ticket enhancement**.

1. Enter the OpenAI API key and save. Blank retains the encrypted key; Remove saved key clears it.
2. Select a **Model** from the dropdown. **Refresh models** retrieves text-model IDs available to the saved key; use a model supporting Responses and structured output. The default choices are GPT-6.2 Astra, GPT-6.2 Sol, GPT-6.1 Terra and GPT-6 Luna. A stored older model remains selectable.
   Select **Reasoning effort** beside the model: Model default, Light, Medium, High, Extra High or Ultra. Model default omits the API parameter and preserves existing behavior. Other levels map to low, medium, high, xhigh and max; supported levels depend on the model. Higher effort may increase token usage and processing time.
3. Add **Code folder**, **Documents folder** or **Database** sources with the structured controls. No raw JSON or enhancement-instructions field is shown.
4. Assign each source to specific projects. These mappings grant enhancement users in those projects access to retrieved excerpts, including approved table samples.
5. Save, then click **Test/reload sources**. This checks current files, schema metadata and opted-in samples in a background job without calling OpenAI. Results show success/failure and counts. Refresh the page for completion.
6. Enable the integration. In each participating project enable **Redmine AI Integration**, then grant the role **Enhance issues with AI** alongside **Edit issues**.

There is no scan at Redmine startup. Enhancement requests read the current sources; Test/reload verifies them rather than building a semantic/vector index. Changed source configuration invalidates previous check results.

If the buttons are absent, enable **Redmine AI Integration** under the project's **Settings → Modules** and grant **Enhance issues with AI** plus **Edit issues** to the appropriate member roles under **Administration → Roles and permissions**. The global Enabled setting alone does not grant project access. The issue toolbar action is placed by the plugin's own JavaScript; without JavaScript, Edit with AI remains below the issue details. Redmine core views are unchanged.

### API key

Create a key in an OpenAI API project at [API keys](https://platform.openai.com/api-keys), copy it when shown, and paste it directly into the plugin's password field. Full secret values are only displayed at creation. Configure API billing separately from ChatGPT. The key needs Responses access; Refresh models additionally needs model-list access.

- [Official key guidance](https://help.openai.com/en/articles/4936850-where-do-i-find-my-openai-api-key)
- [API billing](https://platform.openai.com/settings/organization/billing/overview)
- [Billing separation](https://help.openai.com/en/articles/9039756-managing-billing-for-chatgpt-and-the-api-platform)

An optional existing service environment variable, REDMINE_AI_OPENAI_API_KEY, remains supported. The encrypted administrator key takes precedence.

## Technical sources

**Folders:** enter absolute paths on the Redmine server, not workstation paths. Supported UTF-8 text/code files are discovered recursively. Hidden directories, symlinks, build/dependency outputs, credential-related names and common application/bootstrap credential configuration files are excluded. Limits: 500 eligible files per folder, 20,000 traversed entries, 2 MB per file, and a 10 MB shared file-read budget per enhancement/check. PDF/Word/binary documents need reviewed text exports. Use approved source folders without secrets or personal data; filename exclusions are not a complete data-classification system.

**Database:** select PostgreSQL, Oracle, Microsoft SQL Server or MySQL, then enter IP/hostname, port, database (Oracle service name), schema/owner, username and password. Passwords are encrypted using Redmine's existing secret and never redisplayed. A blank password retains it only while connection identity stays unchanged. Changing its address/type/database/user clears the retained password unless a new one is entered.

Adapters retrieve column types/nullability/size and primary/unique/foreign-key metadata. Queries are application-defined SELECTs, never AI-generated SQL. PostgreSQL, Oracle and MySQL also use read-only transaction controls. SQL Server executes SELECT statements only, with no role/replica restriction, as explicitly requested. No DDL, DML, login changes or privilege changes are performed on source databases.

**Include table samples** is off by default. If enabled, explicitly list 1–10 tables, their 1–20 allowed columns, and 1–20 rows per table. Exact identifiers are checked against freshly read schema metadata before sampling. Values are limited to 500 characters at query time. These approved samples become AI context for the mapped projects; query results are not written to diagnostic logs. Sampling is bounded and unordered, not a full table export. Use exact identifier case; Oracle names are commonly uppercase.

### Driver prerequisites

| Engine | Ruby driver | Native prerequisites |
|---|---|---|
| PostgreSQL | pg (already supplied by a PostgreSQL Redmine installation) | libpq |
| Oracle | ruby-oci8 | Oracle client libraries/headers; compatible runtime library path |
| SQL Server | tiny_tds | FreeTDS libraries/headers unless supplied by a compatible binary gem |
| MySQL | mysql2 | MySQL/MariaDB client libraries/headers |

Optional source drivers must be declared in Redmine's existing Gemfile.local and installed into its bundle. They are not mandatory for wording-only enhancement. Current reviewed versions: ruby-oci8 2.2.14, tiny_tds 3.4.1, mysql2 0.5.7; native compatibility must be verified on the target Ruby/client stack. See [settings and driver setup](documentation/SETTINGS.md). Missing drivers are reported by Test/reload; selecting a type alone does not install system software.

Existing explicit-file and environment-URL PostgreSQL source definitions remain readable/editable for compatibility. Remove and replace a legacy source to use the new discrete connection fields.

## Reliability and privacy

Keys and database passwords are encrypted using Redmine's existing secret. Enhancement drafts, conversations and citation metadata are encrypted in ai_enhancements.payload. Selected ticket fields, conversation and retrieved source excerpts/samples are sent to OpenAI with store:false; account data-retention terms still apply. Connection credentials are excluded from evidence and prompts.

Only the initiating user can access an enhancement session, with current issue visibility/edit and enhancement permissions rechecked. Apply locks the session and issue, checks the original fingerprint, validates field names and citations, then uses Redmine's safe-attribute/journal APIs. Concurrent edits are preserved. AI calls occur outside database transactions. No generated SQL is executed.

Retrieval uses bounded keyword matching of 40-line passages, not exhaustive code analysis. Context is limited to 32,000 characters and 4,000 characters per excerpt. Missing/unreadable sources produce warnings; unsupported AI output fails without changing the issue. Fixed built-in instructions preserve facts and label unknowns; administrator enhancement instructions have been removed and old saved values are ignored.

The existing ActiveJob backend must process the default queue. AsyncAdapter is suitable for evaluation but loses in-memory work on restart; durable production jobs remain an infrastructure decision. Maintenance tasks and failure handling are documented in [operations](documentation/OPERATIONS.md).

## Installation and updates

Target: server 13.127.209.215, application /home/idsspl/redmine/native, service redmine-native.service. Version 1.1.3 is deployed; the initial installation and subsequent upgrades are recorded in [deployment evidence](documentation/DEPLOYMENT-2026-11-19.md).

Build with ruby tools/package.rb. The production archive dist/redmine_ai_integration-1.1.3.tar.gz contains only init.rb, app/, assets/, config/, db/ and lib/, under the required folder redmine_ai_integration. For a source checkout, copy those same production paths into plugins/redmine_ai_integration; do not copy the test Gemfile or development runtime.

Back up the existing app/database, replace the plugin's production files, run the plugin migration task from the Redmine root, publish/precompile plugin assets using the site's normal Redmine asset procedure, and restart Redmine:

```sh
RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=redmine_ai_integration
```

Version 1.1.0 adds no database migration beyond the existing enhancement-session table. Settings compatibility is retained. No API key, source mapping, project membership or role permission is automatically enabled by installation.

## Development

```sh
bundle install
bundle exec ruby test/test_controllers.rb
npm install --prefix tools/runtime/javascript --cache tools/runtime/npm-cache --no-audit --no-fund --package-lock=false jsdom@31.0.1
node test/test_settings_js.cjs
python -m unittest discover -s test -p test_deployment_environment.py
ruby tools/package.rb
```

The Ruby harness uses real Rails 8.1.4 persistence/controllers/jobs with SQLite and Redmine interface doubles; API and adapter calls are simulated. The JavaScript test uses a rendered form and jsdom; jsdom/Node/Python are development/deployment tooling only, excluded from the plugin package. Native database connectivity and paid API responses require real configured credentials. CI runs these checks. Commits/pushes are authorized for this repository; production rollout uses the recorded deployment process.

See the [documentation index](documentation/README.md).
