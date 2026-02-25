# jira-project-sync

Automatic Jira synchronization for git projects. Syncs commits to Jira cards on every push, bootstraps new projects, and onboards existing repos with full commit history import.

## Skills

- **`/jira-project-sync:init`** — Bootstrap a new project with git + Jira integration + CLAUDE.md
- **`/jira-project-sync:onboard`** — Onboard an existing repo: import full commit history to Jira and set up sync

## How it works

1. A PostToolUse hook fires after every Bash command
2. The hook checks if the command was `git push`
3. If the project has `.claude/jira-sync.json`, it reads the config
4. It finds new commits since the last sync (tracked in `.claude/jira-sync-state`)
5. It instructs Claude to create/update Jira cards with the commit info

## Per-project config

Each project needs `.claude/jira-sync.json`:

```json
{
  "project": "PROJECT_KEY",
  "cloudId": "your-cloud-id",
  "transitionDoneId": null
}
```

- `transitionDoneId` starts as `null` — discovered automatically on first push or during onboarding
- Projects without this file are silently ignored

## Files

```
jira-project-sync/
├── .claude-plugin/plugin.json    # Plugin manifest
├── hooks/hooks.json              # PostToolUse hook registration
├── scripts/jira-sync.sh          # Hook script
├── skills/
│   ├── init/SKILL.md             # /jira-project-sync:init
│   └── onboard/
│       ├── SKILL.md              # /jira-project-sync:onboard
│       └── references/
│           └── commit-grouping.md
└── README.md
```
