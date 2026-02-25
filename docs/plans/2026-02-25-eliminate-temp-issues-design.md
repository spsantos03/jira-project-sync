# Eliminate Temp Issues from Onboard/Init Skills

## Problem

Both `onboard` and `init` skills create a temporary Jira issue (`_temp: discovering transition IDs`) to query available workflow transitions. This leaves garbage issues that are hard to delete (requires special Jira permissions). Additionally, the state file (`.claude/jira-sync-state`) is committed to git, creating a circular dependency: commit triggers sync, sync updates state file, state file change needs commit.

## Solution

Three coordinated changes:

### 1. Onboard skill: use first real card for discovery

Remove Step 6 (temp issue creation). Write `jira-sync.json` without `transitionDoneId`. Move transition discovery into Step 9 — after creating Card 1 from the import plan:

- Create Card 1 as a real Jira issue
- Query transitions on that issue via `getTransitionsForJiraIssue`
- Find Done transition by `statusCategory.key === "done"`
- Update `jira-sync.json` with discovered `transitionDoneId`
- Update plan file header with transition ID
- Transition Card 1 to Done
- Continue remaining cards normally

### 2. Init skill: defer transition discovery

Remove Step 6 entirely. Write `jira-sync.json` with `transitionDoneId: null`. The hook already tolerates missing transition IDs (skips transition instructions). Actual discovery happens lazily on first push.

### 3. Hook: lazy transition discovery on first push

When `transitionDoneId` is empty in config, the hook adds extra instructions telling Claude to:

1. After creating the first card, query its transitions
2. Find the Done transition by `statusCategory.key === "done"`
3. Write discovered ID back to `jira-sync.json`
4. Transition that card (and all subsequent) to Done

After first push, `transitionDoneId` is cached and all future pushes work normally.

### 4. Gitignore the state file

Both skills add `.claude/jira-sync-state` to `.gitignore` during setup. The state file is local tracking state, not source code. This prevents the circular commit-sync dependency.

## Files Affected

| File | Change |
|------|--------|
| `skills/onboard/SKILL.md` | Remove Step 6, add first-card discovery in Step 9, add gitignore setup |
| `skills/init/SKILL.md` | Remove Step 6, write null transitionDoneId, add gitignore setup |
| `scripts/jira-sync.sh` | Add conditional lazy discovery instruction block |

## What Gets Deleted

- Step 6 (temp issue creation) from both skills
- State file from committed files in both skills

## What Stays the Same

- Commit grouping logic, plan file format, CLAUDE.md generation
- All MCP tool usage patterns and parameter formats
- Hook trigger logic (git push detection, per-project config)
