# Upkeeper: Independent Claim Verification and Acceptance Authority Contract

Version: **1.0.0-rc.1**  
Authored: **2026-10-15**, in the owner's ChatGPT conversation  
Status: **Complete normative specification; pending owner adoption. Not an implementation or a certification.**

## 1. Purpose, adoption and interpretation

The governing rule is: **No claim of completed work may receive greater authority than the independent evidence actually establishes.** The worker's honesty is not a prerequisite for correct authorization. A dishonest success message, an honest mistake and an interrupted attempt are handled by the same independently enforced conditions.

This contract governs the transition from a requested maintenance outcome to supported claims and narrowly authorized actions. It does not promise universal software correctness, an exhaustive prediction of failures, or a unit test that proves every behavior of a function. It requires every material claim to have an explicit scope, an approved basis for judging it, trustworthy observations and a decision that cannot be conferred by the claimant.

The owner's examples drive the design: a one-character HTML edit is judged against an observable page requirement; a repaired file-to-handler handoff is judged against the actual reading, transformation, receipt and resulting state required by its contract. Checking those claims still requires inspecting or exercising the candidate. A description of the work is not a substitute for doing that verification.

Uppercase MUST, MUST NOT, SHOULD, SHOULD NOT and MAY carry the requirement meanings of BCP 14 [S1, S2]. The requirements below are Upkeeper-specific engineering decisions authored here, not requirements attributed to those external sources. Source references document existing context and terminology. An exception to SHOULD needs an owner-approved rationale; no exception can silently relabel an unmet MUST as satisfied.

### ICV-001: Adoption is explicit

The authority owner MUST adopt exact artifact digests and an activation scope before this contract can authorize operational actions. Authorship, a pull request, a merged document, a schema-valid approval object and a statement by any assistant are not adoption. Until the independently held approval is verified, the deployment MUST report `UNADOPTED` and MUST NOT issue contract-derived operational grants. Review, publication and offline experiments remain possible under separate owner authorization.

### ICV-002: There is one normative baseline

The normative baseline consists of this contract and the bundled verification specification. The adversarial matrix supplies required conformance scenarios, not replacement prose requirements. Implementations MUST reject an unresolved contradiction between adopted artifacts, rather than select the easiest interpretation. Requirement identifiers are stable; changing a requirement's meaning requires a new version and adoption. Local mirrors, issues, AGENTS instructions, prompts and implementation convenience MUST NOT silently override the adopted baseline.

### ICV-003: Assurance is bounded

Every accepted claim MUST state its subject, property, input/environment scope, observation interval or test domain, assurance class and remaining assumptions. `OBSERVED_EXECUTION`, `TESTED_CONTRACT`, `ENFORCED_INVARIANT` and `FORMALLY_ESTABLISHED_PROPERTY` are distinct classes, not interchangeable badges. Finite tests MUST NOT be presented as proof for all inputs. An invariant claim needs a mediated boundary and its stated threat assumptions. A formal claim additionally identifies its proof, checked model and correspondence assumptions; none is supplied by this package.

### ICV-004: Mechanism is not the contract

Implementers MAY choose suitable languages, stores and isolation mechanisms. They MUST preserve the observable properties required here and document unsupported operating conditions. A mechanism name, a file's mode bits, a signature, a hash, a separate process or a second model does not by itself establish independence. The authoritative acceptance path SHOULD remain small and auditable. This contract does not require a new agent platform, a distributed service, per-function production logging, or a universal observability framework.

## 2. Roles and actual authority

The **authority owner** approves the contract, requirement profiles and delegations. The **worker** proposes changes and reports claims. The **execution supervisor** pins inputs, confines execution and captures process results. An **observer/checker** measures a defined fact or evaluates a predicate. The **acceptance authority** evaluates authenticated evidence against approved obligations. An **actuator** performs a specifically authorized side effect. The **custodian** retains evidence and decision history; Lattice can fulfill parts of that indexing role. These are authority roles, not a requirement for seven processes or people.

### ICV-005: Separate controlling credentials

The worker MUST NOT control adopted requirements, approval records, reference checkers, observer credentials, acceptance decisions, actuator credentials or the policy selecting those authorities. Separation MUST be enforced by the effective host/service permissions, not only repository instructions. A second repository with the same reachable administrative credential does not satisfy this rule. Before activation, the owner MUST identify principals and demonstrate denied write, impersonation and bypass attempts under the actual worker identity, including ambient tools and inherited credentials.

### ICV-006: Observe outside the claim's control

