# jira-project-sync

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin that automatically syncs git commits to Jira cards on every `git push`.

- Every push creates or updates Jira cards from your commits
- Commits are grouped semantically (by feature, bugfix, area) into logical cards
- New projects get bootstrapped with Jira integration in one command
- Existing repos can import their full commit history to Jira

## Quick Start

If you already have Claude Code and Atlassian API credentials configured (`~/.claude/.env`):

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

### Atlassian API Credentials

The plugin talks to Jira via REST API using credentials stored in `~/.claude/.env`. You need an Atlassian API token.

**1. Generate an API token:**

Visit [id.atlassian.com/manage-profile/security/api-tokens](https://id.atlassian.com/manage-profile/security/api-tokens) and create a new token. Copy it — you won't see it again.

**2. Save credentials to `~/.claude/.env`:**

```bash
cat >> ~/.claude/.env <<EOF
ATLASSIAN_EMAIL=your-email@example.com
ATLASSIAN_API_TOKEN=your-token-here
ATLASSIAN_SITE=your-site.atlassian.net
EOF
chmod 600 ~/.claude/.env
```

**3. Verify:**

```bash
source ~/.claude/.env
curl -s "https://api.atlassian.com/oauth/token/accessible-resources" \
  -H "Authorization: Basic $(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)" \
  | jq -r '.[0].id'
```

If this returns a UUID (your Cloud ID), you're set.

#### Optional: Atlassian MCP plugin (fallback)

The plugin can fall back to the Atlassian MCP plugin if REST is rate-limited or you explicitly request it — it is **not** required for normal operation. To install it anyway:

```bash
claude /install-plugin @anthropic-ai/claude-code-atlassian
```

Then authenticate via OAuth on first use.

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

After setup, every `git push` (or `gh repo create --push`) automatically:
1. Detects new commits since the last sync
2. Applies the 3-layer semantic algorithm to each commit:
   - **Layer 1** — commit references a ticket (`PROJECT-N`) and fits its scope → comment on that ticket
   - **Layer 2** — no fit, but a different existing ticket matches semantically → comment there (with `see also REF`)
   - **Layer 3** — no match anywhere → create a new ticket (with `Relates` link to the ref, if any)
3. Transitions newly created tickets to Done

The bias is conservative: when uncertain, the commit attaches to its referenced ticket. This preserves the no-duplicate invariant while preventing false grouping when the ref doesn't actually match the commit's scope.

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

### Semantic grouping

The plugin uses two complementary grouping rules:

**Ongoing sync (every push)** — the 3-layer algorithm described above. Documented in the `jira-project-sync:api` skill (`skills/api/SKILL.md`, "Semantic Grouping Algorithm" section) as the single source of truth.

**Initial import (`/jira-project-sync:onboard`)** — clusters raw commits into card summaries before any tickets exist:

- Conventional commit prefixes (`feat:`, `fix:`, `docs:`) guide grouping
- Related commits (same module, same domain) go on the same card
- Single standalone changes get their own card
- Max ~15 commits per card

Documented in `skills/onboard/references/commit-grouping.md`.

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
    │   ├── api/
    │   │   └── SKILL.md         # /jira-project-sync:api (REST API + grouping algorithm SSOT)
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
