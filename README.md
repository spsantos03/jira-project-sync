# jira-project-sync

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin that automatically syncs git commits to Jira cards on every `git push`.

- Every push creates or updates Jira cards from your commits
- Commits are grouped semantically (by feature, bugfix, area) into logical cards
- New projects get bootstrapped with Jira integration in one command
- Existing repos can import their full commit history to Jira

## Quick Start

If you already have Claude Code and the Atlassian MCP plugin configured:

```bash
# 1. Install the plugin
claude /install-plugin https://github.com/spsantos03/jira-project-sync

# 2. For an existing project, run inside your repo:
#    /jira-project-sync:onboard

# 3. For a new project:
#    /jira-project-sync:init

# 4. Every git push now syncs to Jira automatically
```

---

## Prerequisites

### Claude Code

Install Claude Code if you haven't already:

```bash
npm install -g @anthropic-ai/claude-code
```

### Atlassian MCP Plugin

The plugin uses the Atlassian MCP server to communicate with Jira. You need to configure it in Claude Code.

**1. Install the Atlassian MCP plugin in Claude Code:**

```bash
claude /install-plugin @anthropic-ai/claude-code-atlassian
```

**2. Authenticate with Atlassian:**

Run Claude Code and use any Atlassian tool (e.g., list your Jira projects). Claude will prompt you to authenticate via OAuth if you haven't already.

**3. Verify access:**

In a Claude Code session, ask Claude to list your Jira projects. If it returns results, you're set.

### Jira Project

You need an existing Jira project (Software type) to sync to. Create one in your Jira instance if you don't have one yet. Note the **project key** (e.g., `WEB`, `API`, `MOBILE`).

## Installation

```bash
claude /install-plugin https://github.com/spsantos03/jira-project-sync
```

## Usage

### Onboard an existing repo

Run inside your git repository in Claude Code:

```
/jira-project-sync:onboard
```

This will:
1. Ask for your Jira project key and name
2. Auto-detect your Atlassian Cloud ID
3. Import your full commit history as Jira cards (semantically grouped)
4. Set up automatic sync for future pushes

### Bootstrap a new project

```
/jira-project-sync:init
```

This will:
1. Initialize git (if needed)
2. Configure Jira sync
3. Create CLAUDE.md with project info
4. Create .gitignore with sensible defaults

### Automatic sync

After setup, every `git push` automatically:
1. Detects new commits since the last sync
2. Searches for related existing Jira cards
3. Adds commits as comments to matching cards, or creates new cards
4. Transitions new cards to Done

No manual intervention needed.

## Configuration

Each synced project has `.claude/jira-sync.json`:

```json
{
  "project": "PROJECT_KEY",
  "cloudId": "your-cloud-id",
  "transitionDoneId": null
}
```

| Field | Description |
|-------|-------------|
| `project` | Your Jira project key (e.g., `WEB`) |
| `cloudId` | Atlassian Cloud ID — auto-detected during setup |
| `transitionDoneId` | Jira transition ID for "Done" status. `null` on first setup — discovered automatically on first push |

**Projects without this file are silently ignored** — the plugin only activates for configured projects.

### State file

The sync state is tracked in `.claude/jira-sync-state` (the hash of the last synced commit). This file:
- Is created automatically on first push
- Should be in `.gitignore` (both skills set this up automatically)
- Is local to each developer — not shared via git

## How It Works

### Hook system

The plugin registers a PostToolUse hook that runs after every Bash command in Claude Code. The hook:

1. Checks if the command was `git push` — exits silently for anything else
2. Looks for `.claude/jira-sync.json` in the repo root — exits silently if missing
3. Reads new commits since the last sync
4. Outputs instructions to Claude (via stderr + exit code 2) telling it to sync with Jira

### Semantic commit grouping

When importing history (via `/jira-project-sync:onboard`), commits are grouped into logical Jira cards:

- Conventional commit prefixes (`feat:`, `fix:`, `docs:`) guide grouping
- Related commits (same module, same domain) go on the same card
- Single standalone changes get their own card
- Max ~15 commits per card

### Transition discovery

The plugin doesn't hardcode any Jira workflow values. The "Done" transition ID is discovered dynamically:

- **Onboard:** Discovered from the first real card created during import
- **Init:** Deferred to the first `git push`, where the hook instructs Claude to discover and cache it
- Once discovered, the ID is saved in `jira-sync.json` and reused for all future syncs

## Plugin Structure

```
jira-project-sync/
├── .claude-plugin/
│   └── marketplace.json         # Marketplace manifest
└── plugins/jira-project-sync/
    ├── .claude-plugin/
    │   └── plugin.json          # Plugin manifest
    ├── hooks/
    │   └── hooks.json           # PostToolUse hook registration
    ├── scripts/
    │   └── jira-sync.sh         # Hook script
    ├── skills/
    │   ├── init/
    │   │   └── SKILL.md         # /jira-project-sync:init
    │   └── onboard/
    │       ├── SKILL.md         # /jira-project-sync:onboard
    │       └── references/
    │           └── commit-grouping.md
    └── README.md                # Plugin instructions
```

## License

[MIT](LICENSE)
