#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Primary trigger signal: check the BASH COMMAND OUTPUT for evidence that a
# push actually happened. Examining the output (rather than parsing the
# input command string) eliminates false positives from commit messages,
# curl payloads, heredoc bodies, or any other text that mentions push
# commands without actually invoking them.
RESULT=$(echo "$INPUT" | jq -r '.tool_response.content // .tool_result.content // .tool_response // .tool_result // empty')

# DEBUG: temporary one-shot dump to verify field name on the next hook fire.
# Remove this block after observing /tmp/jira-sync-hook-debug.json.
if [ ! -f /tmp/jira-sync-hook-debug.json ]; then
  echo "$INPUT" > /tmp/jira-sync-hook-debug.json
fi

TRIGGER=0
if [ -n "$RESULT" ]; then
  # Real push signatures:
  #   git push success:        "To github.com:user/repo.git"  (or gitlab/bitbucket/git@/https)
  #   git push up-to-date:     "Everything up-to-date"
  #   gh repo create --push:   "Pushed commits to <url>"
  if echo "$RESULT" | grep -qE '^To (github|gitlab|bitbucket)\.com|^To git@|^To https?://|^Everything up-to-date|Pushed commits to'; then
    TRIGGER=1
  fi
else
  # Fallback: input-based check, kept for compatibility with Claude Code
  # versions that don't expose the tool result. Less accurate — heredoc
  # bodies and quoted strings can leak trigger words.
  TMP="${COMMAND//&&/$'\n'}"
  TMP="${TMP//||/$'\n'}"
  TMP="${TMP//;/$'\n'}"
  TMP="${TMP//|/$'\n'}"
  while IFS= read -r SUBCMD; do
    SAFE_PREFIX=$(echo "$SUBCMD" | sed -E "s/['\"\`].*//; s/<<.*//; s/[\$][(].*//")
    if echo "$SAFE_PREFIX" | grep -qE '^[[:space:]]*(git[[:space:]]+push\b|gh[[:space:]]+repo[[:space:]]+create\b.*--push)'; then
      TRIGGER=1
      break
    fi
  done <<< "$TMP"
fi

if [ "$TRIGGER" -eq 0 ]; then
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
  echo "JIRA_SYNC: ERROR — .claude/jira-sync.json missing 'project' or 'cloudId'." >&2
  exit 2
fi

# State file tracking last synced commit
STATE_FILE="$REPO_ROOT/.claude/jira-sync-state"
PENDING_FILE="$REPO_ROOT/.claude/jira-sync-pending"

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
  # No new commits — but check if there's a pending file from a failed sync
  if [ -f "$PENDING_FILE" ]; then
    cat >&2 <<EOF
JIRA_SYNC: AVISO — Sync pendente de sessao anterior detectado!

O arquivo $PENDING_FILE contem commits que ainda NAO foram sincronizados com Jira.
Isso pode ter acontecido porque o Atlassian MCP estava indisponivel na sessao anterior.

Instrucoes:
1. Leia o arquivo $PENDING_FILE para ver os commits pendentes
2. Processe-os conforme as instrucoes no arquivo
3. Apos sincronizar TODOS com sucesso, delete $PENDING_FILE e atualize $STATE_FILE
4. Se o Atlassian MCP nao estiver disponivel agora, NAO delete o arquivo — ele sera reprocessado no proximo push
EOF
    exit 2
  fi
  exit 0
fi

COUNT=$(echo "$COMMITS" | wc -l | tr -d ' ')
CURRENT_HEAD=$(git rev-parse HEAD)

# Build transition instructions
TRANSITION_INSTR=""
DISCOVERY_BLOCK=""
if [ -n "$TRANSITION_DONE_ID" ]; then
  TRANSITION_INSTR=" e transicione para Done (transition ID: $TRANSITION_DONE_ID)"
else
  DISCOVERY_BLOCK="
IMPORTANTE — Transition ID ainda nao configurado:
Apos criar o PRIMEIRO card, use getTransitionsForJiraIssue para descobrir os transitions disponiveis.
Encontre o transition onde statusCategory.key === \"done\" e salve o id.
Atualize $CONFIG_FILE adicionando \"transitionDoneId\": \"<ID>\" ao JSON.
Transicione esse card e todos os seguintes para Done usando o ID descoberto."
fi

# Check if there's already a pending file (previous sync failed)
PENDING_WARNING=""
if [ -f "$PENDING_FILE" ]; then
  PENDING_WARNING="
AVISO: Sync pendente de sessao anterior detectado em $PENDING_FILE.
Os commits abaixo INCLUEM os pendentes anteriores (recalculados desde o ultimo sync bem-sucedido)."
fi

