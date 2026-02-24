---
name: onboard
description: Onboard an existing git project with Jira sync — imports full commit history into Jira cards and configures automatic sync. Use on existing repos that need Jira integration.
---

# jira-project-sync:onboard

Onboard an existing git project — import full commit history to Jira and set up automatic sync.

**This skill is fully project-agnostic.** Nothing is hardcoded — all values are discovered dynamically.

**IMPORTANT:** Before grouping commits, read the reference file at `${CLAUDE_PLUGIN_ROOT}/skills/onboard/references/commit-grouping.md` for grouping rules.

## Flow

Follow these steps in order. Do NOT skip any step.

### Step 1: Verify git repo

```bash
git rev-parse --show-toplevel
```

If this fails, tell the user:
> "This directory is not a git repository. Use `/jira-project-sync:init` to create a new project instead."

Stop here.

### Step 2: Check for existing config

Check if `.claude/jira-sync.json` already exists.

- **If it exists:** Warn the user:
  > "This project already has Jira sync configured (`.claude/jira-sync.json`). Continuing will overwrite the existing configuration. Proceed?"
  Wait for confirmation before continuing.
- **If it does not exist:** Proceed normally.

### Step 3: Gather project info

Ask the user for:
- **Project key** (e.g., `WEB`, `API`, `MOBILE`) — the Jira project key
- **Project name** — human-readable name (e.g., "Web Application")

### Step 4: Auto-detect Atlassian Cloud ID

Use the Atlassian MCP tool `getAccessibleAtlassianResources` to fetch the user's Cloud ID.

```
Tool: mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources
```

Extract the `id` field from the first accessible resource.

### Step 5: Verify Jira project exists

```
Tool: mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql
cloudId: {CLOUD_ID}
jql: "project = {PROJECT_KEY} ORDER BY created DESC"
```

**Note:** Do NOT pass `maxResults` or `fields` parameters — they cause type errors. Just use `cloudId` and `jql`.

- **If project exists:** Confirm and proceed.
- **If NOT found:** Tell user to create the project in Jira UI first, wait for confirmation.

### Step 6: Discover transition Done ID

You need an existing issue to query transitions. If step 5 returned issues, use one. If not, create a temporary issue:

```
Tool: mcp__plugin_atlassian_atlassian__createJiraIssue
cloudId: {CLOUD_ID}
projectKey: {PROJECT_KEY}
issueTypeName: "Task"
summary: "_temp: discovering transition IDs (will be deleted)"
```

Then get available transitions:

```
Tool: mcp__plugin_atlassian_atlassian__getTransitionsForJiraIssue
cloudId: {CLOUD_ID}
issueIdOrKey: {issue key}
```

Look for the transition where `statusCategory.key` is `"done"`. Save its `id` as the Done transition ID.

If you created a temp issue, delete it after getting the transitions, or reuse it as the first onboarding card.

**IMPORTANT:** The transition `name` matters — "Done" is typically ID 41 in standard Jira workflows. Do NOT assume 31 (that is usually "In Progress").

### Step 7: Write `.claude/jira-sync.json`

```bash
mkdir -p .claude
```

```json
{
  "project": "{PROJECT_KEY}",
  "cloudId": "{CLOUD_ID}",
  "transitionDoneId": "{TRANSITION_DONE_ID}"
}
```

### Step 8: Build import plan

This step creates a persistent plan file so that the grouping survives context compaction.

#### 8a: Get full commit history

```bash
git log --format="%h|%ad|%an|%s" --date=short --reverse
```

This outputs oldest-first, pipe-delimited: `hash|date|author|subject`

#### 8b: Read grouping rules

Read the reference file for commit grouping instructions:

```
Read file: ${CLAUDE_PLUGIN_ROOT}/skills/onboard/references/commit-grouping.md
```

Follow these rules exactly when grouping.

#### 8c: Semantically group commits and save plan

Analyze all commits and group them into logical cards based on the grouping rules:
- Group by semantic topic (feature, bugfix area, infrastructure)
- Use prefix hints (`feat:`, `fix:`, `docs:`, etc.)
- Single-commit features get their own card
- Related fixes/iterations go together
- Max ~15 commits per card

**Write the plan to `.claude/jira-onboard-plan.md`** with this exact format:

