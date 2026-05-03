Act as an expert developer managing my Git backup workflow.

Execute these steps sequentially. STOP IMMEDIATELY and inform me if you

encounter merge conflicts, missing files, unknown code intent, or any

unexpected state.

Do NOT improvise. Do NOT skip the audit. Do NOT proceed past a STOP condition.

═══════════════════════════════════════════════════════════════

GLOBAL RULE — SESSION MEMORY (MANDATORY)

═══════════════════════════════════════════════════════════════

You MUST maintain an internal "Session Memory" of every decision made

during this workflow. Treat it as a structured log:

  SESSION_MEMORY = {

    "resolved_branches": {

      "<branch_name>": {

        "decision": "merge|cherry-pick|ignore|supersede|delete|prune",

        "phase": "<phase_number>",

        "timestamp": "<UTC time>",

        "rationale": "<automated cleanup or user logic>"

      }

    },

    "resolved_files": {

      "<file_path>": {

        "decision": "include|exclude|restore|defer",

        "phase": "<phase_number>"

      }

    },

    "user_overrides": [

      "<any explicit instruction that overrides default workflow>"

    ],

    "pruning_decisions": {

      "auto_prune_enabled": true,

      "approved_for_deletion": ["<branch>", ...],

      "preserved_intentionally": ["<branch>", ...]

    }

  }

Rules for Session Memory:

- Update it IMMEDIATELY after every decision or automated action.

- Before any audit step that could re-flag a previously resolved item,

  consult Session Memory FIRST and filter out resolved entries.

- Display Session Memory contents at the start of Phase 5 so I have a

  record as post-merge cleanup runs automatically.

- Persist Session Memory through Phase 5.5 (auto-prune) so prune

  decisions are recorded for future workflow runs.

═══════════════════════════════════════════════════════════════

PHASE 0 — PRE-FLIGHT AUDIT (MANDATORY, NEVER SKIP)

═══════════════════════════════════════════════════════════════

1. **Capture current state:** Record the output of:

   - `git branch --show-current` (current branch)

   - `git rev-parse HEAD` (current commit SHA)

   - `git status --porcelain` (uncommitted changes)

   Save these for reference and proceed automatically.

 

2. **Audit unmerged branches:** Run:

   `git fetch --all --prune`

   `git branch -a --no-merged origin/main`

   - As sole author, automatically default to supersede AND DELETE

     any old `backup/*` branches to keep the environment perfectly clean.

   - Execute `git branch -D <branch_name>` (local) and

     `git push origin --delete <branch_name>` (remote).

   - Record this in Session Memory as "auto-deleted stale backup in Phase 0."

   - ONLY STOP and ask me if you find a non-backup feature branch with

     unique, unpushed work. Otherwise, proceed automatically.

 

