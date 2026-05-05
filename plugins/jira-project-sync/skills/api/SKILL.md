---
name: api
description: All Atlassian REST API operations for the Jira sync plugin. Single source of truth for create/read/update/delete/transition/search and the semantic-grouping algorithm. Use whenever talking to Jira from this plugin's hooks or skills.
---

# jira-project-sync:api

REST API recipes for all Jira operations + the semantic-grouping algorithm. This is the single source of truth — other skills and the sync hook reference this file rather than embedding their own logic.

## Authentication

All operations require credentials from `~/.claude/.env`:

```bash
source ~/.claude/.env
# Required vars: ATLASSIAN_EMAIL, ATLASSIAN_API_TOKEN, ATLASSIAN_SITE
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)
```

**Before running any operation:** Verify the env file exists and has the required variables. If missing, tell the user:
> "Missing `~/.claude/.env` with `ATLASSIAN_EMAIL`, `ATLASSIAN_API_TOKEN`, and `ATLASSIAN_SITE`. Generate an API token at https://id.atlassian.com/manage-profile/security/api-tokens"

## Decision: REST API vs MCP fallback

**Default to REST API for everything.** Reasons:
- Self-contained (only needs `~/.claude/.env`); no plugin dependency
- Stable — Atlassian MCP plugin disconnects mid-session and tools become unusable
- Same auth surface for read and write

**MCP is allowed as fallback only when:**
1. REST API returns 429 (rate-limited) and retry budget is exhausted
2. The user explicitly asks for MCP

When using MCP as fallback, log to the user that you're falling back, with reason. Never silently use MCP.

## Operations

Each operation is self-contained. Pick the one that matches your need.

---

### Get Cloud ID

Discover the Atlassian Cloud ID for the user's site. Use during init/onboard.

```bash
source ~/.claude/.env
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)

curl -s "https://api.atlassian.com/oauth/token/accessible-resources" \
  -H "Authorization: Basic $AUTH" | jq -r '.[0].id'
```

Returns the Cloud ID string (UUID format). If the command returns null or empty, the env file is missing or the token is invalid.

**Fallback:** MCP `getAccessibleAtlassianResources`.

---

### Verify Project Exists

Check whether a Jira project exists. Returns 200 if it does, 404 if not.

```bash
source ~/.claude/.env
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)

curl -s -o /dev/null -w "%{http_code}" \
  "https://$ATLASSIAN_SITE/rest/api/3/project/{PROJECT_KEY}" \
  -H "Authorization: Basic $AUTH"
```

| HTTP Code | Meaning |
|-----------|---------|
| 200 | Project exists, proceed |
| 404 | Project does not exist; tell the user to create it in Jira UI first |
| 401 | Bad credentials; fix `~/.claude/.env` |

**Warning:** Do NOT use JQL for project verification — a JQL query against a non-existent project may return 0 results without erroring (false positive).

**Fallback:** MCP `getVisibleJiraProjects` with `searchString`.

---

### Search Issues by JQL

Find issues matching a JQL query.

```bash
source ~/.claude/.env
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)

curl -s -G "https://$ATLASSIAN_SITE/rest/api/3/search/jql" \
  -H "Authorization: Basic $AUTH" \
  --data-urlencode "jql={JQL}" \
  --data-urlencode "fields=summary,status,issuetype" \
  --data-urlencode "maxResults=50" \
  | jq '.issues[] | {key, summary: .fields.summary, status: .fields.status.name}'
```

Use for: finding existing tickets to comment on, listing tickets in semantic-grouping search, project-wide queries.

**Fallback:** MCP `searchJiraIssuesUsingJql`.

---

### Get Issue (Read with rendered HTML)

Read a ticket's title + description. Use the `expand=renderedFields` flag so Atlassian returns HTML instead of raw ADF — much easier to scan semantically.

```bash
source ~/.claude/.env
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)

curl -s "https://$ATLASSIAN_SITE/rest/api/3/issue/{ISSUE_KEY}?fields=summary,description&expand=renderedFields" \
  -H "Authorization: Basic $AUTH" \
  | jq '{key, summary: .fields.summary, descriptionHtml: .renderedFields.description}'
```

Use for: reading a ticket's title + description before deciding whether the commit fits its scope (Semantic Grouping Algorithm Step 1.2 below).

**Fallback:** MCP `getJiraIssue` with `responseContentFormat: "markdown"`.

