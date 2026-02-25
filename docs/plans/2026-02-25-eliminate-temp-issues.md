# Eliminate Temp Issues Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove temp Jira issue creation from both skills, add lazy transition discovery, and gitignore the state file.

**Architecture:** Three coordinated edits — onboard skill discovers transitions from first real card, init skill defers discovery entirely, and the hook gains lazy discovery instructions for the first push. Both skills add `.claude/jira-sync-state` to `.gitignore`.

**Tech Stack:** Bash (hook script), Markdown (skill files)

**Design doc:** `docs/plans/2026-02-25-eliminate-temp-issues-design.md`

---

### Task 1: Hook script — add lazy transition discovery

**Files:**
- Modify: `plugins/jira-project-sync/scripts/jira-sync.sh:53-57`

**Step 1: Edit the hook script**

Replace the current transition instruction block (lines 53-57):

```bash
# Build transition instruction if configured
TRANSITION_INSTR=""
if [ -n "$TRANSITION_DONE_ID" ]; then
  TRANSITION_INSTR="e transicione para Done (transition ID: $TRANSITION_DONE_ID)"
fi
```

With expanded logic that adds lazy discovery instructions when `transitionDoneId` is missing:

```bash
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
```

Then in the `cat >&2` block (line 73), change:

```bash
   - Se e assunto NOVO → crie um novo card (Task) com descricao detalhada${TRANSITION_INSTR:+ $TRANSITION_INSTR}
```

To:

```bash
   - Se e assunto NOVO → crie um novo card (Task) com descricao detalhada${TRANSITION_INSTR}
${DISCOVERY_BLOCK}
```

**Step 2: Verify syntax**

Run: `bash -n plugins/jira-project-sync/scripts/jira-sync.sh`
Expected: no output (no syntax errors)

**Step 3: Commit**

```bash
git add plugins/jira-project-sync/scripts/jira-sync.sh
git commit -m "feat: add lazy transition discovery in hook for unconfigured projects"
```

---

### Task 2: Onboard skill — remove temp issue, add first-card discovery

**Files:**
- Modify: `plugins/jira-project-sync/skills/onboard/SKILL.md`

**Step 1: Remove Step 6 (Discover transition Done ID)**

Delete the entire Step 6 section (lines 67-91 in current file), from `### Step 6: Discover transition Done ID` through the IMPORTANT note about transition IDs.

**Step 2: Update Step 7 (Write jira-sync.json)**

This becomes the new Step 6. Change the JSON template to omit `transitionDoneId`:

```json
{
  "project": "{PROJECT_KEY}",
  "cloudId": "{CLOUD_ID}"
}
```

Remove any reference to `TRANSITION_DONE_ID` in this step.

**Step 3: Add gitignore setup to new Step 6**

After `mkdir -p .claude`, add:

```markdown
Then ensure `.claude/jira-sync-state` is gitignored:

\`\`\`bash
# Add to .gitignore if not already present
grep -qxF '.claude/jira-sync-state' .gitignore 2>/dev/null || echo '.claude/jira-sync-state' >> .gitignore
\`\`\`
```

**Step 4: Update Step 8 plan file header**

Remove the `Transition Done ID: {TRANSITION_DONE_ID}` line from the plan file format. It will be added dynamically during execution.

**Step 5: Rewrite Step 9 (Execute import plan) — first card has discovery logic**

Replace the "For each pending card" section with two phases:

Phase 1 — First pending card (with transition discovery):
1. Create the Jira issue (same as before)
2. Query transitions: `getTransitionsForJiraIssue` on the new issue
3. Find Done transition by `statusCategory.key === "done"`, save its `id`
4. Update `jira-sync.json`: add `transitionDoneId` field with discovered ID
5. Update plan file header: add `Transition Done ID: {DISCOVERED_ID}`
6. Transition the card to Done
7. Update plan file: `Status: pending` → `Status: created:{ISSUE_KEY}`

Phase 2 — Remaining pending cards (normal loop):
- Same as current: create issue, transition to Done, update plan file

**Step 6: Renumber all steps**

Old Step 7 → new Step 6, old Step 8 → new Step 7, etc. All step numbers shift down by 1. Final step count goes from 13 to 12.