A source is authoritative only for facts it can independently observe within its approved scope. Candidate-generated logs, traces, exit annotations, test names and booleans MUST be classified as claims until verified. A trusted collector that signs worker-supplied text only authenticates collection of that text; it does not authenticate the alleged event. An observer inside candidate-modifiable code cannot be the sole authority for the candidate's success. Separate model review is useful evidence but MUST NOT be described as enforced permission separation.

### ICV-007: Mediate every consequential route

Every route to protected completion, owner-tree application, public reporting, issue resolution, merge, deployment or further autonomous launch MUST cross its applicable authorization boundary. The coverage inventory MUST include normal execution, direct issue pins, local fast paths, cached results, fallback, recovery, obligations, restart and cleanup. A guard implemented but not called is nonconformant. Missing guards in an alternate entrypoint MUST NOT be compensated by a well-guarded primary entrypoint. External side effects require prevention at the actuator, not only detection afterward.

### ICV-008: Promote the checker separately

Upkeeper MAY propose repairs to its own supervisor, checker, contract, schema, policy and evidence store. The proposal MUST be evaluated using the currently approved reference boundary and independent acceptance expectations. Candidate changes MUST NOT become the authority for accepting themselves. Promotion of a new reference requires owner-authorized review, compatibility and negative-case evidence, a new identity and an atomic activation record. The owner can approve a changed requirement, but it remains a requirement change, not proof the old requirement was met.

## 3. Approved work and claim obligations

An **obligation** is a specific requirement with a predicate, required observations, applicability rule, scope, deadline and evaluator identity. A **claim** asserts an outcome about a subject. A **work authorization** permits bounded work; it is not a claim that the result will be correct. Material claims affect completion, operator understanding, safety or a requested action. Unsupported optional statements cannot disappear silently from the report, but they need not block an unrelated, separately authorized diagnostic publication.

### ICV-009: Establish the acceptance basis first

Before worker mutation, an authorized profile or explicit owner decision MUST establish intended outcomes, preserved behavior, forbidden effects, writable scope, relevant checks and permitted actions. Existing tests are evidence about expected behavior, not automatically the owner's complete requirements. The worker MAY suggest obligations and examples but MUST NOT approve them, remove a failing obligation or select an easier interpretation for the same attempt. Discovery work with no accepted repair contract is allowed; its result is a finding or proposal, not an accepted repair.

### ICV-010: Bind a bounded work authorization

The work authorization MUST bind repository identity, initial baseline, allowed logical task, permitted paths/resources, modes, budget, expiration, pause/revocation epoch and allowed side effects. It MUST distinguish client source from central Upkeeper, private evidence, secrets and production state. Relevant dependency readiness MUST be checked, but an open issue, its priority or closed prerequisites do not grant authority. An explicit target cannot override an unsafe path or a governing hold. Recovery inherits or narrows the authorization; it cannot expand it by naming an anomaly.

### ICV-011: Keep obligation identity and applicability stable

Each obligation MUST have a stable identifier and version, an approved predicate or checker reference, required evidence types and a reason it applies. A required obligation is not removable because a worker omits the corresponding claim. An obligation can be `NOT_APPLICABLE` only under its preapproved applicability rule with evidence of that rule's conditions. Missing output, a skipped job, unavailable equipment or an inconvenient failure is not non-applicability. New material requirements discovered during a run require a revised authorization or a review-required disposition.

### ICV-012: Cover outcomes and handoffs, not just functions

Acceptance MUST cover the behaviors and invariants material to the authorized claim, including consequential handoffs between components. A unit-test-per-function policy can supplement this coverage but MUST NOT stand in for it. The obligation set MUST include appropriate positive, negative and boundary cases and preserved behavior. For a bug repair, a reproducer failing before and passing after SHOULD be retained. When a baseline reproducer is unavailable, the limitation and alternative evidence MUST be explicit; no artificial baseline failure may be invented.

### ICV-013: Do not invent a business oracle

The approved acceptance basis MUST distinguish externally approved expected outcomes, independently observed existing behavior and model-proposed expectations. Generating code and expected answers from the same proposal does not establish independent correctness. An ambiguous, subjective or unmeasurable required outcome MUST result in `REVIEW_REQUIRED`, not a fabricated deterministic predicate. Approved reusable task profiles MAY avoid asking a human about every routine fix. Their applicability and limits MUST be checked for each task.

### ICV-014: Preserve scoped claims and unsuccessful attempts

