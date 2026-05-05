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

Use the `jira-project-sync:api` skill, "Get Cloud ID" recipe.

```bash
source ~/.claude/.env
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)
CLOUD_ID=$(curl -s "https://api.atlassian.com/oauth/token/accessible-resources" \
  -H "Authorization: Basic $AUTH" | jq -r '.[0].id')
echo "$CLOUD_ID"
```

If null/empty, the env file is missing or the token is invalid — see api skill "Authentication".

**Fallback:** MCP `getAccessibleAtlassianResources` if REST returns 429.

### Step 5: Verify Jira project exists

Use the `jira-project-sync:api` skill, "Verify Project Exists" recipe.

```bash
HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
  "https://$ATLASSIAN_SITE/rest/api/3/project/{PROJECT_KEY}" \
  -H "Authorization: Basic $AUTH")
echo "$HTTP"
```

- **200** → project exists, proceed
- **404** → tell the user to create it in Jira UI first, wait for confirmation
- **401** → bad credentials; fix `~/.claude/.env`

**Warning:** Do NOT use JQL for project verification — false positives on non-existent projects.

**Fallback:** MCP `getVisibleJiraProjects` with `searchString` if REST returns 429.

### Step 6: Write `.claude/jira-sync.json`

```bash
mkdir -p .claude
```

Then ensure temp/state files are gitignored:

```bash
# Add to .gitignore if not already present
grep -qxF '.claude/jira-sync-state' .gitignore 2>/dev/null || echo '.claude/jira-sync-state' >> .gitignore
grep -qxF '.claude/jira-sync-pending' .gitignore 2>/dev/null || echo '.claude/jira-sync-pending' >> .gitignore
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

**Note on semantic grouping for onboard:** Onboard creates the initial card set from scratch — there are no existing tickets to comment on. The Semantic Grouping Algorithm in the `jira-project-sync:api` skill applies to the *ongoing* sync hook (every push), NOT to onboard's initial import. For onboard, grouping was already done in Step 7d using `commit-grouping.md` rules; Step 8 simply creates one Jira card per group.

All Jira operations below use REST API recipes from the api skill. MCP remains as fallback (use only if REST returns 429).

#### First pending card (with transition discovery):

1. **Create the Jira issue** using the api skill "Create Issue" recipe.

The description must be ADF (Atlassian Document Format). Build it with `jq` to handle escaping safely:

```bash
source ~/.claude/.env
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)

DESC_TEXT="Commits imported from git history:

| Hash | Date | Author | Message |
|------|------|--------|---------|
| {hash} | {date} | {author} | {message} |
..."

PAYLOAD=$(jq -n \
  --arg projectKey "$PROJECT_KEY" \
  --arg summary "$CARD_SUMMARY" \
  --arg desc "$DESC_TEXT" '{
    fields: {
      project: {key: $projectKey},
      issuetype: {name: "Task"},
      summary: $summary,
      description: {
        type: "doc",
        version: 1,
        content: [{type: "paragraph", content: [{type: "text", text: $desc}]}]
      }
    }
  }')

NEW_KEY=$(curl -s -X POST "https://$ATLASSIAN_SITE/rest/api/3/issue" \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" | jq -r '.key')
echo "Created: $NEW_KEY"
```

2. **Discover transition Done ID** using the api skill "Get Transitions" recipe:

```bash
DISCOVERED_ID=$(curl -s "https://$ATLASSIAN_SITE/rest/api/3/issue/$NEW_KEY/transitions" \
  -H "Authorization: Basic $AUTH" \
  | jq -r '.transitions[] | select(.to.statusCategory.key == "done") | .id' | head -1)
echo "$DISCOVERED_ID"
```

**Warning:** Do NOT hardcode or assume a specific transition ID. Always discover it dynamically from the `statusCategory.key == "done"` match.

3. **Update `.claude/jira-sync.json`:** Add `"transitionDoneId": "{DISCOVERED_ID}"` to the config JSON.

4. **Update the plan file header:** Add `Transition Done ID: {DISCOVERED_ID}` line.

5. **Transition to Done** using the api skill "Transition Issue" recipe:

```bash
curl -s -o /dev/null -w "%{http_code}" -X POST \
  "https://$ATLASSIAN_SITE/rest/api/3/issue/$NEW_KEY/transitions" \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -d "{\"transition\": {\"id\": \"$DISCOVERED_ID\"}}"
```

204 = success. Note the `transition` field is an object `{"id": "..."}`, not a flat string.

6. **Update the plan file:** Change `Status: pending` to `Status: created:{ISSUE_KEY}` for that card.

#### Remaining pending cards:

For each remaining card with `Status: pending`:

1. **Create the Jira issue** using the same `curl` recipe as the first card (api skill "Create Issue"). Reuse `$DISCOVERED_ID` from the first card — no need to re-discover.

2. **Transition to Done** using the discovered transition ID (api skill "Transition Issue"):

```bash
curl -s -o /dev/null -w "%{http_code}" -X POST \
  "https://$ATLASSIAN_SITE/rest/api/3/issue/$NEW_KEY/transitions" \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -d "{\"transition\": {\"id\": \"$DISCOVERED_ID\"}}"
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
