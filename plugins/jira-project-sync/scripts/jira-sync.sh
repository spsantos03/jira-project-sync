#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only trigger on git push
if ! echo "$COMMAND" | grep -qE 'git\s+push'; then
  exit 0
fi

# Find git repo root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
  exit 0
fi

# Per-project config — skip silently if not configured
CONFIG_FILE="$REPO_ROOT/.claude/jira-sync.json"
if [ ! -f "$CONFIG_FILE" ]; then
  exit 0
fi

# Read project-specific config
PROJECT=$(jq -r '.project // empty' "$CONFIG_FILE")
CLOUD_ID=$(jq -r '.cloudId // empty' "$CONFIG_FILE")
TRANSITION_DONE_ID=$(jq -r '.transitionDoneId // empty' "$CONFIG_FILE")

if [ -z "$PROJECT" ] || [ -z "$CLOUD_ID" ]; then
  echo "JIRA_SYNC: ERROR — .claude/jira-sync.json missing 'project' or 'cloudId'."
  exit 0
fi

# State file tracking last synced commit
STATE_FILE="$REPO_ROOT/.claude/jira-sync-state"
if [ -f "$STATE_FILE" ]; then
  LAST_SYNC=$(cat "$STATE_FILE")
else
  # First run: initialize with current HEAD (don't sync history)
  git rev-parse HEAD > "$STATE_FILE"
  echo "JIRA_SYNC: State file inicializado para projeto $PROJECT. Proximos pushes serao sincronizados."
  exit 0
fi

# Get new commits since last sync
COMMITS=$(git log --format="%h %ad %s" --date=short "$LAST_SYNC"..HEAD 2>/dev/null)

if [ -z "$COMMITS" ]; then
  exit 0
fi

COUNT=$(echo "$COMMITS" | wc -l | tr -d ' ')
CURRENT_HEAD=$(git rev-parse HEAD)

# Build transition instruction if configured
TRANSITION_INSTR=""
if [ -n "$TRANSITION_DONE_ID" ]; then
  TRANSITION_INSTR="e transicione para Done (transition ID: $TRANSITION_DONE_ID)"
fi

# Instruct Claude to sync with Jira
cat <<EOF
JIRA_SYNC: $COUNT commit(s) novo(s) precisam ser sincronizados com Jira.

Projeto: $PROJECT
Cloud ID: $CLOUD_ID

Commits:
$COMMITS

Instrucoes:
1. Busque issues existentes no $PROJECT (JQL: project = $PROJECT ORDER BY created DESC)
2. Para cada commit acima, avalie semanticamente:
   - Se o assunto JA existe em um card → adicione o commit como comentario no card
   - Se e assunto NOVO → crie um novo card (Task) com descricao detalhada${TRANSITION_INSTR:+ $TRANSITION_INSTR}
3. Apos concluir, atualize o arquivo $STATE_FILE com: $CURRENT_HEAD
EOF