Every material completion claim MUST map to approved obligations or be explicitly recorded as unsupported, contradicted or outside scope. A nonzero worker exit cannot become worker success because a marker says otherwise. A useful artifact left by a failed worker MAY be evaluated in a new, linked acceptance attempt under owner-approved policy. That preserves the failed attempt and independently tests the artifact; it does not rewrite failure as success or silently close its issue. Additional model explanations never repair missing evidence.

## 4. Confinement and exact candidate identity

A **candidate** is the complete input whose behavior is judged, not a branch name. A **validation execution** is a particular run of an approved checker against that candidate under identified conditions. A **receipt** records the actual result of an actuator operation. The identities are related but separate: a PR head, synthetic merge test, resulting main commit and deployed revision are not assumed equal.

### ICV-015: Isolate candidate writes and private material

Worker changes MUST be confined to the authorized candidate area and named scratch. Owner worktrees, pre-existing tracked/untracked changes, secrets, reference artifacts and unrelated repositories MUST remain protected. Read-only modes MUST prevent source writes rather than merely promise to notice them. Candidate rejection MUST NOT trigger a blanket reset, cleanup or overwrite of owner work. Multi-file source/test/documentation repairs MAY be allowed by the task scope; single-file selection does not excuse unprotected writes elsewhere.

### ICV-016: Acquire a coherent snapshot

Before authoritative validation, the supervisor MUST identify and acquire a coherent candidate, reference checker and required inputs. Immutable Git objects plus a verified context are one option, not a mandated implementation. Reading live files and stamping the ending HEAD is forbidden. A recursive copy of changing files or equal start/end hashes does not alone prove a coherent snapshot. Dirty/staged/untracked inputs MUST be captured under a sound explicit policy or refused for certification; diagnostic execution MUST NOT silently substitute clean HEAD for intended changes.

### ICV-017: Pin what runs

Execution MUST use the identified inputs without candidate-controlled modification or substitution during the run. Writable outputs, temporary files and intentional destructive test fixtures MUST be separated from authoritative inputs. A lock provides only the cooperation guarantee it actually enforces. Changes in the original checkout may coexist with a valid result for the old pinned snapshot, but that result MUST NOT certify the new checkout. The actual execution identity, not a label selected after completion, binds all resulting evidence.

### ICV-018: Bind relevant execution conditions

Evidence MUST identify the command, arguments, requested/actual check inventory, source and checker versions, effective configuration, relevant environment, toolchain, filesystem/durability class and Git diff context. Sensitive values MUST be protected or represented without disclosure. Unsupported platform, filesystem, dependency or confinement assumptions MUST block the affected certification, not be normalized to a compatible value. Tests on memory-backed scratch do not establish persistence after power loss on a deployed disk. Changed material conditions require new evidence or an approved equivalence rule.

### ICV-019: Make fixture safety independent of restoration

Validation setup and mutation MUST operate only on test-owned inputs and independent writable copies. Unsupported inherited links, parent-path redirection, shared writable inodes and nonregular inputs MUST be rejected before mutation. Checking a pathname and later opening an uncontrolled target is insufficient. Appropriate non-following operations and actual object checks MUST enforce the declared boundary. External sentinel checks MUST detect writes even when content is restored; relevant identity and modification/change metadata are retained. Cleanup or eventual restoration MUST NOT be the protection mechanism.

### ICV-020: Verify publication subjects again

Before applying a candidate or permitting a merge, the actuator MUST confirm the exact approved candidate, target baseline and applicable current policy. A changed PR head, changed target branch, different diff or different checkout invalidates the old action grant unless an independently approved equivalence rule applies. Compare-and-swap or equivalent server-side preconditions MUST prevent check/use substitution. Post-merge health and issue completion MUST refer to the resulting main revision or a documented valid successor, never an unrelated earlier green check.

## 5. Evidence quality and event semantics

### ICV-021: Require structured provenance

Every authoritative evidence item MUST bind its producer and approved measurement scope, subject, requirement/obligation references, execution/run/attempt identities, observation time/interval, environment, measured result, artifact digest and privacy class. Authentication establishes an authorized origin; it does not establish the truth of unobserved business facts. The verifier MUST validate origin using a trust anchor outside worker control. Existing `upk:` artifact, run, repository and validation references SHOULD be reused where their defined meaning fits [S7].

### ICV-022: Reject self-asserted trust

Fields such as `trusted=true`, `passed=true`, a correlation ID, a named tool or a valid signature from an unapproved key MUST NOT grant authority. Parsing MUST reject duplicate/conflicting keys, unknown required schema versions, invalid values, unsafe paths and resource-exhausting input. Missing required fields MUST NOT default to success. Verification of content identity and verification of producer authorization are separate requirements. A worker-controlled reference to the expected hash or public key is not a trust anchor.