---

### Create Issue

ADF body is required for `description`. Template for plain prose:

```bash
source ~/.claude/.env
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)

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

For multi-paragraph or table content, see [ADF Templates](#adf-templates) below. For epics, change `issuetype.name` to `"Epic"`. To set parent (subtask): add `"parent": {"key": "{PARENT_KEY}"}` to `fields`.

**Fallback:** MCP `createJiraIssue`.

---

### Add Comment

```bash
source ~/.claude/.env
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)

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
  }' | jq '{id}'
```

To use shell variables in the comment text, build the JSON with `jq` to handle escaping:

```bash
COMMENT_TEXT="Multi-line comment with \"quotes\" and special chars"
BODY=$(jq -n --arg text "$COMMENT_TEXT" '{
  body: {
    type: "doc",
    version: 1,
    content: [{type: "paragraph", content: [{type: "text", text: $text}]}]
  }
}')

curl -s -X POST "https://$ATLASSIAN_SITE/rest/api/3/issue/{ISSUE_KEY}/comment" \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -d "$BODY" | jq '{id}'
```

**Fallback:** MCP `addCommentToJiraIssue`.

---

### Get Transitions

List the workflow transitions available for an issue.

```bash
source ~/.claude/.env
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)

curl -s "https://$ATLASSIAN_SITE/rest/api/3/issue/{ISSUE_KEY}/transitions" \
  -H "Authorization: Basic $AUTH" \
  | jq '.transitions[] | {id, name, statusCategory: .to.statusCategory.key}'
```

To find the Done transition specifically:

```bash
curl -s "https://$ATLASSIAN_SITE/rest/api/3/issue/{ISSUE_KEY}/transitions" \
  -H "Authorization: Basic $AUTH" \
  | jq -r '.transitions[] | select(.to.statusCategory.key == "done") | .id' | head -1
```

Use this during onboard's first-card discovery to populate `transitionDoneId` in the project config.

**Warning:** Do NOT hardcode or assume a specific transition ID — workflows differ per project.

**Fallback:** MCP `getTransitionsForJiraIssue`.

---

### Transition Issue

Move an issue through its workflow.

```bash
source ~/.claude/.env
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)

curl -s -o /dev/null -w "%{http_code}" -X POST \
  "https://$ATLASSIAN_SITE/rest/api/3/issue/{ISSUE_KEY}/transitions" \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -d '{"transition": {"id": "{TRANSITION_ID}"}}'
```

204 = success.

**Fallback:** MCP `transitionJiraIssue`.

---

### Create Issue Link

Link two issues with a relationship type. Used by the Semantic Grouping Algorithm when a commit's ref doesn't fit the ref'd ticket but a new ticket is created — the new ticket links back to the ref with `Relates`.

```bash
source ~/.claude/.env
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)

curl -s -o /dev/null -w "%{http_code}" -X POST \
  "https://$ATLASSIAN_SITE/rest/api/3/issueLink" \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -d '{
    "type": {"name": "Relates"},
    "inwardIssue": {"key": "{NEW_ISSUE_KEY}"},
    "outwardIssue": {"key": "{REFERENCED_ISSUE_KEY}"}
  }'
```

201 = success.

To list available link types: `curl -s "https://$ATLASSIAN_SITE/rest/api/3/issueLinkType" -H "Authorization: Basic $AUTH" | jq '.issueLinkTypes[].name'`. Common: `Relates`, `Blocks`, `Duplicate`, `Cause`.

**Fallback:** MCP `createIssueLink`.

---

### Delete Issue

Delete a single Jira issue by key.

```bash
source ~/.claude/.env
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)

curl -s -o /dev/null -w "%{http_code}" -X DELETE \
  "https://$ATLASSIAN_SITE/rest/api/3/issue/{ISSUE_KEY}" \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json"
```

| HTTP Code | Meaning |
|-----------|---------|
| 204 | Deleted successfully |
| 401 | Bad credentials (wrong email or expired token) |
| 404 | Issue not found |
| 403 | No permission to delete |

**Ask for confirmation before deleting.** Show the issue key and summary.

To also delete subtasks:

```bash
curl -s -o /dev/null -w "%{http_code}" -X DELETE \
  "https://$ATLASSIAN_SITE/rest/api/3/issue/{ISSUE_KEY}?deleteSubtasks=true" \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json"
