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

Use the `jira-project-sync:api` skill, "Get Cloud ID" recipe.

```bash
source ~/.claude/.env
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)
CLOUD_ID=$(curl -s "https://api.atlassian.com/oauth/token/accessible-resources" \
  -H "Authorization: Basic $AUTH" | jq -r '.[0].id')
echo "$CLOUD_ID"
```

If the command returns null or empty, the env file is missing or the token is invalid — see api skill "Authentication" section.

**Fallback:** If REST returns 429 (rate-limited), use MCP `getAccessibleAtlassianResources` and report the fallback to the user.

### Step 5: Verify Jira project exists

Use the `jira-project-sync:api` skill, "Verify Project Exists" recipe.

```bash
HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
  "https://$ATLASSIAN_SITE/rest/api/3/project/{PROJECT_KEY}" \
  -H "Authorization: Basic $AUTH")
echo "$HTTP"
```

- **200** → project exists, proceed
- **404** → project does not exist; tell the user to create it in Jira UI first, wait for confirmation
- **401** → bad credentials; fix `~/.claude/.env`

**Warning:** Do NOT use JQL for project verification — a JQL query against a non-existent project may return 0 results without erroring (false positive).

**Fallback:** MCP `getVisibleJiraProjects` with `searchString`.

### Step 6: Write `.claude/jira-sync.json`

Create the per-project config file:

```json
{
  "project": "{PROJECT_KEY}",
  "cloudId": "{CLOUD_ID}",
  "transitionDoneId": null
}
```

**Note:** `transitionDoneId` is null — it will be discovered automatically on the first `git push` via the sync hook.

### Step 7: Write `.claude/jira-sync-state`

**Use Bash for this** (the Write tool will fail on new files that haven't been read):

If the repo has commits:
```bash
git rev-parse HEAD > .claude/jira-sync-state
```

If no commits yet, skip this step (the hook will initialize it on first push).

### Step 8: Detect tech stack

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

### Step 9: Create CLAUDE.md

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

### Step 10: Create .gitignore

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
.claude/jira-sync-state
.claude/jira-sync-pending
```

### Step 11: Initial commit

```bash
git add -A
git commit -m "chore: project init with Jira integration"
```

### Step 12: Confirm

Tell the user:
> "Project initialized! Jira sync is configured for project {PROJECT_KEY}. Every `git push` will now automatically sync commits to Jira cards."
