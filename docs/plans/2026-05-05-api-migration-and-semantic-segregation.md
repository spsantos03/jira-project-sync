# API Migration & Semantic Segregation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** (1) Migrate all Jira operations in this plugin from Atlassian MCP to REST API as the primary path, keeping MCP as optional fallback. (2) Replace the binary "ref → comment, no exceptions" rule with a 3-layer semantic algorithm that prevents both duplication AND false grouping.

**Architecture:** The `api` skill becomes the **single source of truth** for all Jira operations and the semantic-grouping algorithm. The hook script's stderr instructions, `init` skill, and `onboard` skill all reference the `api` skill rather than embedding logic. The MCP plugin stays enabled but is only used as a read-only fallback if the REST API rate-limits or fails.

**Tech Stack:** Bash (hook + curl), Markdown (skill files), JSON (ADF for write payloads), HTML (`expand=renderedFields` for read).

**Key decisions (locked in):**
- D1: Keep MCP plugin enabled as optional fallback. New code paths default to REST API.
- D2: Hybrid format — read uses `?expand=renderedFields` (HTML, easy to scan), write uses ADF JSON (API v3 requirement).
- D3: `api` skill = SSOT for both operations and semantic-grouping rules. Other skills/scripts reference it.
- D4: Semantic algorithm = Conservative (Level A) with 3-layer search: (a) ref → fits scope → comment on ref'd ticket; (b) ref → doesn't fit → search OTHER existing tickets semantically → comment if match; (c) no match anywhere → create new (with `is related to` link if there was a ref).

**Files affected:**
- `plugins/jira-project-sync/skills/api/SKILL.md` (expand significantly — becomes SSOT)
- `plugins/jira-project-sync/scripts/jira-sync.sh` (instructions reference api skill + new algorithm)
- `plugins/jira-project-sync/skills/init/SKILL.md` (replace MCP with curl recipes from api skill)
- `plugins/jira-project-sync/skills/onboard/SKILL.md` (replace MCP with curl recipes; align Step 8 with new algorithm)
- `plugins/jira-project-sync/skills/onboard/references/commit-grouping.md` (add cross-reference to api skill SSOT)
- `~/.claude/CLAUDE.md` (Jira section: API-first, MCP as fallback)
- Plugin cache (sync from source after each task)

**Jira tracking:** Each task creates a JPSP ticket *before* the commit (per CLAUDE.md global rule). Commit message format: `feat(JPSP-XX): description` or `refactor(JPSP-XX): description`.

**Verification before declaring complete:**
- All `mcp__plugin_atlassian_atlassian__*` references in skills replaced with curl recipes (or explicit "fallback" labels)
- Hook script `bash -n` syntax check passes
- Plugin cache files match source files (diff returns empty)
- Semantic-grouping algorithm appears verbatim in `api` skill SSOT and is referenced (not duplicated) by hook output and onboard Step 8

---

### Task 1: Expand `api` skill — make it the SSOT

**Ticket:** Create JPSP ticket "Expand api skill into SSOT for all Jira operations" before commit.

**Files:**
- Modify: `plugins/jira-project-sync/skills/api/SKILL.md`

**Step 1: Update frontmatter description**

Change from:
```yaml
description: Direct Atlassian REST API operations that the MCP server cannot do — delete issues, bulk delete, delete comments, move issues, manage labels.
```

To:
```yaml
description: All Atlassian REST API operations for the Jira sync plugin. Single source of truth for create/read/update/delete/transition/search and the semantic-grouping algorithm. Use whenever talking to Jira from this plugin's hooks or skills.
```

**Step 2: Restructure the skill file**

New top-level structure:

```markdown
# jira-project-sync:api

REST API recipes for all Jira operations + the semantic-grouping algorithm.
This is the single source of truth — other skills and the sync hook reference
this file rather than embedding their own logic.

## Authentication
[existing block — unchanged]

## Decision: REST API vs MCP fallback
[NEW SECTION]

## Operations
  ### Get Cloud ID
  ### Verify Project Exists
  ### Search Issues by JQL
  ### Get Issue (Read)
  ### Create Issue
  ### Add Comment
  ### Get Transitions
  ### Transition Issue
  ### Create Issue Link
  ### Delete Issue
  ### Bulk Delete by JQL
  ### Delete Comment
  ### Move Issue to Another Project
  ### Manage Labels

## Semantic Grouping Algorithm
[NEW SECTION — the SSOT for classification]

## ADF Templates
[NEW SECTION — copy-paste blocks for prose paragraph content]

## Error Reference
[existing block — unchanged]
```

