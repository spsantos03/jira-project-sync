#!/bin/bash
# Regression test for JPSP-29: the hook must sync the repo that was PUSHED,
# not the repo the hook process happens to run in (the session cwd).
#
# Every case runs twice:
#   - against the current hook  → must PASS
#   - against the pre-fix hook  → cases marked "discriminating" must FAIL
# The second run is the counterproof: if the old hook passes a case, the
# fixture does not reproduce the bug and the case protects nothing.
#
# Usage: tests/test-hook-repo-resolution.sh

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
NEW_HOOK="$ROOT/plugins/jira-project-sync/scripts/jira-sync.sh"
PRE_FIX_COMMIT="45954dd"   # last commit before JPSP-29

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

OLD_HOOK="$WORK/jira-sync-prefix.sh"
git -C "$ROOT" show "$PRE_FIX_COMMIT:plugins/jira-project-sync/scripts/jira-sync.sh" > "$OLD_HOOK"
chmod +x "$OLD_HOOK"

# make_repo DIR KEY REMOTE_URL NEW_COMMITS
#   A configured repo whose state file sits NEW_COMMITS behind HEAD.
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
  # Fixture guard: the decoy must have zero new commits, or the old hook's
  # silent exit would not be the failure mode we claim to reproduce.
  [ "$(cat "$DECOY/.claude/jira-sync-state")" = "$(git -C "$DECOY" rev-parse HEAD)" ] \
    || { echo "FIXTURE BROKEN: decoy has unsynced commits"; exit 3; }
}

# run_hook HOOK COMMAND STDERR [INPUT_CWD] — runs from the decoy, like a
# session whose cwd was reset after the command's `cd`.
run_hook() {
  local hook="$1" cmd="$2" err="$3" icwd="${4:-}"
  jq -n --arg c "$cmd" --arg e "$err" --arg w "$icwd" \
    '{tool_input:{command:$c}, tool_response:{stdout:"", stderr:$e}} + (if $w == "" then {} else {cwd:$w} end)' \
    | (cd "$DECOY" && "$hook" 2>"$F/hook.err" >"$F/hook.out"); echo $? > "$F/hook.rc"
}

synced_target() {   # pending written in the target, decoy untouched, model told
  [ "$(cat "$F/hook.rc")" = 2 ] && [ -f "$TARGET/.claude/jira-sync-pending" ] \
    && [ ! -f "$DECOY/.claude/jira-sync-pending" ] && grep -q "Projeto: TGT" "$F/hook.err"
}

PUSH_SSH=$'To github.com:u/target.git\n   aaa..bbb  main -> main'

case_cd()       { setup cd;    run_hook "$1" "cd \"$TARGET\" && git push" "$PUSH_SSH"; synced_target; }
case_git_C()    { setup gitc;  run_hook "$1" "git -C '$TARGET' push origin main" "$PUSH_SSH"; synced_target; }
case_https()    { setup https; run_hook "$1" "cd \"$TARGET\" && git push" $'To https://github.com/u/target.git\n   a..b  main -> main'; synced_target; }
case_input_cwd(){ setup icwd;  run_hook "$1" "git push" "$PUSH_SSH" "$TARGET"; synced_target; }
case_unlocated(){ # push to a repo no candidate owns: must WARN, not exit silently
  setup unloc; run_hook "$1" "git push" $'To github.com:u/elsewhere.git\n   a..b  main -> main'
  [ "$(cat "$F/hook.rc")" = 2 ] && grep -q "github.com/u/elsewhere" "$F/hook.err" \
    && [ ! -f "$DECOY/.claude/jira-sync-pending" ]
}
# Non-discriminating: behavior both versions must keep.
case_plain()    { # push from inside the repo, no cd — the ordinary path
  setup plain; DECOY="$TARGET"; run_hook "$1" "git push" "$PUSH_SSH"; [ "$(cat "$F/hook.rc")" = 2 ] \
    && [ -f "$TARGET/.claude/jira-sync-pending" ] && grep -q "Projeto: TGT" "$F/hook.err"
}
case_no_push()  { setup nopush; run_hook "$1" "cd \"$TARGET\" && git status" ""; [ "$(cat "$F/hook.rc")" = 0 ]; }

DISCRIMINATING="case_cd case_git_C case_https case_input_cwd case_unlocated"
PRESERVED="case_plain case_no_push"

FAIL=0
for c in $DISCRIMINATING $PRESERVED; do
  if $c "$NEW_HOOK"; then echo "PASS  new  $c"; else echo "FAIL  new  $c"; FAIL=1; fi
done
for c in $DISCRIMINATING; do
  if $c "$OLD_HOOK"; then echo "FAIL  old  $c  (pre-fix hook passes — fixture does not reproduce the bug)"; FAIL=1
  else echo "PASS  old  $c  (pre-fix hook rejected, as required)"; fi
done
for c in $PRESERVED; do
  if $c "$OLD_HOOK"; then echo "PASS  old  $c"; else echo "FAIL  old  $c  (baseline broken)"; FAIL=1; fi
done
exit $FAIL
