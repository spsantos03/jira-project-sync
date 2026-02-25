# Changelog

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