**Step 3: Add "Decision: REST API vs MCP fallback" section**

```markdown
## Decision: REST API vs MCP fallback

**Default to REST API for everything.** Reasons:
- Self-contained (only needs `~/.claude/.env`); no plugin dependency
- Stable — Atlassian MCP plugin disconnects mid-session and tools become unusable
- Same auth surface for read and write

**MCP is allowed as fallback only when:**
1. REST API returns 429 (rate-limited) and retry budget is exhausted
2. The user explicitly asks for MCP

When using MCP as fallback, log to the user that you're falling back, with reason. Never silently use MCP.
```

**Step 4: Add new operation recipes**

Add the following operations in the order listed, each as its own `### ` subsection. Each must include: the curl command, the expected HTTP code on success, and a brief explanation of when to use it.

#### Get Cloud ID

```bash
source ~/.claude/.env
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)

curl -s "https://api.atlassian.com/oauth/token/accessible-resources" \
  -H "Authorization: Basic $AUTH" | jq -r '.[0].id'
```

Returns the Cloud ID string (UUID format). Use during init/onboard.

#### Verify Project Exists

```bash
curl -s "https://$ATLASSIAN_SITE/rest/api/3/project/{PROJECT_KEY}" \
  -H "Authorization: Basic $AUTH" -w "\n%{http_code}"
```

200 = exists, 404 = does not exist. Do NOT use JQL for verification (false positives on non-existent projects).

#### Search Issues by JQL

```bash
curl -s -G "https://$ATLASSIAN_SITE/rest/api/3/search/jql" \
  -H "Authorization: Basic $AUTH" \
  --data-urlencode "jql={JQL}" \
  --data-urlencode "fields=summary,status,issuetype" \
  --data-urlencode "maxResults=50" | jq '.issues[] | {key, summary: .fields.summary, status: .fields.status.name}'
```

Use for: finding existing tickets to comment on, listing tickets in semantic-grouping search.

#### Get Issue (Read with rendered HTML)

```bash
curl -s "https://$ATLASSIAN_SITE/rest/api/3/issue/{ISSUE_KEY}?fields=summary,description&expand=renderedFields" \
  -H "Authorization: Basic $AUTH" | jq '{key, summary: .fields.summary, descriptionHtml: .renderedFields.description}'
```

Use for: reading a ticket's title + description before deciding whether the commit fits its scope (semantic algorithm Step 1.2).

#### Create Issue

ADF body is required. Template for plain prose description:

```bash
curl -s -X POST "https://$ATLASSIAN_SITE/rest/api/3/issue" \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -d '{
    "fields": {
      "project": {"key": "{PROJECT_KEY}"},
      "issuetype": {"name": "Task"},
      "summary": "{SUMMARY}",
      "description": {
        "type": "doc",
        "version": 1,
        "content": [
          {"type": "paragraph", "content": [{"type": "text", "text": "{DESCRIPTION_TEXT}"}]}
        ]
      }
    }
  }' | jq '{key, id}'
```

For multi-paragraph or table content, see "ADF Templates" section below.

#### Add Comment

```bash
curl -s -X POST "https://$ATLASSIAN_SITE/rest/api/3/issue/{ISSUE_KEY}/comment" \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -d '{
    "body": {
      "type": "doc",
      "version": 1,
      "content": [
        {"type": "paragraph", "content": [{"type": "text", "text": "{COMMENT_TEXT}"}]}
      ]
    }
  }' | jq '.id'
```

#### Get Transitions

```bash
curl -s "https://$ATLASSIAN_SITE/rest/api/3/issue/{ISSUE_KEY}/transitions" \
  -H "Authorization: Basic $AUTH" | jq '.transitions[] | {id, name, statusCategory: .to.statusCategory.key}'
```

Use during onboard's first-card discovery: filter `where statusCategory == "done"`, save the `id`.

#### Transition Issue

```bash
curl -s -X POST "https://$ATLASSIAN_SITE/rest/api/3/issue/{ISSUE_KEY}/transitions" \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -d '{"transition": {"id": "{TRANSITION_ID}"}}' \
  -o /dev/null -w "%{http_code}"
```

