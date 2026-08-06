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
CLOUD_ID=$(curl -s "https://$ATLASSIAN_SITE/_edge/tenant_info" | jq -r '.cloudId')
echo "$CLOUD_ID"
```

This endpoint is unauthenticated and site-scoped. **Do NOT use `api.atlassian.com/oauth/token/accessible-resources`** — it accepts only OAuth Bearer tokens and returns 401 with the API token in `~/.claude/.env`.

If this returns null or empty, `ATLASSIAN_SITE` is wrong or unset. To check the *token* separately:

```bash
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)
curl -s "https://$ATLASSIAN_SITE/rest/api/3/myself" -H "Authorization: Basic $AUTH" | jq -r '.displayName'
```

### Step 5: Verify — or create — the Jira project

Use the `jira-project-sync:api` skill, "Verify Project Exists" recipe.

```bash
source ~/.claude/.env
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)
HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
  "https://$ATLASSIAN_SITE/rest/api/3/project/{PROJECT_KEY}" \
  -H "Authorization: Basic $AUTH")
echo "$HTTP"
```

- **200** → project exists, proceed to Step 6
- **401** → bad credentials; fix `~/.claude/.env`
- **404** → project does not exist; **create it via the API** (below). Do not tell the user to create it in the Jira UI.

**Warning:** Do NOT use JQL for project verification — a JQL query against a non-existent project may return 0 results without erroring (false positive).

#### On 404: create the project

Use the `jira-project-sync:api` skill, **"Create Project"** recipe. Summary of that flow:

1. **Discover template keys** — `GET /rest/project-templates/1.0/templates`. Never guess them; software keys live under `com.pyxis.greenhopper.jira`, and `com.pyxis.jira:*` is a common invention that does not exist.
2. **Match the site convention** — check an existing project's board type so the new project looks like its siblings:
   ```bash
   curl -s "https://$ATLASSIAN_SITE/rest/agile/1.0/board?maxResults=5" \
     -H "Authorization: Basic $AUTH" | jq -r '.values[] | "\(.type)\t\(.name)"'
   ```
   Kanban (`com.pyxis.greenhopper.jira:gh-kanban-template`) is the usual default.
3. **Create** with `POST /rest/api/3/project`, passing `projectTemplateKey`, `leadAccountId` (from `GET /rest/api/3/myself`), and `assigneeType: "PROJECT_LEAD"`.
4. **Verify the template applied** — a 201 is not enough. Confirm the project has a `{KEY} board` and the full issue type set (`Task, Sub-task, Story, Bug, Epic`). If issue types are only `Task` + `Sub-task`, the template did not apply: the project is unusable, so delete it (`?enableUndo=false`) and retry with a valid key rather than patching it by hand.

Report the created project key, board, and issue types to the user before continuing.

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

If the repo already has commits (i.e. `git init` was skipped in Step 1 because the repo existed):
```bash
git rev-parse HEAD > .claude/jira-sync-state
```

If there are no commits yet — the normal case for a brand-new project — skip this step. Step 11 writes the state file after the initial commit.

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
.DS_Store
.claude/jira-sync-state
.claude/jira-sync-pending
gitignore/
```

Also create the `gitignore/` folder itself (`mkdir -p gitignore`) — it holds local, unversioned notes, drafts, and credentials.

**`.claude/jira-sync-state` must be gitignored** — versioning it causes a commit → sync → state → commit loop. `.claude/jira-sync.json` *is* versioned. Verify with `git check-ignore -v .claude/jira-sync-state`.

### Step 11: Initial commit

```bash
git add -A
git commit -m "chore: project init with Jira integration"
```

This bootstrap commit is the **one sanctioned exception** to the "every commit references a ticket" rule — the project has no tickets yet. The first `git push` will create the initial card for it. Every commit after this one must carry a `{PROJECT_KEY}-N` ref.

Then record the synced commit so the hook doesn't reprocess history:

```bash
git rev-parse HEAD > .claude/jira-sync-state
```

### Step 12: Confirm

Tell the user, filling in what was actually created:
> "Project initialized! Jira sync is configured for project {PROJECT_KEY} ({BOARD_NAME}, issue types: {ISSUE_TYPES}). Every `git push` will now automatically sync commits to Jira cards, using the `{PROJECT_KEY}-N` commit convention."

If the repo has no remote yet, say so — the sync hook can't fire until there's something to push to.