### ICV-023: Require complete observation for the claimed property

For every evidence-dependent predicate, the checker MUST establish that the relevant observation channel was enabled, operational and complete for its declared interval and boundaries. Dropped records, exhausted buffers, unavailable instrumentation or uncertain coverage MUST produce `UNKNOWN`, not absence of a prohibited event. Evidence limits and sampling MUST be disclosed. A negative claim such as no outbound effect needs enforced containment or complete observation over a specified scope; silence in a partial log cannot establish it.

### ICV-024: Bind causal handoffs

A multi-component claim MUST identify the originating input version, operation identity, intended recipient and the data identity at each required handoff. Timestamps or a shared worker-chosen trace ID alone do not establish causality. The checker MUST validate producer/receiver identities, permitted predecessor relationships and transformation-specific assertions. Out-of-order, replayed, duplicated or unrelated events MUST NOT fill a missing link. Legitimate concurrency MAY use a partial order; requiring a fictional global event order is unnecessary.

### ICV-025: Distinguish attempt, receipt and effect

A sender's successful call proves only the observation its API actually reports. It MUST NOT be promoted to receiver receipt, durable storage, exactly-once processing or successful business effect without corresponding authoritative observations. Required acknowledgements MUST bind receiver, input, operation and result. A forged acknowledgement in candidate logs is not receiver evidence. A receiver acknowledgement before commit is not commit evidence. Timeout may mean an unknown outcome rather than definite failure; the contract MUST prescribe reconciliation before retries with irreversible effects.

### ICV-026: Retain contradictions and freshness

Authoritative contradictory observations MUST remain in the evidence set and prevent acceptance of the affected claim until reconciled under approved rules. A later successful retry MUST NOT erase earlier failures or leave their side effects unaccounted for. Evidence freshness is property-specific: an immutable historical event remains historical, but authority, revocation state, deployed conditions and action preconditions need current verification. Safe cache misses MAY lead to fresh checks; malformed or unsafe evidence locations MUST NOT lead to unguarded execution or overwriting unrelated files.

### ICV-027: Bound and protect evidence custody

Evidence and decisions MUST be published atomically with identities linking them to completed work. Partial, failed or interrupted publication MUST NOT appear as a current PASS. Custody storage, keys and retention policy MUST be inaccessible for worker modification. Retained rejected evidence MUST remain distinguishable from current authority. Resource limits, privacy and safe recovery are required; retaining everything forever is not. A loss of required durable recording MUST block dependent publication, merge and further work needing that record, while permitting a separately authorized safe shutdown.

### ICV-028: Lattice is not the judge

Lattice MAY index obligations, observations, decisions, retries and artifacts and support scheduling and deduplication. An entry in Lattice MUST NOT by itself establish a fact, authenticate its producer or authorize an effect. A replay/import MUST preserve origin, scope, status and supersession, and MUST NOT upgrade a model report into authoritative evidence. On missing or inconsistent custody, the authority MUST verify against approved underlying evidence or block the dependent action. Do not build a second ledger solely to satisfy this contract.

## 6. Evaluation, decisions and state transitions

Required logical checks use `TRUE`, `FALSE` and `UNKNOWN`. `UNKNOWN` includes missing evidence, unverifiable provenance, incomplete observation and unsupported measurement conditions. A material conflict remains a conflict, not whichever value is convenient. The machine-readable file defines the finite normalized decision model. It deliberately does not pretend that a schema validator can establish those predicates from arbitrary worker text.

### ICV-029: Evaluate obligations independently

Only an approved checker, under the approved acceptance authority, may assign an obligation `SATISFIED`, `VIOLATED`, `UNKNOWN` or evidence-backed `NOT_APPLICABLE`. A passing generic suite satisfies only the obligations its checks establish. Code coverage, function count, issue closure and process exit zero are not substitutes for required behavioral predicates. Tests with expected nonzero results MUST be explicitly identified as such before execution; that designation cannot excuse an unexpected nonzero worker or validator result.

### ICV-030: Make one authoritative acceptance decision

All completion paths MUST use one logical decision contract, even when implemented through multiple components. At minimum the authority verifies adoption, active work scope, protected authority integrity, exact subject binding, required observation coverage, checker completion, obligation results and absence of unresolved material contradictions. A claim is accepted only for its supported scope. Unknown control/evidence conditions MUST NOT produce acceptance. The worker's `WORK_DONE` or legacy final-status record is advisory input, never the verdict [S4, S5].