204 = success.

#### Create Issue Link

```bash
curl -s -X POST "https://$ATLASSIAN_SITE/rest/api/3/issueLink" \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -d '{
    "type": {"name": "Relates"},
    "inwardIssue": {"key": "{NEW_ISSUE_KEY}"},
    "outwardIssue": {"key": "{REFERENCED_ISSUE_KEY}"}
  }' \
  -o /dev/null -w "%{http_code}"
```

201 = success. Use this when the semantic algorithm decides "ref'd ticket exists but commit is separate scope" → create new + link to ref.

**Step 5: Add "Semantic Grouping Algorithm" section**

This is the SSOT block that hook output and onboard Step 8 must reference (not duplicate).

```markdown
## Semantic Grouping Algorithm

Apply this algorithm to every commit when deciding where it goes in Jira.

### Inputs
- The commit message (subject + body)
- Optional ref: a `{PROJECT}-N` pattern in the commit message
- The list of OPEN tickets in the project (or the most recent N if too many)

### Algorithm

```
function classifyCommit(commit, openTickets):
  ref = extractRef(commit.message)  // e.g., "JPSP-13" or null

  if ref is not null:
    target = readIssue(ref)  // get summary + description (HTML)
    if commitScopeFitsTicket(commit, target):
      return COMMENT_ON(ref)  // follow-up case (most common)
    else:
      // ref doesn't fit — search for a better home
      candidate = findSemanticMatch(commit, openTickets minus ref)
      if candidate is not null:
        return COMMENT_ON(candidate, mention=ref)
      else:
        return CREATE_NEW(commit, link_to=ref, link_type="Relates")

  else:  // no ref
    candidate = findSemanticMatch(commit, openTickets)
    if candidate is not null:
      return COMMENT_ON(candidate)
    else:
      return CREATE_NEW(commit)
```

### Definitions

**`commitScopeFitsTicket(commit, ticket)` — return true when:**
- The commit's primary purpose is a *follow-up* of the ticket's described work (e.g., bug fix in the same feature, refactor of code introduced by the ticket, doc update for the same module)
- OR the commit's subject explicitly addresses something stated in the ticket's description
- Default to TRUE when uncertain (Conservative / Level A bias — the dev wrote the ref deliberately)

Return false ONLY when:
- The commit is *demonstrably* about a different topic, area, or feature
- The ref appears to be a stale or accidental mention (e.g., copy-paste from another commit)

**`findSemanticMatch(commit, tickets)` — return the best ticket when:**
- A ticket's summary or description shares the commit's primary topic, module, or feature area
- Confidence threshold: high (avoid grouping under "vaguely related" tickets — when in doubt, return null and let CREATE_NEW happen)

Return null otherwise.

### Why this is conservative

The default branch is always to attach to existing work (ref'd or semantically matched). New tickets are created only when:
1. There's no ref AND no semantic match, OR
2. There's a ref that demonstrably doesn't fit AND no other match.

This preserves the no-duplicate invariant while introducing a no-false-grouping invariant.
```

**Step 6: Add "ADF Templates" section**

```markdown
## ADF Templates

ADF (Atlassian Document Format) is required for create/comment/edit bodies.

### Single paragraph

```json
{
  "type": "doc",
  "version": 1,
  "content": [
    {"type": "paragraph", "content": [{"type": "text", "text": "Your text here."}]}
  ]
}
```

### Multiple paragraphs

```json
{
  "type": "doc",
  "version": 1,
  "content": [
    {"type": "paragraph", "content": [{"type": "text", "text": "First paragraph."}]},
    {"type": "paragraph", "content": [{"type": "text", "text": "Second paragraph."}]}
  ]
}
```

### Code block

```json
{
  "type": "codeBlock",
  "attrs": {"language": "bash"},
  "content": [{"type": "text", "text": "git push origin main"}]
}
```

### Table (use sparingly — manual ADF tables are verbose)

For commit-history tables in onboard descriptions, prefer rendering the table as Markdown text inside a code block, OR use multiple paragraphs with pipe-delimited rows. Skip full ADF table nodes unless rendering fidelity is critical.
```

**Step 7: Replace "When to Use This vs MCP" section**

Replace the existing decision table with:

