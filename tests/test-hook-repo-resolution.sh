#!/bin/bash
# Regression test for JPSP-29: the hook must sync the repo that was PUSHED,
# not the repo the hook process happens to run in (the session cwd).
# Two-sided: see tests/lib.sh.
#
# Usage: tests/test-hook-repo-resolution.sh

source "$(dirname "$0")/lib.sh"

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
# Preserved: behavior both versions must keep.
case_plain()    { # push from inside the repo, no cd — the ordinary path
  setup plain; DECOY="$TARGET"; run_hook "$1" "git push" "$PUSH_SSH"; [ "$(cat "$F/hook.rc")" = 2 ] \
    && [ -f "$TARGET/.claude/jira-sync-pending" ] && grep -q "Projeto: TGT" "$F/hook.err"
}
case_no_push()  { setup nopush; run_hook "$1" "cd \"$TARGET\" && git status" ""; not_triggered; }

run_suite 45954dd \
  "case_cd case_git_C case_https case_input_cwd case_unlocated" \
  "case_plain case_no_push"