### ICV-031: Separate assessment from permission

`ACCEPTED` means required scoped claims are established; it is not a universal side-effect grant. `REJECTED` means authoritative evidence demonstrates an applicable requirement violation. `BLOCKED` means safe authority/execution/evidence prerequisites cannot be established. `REVIEW_REQUIRED` means an authorized decision or adequate semantic criterion is missing. `CANCELLED` means the work was stopped or revoked. A safe no-op uses `NO_CHANGE_VERIFIED` with its limited predicates. None of these states implicitly closes an issue, performs a merge or starts another task.

### ICV-032: Use deterministic decision precedence

The authority MUST retain all applicable reasons. For a single displayed disposition, revoked/cancelled work takes precedence; invalid authority or unverifiable evidence then yields `BLOCKED`; a verified applicable violation yields `REJECTED`; remaining required unknown evidence yields `BLOCKED`; unresolved approved human judgment yields `REVIEW_REQUIRED`; otherwise the supported scope is `ACCEPTED` or `NO_CHANGE_VERIFIED`. The ordering cannot hide a recorded violation. A malformed request is blocked before interpretation. A separate authorized diagnostic action may still publish a truthful failure report.

### ICV-033: Prevent vacuous success and convenient shrinking

Required-obligation and check inventories MUST be obtained from the approved task, not from the set of results the worker happens to return. Missing required checks, empty inventories for a claimed repair, zero discovered tests, disabled assertions and skipped/neutral CI outcomes cannot silently satisfy them. A zero-obligation task is permissible only when the approved task is explicitly administrative and its separate action preconditions establish the requested administrative result. Deleting a test or weakening expected values is a requirement change, not a repair proof.

### ICV-034: Record decisions before dependent effects

The acceptance authority MUST produce a durable decision record containing the evaluated scope, all material reasons, obligation assessments, evidence references, policy identity and permitted next actions. An actuator MUST NOT infer a decision from log wording or a worker exit. Failure to persist or authenticate a required decision leaves dependent actions blocked. Decisions are immutable historical facts; amendments supersede rather than erase. Recovery reconstructs state from authenticated decisions and receipts, not a model's recollection of what probably happened.

## 7. Action grants, receipts and continuing work

### ICV-035: Grant individual actions with preconditions

Each protected action MUST have a narrowly scoped grant bound to issuer, recipient actuator, action kind, repository/resource, exact subject, request, decision, current policy/revocation epoch, expiration and idempotency identity. Permitted kinds are proposal publication, accepted-patch application, candidate merge, issue resolution, next-task launch and an explicitly owner-defined external effect. The grant MUST state its action-specific preconditions. A draft report can be authorized without repair acceptance if it accurately labels failure; permission to publish a report cannot be replayed as permission to merge.

### ICV-036: Verify at the actuator

The actuator MUST authenticate a grant against an independently protected anchor, verify its binding and current preconditions, and enforce replay/revocation limits before acting. If the candidate can call an equivalent unguarded tool, the protected-action boundary is nonconformant. Privileged credentials MUST remain outside worker access. The authority owner MAY delegate bounded routine actions but MUST NOT delegate the ability to enlarge one's own grant. A GitHub ruleset protects only the operations and principals it actually governs [S10].

### ICV-037: Confirm actual external outcomes

After an effect, an authenticated receipt MUST describe what actually occurred and the resulting resource/version. Network uncertainty MUST yield `OUTCOME_UNKNOWN` until readback or another approved reconciliation establishes the result. No blind retry may duplicate a potentially non-idempotent effect. Exactly-once delivery MUST NOT be claimed from a local retry marker alone. If effect success is observed but receipt persistence fails, continuation is blocked pending reconciliation; the system cannot assert that nothing happened or manufacture a completed receipt.

### ICV-038: Bind issue closure to its real requirement

Issue resolution MUST require its approved completion conditions, the intended durable state and verified publication/main health appropriate to its scope. A pushed branch, generic test result, model claim or automatic closing keyword is insufficient. Design-only issues MAY complete with the specifically requested approved design artifact, not with claimed runtime enforcement. Partial work MUST remain partial. Unexpected automatic closure MUST be recorded and corrected or linked to an unresolved obligation without deleting the historical evidence [S6].

### ICV-039: Treat merged-main health separately

Pre-merge validation, merged-main validation and a deployed effect are distinct claims. The next-work gate MUST use the exact current main or a verified successor relationship under approved policy. Canceled obsolete runs may be superseded, but cancellation by itself is not passing verification. Strict branch checks and permitted merge identities MUST be verified in the actual environment. A current green main does not establish that every earlier issue was genuinely repaired. No deployment authority is inferred from repository merge authority.