```markdown
## When to Use This vs MCP (Decision Table)

| Operation | Default | Fallback |
|-----------|---------|----------|
| Get Cloud ID | REST | MCP `getAccessibleAtlassianResources` |
| Verify project | REST | MCP `getVisibleJiraProjects` |
| Search issues (JQL) | REST | MCP `searchJiraIssuesUsingJql` |
| Get issue | REST | MCP `getJiraIssue` |
| Create issue | REST | MCP `createJiraIssue` |
| Add comment | REST | MCP `addCommentToJiraIssue` |
| Get transitions | REST | MCP `getTransitionsForJiraIssue` |
| Transition | REST | MCP `transitionJiraIssue` |
| Create link | REST | MCP `createIssueLink` |
| Delete issue | REST (only option) | — |
| Bulk delete | REST (only option) | — |
| Delete comment | REST (only option) | — |
| Move issue | REST (only option) | — |
| Manage labels | REST | MCP `editJiraIssue` (awkward) |

Use MCP only when REST returns 429 and retry budget is exhausted, or when the user explicitly asks for MCP.
```

**Step 8: Verify the rewritten file**

Read the file back. Confirm:
- All ten new operations have curl recipes
- Semantic Grouping Algorithm section exists and is the canonical version
- ADF Templates section has at least 3 templates
- No remaining language saying "MCP for create/read/comment/transition" as the primary path

**Step 9: Commit**

```bash
git add plugins/jira-project-sync/skills/api/SKILL.md
git commit -m "refactor(JPSP-XX): expand api skill into SSOT for all Jira operations"
```

Replace `JPSP-XX` with the ticket key created at the start of this task.

---

### Task 2: Update hook script — reference api skill, new algorithm

**Ticket:** Create JPSP ticket "Hook references api skill SSOT and uses 3-layer semantic algorithm" before commit.

**Files:**
- Modify: `plugins/jira-project-sync/scripts/jira-sync.sh`

**Step 1: Replace the lines 105-119 block in PENDING_FILE template**

Current:
```
2. Para cada commit acima, primeiro verifique se a mensagem contem uma referencia a ticket ($PROJECT-\d+):
   - Se contem $PROJECT-XX → adicione o commit como comentario no ticket referenciado (NUNCA crie card novo)
   - Se NAO contem referencia a ticket, avalie semanticamente:
     - Se o assunto JA existe em um card → adicione o commit como comentario no card
     - Se e assunto NOVO → crie um novo card (Task) com descricao detalhada${TRANSITION_INSTR}
```

New:
```
2. Para cada commit acima, aplique o algoritmo de classificacao da skill jira-project-sync:api (secao "Semantic Grouping Algorithm"):
   a. Se o commit tem ref ($PROJECT-\d+):
      - Leia titulo+descricao do ticket referenciado (api skill: "Get Issue")
      - Se o escopo primario do commit cabe no ticket → comente no ticket (api skill: "Add Comment")
      - Se NAO cabe → busque outros tickets candidatos por similaridade semantica (api skill: "Search Issues by JQL")
        - Match encontrado → comente no candidato com mencao "see also $PROJECT-XX"
        - Sem match → crie ticket novo (api skill: "Create Issue") + link "Relates" para o ref (api skill: "Create Issue Link")
   b. Se o commit NAO tem ref → busca semantica classica (api skill: "Search Issues by JQL")
      - Match → comente no candidato
      - Sem match → crie ticket novo${TRANSITION_INSTR}

   Quando em duvida sobre "cabe no escopo": comente (default conservador). So divirja quando claramente eh outro topico.
```

**Step 2: Replace the same block in the stderr output (lines 137-145)**

Apply the same replacement to the second instance of these instructions in the `cat >&2` block.

**Step 3: Update the "Instrucoes" preamble in both blocks**

Add a leading line:

```
**Use a skill jira-project-sync:api para todas as operacoes (REST API). MCP eh fallback opcional.**
```

Place this line immediately after the `Instrucoes:` header in both the pending-file and stderr blocks.

**Step 4: Verify syntax**

```bash
bash -n plugins/jira-project-sync/scripts/jira-sync.sh
```

Expected: no output.

**Step 5: Sync to plugin cache**

```bash
cp plugins/jira-project-sync/scripts/jira-sync.sh ~/.claude/plugins/cache/local-plugins/jira-project-sync/1.0.0/scripts/jira-sync.sh
```