```

**No MCP fallback — MCP plugin doesn't expose delete.**

---

### Bulk Delete by JQL

Delete multiple issues matching a JQL query. **Destructive — always confirm with the user first.**

**Step 1:** Search using the "Search Issues by JQL" recipe above to show what will be deleted.

**Step 2:** Show the list and ask for confirmation:
> "Found {N} issues matching `{JQL}`. Delete all of them? This cannot be undone."

**Step 3:** Delete each issue:

```bash
source ~/.claude/.env
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)

for KEY in {ISSUE_KEY_1} {ISSUE_KEY_2} ...; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
    "https://$ATLASSIAN_SITE/rest/api/3/issue/$KEY" \
    -H "Authorization: Basic $AUTH" \
    -H "Content-Type: application/json")
  echo "$KEY: $HTTP_CODE"
done
```

Report results: how many deleted (204), how many failed.

---

### Delete Comment

**Step 1:** List comments on the issue:

```bash
source ~/.claude/.env
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)

curl -s "https://$ATLASSIAN_SITE/rest/api/3/issue/{ISSUE_KEY}/comment" \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  | jq '.comments[] | {id, body: .body[:80], author: .author.displayName, created}'
```

**Step 2:** Confirm which comment to delete (show snippet + author + date).

**Step 3:** Delete:

```bash
curl -s -o /dev/null -w "%{http_code}" -X DELETE \
  "https://$ATLASSIAN_SITE/rest/api/3/issue/{ISSUE_KEY}/comment/{COMMENT_ID}" \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json"
```

204 = success.

**No MCP fallback.**

---

### Move Issue to Another Project

Move an issue to a different Jira project. The issue key changes (e.g., `JPSP-5` → `ART-12`).

```bash
source ~/.claude/.env
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)

curl -s -w "\n%{http_code}" -X POST \
  "https://$ATLASSIAN_SITE/rest/api/3/issue/{ISSUE_KEY}/move" \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -d '{
    "fields": {
      "project": {"key": "{TARGET_PROJECT_KEY}"}
    }
  }'
```

**Note:** If the target project has required fields that the source didn't, the move may fail. In that case, include the required fields in the `fields` object.

Returns the updated issue with its new key.

**No MCP fallback.**

---

### Manage Labels

Add or remove labels on an issue.

#### Add labels:

```bash
source ~/.claude/.env
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)

curl -s -o /dev/null -w "%{http_code}" -X PUT \
  "https://$ATLASSIAN_SITE/rest/api/3/issue/{ISSUE_KEY}" \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -d '{
    "update": {
      "labels": [{"add": "{LABEL_1}"}, {"add": "{LABEL_2}"}]
    }
  }'
```

#### Remove labels:

```bash
curl -s -o /dev/null -w "%{http_code}" -X PUT \
  "https://$ATLASSIAN_SITE/rest/api/3/issue/{ISSUE_KEY}" \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  -d '{
    "update": {
      "labels": [{"remove": "{LABEL}"}]
    }
  }'
```

204 = success.

**Fallback:** MCP `editJiraIssue` (awkward array handling).

---

## Semantic Grouping Algorithm

This is the **single source of truth** for deciding what to do with each commit. The hook script's stderr output and the onboard skill's Step 8 reference this section rather than duplicating the logic.

### Inputs
- The commit message (subject + body)
- Optional ref: a `{PROJECT}-N` pattern in the commit message
- The list of OPEN tickets in the project (or the most recent N if too many)

### Algorithm (3-layer search)

```
function classifyCommit(commit, openTickets):
  ref = extractRef(commit.message)  // e.g., "JPSP-13" or null

  if ref is not null:
    target = readIssue(ref)  // get summary + description (HTML)
    if commitScopeFitsTicket(commit, target):
      return COMMENT_ON(ref)              // [LAYER 1] follow-up case (most common)
    else:
      candidate = findSemanticMatch(commit, openTickets minus ref)
      if candidate is not null:
        return COMMENT_ON(candidate, mention=ref)  // [LAYER 2] better home found
      else:
        return CREATE_NEW(commit, link_to=ref, link_type="Relates")  // [LAYER 3]

  else:  // no ref
    candidate = findSemanticMatch(commit, openTickets)
    if candidate is not null:
      return COMMENT_ON(candidate)        // [LAYER 2] semantic match
    else:
      return CREATE_NEW(commit)            // [LAYER 3]
