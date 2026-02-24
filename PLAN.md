# Plan: `jira-project-sync` Plugin

## Plugin Name

**`jira-project-sync`** — invoked as `/jira-project-sync:init` and `/jira-project-sync:onboard`

## Core Principle: Fully Project-Agnostic

This plugin is **generic** — it works for ANY git project. Nothing is hardcoded for any specific Jira space. Every run:
- Asks the user for the Jira project key (e.g., `WEB`, `API`, `MOBILE`)
- Auto-detects the Atlassian Cloud ID via MCP
- Discovers the transition IDs dynamically
- Writes per-project config to `.claude/jira-sync.json` in that project's root

## Plugin Structure

```
~/.claude/plugins/local/jira-project-sync/
├── .claude-plugin/
│   └── plugin.json                     # Manifest
├── skills/
│   ├── init/
│   │   └── SKILL.md                    # /jira-project-sync:init
│   └── onboard/
│       ├── SKILL.md                    # /jira-project-sync:onboard
│       └── references/
│           └── commit-grouping.md      # Instructions for semantic grouping
├── hooks/
│   └── hooks.json                      # PostToolUse hook for git push
├── scripts/
│   └── jira-sync.sh                    # The hook script (moved here)
└── README.md
```

## Implementation Steps

### Step 1: Create plugin directory + manifest

Create `~/.claude/plugins/local/jira-project-sync/.claude-plugin/plugin.json`:

```json
{
  "name": "jira-project-sync",
  "description": "Automatic Jira synchronization for git projects. Syncs commits to Jira cards on every push, bootstraps new projects, and onboards existing repos with full commit history import.",
  "version": "1.0.0",
  "author": {
    "name": "Sergio Santos"
  }
}
```

### Step 2: Move hook into plugin

Create `hooks/hooks.json`:
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/plugins/local/jira-project-sync/scripts/jira-sync.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

Move `~/.claude/hooks/jira-sync.sh` → `scripts/jira-sync.sh` (inside plugin).

Remove the PostToolUse Bash entry from `~/.claude/settings.json` (plugin owns it now).

### Step 3: Create `/jira-project-sync:init` skill

**Purpose:** Bootstrap a brand-new project with git + Jira integration + CLAUDE.md.

**Flow:**
1. `git init`
2. Create `.claude/` directory
3. Ask user for: project key, project name, short description
4. Fetch Cloud ID via `getAccessibleAtlassianResources`
5. Check if Jira project exists via `searchJiraIssuesUsingJql`
   - If not: prompt user to create it in Jira UI, wait for confirmation
   - If yes: confirm and proceed
6. Get available transitions via `getTransitionsForJiraIssue` on a test issue (to find Done ID), or ask user
7. Write `.claude/jira-sync.json`
8. Write `.claude/jira-sync-state` with current HEAD (or skip if no commits yet)
9. Detect tech stack (package.json, requirements.txt, Cargo.toml, etc.)
10. Create `CLAUDE.md` with:
    - Project name, description, tech stack
    - Jira integration section (project key, sync behavior)
    - Standard structure following global CLAUDE.md patterns
11. Create `.gitignore` with essentials (from global CLAUDE.md patterns)
12. Make initial commit: `git add -A && git commit -m "chore: project init with Jira integration"`

### Step 4: Create `/jira-project-sync:onboard` skill

**Purpose:** Onboard an existing git project — import full commit history to Jira, set up sync.

**Flow:**
1. Verify current directory is a git repo (fail if not)
2. Check if `.claude/jira-sync.json` exists (warn before overwriting)
3. Ask user for: project key, project name
4. Fetch Cloud ID via `getAccessibleAtlassianResources`
5. Check if Jira project exists
   - If not: prompt user to create it, wait for confirmation
   - If yes: proceed
6. Get transition Done ID (try from existing issue or ask user)
7. Write `.claude/jira-sync.json`
8. **Import all existing commits:**
   - Run `git log --format="%h|%ad|%an|%s" --date=short --reverse` (oldest first)
   - Semantically group commits by subject/feature into logical cards
   - For each group:
     - Create Jira card (Task) with:
       - Summary: feature/topic name
       - Description: table of all commits (hash, date, author, message)
     - Transition to Done
   - Report: "Created X cards from Y commits"
9. Write `.claude/jira-sync-state` with HEAD
10. Update CLAUDE.md:
    - If exists: append Jira integration section
    - If not: create minimal CLAUDE.md with Jira section
11. Confirm setup complete

**Reference file** `references/commit-grouping.md` provides Claude with explicit rules for how to group commits:
- Group by semantic topic (feature, bugfix area, infrastructure)
- Prefix-based hints: `feat:`, `fix:`, `docs:`, `chore:`, `refactor:` etc.
- Single-commit features get their own card
- Related fixes can be grouped together
- Keep card summaries concise but descriptive

### Step 5: Update `~/.claude/CLAUDE.md`

Add section **"# Integracao Jira (Global)"** after the deploy section, documenting:

- How the automatic sync works (hook → config → Claude processes)
- Per-project config format (`.claude/jira-sync.json`)
- All files in the system and their roles
- Slash commands: `/jira-project-sync:init` and `/jira-project-sync:onboard`
- Rules (no config = no sync, state file behavior, semantic grouping)

### Step 6: Register plugin + cleanup

- Register the plugin in `installed_plugins.json` or install via `claude plugin add --local`
- Enable in `settings.json` via `enabledPlugins`
- Remove the old Bash PostToolUse hook from `~/.claude/settings.json` (plugin provides it now)
- Delete `~/.claude/hooks/jira-sync.sh` (now at `scripts/jira-sync.sh` inside plugin)
- Verify the hook still fires correctly after the move

### Step 7: Test

1. Test `/jira-project-sync:init` in a temp directory
2. Test `/jira-project-sync:onboard` on an existing project
3. Verify hook still fires on `git push`
4. Confirm `.claude/jira-sync-state` updates correctly

## Key Design Decisions

- **Plugin-owned hook**: The PostToolUse hook lives inside the plugin via `hooks/hooks.json`, not in global settings — makes the system self-contained
- **Cloud ID auto-detected**: Skills fetch it via MCP instead of hardcoding
- **Transition ID discovery**: Skills try to detect the Done transition ID rather than assuming `31`
- **CLAUDE.md templating**: The init skill creates a full CLAUDE.md following the patterns from the global one; the onboard skill only appends the Jira section
- **Commit grouping reference**: A dedicated reference file guides Claude on how to semantically cluster commits, avoiding arbitrary splits

## What's NOT in the Plugin

- No hardcoded project keys, Cloud IDs, or transition IDs
- No project-specific logic — each project's `.claude/jira-sync.json` is created dynamically by the skills
- No assumption about Jira workflow — transition IDs are discovered per project

## Open Questions

None — all requirements are clear from the user's description. The Atlassian MCP plugin is already installed with all necessary permissions.