**Step 6: Commit**

```bash
git add plugins/jira-project-sync/scripts/jira-sync.sh
git commit -m "feat(JPSP-XX): hook references api skill SSOT and uses 3-layer semantic algorithm"
```

---

### Task 3: Refactor `init` skill — REST API for cloud ID and project verification

**Ticket:** Create JPSP ticket "Migrate init skill from MCP to REST API" before commit.

**Files:**
- Modify: `plugins/jira-project-sync/skills/init/SKILL.md`

**Step 1: Update Step 4 (Auto-detect Atlassian Cloud ID)**

Replace:
```
Use the Atlassian MCP tool `getAccessibleAtlassianResources` to fetch the user's Cloud ID.

```
Tool: mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources
```

Extract the `id` field from the first accessible resource. This is the Cloud ID.
```

With:
```
Use the `jira-project-sync:api` skill, "Get Cloud ID" recipe.

Quick reference (see api skill for full context):

```bash
source ~/.claude/.env
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)
CLOUD_ID=$(curl -s "https://api.atlassian.com/oauth/token/accessible-resources" \
  -H "Authorization: Basic $AUTH" | jq -r '.[0].id')
echo "$CLOUD_ID"
```

If the command returns null or empty, the env file is missing or the token is invalid — see api skill "Authentication" for the fix.

**Fallback:** If REST is rate-limited, use MCP `getAccessibleAtlassianResources` and report the fallback to the user.
```

**Step 2: Update Step 5 (Verify Jira project exists)**

Replace the MCP block with:

```
Use the `jira-project-sync:api` skill, "Verify Project Exists" recipe.

```bash
HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
  "https://$ATLASSIAN_SITE/rest/api/3/project/{PROJECT_KEY}" \
  -H "Authorization: Basic $AUTH")
echo "$HTTP"
```

- 200 → project exists, proceed
- 404 → project does not exist; tell the user to create it in Jira UI first, wait for confirmation
- 401 → bad credentials; fix `~/.claude/.env`

**Warning:** Do NOT use JQL for project verification — a JQL query against a non-existent project may return 0 results without erroring.

**Fallback:** MCP `getVisibleJiraProjects` with `searchString`.
```

**Step 3: Verify the file**

Read the full file and confirm:
- All `mcp__plugin_atlassian_atlassian__*` references are gone OR explicitly marked as "Fallback"
- Steps 4 and 5 reference the api skill

**Step 4: Sync to plugin cache**

```bash
cp plugins/jira-project-sync/skills/init/SKILL.md ~/.claude/plugins/cache/local-plugins/jira-project-sync/1.0.0/skills/init/SKILL.md
```

**Step 5: Commit**

```bash
git add plugins/jira-project-sync/skills/init/SKILL.md
git commit -m "refactor(JPSP-XX): migrate init skill from MCP to REST API"
```

---

### Task 4: Refactor `onboard` skill + commit-grouping reference

**Ticket:** Create JPSP ticket "Migrate onboard skill from MCP to REST API and align with semantic algorithm" before commit.

**Files:**
- Modify: `plugins/jira-project-sync/skills/onboard/SKILL.md`
- Modify: `plugins/jira-project-sync/skills/onboard/references/commit-grouping.md`

**Step 1: Update Step 4 (Cloud ID detection)**

Apply the same replacement as Task 3 / Step 1 (Cloud ID via REST API, MCP as fallback).

**Step 2: Update Step 5 (Verify project)**

Apply the same replacement as Task 3 / Step 2 (REST API project endpoint, MCP as fallback).

**Step 3: Update Step 8 — replace MCP createJiraIssue and transitions with REST**

In the "First pending card (with transition discovery)" subsection:

Replace:
```
1. **Create the Jira issue** (same as normal):

```
Tool: mcp__plugin_atlassian_atlassian__createJiraIssue
cloudId: {CLOUD_ID}
projectKey: {PROJECT_KEY}
issueTypeName: "Task"
summary: {card summary from plan}
description: |
  Commits imported from git history:
  ...
```
```

