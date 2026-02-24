---
name: init
description: Bootstrap a brand-new project with git repo, Jira integration, and CLAUDE.md. Use when starting a new project from scratch that needs Jira sync.
---

# jira-project-sync:init

Bootstrap a new project with git + Jira integration + CLAUDE.md.

**This skill is fully project-agnostic.** Nothing is hardcoded — all values are discovered dynamically per project.

## Flow

Follow these steps in order. Do NOT skip any step.

### Step 1: Initialize git

```bash
git init
```

If the directory already has a git repo, skip this step.

### Step 2: Create .claude directory

```bash
mkdir -p .claude
```

### Step 3: Gather project info

Ask the user for:
- **Project key** (e.g., `WEB`, `API`, `MOBILE`) — the Jira project key
- **Project name** — human-readable name (e.g., "Web Application")
- **Short description** — one-line description of the project

### Step 4: Auto-detect Atlassian Cloud ID

Use the Atlassian MCP tool `getAccessibleAtlassianResources` to fetch the user's Cloud ID.

```
Tool: mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources
```

Extract the `id` field from the first accessible resource. This is the Cloud ID.

### Step 5: Verify Jira project exists

Search for the project using JQL:

```
Tool: mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql
cloudId: {CLOUD_ID}
jql: "project = {PROJECT_KEY} ORDER BY created DESC"
```

**Note:** Do NOT pass `maxResults` or `fields` parameters — they cause type errors. Just use `cloudId` and `jql`.

- **If project exists:** Confirm to user and proceed.
- **If project NOT found:** Tell the user to create the project in Jira UI first, then wait for them to confirm before continuing.

### Step 6: Discover transition IDs

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

Delete the temp issue after getting the transitions (or transition it to Done and leave it).

**IMPORTANT:** "Done" is typically transition ID 41 in standard Jira workflows. Do NOT assume 31 (that is usually "In Progress").

### Step 7: Write `.claude/jira-sync.json`

Create the per-project config file:

```json
{
  "project": "{PROJECT_KEY}",
  "cloudId": "{CLOUD_ID}",
  "transitionDoneId": "{TRANSITION_DONE_ID}"
}
```

### Step 8: Write `.claude/jira-sync-state`

If the repo has commits:
```bash
git rev-parse HEAD > .claude/jira-sync-state
```

If no commits yet, skip this step (the hook will initialize it on first push).

### Step 9: Detect tech stack

Check for the presence of these files to determine the tech stack:
- `package.json` → Node.js / JavaScript / TypeScript
- `requirements.txt` or `pyproject.toml` or `setup.py` → Python
- `Cargo.toml` → Rust
- `go.mod` → Go
- `pom.xml` or `build.gradle` → Java
- `Gemfile` → Ruby
- `composer.json` → PHP
- `docker-compose*.yml` → Docker

List all detected technologies.

### Step 10: Create CLAUDE.md

Generate a `CLAUDE.md` at the project root with:

```markdown
# {PROJECT_NAME}

{SHORT_DESCRIPTION}

## Tech Stack

{DETECTED_TECHNOLOGIES}

## Project Structure

> TODO: Update as the project grows.

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

## Comandos Uteis

> TODO: Add project-specific commands as they are established.
```

### Step 11: Create .gitignore

Create a `.gitignore` with essentials (only if one doesn't already exist):

```
.env
.env.prod
*.pem
node_modules/
__pycache__/
*.pyc
dist/
build/
.vscode/
.idea/
```

### Step 12: Initial commit

```bash
git add -A
git commit -m "chore: project init with Jira integration"
```

### Step 13: Confirm

Tell the user:
> "Project initialized! Jira sync is configured for project {PROJECT_KEY}. Every `git push` will now automatically sync commits to Jira cards."