# Write pending file — this persists until Claude confirms successful sync
cat > "$PENDING_FILE" <<PENDING
# Jira Sync Pending
# Written: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
# Project: $PROJECT
# Cloud ID: $CLOUD_ID
# Last synced commit: $LAST_SYNC
# Target state after sync: $CURRENT_HEAD

Commits to sync:
$COMMITS

Instrucoes (operacoes via skill jira-project-sync:api - REST API por padrao, MCP fallback):
1. Busque issues existentes no $PROJECT (api skill: "Search Issues by JQL" com "project = $PROJECT ORDER BY created DESC")
2. Para cada commit acima, aplique o algoritmo da skill jira-project-sync:api (secao "Semantic Grouping Algorithm"):
   a. Se o commit tem ref ($PROJECT-\d+):
      - Leia titulo+descricao do ticket referenciado (api skill: "Get Issue")
      - Se o escopo primario do commit cabe no ticket [LAYER 1] → comente nele (api skill: "Add Comment")
      - Se NAO cabe → busque outros candidatos (api skill: "Search Issues by JQL"):
        * Match encontrado [LAYER 2] → comente no candidato mencionando "see also $PROJECT-XX"
        * Sem match [LAYER 3] → crie ticket novo (api skill: "Create Issue")${TRANSITION_INSTR} + link "Relates" para o ref (api skill: "Create Issue Link")
   b. Se NAO tem ref → busca semantica em tickets existentes (api skill: "Search Issues by JQL"):
      * Match [LAYER 2] → comente no candidato (api skill: "Add Comment")
      * Sem match [LAYER 3] → crie ticket novo (api skill: "Create Issue")${TRANSITION_INSTR}${DISCOVERY_BLOCK:+
$DISCOVERY_BLOCK}

   Default conservador: na duvida sobre "cabe no escopo", comente no ticket referenciado. So divirja quando o commit eh claramente sobre outro topico.
3. Apos sincronizar TODOS os commits com sucesso:
   a. Atualize o state file: echo "$CURRENT_HEAD" > $STATE_FILE
   b. Delete este arquivo pendente: rm $PENDING_FILE
4. Se o sync NAO foi possivel (REST API e MCP fallback ambos indisponiveis):
   - NAO atualize o state file
   - NAO delete este arquivo
   - Os commits serao reprocessados no proximo push
PENDING

# Output instructions to Claude (stderr + exit 2 = visible to model)
cat >&2 <<EOF
JIRA_SYNC: $COUNT commit(s) novo(s) precisam ser sincronizados com Jira.${PENDING_WARNING}

Projeto: $PROJECT
Cloud ID: $CLOUD_ID

Commits:
$COMMITS

Um arquivo pendente foi salvo em: $PENDING_FILE
Este arquivo persiste ate que o sync seja concluido com sucesso.

Instrucoes (operacoes via skill jira-project-sync:api - REST API por padrao, MCP fallback):
1. Busque issues existentes no $PROJECT (api skill: "Search Issues by JQL" com "project = $PROJECT ORDER BY created DESC")
2. Para cada commit acima, aplique o algoritmo da skill jira-project-sync:api (secao "Semantic Grouping Algorithm"):
   a. Se o commit tem ref ($PROJECT-\d+):
      - Leia titulo+descricao do ticket referenciado (api skill: "Get Issue")
      - Se o escopo primario do commit cabe no ticket [LAYER 1] → comente nele (api skill: "Add Comment")
      - Se NAO cabe → busque outros candidatos (api skill: "Search Issues by JQL"):
        * Match encontrado [LAYER 2] → comente no candidato mencionando "see also $PROJECT-XX"
        * Sem match [LAYER 3] → crie ticket novo (api skill: "Create Issue")${TRANSITION_INSTR} + link "Relates" para o ref (api skill: "Create Issue Link")
   b. Se NAO tem ref → busca semantica em tickets existentes (api skill: "Search Issues by JQL"):
      * Match [LAYER 2] → comente no candidato (api skill: "Add Comment")
      * Sem match [LAYER 3] → crie ticket novo (api skill: "Create Issue")${TRANSITION_INSTR}${DISCOVERY_BLOCK:+
$DISCOVERY_BLOCK}

   Default conservador: na duvida sobre "cabe no escopo", comente no ticket referenciado. So divirja quando o commit eh claramente sobre outro topico.
3. Apos sincronizar TODOS os commits com sucesso:
   a. Atualize o state file: echo "$CURRENT_HEAD" > $STATE_FILE
   b. Delete o arquivo pendente: rm $PENDING_FILE
4. Se o sync NAO foi possivel (REST API e MCP fallback ambos indisponiveis):
   - NAO atualize o state file
   - NAO delete o arquivo pendente
   - Os commits serao reprocessados no proximo push
EOF
exit 2