### ICV-040: Reauthorize selection and preserve holds

Automatic selection MUST respect owner scope, dependencies, relevant health obligations, budgets, pause state and revocation before launch. Eligibility is not authorization. A failure in one task does not require freezing all unrelated work if an approved policy permits independent safe work; a compromised common acceptance boundary does. A clean queue MUST NOT restart a paused GOAL. Expected rejection, exhausted budget, a planned pause and a legitimate no-op MUST NOT create an unlimited self-remediation loop or a reason to bypass controls.

## 8. Failure, no-op, human judgment and real effects

### ICV-041: Stop without having to diagnose the cause

When a required predicate is false or unknown, the system MUST record the appropriate rejected/blocked state and prevent dependent unauthorized action even when no component can explain why. Error classification and model-generated postmortems are advisory. A durable obligation SHOULD identify the affected property, exact subject, evidence and permitted next step. Failure to write that obligation cannot make the run successful; retain an emergency diagnostic and block actions needing durable custody. Remediation requires its own bounded authority.

### ICV-042: Define a useful no-op

`NO_CHANGE_VERIFIED` MUST identify what was checked, its freshness and the scope in which no eligible action remains. It MUST NOT mean all possible defects are absent. A missing queue response, filtered-out unresolved work or unavailable health data is not an empty healthy queue. Known blocked/deferred work remains visible. The no-op path SHOULD use cheap deterministic checks and valid cached evidence before model contact; unnecessary touching of source or broad repeated tests is not evidence of useful maintenance.

### ICV-043: Preserve human judgments without counterfeit proof

A required human decision MUST be made by an independently authenticated authorized approver and bind the exact subject, requirement version and allowed action. It can establish an explicitly human-judged obligation. It MUST NOT be represented as a successful automated test or proof of an unobserved fact. Overrides that accept known risk MUST be recorded as such and cannot confer contract conformance for the violated requirement. Amendments take effect prospectively through adoption; the failed history remains intact.

### ICV-044: Separate repository changes from irreversible effects

This contract grants no deployment, production database, credential disclosure, message transmission or destructive cloud authority. Any such scope requires an owner-approved external-effect profile with its own preconditions, observation and recovery contract. A source rollback does not prove data recovery or undo disclosure. Build scripts, tests and migrations can be effectful too and MUST run under the applicable confinement. Post-hoc logs are not a substitute for denying an unauthorized irreversible action before it occurs.

## 9. Self-maintenance, cost and conformance

### ICV-045: Keep the authoritative copy independent

The owner MUST retain an adopted contract, schema/policy/checker identity and approval anchor outside every maintenance worker's write and administrative reach. A public copy in Upkeeper is a distribution mirror. Editing it changes a proposal, not the adopted reference. Hash manifests establish byte identity, not owner consent or protection. The worker MAY read the contract and submit amendments; it MUST NOT replace the authoritative digest, trust key, validation source or enforcement workflow. The deployment arrangement is specified in AUTHORITY.md.

### ICV-046: Fail safely during authority updates

Contract/checker promotion MUST be atomic, versioned, reversible under owner policy and separate from the candidate's own acceptance. In-flight requests remain bound to their authorized revision unless revoked. Newly discovered control defects can revoke pending grants without erasing historical results. Rollback to an earlier baseline requires explicit review of its known defects; an old signature does not make an unsafe baseline acceptable. Crash, partial installation or mismatched artifact versions MUST leave new protected actions blocked rather than selecting whatever file exists.

### ICV-047: Test forbidden success and legitimate progress

Conformance MUST include attempts to obtain success from false status, missing checks, wrong candidates, altered criteria, incomplete handoffs, forged/replayed evidence, prohibited writes and bypass paths, plus valid positive and no-op cases. The tests MUST challenge actual entrypoints and actuators or explicitly identify the test doubles used. Parser tests and inspection alone do not establish runtime enforcement. Reference expectations MUST remain outside candidate control. This package's case matrix is a specification of required tests, not evidence those tests already passed.

### ICV-048: Preserve evidence limits and inspection history

Reports MUST distinguish authored requirements, source inspection, synthetic model checks, controlled execution, live integration, independent review and production observations. An author running the candidate's own tests is not automatically independent acceptance. An environmental failure MUST remain failed or blocked, not be waived because local tests passed. Existing working protections MUST NOT be disabled to improve a dashboard. The documented reason for a host failure is limited to observed evidence; this contract does not prescribe a speculative platform workaround.

