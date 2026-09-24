#!/bin/bash
# Shared fixture + runner for the hook tests. Source it, define case_*
# functions, then call: run_suite PRE_FIX_COMMIT "discriminating cases" "preserved cases"
#
# Every case runs twice:
#   - against the current hook  → must PASS
#   - against the pre-fix hook  → discriminating cases must FAIL, preserved must PASS
# The second run is the counterproof: if the old hook passes a discriminating
# case, the fixture does not reproduce the bug and the case protects nothing.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
NEW_HOOK="$ROOT/plugins/jira-project-sync/scripts/jira-sync.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# make_repo DIR KEY REMOTE_URL NEW_COMMITS
#   A configured repo whose state file sits NEW_COMMITS behind HEAD.
#   Fixture commits skip git hooks (core.hooksPath) — fixtures only.
make_repo() {
  local dir="$1" key="$2" url="$3" new="$4"
  mkdir -p "$dir/.claude"
  git -C "$dir" init -q
  git -C "$dir" config user.email t@t; git -C "$dir" config user.name t
  git -C "$dir" remote add origin "$url"
  printf '{"project":"%s","cloudId":"c","transitionDoneId":"41"}\n' "$key" > "$dir/.claude/jira-sync.json"
  git -C "$dir" -c core.hooksPath=/dev/null commit -q --allow-empty -m "chore($key-1): base"
  git -C "$dir" rev-parse HEAD > "$dir/.claude/jira-sync-state"
  local i; for ((i = 1; i <= new; i++)); do
    git -C "$dir" -c core.hooksPath=/dev/null commit -q --allow-empty -m "feat($key-$((i + 1))): change $i"
  done
}

# Fresh fixture per case:
#   $F/decoy        — the session cwd: configured, NOTHING new to sync
#   $F/tgt dir      — the pushed repo: 2 new commits (path has a space)
setup() {
  F="$(mktemp -d "$WORK/case-$1.XXXX")"   # unique per run: old and new never share a fixture
  DECOY="$F/decoy"; TARGET="$F/tgt dir"
  make_repo "$DECOY" DEC "git@github.com:u/decoy.git" 0
  make_repo "$TARGET" TGT "git@github.com:u/target.git" 2
  # Fixture guards: the decoy must have nothing to sync (so the old hook's
  # silent exit is the failure we claim), and the target MUST have something
  # (so a silent exit can never pass a "should have synced" case by accident).
  [ "$(cat "$DECOY/.claude/jira-sync-state")" = "$(git -C "$DECOY" rev-parse HEAD)" ] \
    || { echo "FIXTURE BROKEN: decoy has unsynced commits"; exit 3; }
  [ "$(cat "$TARGET/.claude/jira-sync-state")" != "$(git -C "$TARGET" rev-parse HEAD)" ] \
    || { echo "FIXTURE BROKEN: target has nothing to sync"; exit 3; }
}

# run_hook HOOK COMMAND OUTPUT [INPUT_CWD] — runs from the decoy, like a
# session whose cwd was reset after the command's `cd`. OUTPUT goes to stderr,
# where `git push` writes; the hook reads stdout + stderr together.
run_hook() {
  local hook="$1" cmd="$2" out="$3" icwd="${4:-}"
  jq -n --arg c "$cmd" --arg e "$out" --arg w "$icwd" \
    '{tool_input:{command:$c}, tool_response:{stdout:"", stderr:$e}} + (if $w == "" then {} else {cwd:$w} end)' \
    | (cd "$DECOY" && "$hook" 2>"$F/hook.err" >"$F/hook.out"); echo $? > "$F/hook.rc"
}

synced_target() {   # pending written in the target, decoy untouched, model told
  [ "$(cat "$F/hook.rc")" = 2 ] && [ -f "$TARGET/.claude/jira-sync-pending" ] \
    && [ ! -f "$DECOY/.claude/jira-sync-pending" ] && grep -q "Projeto: TGT" "$F/hook.err"
}

not_triggered() {   # silent, and nothing written anywhere — the target HAS commits to sync
  [ "$(cat "$F/hook.rc")" = 0 ] && [ ! -f "$TARGET/.claude/jira-sync-pending" ] \
    && [ ! -f "$DECOY/.claude/jira-sync-pending" ]
}

# run_suite PRE_FIX_COMMIT "DISCRIMINATING" "PRESERVED"
run_suite() {
  local old="$WORK/jira-sync-$1.sh" c fail=0
  git -C "$ROOT" show "$1:plugins/jira-project-sync/scripts/jira-sync.sh" > "$old"
  chmod +x "$old"
  for c in $2 $3; do
    if $c "$NEW_HOOK"; then echo "PASS  new  $c"; else echo "FAIL  new  $c"; fail=1; fi
  done
  for c in $2; do
    if $c "$old"; then echo "FAIL  old  $c  (pre-fix hook passes — fixture does not reproduce the bug)"; fail=1
    else echo "PASS  old  $c  (pre-fix hook rejected, as required)"; fi
  done
  for c in $3; do
    if $c "$old"; then echo "PASS  old  $c"; else echo "FAIL  old  $c  (baseline broken)"; fail=1; fi
  done
  return $fail
}
