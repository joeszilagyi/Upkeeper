• Most of the control plane is now scripted if x, do y. The LLM is still used for the repair work itself, but it is not supposed to be trusted to decide whether the machine is healthy, whether checks passed,
  whether quota is blocked, whether obligations exist, or whether a PR can merge.

  A useful split:

  | Area | Scripted or LLM? | What decides |
  |---|---:|---|
  | Quota hibernation | Scripted | Reads quota/session markers; if blocked, sleep/exit before backend work. |
  | Owner lease / duplicate loop protection | Scripted | PID/start-tick/state files; duplicate healthy owner exits. |
  | Dirty worktree autoshelve | Scripted | Git status/path classes; shelves or transplants local control-plane changes. |
  | PR check gate | Scripted | gh pr checks, state machine for pass/fail/pending/empty-settling. |
  | Batch merge gate | Scripted | Local validation + GitHub checks before merge. |
  | Open obligation detection | Scripted | Files under runtime/upkeeper-obligations/open. |
  | Obligation reconciliation | Scripted | JSON grouping by root/kind/reason/target/fingerprint. |
  | Obligation cooldown | Scripted | Attempt count + timestamps. |
  | Foreign-root obligation deferral | Scripted | Root path comparison. |
  | Prior-run anomaly scan | Mostly scripted | tools/upkeeper_anomaly_custody.py pattern/fingerprint rules. |
  | Live output PAGE/FYI classification | Scripted heuristics | Pattern matching in orchestration/backlog.sh and transcript filters. |
  | Lattice path safety / artifact recording | Scripted | Python path checks, HMAC storage, SQLite schema checks. |
  | Target path safety | Scripted | Repo-relative/path/symlink/runtime checks. |
  | Status marker acceptance | Scripted | Strict parser for UPKEEPER_STATUS. |
  | Validation | Scripted | Bash syntax, unit tests, docs checks, quick/full validator, CI. |
  | Actual code changes | LLM | Codex decides patch content inside the selected task. |
  | Explaining/fixing a novel obligation | LLM, then gated | Codex proposes a fix; scripts validate/commit or record BLOCKED. |
  | Final review prose | LLM, parsed strictly | Wrapper accepts only strict markers and safe selected-path evidence. |

  So the answer is: the gates are mostly deterministic; the repairs are still LLM-authored.

  The ideal architecture is:

  script detects state
  script chooses allowed next action
  LLM may attempt repair only inside that allowed action
  script validates result
  script commits/pushes/merges only if validation passes
  script records obligation if repair fails or output is anomalous

  That is substantially what now exists.

  Scripted “if x, do y” controls now in place

  1. If quota is blocked, do not ask the model to work.
      - Backlog hibernates locally.
      - It prints the blocked bucket, reset/wake time, branch, and recent activity.
      - This is not an LLM decision.
  2. If PR checks fail, stop before selecting another issue.
      - gh pr checks is polled locally.
      - Empty check sets are treated as settling for a bounded grace period.
      - Failures stop the loop.
      - The LLM cannot declare CI green.
  3. If open current-root obligations exist, handle them before issue work.
      - Obligation selection is local JSON logic.
      - Reconciliation runs before selection.
      - Duplicate obligations collapse.
      - Foreign-root obligations defer.
      - Cooling obligations do not consume the whole loop forever.
      - The LLM does not get to choose “ignore obligations and work issue #whatever.”
  4. If prior logs contain actionable anomalies, create/update obligations.
      - tools/upkeeper_anomaly_custody.py scans recent loop output.
      - It classifies known expected fixtures.
      - It fingerprints anomalies so repeats update one record.
      - It opens local obligations without waiting for LLM interpretation.
  5. If output is a quoted fixture, do not page it as a real wrapper failure.
      - This is scripted classification.
      - printf ... [WARN] ..., grep ... [ERROR] ..., and except Exception as exc: are now handled deterministically when they match fixture/source patterns.
      - Real PAGE [ERROR] still stays loud.
  6. If the model omits or mangles UPKEEPER_STATUS, fail closed.
      - The marker parser is strict.
      - Missing marker becomes a controlled failure/obligation.
      - The model cannot simply hand-wave success.
  7. If the model reports a different selected file than the wrapper selected, reject it.
      - Wrapper-selected target stays authoritative.
      - Lattice records substitution attempts as evidence.
      - This closes a major “model drifted the task” class.
  8. If local validation fails, do not commit/merge.
      - Bash syntax, unit tests, docs quick, validator quick/full, diff whitespace, CI are command gates.
      - We specifically fixed cases where Bash conditional structure could mask failed validation.
  9. If Lattice cannot safely record optional evidence, degrade only where allowed.
      - Required Lattice can fail closed.
      - Optional Lattice can continue without destabilizing the whole run, but with bounded recovery evidence.
      - Transcript paths under Upkeeper-owned state/temp dirs are now classified safely.
  10. If repeated obligation repair blocks, cool it down.

  - The retry limit and cooldown are local counters/timestamps.
  - This prevents one bad obligation from eating a 99-loop run.

  Where the LLM still matters

  The model still does the part it is actually good for: reading a target file/obligation and producing a source patch or a BLOCKED explanation.

  That means there is still LLM involvement in:

  1. Choosing the actual code edit
      - Codex writes the patch.
      - It may choose a wrong implementation.
      - Validators/CI catch what they can.
  2. Understanding novel failures
      - If a new anomaly appears and no deterministic rule exists yet, it becomes an obligation.
      - The LLM may be asked to diagnose and patch it.
      - Afterward, good fixes should add deterministic validation so the same class stops requiring interpretation.
  3. Repairing obligation evidence
      - The obligation prompt is local/script-generated, but the repair is model-authored.
      - The wrapper then records success, no changes, or BLOCKED.
  4. Producing final status text
      - The model emits the final marker.
      - The wrapper parses it strictly.
      - If the marker is absent or invalid, the model does not get trusted success.
  5. Possibly making a bad no-op
      - A model can still say WORK_DONE with no tracked changes.
      - The wrapper can report “no tracked changes produced,” defer or record depending on path, but this remains an area where quality pressure exists.

  The important trust boundary

  The model can still be arbitrary inside its repair attempt, but the system now treats that attempt as untrusted output.

  The wrapper trusts:

  - Git state
  - local files
  - JSON obligation records
  - local scripts
  - strict parsers
  - validation command exit codes
  - GitHub check states
  - Lattice/path safety checks
  - quota/session markers

  The wrapper does not blindly trust:

  - model prose
  - model claims that something is fixed
  - model-selected replacement targets
  - model-emitted log-looking text
  - model-emitted ERROR/WARN snippets
  - model success without a valid status marker
  - model success without validation/CI where required

  That is the right shape.

  Rough percentage

  If we talk about gates and controls, I’d put it around:

  - 80-90% scripted/deterministic now
  - 10-20% still dependent on LLM interpretation, mostly when a novel anomaly needs diagnosis or a patch needs to be authored

  If we talk about actual bug fixing, the split flips:

  - LLM writes most repair patches
  - Scripts decide whether the patch is allowed to count

  That is probably the correct architecture. You do not want the LLM deciding whether the machine is healthy. You do want it trying repairs inside a cage where local commands decide if the repair counts.

  Remaining soft spots

  There are still some places that are not pure hard logic:

  1. Anomaly classification is heuristic.
      - It is scripted, but the rule set is not complete by nature.
      - Unknown patterns will still appear.
      - The good behavior is that they become obligations instead of disappearing.
  2. “Quality of fix” is partly validator-dependent.
      - If tests do not cover a behavior, a weak LLM patch can pass.
      - This is why the recent work kept adding targeted validation for every repeated failure.
  3. Issue-to-target inference can still be imperfect.
      - The wrapper treats inferred targets cautiously.
      - --target-file remains strongest.
      - Untrusted inferred sources are not supposed to silently pin unsafe targets.
  4. Human reset/archive is still possible.
      - We just used an operator reset after source fixes and green CI.
      - That was evidence-preserving, but still human-directed cleanup.
      - A future improvement would be a first-class scripted resolve stale pre-merge obligation set after merged fix command with explicit safety checks.
  5. LLM can still generate new weird terminal shapes.
      - The output classifier is much better, but not omniscient.
      - New weirdness should now become one obligation, not 50.

  Bottom line

  The thing that decides whether the loop may proceed is now mostly scripted.

  The thing that decides what code to write is still the LLM.

  That is the correct separation for your “unkillable” model:

  Scripts own survival.
  Scripts own gates.
  Scripts own evidence.
  Scripts own validation.
  LLM owns proposed repairs.
  Scripts decide whether proposed repairs count.

  The recent work moved Upkeeper much closer to that line.