**Step 7: Remove state file from commit step**

In the CLAUDE.md/commit step (formerly Step 12), ensure `.claude/jira-sync-state` is NOT listed as a file to commit. Only commit: `.claude/jira-sync.json`, `.gitignore`, and `CLAUDE.md`.

**Step 8: Verify the skill file**

Read the full file to ensure all step references are consistent and no orphaned references to temp issues or `TRANSITION_DONE_ID` remain in early steps.

**Step 9: Commit**

```bash
git add plugins/jira-project-sync/skills/onboard/SKILL.md
git commit -m "feat: onboard skill discovers transitions from first real card"
```

---

### Task 3: Init skill — remove temp issue, defer discovery

**Files:**
- Modify: `plugins/jira-project-sync/skills/init/SKILL.md`

**Step 1: Remove Step 6 (Discover transition IDs)**

Delete the entire Step 6 section (lines 62-86 in current file), from `### Step 6: Discover transition IDs` through the IMPORTANT note.

**Step 2: Update Step 7 (Write jira-sync.json)**

This becomes the new Step 6. Change the JSON template to use `null`:

```json
{
  "project": "{PROJECT_KEY}",
  "cloudId": "{CLOUD_ID}",
  "transitionDoneId": null
}
```

Add a note:

```markdown
**Note:** `transitionDoneId` is null — it will be discovered automatically on the first `git push` via the sync hook.
```

**Step 3: Add gitignore setup**

In the new Step 6, after `mkdir -p .claude`, add the same gitignore logic:

```bash
grep -qxF '.claude/jira-sync-state' .gitignore 2>/dev/null || echo '.claude/jira-sync-state' >> .gitignore
```

Also, in Step 11 (Create .gitignore), add `.claude/jira-sync-state` to the default gitignore template.

**Step 4: Renumber all steps**

Old Step 7 → new Step 6, etc. All step numbers shift down by 1. Final step count goes from 13 to 12.

**Step 5: Verify the skill file**

Read the full file to ensure no orphaned references to temp issues remain.

**Step 6: Commit**

```bash
git add plugins/jira-project-sync/skills/init/SKILL.md
git commit -m "feat: init skill defers transition discovery to first push"
```

---

### Task 4: Update plugin cache and verify

**Step 1: Copy modified files to plugin cache**

The plugin cache at `~/.claude/plugins/cache/local-plugins/jira-project-sync/1.0.0/` needs to match the source. Copy all three modified files:

```bash
cp plugins/jira-project-sync/scripts/jira-sync.sh ~/.claude/plugins/cache/local-plugins/jira-project-sync/1.0.0/scripts/jira-sync.sh
cp plugins/jira-project-sync/skills/onboard/SKILL.md ~/.claude/plugins/cache/local-plugins/jira-project-sync/1.0.0/skills/onboard/SKILL.md
cp plugins/jira-project-sync/skills/init/SKILL.md ~/.claude/plugins/cache/local-plugins/jira-project-sync/1.0.0/skills/init/SKILL.md
```

**Step 2: Verify hook script syntax**

```bash
bash -n ~/.claude/plugins/cache/local-plugins/jira-project-sync/1.0.0/scripts/jira-sync.sh
```

Expected: no output (no syntax errors)

**Step 3: Verify no temp issue references remain**

```bash
grep -r "_temp" plugins/jira-project-sync/skills/
grep -r "temporary issue" plugins/jira-project-sync/skills/
grep -r "will be deleted" plugins/jira-project-sync/skills/
```

Expected: no matches

**Step 4: Commit cache sync note**

No commit needed — cache is local and gitignored. But confirm the files match:

```bash
diff plugins/jira-project-sync/scripts/jira-sync.sh ~/.claude/plugins/cache/local-plugins/jira-project-sync/1.0.0/scripts/jira-sync.sh
diff plugins/jira-project-sync/skills/onboard/SKILL.md ~/.claude/plugins/cache/local-plugins/jira-project-sync/1.0.0/skills/onboard/SKILL.md
diff plugins/jira-project-sync/skills/init/SKILL.md ~/.claude/plugins/cache/local-plugins/jira-project-sync/1.0.0/skills/init/SKILL.md
```

Expected: no differences
