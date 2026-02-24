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

Try to detect the Done transition from an existing issue:

```
Tool: mcp__plugin_atlassian_atlassian__getTransitionsForJiraIssue
issueIdOrKey: {any issue from step 5, or skip if none}
```

If no issues exist, ask the user:
> "What is the transition ID for 'Done' in your Jira workflow? (Common values: 31, 41, 51)"

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

### Step 8: Import all existing commits

This is the core of the onboard flow. Follow carefully.

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

#### 8c: Semantically group commits

Analyze all commits and group them into logical cards based on the grouping rules:
- Group by semantic topic (feature, bugfix area, infrastructure)
- Use prefix hints (`feat:`, `fix:`, `docs:`, etc.)
- Single-commit features get their own card
- Related fixes/iterations go together
- Max ~15 commits per card

#### 8d: Create Jira cards for each group

For each group, create a Jira card:

```
Tool: mcp__plugin_atlassian_atlassian__createJiraIssue
projectKey: {PROJECT_KEY}
issueType: "Task"
summary: {group topic name — concise, imperative}
description: |
  Commits imported from git history:

  | Hash | Date | Author | Message |
  |------|------|--------|---------|
  | {hash} | {date} | {author} | {message} |
  ...
```

Then transition to Done:

```
Tool: mcp__plugin_atlassian_atlassian__transitionJiraIssue
issueIdOrKey: {newly created issue key}
transitionId: {TRANSITION_DONE_ID}
```

#### 8e: Report results

After all cards are created, report:
> "Created X cards from Y commits in project {PROJECT_KEY}."

List the card summaries briefly.

### Step 9: Write `.claude/jira-sync-state`

```bash
git rev-parse HEAD > .claude/jira-sync-state
```

This marks the current HEAD so the hook doesn't re-process these commits.

### Step 10: Update CLAUDE.md

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

### Step 11: Confirm

Tell the user:
> "Onboarding complete! {X} cards created from {Y} commits. Jira sync is now active for project {PROJECT_KEY}. Every `git push` will automatically sync new commits to Jira."
