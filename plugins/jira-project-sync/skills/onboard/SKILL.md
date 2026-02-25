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

### Step 6: Write `.claude/jira-sync.json`

```bash
mkdir -p .claude
```

Then ensure temp/state files are gitignored:

```bash
# Add to .gitignore if not already present
grep -qxF '.claude/jira-sync-state' .gitignore 2>/dev/null || echo '.claude/jira-sync-state' >> .gitignore
grep -qxF '.claude/jira-onboard-plan.md' .gitignore 2>/dev/null || echo '.claude/jira-onboard-plan.md' >> .gitignore
```

```json
{
  "project": "{PROJECT_KEY}",
  "cloudId": "{CLOUD_ID}"
}
```

### Step 7: Build import plan

This step creates a persistent plan file **incrementally** so that work survives context compaction.

#### 7a: Get full commit history

```bash
git log --format="%h|%ad|%an|%s" --date=short --reverse
```

This outputs oldest-first, pipe-delimited: `hash|date|author|subject`

#### 7b: Read grouping rules

Read the reference file for commit grouping instructions:

```
Read file: ${CLAUDE_PLUGIN_ROOT}/skills/onboard/references/commit-grouping.md
```

Follow these rules exactly when grouping.

#### 7c: Initialize plan file with header and raw commits

**Write the plan file immediately** with the header and raw commit list. This preserves the commit data even if context is compacted before grouping completes.

Write `.claude/jira-onboard-plan.md`:

```markdown
# Jira Onboard Plan

Project: {PROJECT_KEY}
Cloud ID: {CLOUD_ID}
Total commits: {N}
Grouping: in-progress

## Raw Commits

- {hash1}|{date1}|{author1}|{message1}
- {hash2}|{date2}|{author2}|{message2}
...

## Cards

```

The `Grouping: in-progress` marker indicates that card grouping has not finished yet.

#### 7d: Semantically group commits — write each card as you go

Analyze commits and group them into logical cards based on the grouping rules:
- Group by semantic topic (feature, bugfix area, infrastructure)
- Use prefix hints (`feat:`, `fix:`, `docs:`, etc.)
- Single-commit features get their own card
- Related fixes/iterations go together
- Max ~15 commits per card

**IMPORTANT — Write incrementally:** As you identify each card group, **append it to the plan file immediately** before moving to the next group. Do NOT hold all cards in memory and write at the end.

For each card group identified, append to the plan file:

```markdown
### Card N: {summary}
Status: pending
- {hash}|{date}|{author}|{message}
- {hash}|{date}|{author}|{message}

```

After ALL cards have been written, update the header: change `Grouping: in-progress` to `Grouping: complete` and add `Total cards: {M}`.

#### 7e: Verify plan completeness

Confirm the plan file has `Grouping: complete` and all commits from the raw list are accounted for in card groups.

**Recovery from compaction:** If the session is compacted or restarted mid-grouping, read `.claude/jira-onboard-plan.md`:
- If `Grouping: complete` → proceed to Step 8
- If `Grouping: in-progress` → the `## Raw Commits` section has the full commit list, and any cards already written under `## Cards` are preserved. Continue grouping only the commits not yet assigned to cards.

**This file is the source of truth for the import.** If the session is compacted or restarted, read this file to resume where you left off.

### Step 8: Execute import plan

Read `.claude/jira-onboard-plan.md` and process each card with `Status: pending`:

#### First pending card (with transition discovery):

1. **Create the Jira issue** (same as normal):

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

2. **Discover transition Done ID:**

```
Tool: mcp__plugin_atlassian_atlassian__getTransitionsForJiraIssue
cloudId: {CLOUD_ID}
issueIdOrKey: {newly created issue key}
```

Look for the transition where `statusCategory.key` is `"done"`. Save its `id` as the Done transition ID.

**Warning:** Do NOT hardcode or assume a specific transition ID. Always discover it dynamically from the `statusCategory.key === "done"` match.

3. **Update `.claude/jira-sync.json`:** Add `"transitionDoneId": "{DISCOVERED_ID}"` to the config JSON.

4. **Update the plan file header:** Add `Transition Done ID: {DISCOVERED_ID}` line.

5. **Transition to Done:**

```
Tool: mcp__plugin_atlassian_atlassian__transitionJiraIssue
cloudId: {CLOUD_ID}
issueIdOrKey: {newly created issue key}
transition: {"id": "{DISCOVERED_ID}"}
```

**IMPORTANT:** The `transition` parameter must be an object `{"id": "41"}`, NOT a flat string. And `transitionId` is NOT a valid parameter — use `transition` instead.

6. **Update the plan file:** Change `Status: pending` to `Status: created:{ISSUE_KEY}` for that card.

#### Remaining pending cards:

For each remaining card with `Status: pending`:

1. **Create the Jira issue** (same tool call as above)

2. **Transition to Done** using the discovered transition ID:

```
Tool: mcp__plugin_atlassian_atlassian__transitionJiraIssue
cloudId: {CLOUD_ID}
issueIdOrKey: {newly created issue key}
transition: {"id": "{DISCOVERED_ID}"}
```

3. **Update the plan file:** Change `Status: pending` to `Status: created:{ISSUE_KEY}` for that card.

#### After all cards are processed:

Report:
> "Created X cards from Y commits in project {PROJECT_KEY}."

List the card summaries briefly.

### Step 9: Clean up plan file

Delete the plan file after successful import:

```bash
rm .claude/jira-onboard-plan.md
```

### Step 10: Write `.claude/jira-sync-state`

**Use Bash for this** (the Write tool will fail on new files that haven't been read):

```bash
git rev-parse HEAD > .claude/jira-sync-state
```

This marks the current HEAD so the hook doesn't re-process these commits.

### Step 11: Update CLAUDE.md

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

### Step 12: Confirm

Tell the user:
> "Onboarding complete! {X} cards created from {Y} commits. Jira sync is now active for project {PROJECT_KEY}. Every `git push` will automatically sync new commits to Jira."
