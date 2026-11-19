# Settings and source setup — 1.1.0

## Model and API key

Administration → AI ticket enhancement offers a model dropdown. Save the key first, then Refresh models to load your account's text-model IDs. This is a GET /v1/models metadata request, not a paid text-generation probe. The list endpoint does not advertise structured-output capability; choose a suitable Responses/structured-output model. Fallback choices are the current GPT-6 text models, and an older stored choice remains visible.

Create a key at https://platform.openai.com/api-keys. Select the intended API project, create a secret key and copy it when first shown. Add API billing or credits at https://platform.openai.com/settings/organization/billing/overview. ChatGPT and API billing are separate. Enter the key in Redmine; do not put it in source definitions. A restricted key needs Responses write access, plus Models read access if using Refresh models.

Old enhancement instructions are ignored and removed on the next settings save. The plugin uses its built-in enhancement policy.

## Source forms

Add a named source, select Code folder / Documents folder / Database and assign one or more projects. Fields appear for the chosen type. A mapping authorizes enhancement users in those projects to receive retrieved context. Removing a row and saving removes the source; it does not delete server files or databases.

Folder paths are absolute server paths. Recursive discovery includes supported code/text extensions and excludes hidden folders, symlinks, dependency/build output, credential-related names and common application/bootstrap config files. Scanning is bounded: 500 eligible files per source, 20,000 entries, 2 MB/file and 10 MB shared read budget. PDF/Word need reviewed text exports. Changes are read at enhancement time; Test/reload verifies accessibility and reports counts.

Database forms collect type, host/IP, port, database/service, schema/owner, username and password. Passwords stay encrypted and blank in the rendered page. Blank retains the saved value only if the connection identity is unchanged; changing the target clears it unless a new password is supplied. Clear saved password explicitly removes it.

Primary/unique/foreign-key and column metadata is retrieved using fixed SELECTs. The SQL Server adapter has no role or replica restrictions and executes SELECTs only. PostgreSQL, Oracle and MySQL add read-only transaction controls. No source privileges/schema/data are changed.

## Optional table values

Enable Include table samples only for approved data. Add exact table names, comma-separated column names and row limits. Bounds: 1–10 tables, 1–20 columns each and 1–20 rows each, 500 characters/value. Identifiers are checked against the current schema metadata and quoted by engine. Do not include schema prefixes in table names; use the source's separate schema field. Oracle identifiers generally need uppercase unless the actual schema uses quoted names.

Test/reload reads approved samples as well as metadata. At enhancement time those samples may be sent to OpenAI as context for the source's mapped projects. No query results are logged. This is bounded sampling, not bulk export or unrestricted SQL execution.

## Native driver setup

PostgreSQL uses the existing pg gem. Other engines are optional. Add only required drivers to Redmine's existing Gemfile.local, preserving other declarations:

```ruby
gem 'ruby-oci8', '2.2.14', require: false
gem 'tiny_tds', '3.4.1', require: false
gem 'mysql2', '0.5.7', require: false
```

Install suitable client headers/libraries first, then run bundle install with the site's existing production bundle configuration. Oracle needs compatible Oracle client libraries and their runtime search path. Do not put credentials in Gemfiles, native-client configuration committed to Git, or source-control history. The connection form holds the credentials.

Reference driver documentation:
- https://github.com/kubo/ruby-oci8
- https://github.com/rails-sqlserver/tiny_tds
- https://github.com/brianmario/mysql2

A type selection does not silently install native software. Test/reload identifies missing drivers or connection problems without exposing credentials, raw errors or returned data.

## Checks and concurrency

Save before Test/reload. It enqueues AiSourceCheckJob on the existing default queue and shows queued/completed/needs-attention/failed state with per-source counts. Refresh the page for completion. The button is administrator-only and POST-only.

There is no network/file scan at startup, no semantic index and no paid model request in source tests. Old queued results cannot overwrite a changed source configuration: worker completion uses a settings-row lock, request token and configuration fingerprint. Changing source configuration invalidates saved results. The existing AsyncAdapter can lose queued checks on restart; rerun the button if needed.

The built-in retrieval context and source budgets still apply even if a source check passes. A successful connection test is not proof that every future SQL type/value or every model supports the desired workflow.

## Local verification

On the recorded Windows development workstation, tools/verify.ps1 uses the project's existing portable Ruby/gems, runs Ruby and dynamic-form tests, checks syntax, builds the package and validates archive entries. Use -InstallJavascriptTooling if the ignored jsdom test runtime is absent. Node 24.15+ is required by the pinned jsdom 31.0.1; neither is a production plugin dependency.
