# Changelog

## [2026-05-09] - v1.1.1

### Bug Fixes
- **Hook no longer false-triggers on text mentioning push commands.** Previously, a `git commit` whose message body contained literal `git push` or `gh repo create --push` text (e.g., meta-documentation about the plugin itself, or `curl` payloads passing such text in JSON) would falsely fire the sync hook. The trigger now inspects the bash command's *output* (`tool_response.stdout` + `stderr`) for actual push signatures — `To <remote>`, `Everything up-to-date`, `Pushed commits to` — instead of parsing the input command string. False positives from commit messages, JSON payloads, heredoc bodies, and quoted text are now structurally impossible. Includes input-based fallback for Claude Code versions that don't expose `tool_response`.

## [2026-05-09] - v1.1.0

### Features
- **3-layer semantic-grouping algorithm** replaces the previous binary "ref means comment, never create" rule:
  - LAYER 1: ref present + scope fits the ref'd ticket → comment on it (most common case)
  - LAYER 2: ref present + scope diverges + match found elsewhere → comment on better candidate, mention `see also REF`
  - LAYER 3: ref present + scope diverges + no match → create new ticket + `Relates` link to ref
  - No-ref commits: classic semantic search (LAYER 2 or 3)
  - Conservative default: when uncertain, comment on ref'd ticket — preserves the no-duplicate invariant while introducing a no-false-grouping invariant
- **REST API is now the primary transport** for all Jira operations; Atlassian MCP becomes opt-in fallback (HTTP 429 or explicit user request). All `init`/`onboard` skill flows migrated.
- **`jira-project-sync:api` skill expanded into single source of truth** for both operations (14 curl recipes: search, get/create issue, comments, transitions, links, delete, bulk delete, move, labels) and the semantic-grouping algorithm. ADF templates section included for write payloads.
- **Persistent pending file** (`.claude/jira-sync-pending`) survives session boundaries — sync failures (e.g., MCP disconnect mid-session) no longer silently lose work; the next push reprocesses.
- Hook detects ticket references (`PROJECT-N`) in commits to avoid duplicate cards when working from plans
- Hook also triggers on `gh repo create --push` (not just `git push`)

### Bug Fixes
- **PostToolUse hook output now visible to the model**: switched from `exit 0 + stdout` (silently dropped) to `exit 2 + stderr` (injected as system reminder). Early-exit branches (no config, no push, no commits) keep `exit 0` for silence. Resolves the silent-failure mode where sync instructions were emitted but never reached Claude.
- Project verification uses the dedicated `/rest/api/3/project/{KEY}` endpoint (or MCP `getVisibleJiraProjects`) instead of JQL — JQL returned 0 results without erroring on non-existent projects, creating false positives.

### Documentation
- Implementation plan: `docs/plans/2026-05-05-api-migration-and-semantic-segregation.md`
- New "Semantic Grouping Algorithm" section in `api` skill (worked examples + 3-layer pseudocode)
- New "Algoritmo de Agrupamento Semantico" section in global `~/.claude/CLAUDE.md`
- `commit-grouping.md` gains a "Relationship to the api skill SSOT" preamble clarifying its scope (initial import) vs the api skill SGA (ongoing sync)

## [2026-02-25] - v1.0.1

### Features
- Onboard skill writes plan file incrementally — raw commits persisted to disk before grouping, each card appended as identified
- `Grouping: in-progress/complete` marker enables session recovery if context is compacted mid-grouping
- Onboard plan file (`.claude/jira-onboard-plan.md`) automatically gitignored

## [2026-02-25] - v1.0.0

### Features
- Automatic Jira sync on every `git push` via PostToolUse hook
- `/jira-project-sync:init` skill for bootstrapping new projects with Jira integration
- `/jira-project-sync:onboard` skill for importing full commit history into Jira cards
- Semantic commit grouping into logical Jira cards (by feature, bugfix, area)
- Lazy transition ID discovery — no temporary Jira issues created
- Per-project configuration via `.claude/jira-sync.json`
- State file (`.claude/jira-sync-state`) automatically gitignored to prevent commit-sync loops

### Documentation
- README with quick start guide, full setup instructions, and configuration reference
- MIT license