With:
```
1. **Create the Jira issue** using the api skill "Create Issue" recipe.

The description must be ADF format. For the commit-history table, use a code block (see api skill "ADF Templates" → "Code block"):

```bash
DESC_JSON=$(jq -n --arg text "Commits imported from git history:

| Hash | Date | Author | Message |
|------|------|--------|---------|
| {hash} | {date} | {author} | {message} |
..." '{
  "type": "doc",
  "version": 1,
  "content": [
    {"type": "paragraph", "content": [{"type": "text", "text": $text}]}
  ]
}')

NEW_KEY=$(curl -s -X POST "https://$ATLASSIAN_SITE/rest/api/3/issue" \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -d "{\"fields\": {\"project\":{\"key\":\"$PROJECT_KEY\"},\"issuetype\":{\"name\":\"Task\"},\"summary\":\"$SUMMARY\",\"description\":$DESC_JSON}}" | jq -r '.key')
```
```

For Step 8.2 (transitions discovery), replace MCP `getTransitionsForJiraIssue` with the api skill "Get Transitions" recipe.

For Step 8.5 (transition to Done), replace MCP `transitionJiraIssue` with the api skill "Transition Issue" recipe.

**Step 4: Update "Remaining pending cards" subsection**

Same replacements: REST recipes for create + transition.

**Step 5: Update Step 8 to apply the new semantic algorithm**

The current onboard skill imports an entire commit history into NEW cards (no existing-tickets-to-comment-on case). For onboard specifically, semantic grouping is across the COMMIT GROUPS (not against existing Jira tickets). Add a clarifying note at the top of Step 8:

```
**Note on semantic grouping for onboard:** Onboard creates the initial card set from scratch — there are no existing tickets to comment on. The semantic-grouping algorithm in the api skill applies to the *ongoing* sync hook, not to onboard's initial import. For onboard, follow the rules in `commit-grouping.md` to group commits into cards before creating any issues.
```

**Step 6: Update `commit-grouping.md`**

Add a new section at the top, after the intro paragraph:

```markdown
## Relationship to the api skill SSOT

This file covers the **initial import** case (onboard): how to group raw commits into cards when no Jira tickets exist yet.

For the **ongoing sync** case (hook on every push), the algorithm lives in the
`jira-project-sync:api` skill, section "Semantic Grouping Algorithm". That algorithm
decides: ref vs no-ref, comment-on-existing vs create-new, with link-to-ref logic.

The two are complementary, not duplicate:
- **commit-grouping.md (this file):** "How do I cluster N raw commits into M card summaries?"
- **api skill SGA:** "Given one commit and a set of existing tickets, what action do I take?"
```

**Step 7: Verify the files**

Read both files. Confirm:
- All `mcp__plugin_atlassian_atlassian__*` references are gone OR marked as fallback
- Step 8 of onboard uses curl recipes from api skill
- commit-grouping.md cross-references the api skill SSOT

**Step 8: Sync to plugin cache**

```bash
cp plugins/jira-project-sync/skills/onboard/SKILL.md ~/.claude/plugins/cache/local-plugins/jira-project-sync/1.0.0/skills/onboard/SKILL.md
cp plugins/jira-project-sync/skills/onboard/references/commit-grouping.md ~/.claude/plugins/cache/local-plugins/jira-project-sync/1.0.0/skills/onboard/references/commit-grouping.md
```

**Step 9: Commit**

```bash
git add plugins/jira-project-sync/skills/onboard/SKILL.md plugins/jira-project-sync/skills/onboard/references/commit-grouping.md
git commit -m "refactor(JPSP-XX): migrate onboard skill from MCP to REST API and align with semantic algorithm"
```

---

### Task 5: Update global CLAUDE.md — Jira section

**Ticket:** Create JPSP ticket "Update global CLAUDE.md to document API-first Jira workflow" before commit.

**Files:**
- Modify: `~/.claude/CLAUDE.md` (this is OUTSIDE the repo — commit step changes accordingly)

**Step 1: Find the "Integracao Jira (Global)" section**

Locate the section that begins with `# Integracao Jira (Global)` and ends before `# REGRA CRITICA: RASTREABILIDADE TOTAL NO JIRA`.

**Step 2: Replace the "Como Funciona" subsection**

Add a new lead bullet stating REST API is primary:

```markdown
## Como Funciona

O plugin `jira-project-sync` sincroniza commits automaticamente com Jira a cada `git push`. Operacoes Jira usam REST API por padrao (skill `jira-project-sync:api`); MCP Atlassian fica como fallback opcional. O sistema e composto por:
```

