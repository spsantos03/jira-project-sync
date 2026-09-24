#!/bin/bash
# Regression test for JPSP-32: a push whose output was truncated
# (`git push | tail -1`) or silenced (`>/dev/null 2>&1`) must still trigger
# the sync — and look-alikes must not. Two-sided: see tests/lib.sh.
#
# Every case runs against a target that HAS unsynced commits, so a silent
# exit 0 can never pass a "should have synced" case by accident.
#
# Usage: tests/test-hook-push-detection.sh

source "$(dirname "$0")/lib.sh"

# Detection cases (see run_suite below for which ones the old hook fails).
case_truncated() {    # today's real case: only the ref-update line survived `tail -1`
  setup trunc; run_hook "$1" "cd \"$TARGET\" && git push 2>&1 | tail -1" "   7dd4454..5de5248  main -> main"
  synced_target
}
case_new_branch() {   # first push of a branch, truncated, via a quoted git -C
  setup newbr; run_hook "$1" "git -C \"$TARGET\" push -u origin main 2>&1 | tail -1" " * [new branch]      main -> main"
  synced_target
}
case_forced() {       # forced update line: "+ a...b main -> main (forced update)"
  setup forced; run_hook "$1" "cd \"$TARGET\" && git push --force 2>&1 | tail -1" " + 1a2b3c4...5d6e7f8 main -> main (forced update)"
  synced_target
}
case_silenced() {     # no output at all: only the command says it was a push
  setup silent; run_hook "$1" "cd \"$TARGET\" && git push >/dev/null 2>&1" ""
  synced_target
}
case_silenced_git_C(){ # quiet push through a quoted -C path (has a space)
  setup silentc; run_hook "$1" "git -C \"$TARGET\" push -q" ""
  synced_target
}

# Look-alikes that must NOT trigger.
case_fetch() {        # fetch prints the same ref-update lines — but it is not a push
  setup fetch; run_hook "$1" "cd \"$TARGET\" && git fetch" "   aaa1111..bbb2222  main       -> origin/main"
  not_triggered
}
case_pull() {
  setup pull; run_hook "$1" "cd \"$TARGET\" && git pull" $'Updating aaa1111..bbb2222\nFast-forward\n   aaa1111..bbb2222  main       -> origin/main'
  not_triggered
}
case_quoted_text() {  # "git push" only inside a quoted commit message, no output
  setup quoted; run_hook "$1" "cd \"$TARGET\" && git commit -q -m \"then git push\"" ""
  not_triggered
}
case_quoted_separator() { # a separator INSIDE quotes must not split out a fake "git push"
  setup qsep; run_hook "$1" "cd \"$TARGET\" && echo \"done; git push origin main\" >/dev/null" ""
  not_triggered
}
case_heredoc() {      # "git push" only inside a heredoc body, no output
  setup heredoc; run_hook "$1" $'cd "'"$TARGET"$'" && cat > notes.txt <<EOF\ngit push\nEOF' ""
  not_triggered
}
case_echo_refline() { # push-like text printed by a non-push command
  setup echo; run_hook "$1" "cd \"$TARGET\" && cat log.txt" "   aaa1111..bbb2222  main -> main"
  not_triggered
}

# Classification follows the red run against 5de5248, not intuition: a fully
# silent push already reached the input fallback (`$(…)` strips the lone
# newline, so RESULT is empty) — preserved; the heredoc case was a live FALSE
# POSITIVE in that fallback — discriminating (old fires, new must not).
run_suite 5de5248 \
  "case_truncated case_new_branch case_forced case_silenced_git_C case_heredoc case_quoted_separator" \
  "case_silenced case_fetch case_pull case_quoted_text case_echo_refline"