```markdown
# Jira Onboard Plan

Project: {PROJECT_KEY}
Cloud ID: {CLOUD_ID}
Transition Done ID: {TRANSITION_DONE_ID}
Total commits: {N}
Total cards: {M}

## Cards

### Card 1: {summary}
Status: pending
- {hash1}|{date}|{author}|{message}
- {hash2}|{date}|{author}|{message}

### Card 2: {summary}
Status: pending
- {hash3}|{date}|{author}|{message}

...
```

Each card section has:
- A `### Card N: {summary}` heading with the Jira card summary
- A `Status:` line — starts as `pending`, updated to `created:{ISSUE_KEY}` after creation
- A list of commits belonging to that card (pipe-delimited)

**This file is the source of truth for the import.** If the session is compacted or restarted, read this file to resume where you left off.

### Step 9: Execute import plan

Read `.claude/jira-onboard-plan.md` and process each card with `Status: pending`:

#### For each pending card:

1. **Create the Jira issue:**

```
Tool: mcp__plugin_atlassian_atlassian__createJiraIssue
cloudId: {CLOUD_ID}
projectKey: {PROJECT_KEY}
issueTypeName: "Task"
summary: {card summary from plan}
description: |
  Commits imported from git history:

  | Hash | Date | Author | Message |
  |------|------|--------|---------|
  | {hash} | {date} | {author} | {message} |
  ...
```

**Note:** Use `issueTypeName` (not `issueType`). Always include `cloudId`.

2. **Transition to Done:**

```
Tool: mcp__plugin_atlassian_atlassian__transitionJiraIssue
cloudId: {CLOUD_ID}
issueIdOrKey: {newly created issue key}
transition: {"id": "{TRANSITION_DONE_ID}"}
```

**IMPORTANT:** The `transition` parameter must be an object `{"id": "41"}`, NOT a flat string. And `transitionId` is NOT a valid parameter — use `transition` instead.

3. **Update the plan file:** Change `Status: pending` to `Status: created:{ISSUE_KEY}` for that card.

#### After all cards are processed:

Report:
> "Created X cards from Y commits in project {PROJECT_KEY}."

List the card summaries briefly.

### Step 10: Clean up plan file

Delete the plan file after successful import:

```bash
rm .claude/jira-onboard-plan.md
```

### Step 11: Write `.claude/jira-sync-state`

```bash
git rev-parse HEAD > .claude/jira-sync-state
```

This marks the current HEAD so the hook doesn't re-process these commits.

### Step 12: Update CLAUDE.md

Check if `CLAUDE.md` exists at the project root.

**If CLAUDE.md exists:** Append the Jira integration section (only if not already present):

```markdown

## Integracao Jira

- **Projeto Jira:** {PROJECT_KEY}
- **Sync automatico:** Commits sao sincronizados com Jira automaticamente a cada `git push`
- **Config:** `.claude/jira-sync.json`
- **Estado:** `.claude/jira-sync-state`

### Comportamento do Sync

- Cada push dispara o hook que analisa commits desde o ultimo sync
- Commits sao agrupados semanticamente em cards Jira
- Cards novos sao criados para features/fixes novos
- Commits relacionados a cards existentes sao adicionados como comentarios
- Cards criados sao automaticamente transicionados para Done
```

**If CLAUDE.md does NOT exist:** Create a minimal one:

```markdown
# {PROJECT_NAME}

## Integracao Jira

- **Projeto Jira:** {PROJECT_KEY}
- **Sync automatico:** Commits sao sincronizados com Jira automaticamente a cada `git push`
- **Config:** `.claude/jira-sync.json`
- **Estado:** `.claude/jira-sync-state`

### Comportamento do Sync

- Cada push dispara o hook que analisa commits desde o ultimo sync
- Commits sao agrupados semanticamente em cards Jira
- Cards novos sao criados para features/fixes novos
- Commits relacionados a cards existentes sao adicionados como comentarios
- Cards criados sao automaticamente transicionados para Done
```

### Step 13: Confirm

Tell the user:
> "Onboarding complete! {X} cards created from {Y} commits. Jira sync is now active for project {PROJECT_KEY}. Every `git push` will automatically sync new commits to Jira."
