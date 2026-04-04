---
name: api
description: Direct Atlassian REST API operations that the MCP server cannot do — delete issues, bulk delete, delete comments, move issues, manage labels.
---

# jira-project-sync:api

Direct Atlassian REST API for operations the MCP server doesn't support.

## Authentication

All operations require credentials from `~/.claude/.env`:

```bash
source ~/.claude/.env
# Required vars: ATLASSIAN_EMAIL, ATLASSIAN_API_TOKEN, ATLASSIAN_SITE
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)
```

**Before running any operation:** Verify the env file exists and has the required variables. If missing, tell the user:
> "Missing `~/.claude/.env` with `ATLASSIAN_EMAIL`, `ATLASSIAN_API_TOKEN`, and `ATLASSIAN_SITE`. Generate an API token at https://id.atlassian.com/manage-profile/security/api-tokens"

## Operations

Pick the operation that matches the user's request. Each is self-contained.

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

---

### Bulk Delete by JQL

Delete multiple issues matching a JQL query. **This is destructive — always confirm with the user first.**

**Step 1:** Search for matching issues using the MCP tool (to show the user what will be deleted):

```
Tool: mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql
cloudId: {CLOUD_ID}
jql: "{USER_JQL}"
```

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

Remove a comment from an issue.

**Step 1:** Find the comment ID. List comments on the issue:

```bash
source ~/.claude/.env
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64)

curl -s \
  "https://$ATLASSIAN_SITE/rest/api/3/issue/{ISSUE_KEY}/comment" \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" | jq '.comments[] | {id, body: .body[:80], author: .author.displayName, created}'
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

---

### Move Issue to Another Project

Move an issue to a different Jira project. The issue key changes (e.g., `JPSP-5` becomes `ART-12`).

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

---

### Manage Labels

Add or remove labels on an issue. The MCP `editJiraIssue` can set labels but the array handling is awkward. The REST API has explicit add/remove operations.

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

---

## When to Use This vs MCP

| Need | Use |
|------|-----|
| Create issue | MCP `createJiraIssue` |
| Read/search issues | MCP `searchJiraIssuesUsingJql` |
| Transition issue | MCP `transitionJiraIssue` |
| Add comment | MCP `addCommentToJiraIssue` |
| Edit issue fields | MCP `editJiraIssue` |
| **Delete** anything | **This skill (REST API)** |
| **Bulk operations** | **This skill (REST API)** |
| **Move issue** | **This skill (REST API)** |
| **Add/remove labels** | **This skill (REST API)** |

## Error Reference

| Code | Meaning | Fix |
|------|---------|-----|
| 204 | Success (no content) | — |
| 200 | Success (with content) | — |
| 401 | Auth failed | Check `ATLASSIAN_EMAIL` and `ATLASSIAN_API_TOKEN` in `~/.claude/.env` |
| 403 | No permission | User lacks the required Jira permission for this operation |
| 404 | Not found | Issue/comment doesn't exist or was already deleted |
| 400 | Bad request | Check the JSON payload — likely missing required fields |
