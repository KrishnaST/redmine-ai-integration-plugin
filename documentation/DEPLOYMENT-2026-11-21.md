# Code with AI rollout — 21 November 2026

Version 1.3.0 deployed on server 13.127.209.215, app `/home/idsspl/redmine/native`, service `redmine-native.service`. Reverified Redmine 7.0.2.stable / Ruby 4.0.9 / Rails 8.1.4. The existing session mode/state/payload database columns support the new code/applying values; no migration was added.

Package SHA-256: `9a4917afe4cefd8838c4ff9b37aea25462cd65ae2e7651b05279629faac9b02a`. Database/config/plugin/bundle rollback material and read-only verification are in `/home/idsspl/redmine/ai-integration-deployment/settings-upgrade-20261121T175441Z/`.

## Verified

- Service running; local/public login and fingerprinted issue-actions JavaScript HTTP 200.
- Native read-only rendering of Code with AI review, patch route, administrator button and role/source settings passed. The synthetic session was not persisted and generated_code_written=false.
- Existing settings, all four driver loads, issue buttons and unsaved SVG attachment validation/rendering passed.
- Existing API key, low reasoning effort, project access and source settings preserved. At inspection the AI module was present in 35 projects and enhancement permission in five signed-in roles; this rollout did not modify those grants.
- Windows verification: 104 Ruby tests / 622 assertions, no failures/errors; one skipped symlink/hardlink test requiring Linux or Windows link privileges. JavaScript: 13 form + 12 toolbar assertions. Four deployment-helper tests passed. Linux CI also runs the link test.
- No paid OpenAI request, source-code write, command/build/test execution or live ticket modification was performed during server verification.

## Configuration still required

The user requested role-based configuration. Code with AI member-role selection defaults to empty and all code folders default to read-only. At rollout both selected code roles and opted-in writable code sources were zero. Administrators can see the button; other users need a selected role in the issue project plus existing visibility/edit/enhancement access.

In AI configuration, select the desired roles and add a project-mapped dedicated Code folder with Allow reviewed code changes enabled. Do not point it at Redmine or an automatically deployed runtime tree. The service account must own the editable files. Generation proposes changes; Apply is an explicit review step. Build/test/Git/deployment remain separate.

Read [Code with AI operations](CODE-WITH-AI.md) for bounds, file/hash checks, encrypted before/after recovery, filesystem/DB atomicity limits and interrupted applying-state handling. A configured test checkout and a real user-reviewed generation/Apply are still needed for native end-to-end acceptance. No live checkout was chosen on the user's behalf.