(Rest of subsection unchanged.)

**Step 3: Replace the "Deletar Tickets Jira via API" section**

This section currently says "MCP plugin NAO tem funcao de delete". Replace its first paragraph with:

```markdown
Todas as operacoes Jira do plugin usam REST API por padrao. A skill `jira-project-sync:api` documenta cada operacao com seu curl correspondente. MCP fica como fallback (rate limit ou usuario pediu explicitamente).

Exemplo — deletar issue:
```

(Keep the existing curl example below.)

**Step 4: Add a new subsection "Algoritmo de Agrupamento Semantico"**

After "Sync Manual (quando hook dispara)", add:

```markdown
## Algoritmo de Agrupamento Semantico

A regra que decide "comentar em ticket existente vs criar novo" mora na skill `jira-project-sync:api`, secao "Semantic Grouping Algorithm". Resumo:

1. Se o commit tem ref ($PROJECT-XX) E o escopo cabe no ticket → comentar no ticket (caso comum)
2. Se tem ref mas NAO cabe → buscar outro ticket candidato; comentar la se houver match; criar novo + link "Relates" se nao houver
3. Se NAO tem ref → buscar candidato; comentar se match, criar novo se nao

Default eh sempre conservador: na duvida, comente (preserva no-duplicate). So crie novo ticket quando o escopo eh demonstravelmente diferente (preserva no-false-grouping).

Esta regra eh a SSOT — nunca duplique a logica em outras skills/scripts. Sempre referencie a api skill.
```

**Step 5: Verify the changes**

Read the modified section of `~/.claude/CLAUDE.md` and confirm the three subsections are updated correctly.

**Step 6: Commit (special case — outside the repo)**

The global CLAUDE.md is NOT in this repo. Don't try to `git add` it. Instead, after editing, tell the user:

> "Updated `~/.claude/CLAUDE.md`. This file lives outside the repo — no commit needed in this project. The change takes effect immediately for all future Claude Code sessions."

---

### Task 6: Push and process Jira sync

**Step 1: Push all commits**

```bash
git push origin main
```

The hook will fire with the new instructions. Process the sync:
- For each commit pushed (Tasks 1-4), apply the new algorithm against the JPSP project
- All four commits have refs (JPSP-15 through JPSP-18); each should fit its respective ticket → comment on the ticket
- Transition each ticket to Done after commenting

**Step 2: Verify Jira state**

Search JPSP for tickets created during this implementation:

```bash
source ~/.claude/.env
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)
curl -s -G "https://$ATLASSIAN_SITE/rest/api/3/search/jql" \
  -H "Authorization: Basic $AUTH" \
  --data-urlencode "jql=project = JPSP AND created >= -1d ORDER BY created DESC" \
  --data-urlencode "fields=summary,status" | jq '.issues[] | {key, summary: .fields.summary, status: .fields.status.name}'
```

Expected: 4-5 tickets (one per task), all in Done status.

**Step 3: Cleanup pending and state files**

After successful sync:

```bash
echo "$(git rev-parse HEAD)" > .claude/jira-sync-state
rm -f .claude/jira-sync-pending
```

---

## Self-review

Before marking complete:

- [ ] `api` skill has all 14 operations (Cloud ID, Verify Project, Search, Get Issue, Create Issue, Add Comment, Get Transitions, Transition Issue, Create Issue Link, Delete Issue, Bulk Delete, Delete Comment, Move Issue, Manage Labels)
- [ ] `api` skill has the Semantic Grouping Algorithm as the SSOT
- [ ] `api` skill has ADF templates section
- [ ] Hook script references the api skill (no embedded duplicate algorithm)
- [ ] `init` skill uses REST recipes for Steps 4 and 5
- [ ] `onboard` skill uses REST recipes for Steps 4, 5, and 8
- [ ] `commit-grouping.md` cross-references the api skill SSOT
- [ ] `~/.claude/CLAUDE.md` Jira section reflects API-first
- [ ] All edits synced to plugin cache (`diff` returns no differences)
- [ ] All commits use `feat(JPSP-XX):` or `refactor(JPSP-XX):` format
- [ ] All JPSP tickets transitioned to Done after final push
- [ ] Hook fires after final push and the new instructions are visible (exit 2 + stderr from previous fix)