```

### Definitions

**`commitScopeFitsTicket(commit, ticket)` — return TRUE when:**
- The commit's primary purpose is a *follow-up* of the ticket's described work (e.g., bug fix in the same feature, refactor of code introduced by the ticket, doc update for the same module)
- OR the commit's subject explicitly addresses something stated in the ticket's description
- **Default to TRUE when uncertain** (Conservative bias — the dev wrote the ref deliberately)

Return FALSE only when:
- The commit is *demonstrably* about a different topic, area, or feature
- The ref appears to be a stale or accidental mention (e.g., copy-paste from another commit)

**`findSemanticMatch(commit, tickets)` — return the best ticket when:**
- A ticket's summary or description shares the commit's primary topic, module, or feature area
- **Confidence threshold: HIGH** — avoid grouping under "vaguely related" tickets

Return null when no high-confidence match exists.

### Why this is conservative

The default branch is always to **attach to existing work** (ref'd or semantically matched). New tickets are created only when:
1. There's no ref AND no semantic match, OR
2. There's a ref that demonstrably doesn't fit AND no other match.

This preserves the **no-duplicate** invariant while introducing a **no-false-grouping** invariant.

### Worked examples

| Commit | Ref'd ticket scope | Decision |
|--------|--------------------|----------|
| `fix(JPSP-13): use exit 2 instead of exit 0` | JPSP-13 = pending file persistence | LAYER 3: scope fits but is root-cause fix vs workaround → could go either way; Conservative bias → COMMENT_ON(JPSP-13) |
| `feat(JPSP-13): add new MCP integration` | JPSP-13 = pending file persistence | LAYER 2 or 3: scope demonstrably different (MCP vs hook output) → search other tickets; if no match → CREATE_NEW + Relates → JPSP-13 |
| `chore: bump dependency versions` | (no ref) | LAYER 2 or 3: search for "deps" or "chore" tickets; likely CREATE_NEW |
| `feat(JPSP-15): expand api skill` | JPSP-15 = expand api skill | LAYER 1: exact match → COMMENT_ON(JPSP-15) |

---

## ADF Templates

ADF (Atlassian Document Format) is required for `description`, `comment.body`, and similar prose fields in API v3.

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
  "type": "doc",
  "version": 1,
  "content": [
    {
      "type": "codeBlock",
      "attrs": {"language": "bash"},
      "content": [{"type": "text", "text": "git push origin main"}]
    }
  ]
}
```

### Heading + paragraph

```json
{
  "type": "doc",
  "version": 1,
  "content": [
    {"type": "heading", "attrs": {"level": 2}, "content": [{"type": "text", "text": "Section Title"}]},
    {"type": "paragraph", "content": [{"type": "text", "text": "Body text."}]}
  ]
}
```

### Building ADF safely with `jq`

When the text contains shell-special characters, build the JSON with `jq -n --arg`:

```bash
TEXT="Line with \"quotes\" and special chars"
ADF=$(jq -n --arg text "$TEXT" '{
  type: "doc",
  version: 1,
  content: [{type: "paragraph", content: [{type: "text", text: $text}]}]
}')
echo "$ADF"
```

### Tables

Manual ADF tables are very verbose. For commit-history tables (used by onboard imports), prefer rendering the table as Markdown text inside a `codeBlock` node — Jira will display it as preformatted text but it's compact and easy to generate.

---

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
| Delete issue | REST (only) | — |
| Bulk delete | REST (only) | — |
| Delete comment | REST (only) | — |
| Move issue | REST (only) | — |
| Manage labels | REST | MCP `editJiraIssue` (awkward) |

Use MCP only when REST returns 429 and retry budget is exhausted, or when the user explicitly asks for MCP.

## Error Reference

| Code | Meaning | Fix |
|------|---------|-----|
| 200 | Success (with content) | — |
| 201 | Created | — |
| 204 | Success (no content) | — |
| 400 | Bad request | Check the JSON payload — likely missing required fields or invalid ADF |
| 401 | Auth failed | Check `ATLASSIAN_EMAIL` and `ATLASSIAN_API_TOKEN` in `~/.claude/.env` |
| 403 | No permission | User lacks the required Jira permission for this operation |
| 404 | Not found | Issue/comment/project doesn't exist or was already deleted |
| 429 | Rate limited | Back off and retry; if persistent, fall back to MCP for read operations |
