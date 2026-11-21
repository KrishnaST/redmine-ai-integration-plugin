# Code with AI — 1.3.0

## Configure access and an editable checkout

1. Open Administration → AI ticket enhancement. Under **Code with AI access**, select the member roles allowed to generate, inspect, download and apply code proposals. Save configuration. Administrators remain eligible; no other role is selected by default. This does not add issue visibility/edit privileges or memberships.
2. Add a **Code folder** technical source, assign the projects allowed to use it, and check **Allow reviewed code changes**. Existing sources default to read-only. Use an explicitly approved, dedicated source checkout on the Redmine server that the service account owns and can write. Documents/database sources cannot be write targets.
3. Save and run **Test/reload sources**. The opt-in code root must be a real, readable/writable directory. Redmine's own application directory, its children/ancestors and standard Unix system directories are blocked. Source/database credentials and excluded configuration files are not editable.
4. Open an existing issue you can view/edit. The toolbar shows **Edit → Edit with AI → Code with AI** for eligible users. A missing native toolbar leaves plugin actions below issue details. Anonymous users are excluded.

The role selection is project-role based. A user must have a selected role in that issue's project, in addition to existing edit/enhancement access. Selecting a role does not grant it in other projects. Removing the role/source option prevents subsequent use/Apply.

## Generate, review and apply

Code with AI queues a private code session using the ticket's editable textual fields, project-mapped technical evidence and matching complete code files. The plugin selects up to eight files by bounded keyword/path matching, not semantic indexing. Add concrete filenames, class names or identifiers to the ticket when discovery is insufficient.

The separate review page shows an implementation summary, questions, explanations and a whole-file unified diff. Download proposed patch is available without writing code. Use Revise code with AI to clarify the implementation; each revision creates a complete new proposal from current files. Prior proposals are conversation context, not already-applied changes.

**Apply code changes** replaces only the reviewed existing files in the opted-in checkout. It does not change the ticket's subject, description, status, assignee or other workflow values. A normal issue journal records the operation, source-relative paths and resulting SHA-256 hashes. Native Redmine notifications may be emitted by that journal save. Generate/download does not write code or change tickets.

Nothing automatically builds, runs tests, executes code/scripts/SQL, adds dependencies, commits, pushes, restarts services or deploys. Review the code and run your normal development verification and release process afterwards. A generated proposal does not establish correctness. No live write capability is configured by installation.

## Supported changes and bounds

- Existing UTF-8 source/text files only, in the existing source extension allowlist. File creation, deletion, moves, binary edits and unlisted file paths are not supported in this first version.
- At most eight captured files / 96,000 bytes of source context, 32,000 bytes per file, five changed files and 96,000 bytes of revised content. Discovery retains the existing 500-file / 20,000-entry / 10 MB scan limits.
- Relative editable paths use letters, digits, underscores, dots, slashes and hyphens. Hidden, traversal, credential-related, dependency/build output and unsupported files are excluded. Symlinks/hardlinks are rejected.
- Apply requires existing files owned by the Redmine process identity, writable files and writable parent directories. Do not grant blanket permissions to deployed application trees to satisfy this requirement. Use a dedicated checkout.
- The model returns known file IDs and full revised file content, never filesystem paths or executable tool calls. Output schema, IDs, uniqueness, UTF-8/size bounds and evidence citations are validated before accepting a draft.
- Code requests share the configured model/reasoning effort and HTTP timeout, with a 12,000-output-token cap and 400,000-byte serialized-input cap. Long revisions may need a new session. Ticket enhancement keeps its existing 8,000-output-token cap.

Sources and code may contain confidential information. Approved matching code content and source excerpts are sent to the configured OpenAI API account. Existing filename exclusions do not detect every inline secret; curate the checkout before mapping it.

## Apply safety, backups and interrupted operations

Apply rechecks the requester, selected role, source configuration/project mapping, ticket fingerprint and exact file hashes. Changed sources/files block Apply rather than silently overwriting them. The plugin takes cooperating-writer locks for target paths and rechecks bytes immediately before replacement and before the ticket journal commit.

Before writing any file, the session is persisted as **applying** and an encrypted before/after recovery inventory is written and fsynced under:

`<Redmine attachment storage>/ai-code-recovery/<session-id>-<operation-token>.encrypted`

The directory is private (0700 on Unix), files are 0600, and encryption uses Redmine's existing secret. Normal Redmine attachment download routes cannot discover these files. Keep this directory and the Rails secret in application backups. No code content is emitted in logs or journal notes.

Each file is written to a temporary file beside its target, fsynced, assigned the original basic file mode and renamed. Multi-file filesystem operations and a database transaction cannot be made fully atomic together. On a caught failure, written files are restored **only if they still contain this attempt's output**. An external edit is preserved, and the session stays applying with an operator-recovery warning. Unexpected process/server termination can also leave applying state; the plugin never retries these operations automatically. New sessions on that ticket are blocked, and purge excludes applying sessions.

OS renames, ACLs, ownership and filesystem durability differ by platform. The service account must own the files; advanced ACL/extended-attribute preservation is not promised. Other tools/editors do not honor the plugin's locks, so do not edit or deploy the same checkout during Apply. Path/hash checks reduce accidental races but are not a security boundary against a hostile process running as the same OS user.

For an interrupted apply, stop concurrent writers and have an administrator inspect the session and encrypted inventory through a trusted Rails console. Decrypt using `RedmineAi::Configuration.encryptor.decrypt_and_verify(File.binread(reviewed_inventory_path))`. Do not print decrypted contents into shared logs. Compare each current hash with the recorded before/after values, preserve external edits, and restore only explicitly reviewed files. Reconcile the issue journal/session state after recovery; do not simply mark an unresolved session applied/failed. Retain the encrypted recovery evidence until the code release and recovery review are complete. No automatic recovery deletion is installed.

## Verification

Local tests exercise actual temporary source files and Rails/SQLite persistence: generation/download without writes, configured-role checks, source opt-in/mapping, traversal/type/encoding bounds, source/file/ticket changes, exact byte writes, duplicate Apply, encrypted recovery, rollback after a later write or journal failure, and preservation of an external edit when rollback becomes unsafe. Symlink/hardlink tests run on Linux CI; the symlink test is skipped on Windows where the development account lacks guaranteed link privileges.

`tools/deployment/verify_code.rb` renders the native review/configuration/button and recognizes the patch route inside a read-only database transaction. It uses synthetic in-memory content and does not generate code, call OpenAI or write a checkout. Native end-to-end code generation/Apply requires an explicitly configured test checkout and selected roles; no production source tree is selected by deployment.