### ICV-049: Bound resource use and new machinery

Approved work and validation profiles MUST bound compute, model contact, observation volume, retention, retries and external writes. Limits that prevent required verification produce a visible blocked result rather than false success. Conservatively keyed reuse MAY reduce cost once input, producer, predicate, environment, scope and freshness are established. Whole-request reuse is acceptable; a new dependency graph engine is not required. SHOULD-level cost targets do not override MUST-level safety, and safety wording MUST NOT justify unrelated architecture growth.

### ICV-050: Publish conformance by property, not by slogan

A deployment MUST maintain a requirement-to-control-to-test-to-evidence map with current states `NOT_IMPLEMENTED`, `IMPLEMENTED_UNVERIFIED`, `TESTED_IN_SCOPE`, `ENFORCED_IN_SCOPE` or `KNOWN_NONCONFORMANT`. Supported modes/platforms and threat assumptions MUST be listed. No percentage score, green suite or count of closed issues is a substitute. Where only part is implemented, the system MAY operate within independently authorized narrower modes, but MUST NOT claim this full contract governs unmediated operations.

## 10. Normative decision and action semantics

The finite normalized decision model is specified in `verification-spec.json`. Its inputs are produced by trusted adapters from actual evidence, never accepted as worker-supplied assertions. The model uses eleven three-valued facts: request active; adoption valid; authority integrity valid; subject binding valid; evidence authenticity valid; approved inventory complete; verified violation present; required observation complete; checker completed; required unknown present; and human judgment resolved. A separate Boolean records whether the approved task is a no-op. The field names and polarity are fixed in the JSON specification. Missing facts are `UNKNOWN`, never implicitly true.

Decision evaluation first retains every reason. Cancellation/revocation yields `CANCELLED`. Invalid adoption/authority/subject/evidence authenticity yields `BLOCKED`. A valid established violation yields `REJECTED`. Incomplete observations or remaining required unknowns yield `BLOCKED`. Unresolved human judgment yields `REVIEW_REQUIRED`. The remaining complete valid set yields `NO_CHANGE_VERIFIED` for a no-op task and `ACCEPTED` otherwise. These categories judge the declared claim set only.

An action grant is evaluated separately. All actions need live authorization, protected issuer/actuator integrity, binding, current preconditions, intact custody and available budget. Accepted-patch application and candidate merge additionally require `ACCEPTED` for their defined candidate obligations. Issue resolution additionally requires its issue-specific completion and actual durable state; a previously repaired/no-change case is allowed only with approved independent proof of that requirement. Next-task launch uses its own readiness policy, not the previous worker's completion marker. Proposal publication may use a rejected or blocked repair disposition while preserving that label. No grant includes a wildcard meaning do anything next.

A receipt transitions from `NOT_STARTED` through `IN_FLIGHT` to `CONFIRMED`, `FAILED` or `OUTCOME_UNKNOWN`. Only readback or another approved observation can resolve unknown external outcomes. A decision or grant cannot assert its own future receipt. Retrying a protected side effect requires checking its idempotency identity and current external state.

## 11. Fully specified acceptance examples

### 11.1 One-character HTML correction

Approved task: on the designated local page, change the visible heading from `Acount` to `Account`, preserve its link destination and leave an unrelated page unchanged. The write scope includes the template and a proposed regression, not the protected expected heading. An independent browser or parser checker, according to the approved rendering scope, loads the pinned candidate and checks the selected element's text, link target and unrelated artifact identity. A raw source substring is insufficient if the claim concerns rendered text and the substring is hidden or overwritten.

A correct candidate satisfies the scoped observations. A worker that edits a comment, another page, only its own test expectation, or a success log does not. A checker unable to render the required page yields an unknown required observation. The report distinguishes a parser-only test from browser-visible rendering. Acceptance allows only the specifically authorized next action, not deployment. This is a synthetic example, not a claim about an existing Upkeeper client.

### 11.2 File, predicate, handler and payload

Approved task: for a valid fixture file whose parsed `mode` field equals `xyz`, invoke handler H with payload P and obtain the specified receiver state. Approved predicates establish the input version and parsing rule, authorized H identity, transformation from parsed input to P, receipt of P for the same operation, and committed receiver state. For absent `xyz`, malformed input and refused receipt, the contract names the required non-send/error behavior and preserved data.