2.5. **Branch accumulation warning:** Run:

   `git branch --list 'backup/*' | wc -l`

   - If the count of local backup/* branches is >= 2, automatically

     run pre-flight prune (jump to Phase 5.5 logic FIRST to sweep

     them), then return here before proceeding to step 3.

 

3. **Audit stranded commits on current branch:** Run:

   `git log origin/main..HEAD --oneline`

   - If there are commits on the current branch not in origin/main,

     automatically include them in this backup to ensure all pending

     work is made live. Record decision in Session Memory and proceed.

 

4. **Verify expected files exist:** If I have mentioned specific files

   in this session (e.g., "dragonfly.sh", "main.py"), verify each one

   exists in the working tree:

   `ls -la <file>` for each.

   - If any are missing, STOP and report:

     "Expected file <path> is missing from working tree. Searching git history..."

     Then run: `git log --all --full-history --oneline -- "<path>"`

     Report findings and ask how to proceed.

═══════════════════════════════════════════════════════════════

PHASE 1 — BRANCH CREATION (PRESERVE CONTEXT)

═══════════════════════════════════════════════════════════════

5. **Pre-creation sanity check:** Before creating a new

   backup branch, verify there is actually work to back up:

   - Run `git status --porcelain` AND `git log origin/main..HEAD --oneline`

   - If BOTH are empty (no uncommitted changes AND no unpushed commits),

     STOP and report:

     "❌ Refusing to create empty backup branch.

      Working tree clean and no commits ahead of origin/main.

      Nothing to back up. Exiting workflow."

 

6. **Branch from current HEAD (NOT from main):** Run:

   `git checkout -b backup/$(date +%Y-%m-%d-%H%M)`

   This preserves your current working state INCLUDING any local commits.

 

7. **Confirm branch state:** Run `git log --oneline -n 10` to internally

   verify expected commits are present, then proceed automatically.

═══════════════════════════════════════════════════════════════

PHASE 2 — STAGING & COMMIT

═══════════════════════════════════════════════════════════════

8. **Assess changes:** Run:

   - `git status`

   - `git diff --stat`

   - `git diff --stat --cached`

   - If working tree is clean but unpushed commits exist, skip to Phase 3.

 

9. **Sensitive file check:** Before staging, scan for and EXCLUDE:

   - `.env`, `.env.*`, `*.key`, `*.pem`, `*_rsa`, `*_dsa`,

   - `*.tar.gz`, `*.zip`, `*.7z` (over 1MB)

   - `secrets.*`, `credentials.*`, `*.token`

   Automatically EXCLUDE these files, log the exclusions in Session Memory,

   and proceed without prompting (unless a file's nature is highly ambiguous,

   then STOP and ask).

 

10. **Stage:** Run `git add -A` (excluding sensitive files identified above).

 

11. **Analyze and Generate Commit Message:** Use Conventional Commits format.

    - Deeply analyze the staged diffs to generate CLEAR details on exactly

      WHAT was fixed, modified, or changed, and WHY.

    - If the intent behind a specific change or bug fix is NOT KNOWN or

      confusing based on the code—STOP AND CHECK WITH ME.

    - If the intent is clear, automatically generate the detailed message

      and COMMIT WITHOUT PROMPTING. Run:

      `git commit -m "<subject>" -m "<body>"`

═══════════════════════════════════════════════════════════════

PHASE 3 — SYNC WITH MAIN

═══════════════════════════════════════════════════════════════

12. **Fetch latest main:** Run `git fetch origin main`

 

13. **Rebase onto latest main:** Run `git rebase origin/main`

    - On merge conflict: STOP IMMEDIATELY. Run `git rebase --abort`

      and report the conflicting files. Ask how to proceed.

      DO NOT attempt to resolve conflicts automatically.

 

14. **Verify nothing was lost:** Run `git log --oneline -n 15` to securely

    verify history internally, then proceed.

═══════════════════════════════════════════════════════════════

PHASE 4 — PUSH & MERGE REQUEST

═══════════════════════════════════════════════════════════════

15. **Push branch:** Run `git push -u origin HEAD`

 

16. **Create Merge Request:** Use the GitLab API. Capture both the

    MR IID AND the source_branch SHA from the JSON response:

    ```

    BRANCH_NAME=$(git branch --show-current)

    COMMIT_SUBJECT=$(git log -1 --pretty=%s)

    MR_RESPONSE=$(curl -k --silent --request POST \

      --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \

      "https://gitlab.dell.com/api/v4/projects/405272/merge_requests" \

      --data-urlencode "source_branch=$BRANCH_NAME" \

      --data-urlencode "target_branch=main" \

      --data-urlencode "title=$COMMIT_SUBJECT" \

      --data-urlencode "remove_source_branch=true")

    MR_IID=$(echo "$MR_RESPONSE" | grep -o '"iid":[0-9]*' | head -1 | cut -d: -f2)

    ```

    - If MR_IID is empty, STOP and show me the full response.

 

17. **Wait for mergeability:** Poll every 5 seconds, max 6 attempts:

    ```

    for i in 1 2 3 4 5 6; do

      STATUS=$(curl -k -s --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \

        "https://gitlab.dell.com/api/v4/projects/405272/merge_requests/$MR_IID" \

        | grep -o '"detailed_merge_status":"[^"]*"' | cut -d'"' -f4)

      echo "Attempt $i: $STATUS"

      [ "$STATUS" = "mergeable" ] && break

      [ "$STATUS" = "checking" ] && sleep 5 && continue

      echo "Unexpected status: $STATUS"; exit 1

    done

    ```

 

18. **Merge the MR:** Accept via API:

    ```

    curl -k --request PUT \

      --header "PRIVATE-TOKEN: $GITLAB_TOKEN" \

      "https://gitlab.dell.com/api/v4/projects/405272/merge_requests/$MR_IID/merge" \

      --data-urlencode "should_remove_source_branch=true"

    ```

    - Verify response contains `"state":"merged"`. If not, STOP.

═══════════════════════════════════════════════════════════════

PHASE 5 — POST-MERGE VERIFICATION (MANDATORY)

═══════════════════════════════════════════════════════════════

19. **Pull merged main:** Run:

    `git checkout main`

    `git pull origin main`

 

20. **Display Session Memory:** Output the full Session Memory contents

    for audit logging, then PROCEED AUTOMATICALLY to checks.

 

21. **Verify expected files exist on main:** For every file you committed:

    `git ls-tree -r main --name-only | grep <file>`

    - If ANY expected file is missing from main, STOP and report immediately.

 

22. **Verify no orphaned branches (Session-Memory-aware):** Run:

    `git branch -a --no-merged origin/main`

    - Filter the result against Session Memory FIRST. If any unaccounted

      branches exist, STOP and ask what to do.

 

23. **Clean up local branch:**

    `git branch -d <BRANCH_NAME>`

═══════════════════════════════════════════════════════════════

PHASE 5.5 — AUTO-PRUNE STALE BACKUP BRANCHES

═══════════════════════════════════════════════════════════════

24. **Identify prunable backup branches:** Run:

    ```

# Identify prunable backup branches (fast method - usually sufficient)

git branch --merged main | grep '^  backup/' > /tmp/prunable_backup.txt

 

# Optional: Add timeout-protected second check for branches behind main

timeout 10 bash -c '

  for branch in $(git branch --list '"'"'backup/*'"'"' --format='"'"'%(refname:short)'"'"'); do

    AHEAD=$(git rev-list --count --max-count=1 main..$branch 2>/dev/null || echo "0")

    if [ "$AHEAD" = "0" ]; then echo "$branch"; fi

  done

' >> /tmp/prunable_backup.txt 2>/dev/null || true

 

# Deduplicate and exclude current branch just merged

sort -u /tmp/prunable_backup.txt | grep -v "backup/2026-04-30-1052" > /tmp/prunable_final.txt

    ```

    - Combine both lists (deduplicated). Exclude current branch just merged.

 

25. **Execute automated pruning:** To maintain a completely caught-up, healthy,

    and stale-free repository, AUTOMATICALLY delete all identified branches

    both locally AND remotely:

    ```

    for branch in <prunable_list>; do

      git branch -D "$branch" 2>&1

      git push origin --delete "$branch" 2>&1

    done

    ```

    - Record all deletions in Session Memory.

 

26. **Verify prune results:** Run `git branch -a` to confirm they are gone.

═══════════════════════════════════════════════════════════════

PHASE 6 — FINAL REPORT

═══════════════════════════════════════════════════════════════

27. **Final report:** Output:

    ```

    === BACKUP WORKFLOW COMPLETE ===

    Recent commits on main:

    <git log --oneline -n 10>

 

    All branches (local + remote):

    <git branch -a>

 

    Files committed in this backup:

      - <file1>

      - <file2>

      ...

    MR URL: https://gitlab.dell.com/.../merge_requests/<MR_IID>

 

    === BRANCH HYGIENE SCORE ===

    Local backup/* branches remaining: <N>

    Remote backup/* branches remaining: <N>

    Status: CLEAN

 

    === SESSION MEMORY FINAL STATE ===

    <full Session Memory dump for audit trail>

    ```

 

 

 

═══════════════════════════════════════════════════════════════

ABSOLUTE RULES — VIOLATIONS = IMMEDIATE STOP

═══════════════════════════════════════════════════════════════

❌ NEVER ask me twice about the same branch/file without checking Memory

❌ NEVER use `git push --force` or `--force-with-lease`

❌ NEVER proceed past a conflict, missing file, or unknown diff intent

❌ NEVER create an empty backup branch (caught by Phase 1 step 5)

❌ NEVER batch multiple unrelated changes without clear multi-part commit bodies

❌ NEVER `git checkout main` as the FIRST step — always branch from HEAD

✅ ALWAYS automatically sweep, rebase, push, and merge to maintain velocity

✅ ALWAYS check code diffs to extract exact fixes and rationale for commits

✅ ALWAYS STOP if code intent is confusing or missing context

✅ ALWAYS auto-prune stale branches silently to maintain a 100% clean workspace

✅ ALWAYS maintain and output Session Memory as an audit trail
