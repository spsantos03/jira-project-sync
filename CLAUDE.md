# Jira Project Sync Plugin

Claude Code plugin marketplace (`local-plugins`) hosting two plugins: **`jira-project-sync`** (PostToolUse hook that syncs pushed commits to Jira + `init` / `onboard` / `api` skills) and **`doc-standard`** (documentation generator skill).

## Layout

- `.claude-plugin/marketplace.json` — marketplace manifest (name `local-plugins`, plugin versions)
- `plugins/jira-project-sync/`
  - `.claude-plugin/plugin.json` — **authoritative version** (wins over marketplace entries at install)
  - `hooks/hooks.json` — registers the hook via `${CLAUDE_PLUGIN_ROOT}/scripts/jira-sync.sh`
  - `scripts/jira-sync.sh` — the hook (bash 3.2-compatible: macOS `/bin/bash`)
  - `skills/{api,init,onboard}/SKILL.md` — `api` is the SSOT for every Jira REST recipe and the semantic-grouping algorithm
- `plugins/doc-standard/` — separate plugin, same marketplace
- `tests/` — hook tests (bash)
- `docs/plans/` — historical design docs; **do not rewrite**, they record past decisions

## Release workflow

1. Ticket first (`JPSP-N`), then commit (`fix(JPSP-N): …`); version bump as a **separate** commit (`chore(JPSP-N): bump jira-project-sync to X.Y.Z`).
2. Bump the version in **all three** places: `plugins/jira-project-sync/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and `plugins/jira-project-sync/.claude-plugin/marketplace.json`. Run `claude plugin validate plugins/jira-project-sync` — it flags mismatches.
3. `CHANGELOG.md` entry (`## [YYYY-MM-DD] - vX.Y.Z`); README if behavior or setup changed.
4. **Push**, then install: `claude plugin marketplace update local-plugins && claude plugin update jira-project-sync@local-plugins`, then **restart Claude Code** (hooks and skills load at session start). The marketplace is a GitHub clone: **only pushed commits install**.
5. Verify in the restarted session with a real push: exactly one `JIRA_SYNC` message, from `cache/local-plugins/jira-project-sync/<version>/`. If the release touched the **trigger**, make that verification push the shape the fix is about (e.g. `git push 2>&1 | tail -1` for JPSP-32) — a normal push still shows `To <url>` and proves nothing about the new path.

Never hand-copy files into `~/.claude/plugins/cache/…` and never register the hook in `~/.claude/settings.json` — that is how releases silently stopped reaching the running system until v1.2.3 (JPSP-30).

## Testing

```bash
for t in tests/test-*.sh; do $t || echo "FAILED: $t"; done
```

Shared fixture and runner live in `tests/lib.sh`; each test file calls `run_suite <pre-fix commit> "<discriminating cases>" "<preserved cases>"`. Discriminating cases must pass on the current hook **and fail** on the pre-fix hook from git — the counterproof that the fixture reproduces the bug; a case the old hook also passes protects nothing. Classify cases by running them against the old hook, not by intuition (JPSP-32's red run moved two cases). The target repo in every fixture has unsynced commits, so a silent `exit 0` can never pass a "should have synced" case by accident. Test fixtures commit with `-c core.hooksPath=/dev/null` (only fixtures — never real commits).

## Invariants (learned the hard way)

- **The hook can never sync a repo's first commit.** It syncs `git log LAST_SYNC..HEAD`, and `A..B` never contains `A`. Anything that must reach Jira for the bootstrap commit is done by `init` itself (JPSP-28).
- **The hook's cwd is not the pushed repo.** Harnesses reset the shell cwd after each command, and `cd x && git push` / `git -C x push` push elsewhere. Resolve the repo from the push output's `To <url>` matched against candidate remotes (JPSP-29).
- **The hook only sees what the push printed.** Detection is output-first (`To <remote>` …); a truncated (`| tail -1`) or silenced (`>/dev/null`) push is caught only because the parsed command really invokes `git push` (heredoc bodies, quoted strings and `$(…)` stripped first — each was a live false positive). Filtering the output down to lines that prove nothing (`| grep -c`) still slips through, by design: keep push output unfiltered (JPSP-32).
- **Never exit 0 silently on a push you could not place.** `exit 0` is also "nothing new to sync", so a lost sync looks like success. Warn with exit 2.
- **A 2xx is not proof** (Jira project creation, transitions): re-read the resulting state.
- **`claude plugin marketplace remove` uninstalls and disables every plugin of that marketplace**; if its install location is ever a symlink, delete the link yourself first so the removal cannot reach the target.

## Integracao Jira

- **Projeto Jira:** JPSP
- **Sync automatico:** Commits sao sincronizados com Jira automaticamente a cada `git push`
- **Config:** `.claude/jira-sync.json`
- **Estado:** `.claude/jira-sync-state`

### Comportamento do Sync

- Cada push dispara o hook que analisa commits desde o ultimo sync
- Commits sao agrupados semanticamente em cards Jira
- Cards novos sao criados para features/fixes novos
- Commits relacionados a cards existentes sao adicionados como comentarios
- Cards criados sao automaticamente transicionados para Done