Trusted observation of reading a file alone does not establish the branch condition. A sender trace alone does not establish receiver receipt. A signed receipt before persistence does not establish committed receiver state. The checker compares the actual state through a protected receiver interface or controlled fixture and reconciles duplicate/time-out cases. It also establishes the bounded no-forbidden-effects condition through containment or complete observation. When the receiver is unavailable, the claim is blocked or its outcome remains unknown; no logging trick fills the gap.

One passing execution supports `OBSERVED_EXECUTION`. Required positive/negative/boundary cases support `TESTED_CONTRACT` in that domain. A claim that every send is mediated requires independent proof of the guarded sending boundary and exclusion of other authorized send paths. None of these claims proves all unspecified behaviors for every future file, environment or receiver.

## 12. Adoption and integration with existing Upkeeper work

This document completes the requirement definition; it does not implement the required runtime or delegate specification authorship to a worker. The companion JSON fixes requirement identities, semantics, mandatory record fields, decision vectors and traceability. The matrix fixes adversarial and positive expectations. Implementers can propose better mechanisms, not silently substitute weaker acceptance.

Mapping is by responsibility, not an instruction to reopen closed work: #715 owns exact execution/evidence identity; #679 owns read-only/mutation evidence; #912 owns effective worker/checker authority; #910 owns the common acceptance decision; #805 owns issue-completion custody; #913 owns resulting-main readiness; #908 owns actual merge protection and remaining privilege separation; #914 owns safe fixtures; #915 coordinates the program; #916/#917 own later bounded evaluations. #135/#136/#687 cover custody and controlled publication. #227/#231 cover scope and operating boundaries. Existing airlocks parse untrusted inputs; Lattice indexes evidence; neither replaces the acceptance authority [S4-S9].

At authoring, reviewed main is `7886b35da837497b350f58694c8eb3a8f3e7da06`. The #715 candidate is draft PR #922 at `9e178af3fd0678c0fa682018bbd13660e1c4dd02`, with a reported required CI isolation blocker. This statement is a snapshot, not a new audit or a grant to continue that work [S8]. No existing GOAL, merge, deployment or client run is authorized by publication of this contract.

Before activation, the owner selects the protected authority location and identities, approves this exact bundle or a revised version, and commissions the enforcement/conformance work through the existing issues. Initial operating scope SHOULD be narrow, with explicit blocked unsupported states. No requirement to finish optional community contribution, a universal UI or a complete business-oracle library is imposed before a bounded conforming task can run.

## Sources and authority provenance

The requirements are authored engineering decisions based on the owner's discussion, not quotations or assertions that the following sources certify Upkeeper. Repository sources establish terminology and known gaps; the proposed contract intentionally strengthens the acceptance boundary. External sources establish terminology and structural mechanics only.

- **S1. RFC Editor, RFC 2119, requirement terminology.** https://www.rfc-editor.org/rfc/rfc2119.html
- **S2. RFC Editor, RFC 8174, uppercase requirement terminology.** https://www.rfc-editor.org/rfc/rfc8174.html
- **S3. NIST CSRC, Reference monitor glossary.** Context for complete mediation and a protected, analyzable enforcement mechanism. https://csrc.nist.gov/glossary/term/reference_monitor
- **S4. Upkeeper, schema-gated airlocks, pinned main.** https://github.com/joeszilagyi/Upkeeper/blob/7886b35da837497b350f58694c8eb3a8f3e7da06/docs/decisions/0003-schema-gated-airlocks.md
- **S5. Upkeeper, independent candidate acceptance issue #910.** https://github.com/joeszilagyi/Upkeeper/issues/910
- **S6. Upkeeper, durable issue completion issue #805.** https://github.com/joeszilagyi/Upkeeper/issues/805
- **S7. Upkeeper, run BOM and identifier namespace, pinned main.** https://github.com/joeszilagyi/Upkeeper/blob/7886b35da837497b350f58694c8eb3a8f3e7da06/docs/run-bom-identifiers.md
- **S8. Upkeeper, pinned validation-evidence candidate PR #922.** https://github.com/joeszilagyi/Upkeeper/pull/922
- **S9. Upkeeper, authority model, pinned main.** https://github.com/joeszilagyi/Upkeeper/blob/7886b35da837497b350f58694c8eb3a8f3e7da06/docs/authority.md
- **S10. GitHub Docs, reviewing installed app permissions and repository selection.** https://docs.github.com/en/apps/using-github-apps/reviewing-and-modifying-installed-github-apps
- **S11. JSON Schema, Draft 2020-12 structural validation.** Schema validity is distinct from authenticated provenance and semantic acceptance. https://json-schema.org/draft/2020-12/json-schema-validation
