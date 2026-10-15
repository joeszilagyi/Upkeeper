# Upkeeper Independent Claim Verification and Acceptance Contract

**Status:** Draft 2. Not adopted or operationally enforced by publication.

## 1. Purpose and scope

Upkeeper must distinguish a worker's account of its work from evidence that the requested result was achieved. Its governing rule is:

> No claim of completed work may receive greater authority than the independent evidence supports.

This contract specifies the requirements for verifying maintenance claims, accepting a particular candidate, authorizing consequential actions, and recording their actual outcomes. It applies whether work is produced by an LLM, a deterministic repair tool, or another automated worker. It does not require the verifier to determine whether an inaccurate claim resulted from deception, error, or interruption.

Verification concerns defined properties, not unrestricted software correctness. It must be possible to establish a useful bounded result without claiming that every input, execution path, deployment, or future change has been proved correct. Checking a claim still requires suitable inspection or execution of the work; checking the wording of the claim is insufficient.

The uppercase terms MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY have the meanings defined by RFC 2119 and RFC 8174 [1, 2]. A documented alternative to a SHOULD requirement does not waive a MUST requirement. Sections 1 through 10 are normative. Section 11 contains illustrative acceptance cases. Section 12 identifies references.

### ICV-001: Explicit adoption

The policy owner MUST approve an exact contract revision, its associated authoritative artifacts, and the operating scope in which it applies. Publication, a merge, or an approval-shaped data record does not itself establish that approval. A deployment MUST NOT claim that this contract is active until it can authenticate the adoption through a channel outside worker control. Offline analysis and proposed implementation may proceed under separate authorization without claiming conformance.

### ICV-002: One governing requirements baseline

Each authorized task MUST identify its governing requirements revision. Derived schemas, manifests, prompts, and tests MUST preserve that revision's meaning. An unresolved discrepancy between governing artifacts blocks the affected acceptance decision; the implementation MUST NOT silently choose the easier requirement. This prose contract is the requirements baseline unless an explicit adoption identifies additional normative artifacts. Unadopted companion files are not governing requirements.

### ICV-003: Bounded assurance

Every accepted claim MUST identify its subject, required property, tested inputs or observed interval, relevant environment, and limitations. Reports MUST distinguish an observed execution, a tested behavioral contract, and an invariant enforced at a protected boundary. A stronger or formal assurance claim needs its own evidence and stated assumptions. Passing finite cases MUST NOT be presented as proof of unrestricted correctness.

### ICV-004: Minimal sufficient mechanisms

Implementations MAY choose their languages, storage, and confinement mechanisms. They MUST establish the properties required here within a declared threat model. They SHOULD use existing reliable components and the smallest sufficient checks. This contract does not require a new service per role, a test per private helper, continuous logging of every function call, or a new observability platform. Mechanism choice and assurance level MUST NOT be confused.

## 2. Roles and protected authority

The **policy owner** approves requirements and delegates operating authority. The **worker** proposes or produces changes within a permitted workspace. The **execution supervisor** controls the execution boundary and identifies what runs. **Observers and checkers** collect facts and evaluate specified conditions. The **acceptance authority** decides whether required conditions are established. An **actuator** performs an authorized operation. The **evidence custodian** retains the relevant records.

These are logical responsibilities. Trusted responsibilities may share an implementation. The required separation is between the worker and the authority that governs, judges, and publishes its work.

The protected boundary includes the reference requirements, expected results, verifier selection, configuration, executable dependencies, credentials, approval records, and action controls. A deployment must declare its trusted host and service assumptions. A hostile administrator outside the worker's capabilities may be excluded from that threat model; administrative capabilities actually available to the worker may not be excluded by assertion.

### ICV-005: Effective separation

The worker MUST NOT be able to modify, impersonate, or bypass the protected authority. This includes indirect access through inherited credentials, plugins, subprocesses, configuration overrides, writable dependencies, or alternative tool paths. The deployment MUST verify the effective permissions under the worker's actual identity. Different repositories, processes, accounts, or interfaces establish separation only to the extent their access controls enforce it.

### ICV-006: Independent observations

An observer is authoritative only for the facts its approved measurement method establishes. Candidate-authored logs and status fields MUST be treated as claims unless independently verified. A protected collector signing a worker message proves collection and origin of that message, not the event described in it. A checker MUST NOT rely solely on candidate-modifiable instrumentation to establish the candidate's own compliance.

### ICV-007: Complete mediation of protected actions

Every implemented route to an action requiring authorization MUST enforce the same applicable permission and evidence rules. The route inventory MUST include normal execution, direct invocation, fast paths, cached results, fallback, recovery, restart, and cleanup. A defined but uncalled guard does not satisfy this requirement. Unauthorized external effects MUST be prevented before execution; logging them afterward is not equivalent protection.

### ICV-008: Separate promotion of control changes

The worker MAY propose changes to a checker, observer, supervisor, schema, or policy. Those proposed changes MUST NOT become the reference that approves the same candidate. Promotion requires a separately authorized evaluation against protected expectations and an identifiable new reference. When the old reference is defective, the policy owner MUST establish a replacement-review procedure rather than allow the worker to select its own judge.

## 3. Work authorization and acceptance obligations

A **work authorization** permits a bounded attempt. A **candidate** is the identified output of that attempt. An **acceptance obligation** states an outcome or constraint that must be established before a particular claim or action can be accepted. An obligation includes its scope, applicability rule, evaluation method, required observations, and completion condition.

The task's required obligation set is authoritative. The worker's report may add proposed claims, but cannot shrink that set. Discovery and exploratory work can be authorized without an accepted repair specification; their output remains a finding or candidate for later evaluation.

### ICV-009: Establish requirements before acceptance-directed work

Before an attempt intended to complete a repair begins, the approved task MUST identify the required outcome, preserved behavior, prohibited effects, and acceptance method. A policy owner may approve a reusable task profile instead of individually approving every routine repair. The verifier MUST check that the profile applies to the particular task. Worker-generated tests or expectations are proposals until approved through that policy.

### ICV-010: Bound the attempt

Work authorization MUST identify the repository, initial baseline, permitted task, writable resources, operating mode, resource budget, expiry or bounded lifetime, and revocation/hold conditions. It MUST distinguish candidate source, owner working files, private evidence, and external systems. An issue number, priority label, selected file, or unresolved anomaly does not enlarge those permissions. Fallback and recovery MUST stay within the same authority or obtain a separate grant.

### ICV-011: Preserve obligation identity and applicability

Each required obligation MUST have an identifier and a versioned acceptance definition. Required obligations remain required when the worker omits them from its report. An obligation may be excluded only under a preapproved applicability rule whose conditions are established. A missing dependency, skipped check, disabled assertion, or absent observation is not evidence of non-applicability. Material changes to the task's expectations require a new approved revision.

### ICV-012: Cover behavior and handoffs

The acceptance plan MUST cover the material input/output behavior, component handoffs, and system constraints named by the task. Unit tests MAY support that plan but MUST NOT substitute for a required integration outcome. The plan MUST state suitable positive, negative, boundary, and preserved-behavior cases. A before-failing/after-passing reproducer SHOULD be retained for a repair. Where one is unavailable, the alternative evidence and limitation MUST be stated without inventing a baseline failure.

### ICV-013: Handle missing or subjective criteria explicitly

A required outcome with no approved evaluation method MUST remain unresolved. The result is `REVIEW_REQUIRED` when an authorized clarification or judgment is needed, not a worker-created passing criterion. A human judgment may be an approved evaluation method; it is not an automated measurement. New regression tests proposed by the worker MAY be executed for useful evidence before approval, but their expected answers MUST NOT thereby become authoritative.

### ICV-014: Preserve failed attempts and unsupported claims

Worker completion and candidate acceptance MUST remain separate records. A nonzero worker exit or interruption cannot be rewritten as successful execution because the worker emitted `WORK_DONE`. A usable candidate left by such an attempt MAY undergo a new, linked, independently authorized assessment. The old attempt remains failed. Every material reported claim MUST be supported, contradicted, or explicitly unverified; unsupported additional claims cannot be published as verified merely because the required repair passed.

## 4. Candidate isolation and execution identity

### ICV-015: Protect source and owner state

The supervisor MUST constrain worker writes to the authorized candidate area and named scratch resources. Read-only modes MUST prevent source mutation. Pre-existing owner edits, untracked files, unrelated repositories, secrets, and protected references MUST remain outside that write authority. Rejection MUST NOT reset, clean, or overwrite an owner's working tree. Legitimate multi-file repairs are permitted when their complete write scope is authorized.

### ICV-016: Acquire a coherent candidate

Authoritative validation MUST identify its candidate before execution and acquire a coherent set of inputs. It MUST NOT infer the tested revision from the live checkout at the end. A changing-directory copy or equal before/after hashes alone does not establish coherent acquisition. Dirty, staged, and untracked inputs MUST be captured under an explicit sound policy or excluded with an honest refusal to certify the intended dirty candidate. Diagnostic runs MUST identify what they actually examined.

### ICV-017: Keep the identified execution inputs stable

The validated source, protected expectations, and reference checker MUST remain the identified versions during authoritative execution. Writable build outputs and destructive test fixtures MUST be separate from those reference inputs. Changes to the original checkout may coexist with a valid result for the pinned candidate, but MUST NOT retarget that result to the changed checkout. Cooperative locks MUST NOT be described as protection from processes that can ignore them.

### ICV-018: Bind relevant conditions

Validation evidence MUST identify the command, arguments, requested and completed checks, source and checker versions, effective configuration, relevant toolchain/environment, and applicable baseline/diff context. Storage durability and external-service assumptions MUST be included when material to the claim. Unsupported conditions block the affected certification. A changed material input requires fresh verification or an independently approved equivalence rule. Private values MUST be protected rather than dumped into public evidence.

### ICV-019: Contain validation itself

Tests and fixture preparation MUST obey the same write and effect boundaries as other untrusted execution. Deliberate mutation MUST target independent test-owned objects, not inherited links or shared writable source objects. Unsafe path components and object substitution MUST be handled before an unintended write occurs. Safety MUST NOT depend on restoring an external file afterward. Relevant regression cases MUST check contents and object metadata sufficient to detect the demonstrated class of write, including interrupted cleanup.

### ICV-020: Recheck identity at application or merge

Before applying or merging a candidate, the actuator MUST verify that its current subject and target baseline satisfy the approved action's preconditions. A changed head, target, or material context invalidates stale permission unless an approved equivalence rule applies. The actual update MUST use a server-side condition, compare-and-swap, or another mechanism preventing substitution between verification and mutation. An earlier passing candidate is not automatic permission for a later one.

## 5. Evidence and observable conditions

A required fact may be established by a protected state inspection, an independently executed check, an authoritative receiver observation, or an enforced boundary. The contract does not require reconstructing every internal function call when a simpler observation establishes the actual required outcome.

Positive and negative claims need different evidence. A trustworthy receipt may establish that a particular delivery occurred despite unrelated lost diagnostics. Proving that no prohibited delivery occurred requires adequate coverage of every relevant route during the declared interval, or an enforced restriction that prevents it.

### ICV-021: Identify origin and subject

Authoritative evidence MUST identify its producer, approved measurement scope, candidate/input, task and attempt, validation execution, observation interval, measured result, and applicable obligation. The verifier MUST establish that the producer was authorized and that the evidence belongs to this subject. Artifact digests MAY identify bytes; authentication or a protected local origin must separately establish authority. Existing identifier conventions SHOULD be reused where their semantics fit.

### ICV-022: Reject self-asserted trust and unsafe parsing

A field such as `trusted`, `passed`, or `verified`, a familiar tool name, or a signature under a worker-selected key MUST NOT establish authority. Parsers MUST reject conflicting duplicate fields, unsupported authoritative schema versions, invalid required data, unsafe references, and inputs exceeding defined resource bounds. Missing required evidence MUST NOT default to success. The reference used to validate a hash, signature, or producer MUST itself be protected from worker replacement.

### ICV-023: Establish sufficient observation

The verifier MUST establish observation availability and completeness to the extent required by each predicate. Silence in sampled, disabled, truncated, or lossy logging MUST NOT prove that an event did not occur. A missing mandatory handoff observation leaves that obligation unknown. Loss of unrelated optional diagnostics need not invalidate a separately established positive fact. Every limitation affecting a claim MUST remain visible in its assessment.

### ICV-024: Verify required causal handoffs

For a claim that depends on a handoff, the verifier MUST establish the relevant input version, operation identity, sender and receiver, and payload or transformation relationship. Timestamps or a copied correlation identifier alone are insufficient. Unrelated, duplicated, or replayed events MUST NOT fill a missing link. Legitimate concurrency may be represented by a partial order; an arbitrary total order MUST NOT be imposed as proof of causality.

### ICV-025: Distinguish attempt, receipt, and resulting state

Evidence of a send attempt MUST NOT be promoted to receipt or completion without the observations required for those separate claims. An acknowledgement establishes only its defined semantics. A receipt before persistence is not proof of durable state. A candidate log claiming receipt is not an authoritative receiver observation. Timeouts or connection loss MUST be treated as uncertain effects when success cannot be ruled out, with reconciliation before potentially duplicating a non-idempotent action.

### ICV-026: Preserve contradictory evidence and control reuse

Relevant failures and contradictory authoritative observations MUST remain recorded. A later retry does not erase them. The verifier MUST reconcile contradictions before accepting the affected claim. Evidence reuse MUST verify the subject, evaluation method, environment, scope, origin, and property-specific freshness; historical truth does not imply current action permission. A rejected cache entry MAY lead to fresh verification under valid authorization, but MUST NOT lead to skipped verification or an unsafe fallback.

### ICV-027: Protect evidence custody

Required evidence and decisions MUST be committed to protected storage so incomplete, interrupted, or failed publication cannot appear as a completed passing record. Storage ownership, retention, and recovery rules MUST preserve identity and distinguish current evidence from rejected or superseded records. The worker MUST NOT be able to rewrite authoritative custody. Failure to retain a required record blocks actions depending on it; emergency diagnostics and safe shutdown remain permitted without claiming durable recording succeeded.

### ICV-028: Keep Lattice in its evidence role

Lattice MAY retain references, history, obligations, and scheduling information. A Lattice row MUST NOT, merely by existing or carrying a passing label, authenticate its origin or authorize a protected action. Import and replay MUST preserve evidence class and provenance. Missing or conflicting custody requires verification of the underlying authoritative records or a blocked dependent action. A second ledger is not required when the existing one can satisfy these constraints.

## 6. Acceptance decisions

Each required obligation has one of five evaluation states:

| State | Meaning |
|---|---|
| `SATISFIED` | The approved condition is established for its declared scope. |
| `VIOLATED` | Valid evidence establishes that the condition is not met. |
| `UNKNOWN` | Required measurement, identity, execution, or evidence cannot be established. |
| `PENDING_REVIEW` | An authorized clarification or judgment is required. |
| `NOT_APPLICABLE` | The approved applicability rule demonstrably excludes the obligation. |

An empty observation is not automatically `VIOLATED`: missing receipt evidence can mean unknown receipt rather than proven nondelivery. Both prevent acceptance when receipt is required. A rejected optional or forged input need not contaminate a complete independent evidence set, but the attempted misuse remains recorded when material.

### ICV-029: Evaluate against the approved obligation set

Only the protected verification process may assign authoritative obligation states. The expected set MUST come from the approved task, not the worker's returned results. Generic suite success satisfies only the properties its checks actually establish. Expected-failure test children MUST be distinguished from failed workers or checkers using the approved test definition. An ordinary exit zero proves completion of that process, not every claimed behavioral outcome.

### ICV-030: Use a common decision boundary

All result-producing routes MUST apply the same acceptance rules to the relevant task and candidate. The authority MUST establish governing authorization, protected verifier integrity, exact subject binding, the required obligation inventory, adequate evidence, and the obligation results. A worker status marker is only a reported status. No fallback, local repair, cache, or fast path may independently turn that marker into accepted work.

### ICV-031: Separate assessment, authorization, and effect

An acceptance decision establishes the supported task outcome. A work authorization permits an attempt. An action authorization permits a particular consequential operation. A receipt records that operation's actual result. These records MAY share a storage format, but their meanings and controlling authorities MUST remain distinct. In particular, accepting a local candidate does not itself permit applying it, merging it, resolving an issue, or deploying it.

### ICV-032: Determine disposition without hiding failure

The authority MUST retain all material reasons and use the following decision order. A verified cancellation or revocation yields `CANCELLED`. An invalid or unestablished governing context, verifier integrity, or candidate identity yields `BLOCKED`. Within a valid context, any authoritative required violation yields `REJECTED`, even if other obligations remain unknown. Otherwise, any required `UNKNOWN` yields `BLOCKED`; any required `PENDING_REVIEW` yields `REVIEW_REQUIRED`. Only a complete set of satisfied or validly inapplicable obligations yields `ACCEPTED`, or `NO_CHANGE_VERIFIED` for an approved no-change task. An unverified cancellation claim yields uncertainty, not authenticated cancellation.

### ICV-033: Prevent vacuous completion

A claimed repair MUST NOT pass because no tests were found, checks were filtered out, results were skipped, or required assertions were disabled. The approved inventory and actual completion MUST be compared. Administrative tasks and no-change checks may use observations other than tests, but still need an explicit completion predicate. Removing a required check or changing its expected answer requires separate approval; it is not evidence that the original obligation passed.

### ICV-034: Retain a decision before using it

An authoritative acceptance record MUST identify the task, attempt, candidate, requirements revision, obligation assessments, evidence references, disposition, and reasons. It MUST be retained before a dependent protected action uses it. Subsequent corrections supersede rather than erase the record. A record that cannot be authenticated or durably retained cannot authorize its dependent effect. Restart recovery MUST use verified records and actual state rather than reconstruct authority from explanatory prose.

## 7. Consequential actions and continuation

The action boundary governs application to owner-controlled state, public reporting, merge, issue resolution, further automated work, and any separately authorized external effect. Ordinary writes within an already authorized disposable candidate workspace do not require completed-repair acceptance; they remain constrained by the work authorization.

### ICV-035: Authorize the particular action

Every protected action MUST identify its authorizing owner policy or delegation, executor, operation, resource, exact subject, current preconditions, budget, validity period, and replay controls. It MUST cite an acceptance decision when that action requires one. Starting a new task depends on its work authorization and current readiness, not on a completed acceptance decision for work that has not yet occurred. Publishing a truthful failure report MAY be authorized without accepting the attempted repair. That permission cannot be reused for merge or issue resolution.

### ICV-036: Enforce permission where the effect occurs

The actuator MUST establish the authorization's protected origin, exact binding, current validity, and action-specific preconditions immediately before acting. Any equivalent reachable operation outside that boundary invalidates the claim of complete mediation. Worker access to a privileged token, alternate tool, or editable enforcement configuration MUST be addressed rather than excluded from testing. A bounded owner delegation MAY permit routine automation without individual approval of every action.

### ICV-037: Reconcile actual action outcomes

A receipt MUST distinguish `CONFIRMED`, `FAILED`, and `OUTCOME_UNKNOWN`, with evidence identifying the affected resource and result. A sent request is not a confirmed effect. If an effect is observed but its receipt cannot be retained, record the custody failure and block dependent continuation; do not falsify the observed success as nondelivery. Where the effect itself is uncertain, obtain authoritative readback or other approved reconciliation before retrying a potentially duplicative action. A local idempotency marker alone does not prove exactly-once remote execution.

### ICV-038: Resolve issues only on their real completion conditions

Issue resolution MUST be authorized against its specific approved requirement and verified durable state. Partial repairs remain partial. A design issue may be resolved by the requested approved design without asserting runtime implementation. An already-repaired issue may be resolved using current independent proof without generating unnecessary changes. Unexpected automatic closure MUST be recorded and reconciled, not treated as evidence of success. A failure to correct the tracker leaves a visible unresolved tracking obligation.

### ICV-039: Establish readiness of the actual integrated result

PR-head verification, merge-test verification, resulting-main health, and deployment health MUST remain distinct. The continuation policy MUST identify which state is required and verify that state or an explicitly valid successor. A canceled obsolete run may be superseded under that policy, but cancellation is not success. Required server-side checks and applicable non-bypass identities MUST remain effective. A green repository state does not establish completion of an unrelated issue or confer deployment authority.

### ICV-040: Preserve holds and bound subsequent work

Before a new automated attempt, the controller MUST check scope, applicable dependencies, relevant health obligations, budget, and current pause/revocation state. Eligibility is not authority. Expected refusal, a planned pause, exhausted resources, or legitimately blocked work MUST NOT trigger unrestricted self-repair. A task-local failure need not stop independent work when approved policy permits it; uncertainty in shared acceptance or action authority blocks all work relying on that compromised boundary.

## 8. Stops, no-change outcomes, and human decisions

### ICV-041: Stop without requiring a diagnosis

A required false or unknown condition MUST prevent the dependent acceptance or action even when its cause is unknown. The system MUST retain the failure scope, subject, evidence, and permitted next step as a durable record when the required store is available. If that store fails, it MUST stop dependent actions, retain an emergency diagnostic where safely possible, and report the recording failure. Explanations and postmortems do not satisfy the original obligation. Remediation remains separately bounded work.

### ICV-042: Make no-change outcomes meaningful

`NO_CHANGE_VERIFIED` MUST state the checked scope, freshness, and established reason that no change is required or no eligible work exists. It MUST NOT imply absence of every possible defect. An inaccessible queue is not empty; all-blocked work is not a repaired queue. Known deferred work remains visible. A healthy no-change path SHOULD avoid model calls, unnecessary source touches, and repeated broad validation when appropriate protected evidence is already available.

### ICV-043: Keep human approval honest

A human decision MUST be authenticated through the owner-approved channel and bound to its exact subject, obligation version, and permitted consequence. It MAY satisfy an explicitly human-judged requirement. It MUST NOT be represented as a successful automated check or as observation of an event that was not observed. An owner override accepting known risk does not make a violated requirement conformant. Revising the requirement prospectively does not erase a prior failure under the earlier requirement.

### ICV-044: Treat irreversible effects separately

Repository-maintenance permission MUST NOT imply permission to deploy, disclose credentials, send external messages, migrate production data, or delete external resources. Such operations require their own approved effect, observation, and recovery conditions. Tests, build hooks, and migration scripts MUST obey these limits too. Reverting source is not evidence that an external effect was reversed. A separately authorized safe stop or cancellation MUST remain available without requiring successful completion of the task it is stopping.

## 9. Reference protection, self-maintenance, and cost

### ICV-045: Protect the adopted reference and its selector

The adopted contract and the references selecting its policy, verifier, expectations, and approval keys MUST be outside worker write and administrative reach. A repository copy may be a readable mirror. A digest identifies content only when compared against an independently held reference; changing both a writable document and its adjacent digest cannot change adoption. Workers MAY propose amendments, not promote them. Enforcement of this separation MUST be demonstrated before it is claimed.

### ICV-046: Change authority coherently

Contract or verifier promotion MUST activate a consistent versioned reference set through a protected procedure. Interrupted promotion MUST NOT leave mixed artifacts authorizing new actions. In-flight tasks remain bound to their approved versions unless revoked. Rollback requires owner-approved consideration of known defects and revocation state; a previously signed version is not automatically a currently authorized version. Reference review and operational activation are separate stages.

### ICV-047: Test forbidden success and valid progress

Conformance evidence MUST include deliberate false claims, wrong or stale subjects, missing checks, altered expectations, incomplete handoffs, forged evidence, prohibited effects, alternate routes, and interrupted recording. It MUST also include legitimate acceptance, safe no-change, and authorized recovery cases so a system that always refuses cannot claim functional conformance. Tests MUST exercise actual applicable boundaries; mocks, source inspection, and hypothetical cases MUST be identified as such. Acceptance expectations remain protected from the candidate under test.

### ICV-048: Report only the verification actually performed

Reports MUST distinguish source inspection, structural checks, synthetic model evaluation, candidate execution, integration checks, independent review, and production observation. Test results MUST name the revision and relevant conditions actually examined. Missing or environment-blocked verification remains unmet. Test counts, schema validity, and separately named agents MUST NOT substitute for proof of the relevant behavior or independence. A failed check MUST NOT be weakened merely to produce an accepting status.

### ICV-049: Bound costs without weakening acceptance

The authorized profile MUST bound execution, model contact, retries, observation volume, retention, and public writes. If those limits prevent required verification, the result is blocked or review-required rather than a fabricated pass. Valid reuse MAY reduce cost. A conservative whole-request reuse policy is acceptable; finer dependency caching is optional. Proportional verification and simple local mechanisms SHOULD be preferred when they establish the same required properties.

### ICV-050: State conformance by property and operating scope

A deployment MUST map each applicable requirement to its enforcing component, actual entrypoints, supported environment, verification cases, and evidence. It MUST distinguish specified, implemented, tested, enforced, and known-nonconformant states. Partial implementation may support a narrower independently authorized mode, but MUST NOT be advertised as coverage of excluded or unguarded modes. Publication of this contract or its test plan does not establish any implementation's conformance.

## 10. Minimum decision and action records

No particular database, message transport, or cryptographic format is mandated. A protected local API may establish origin without a separate signature on every internal record. Cross-boundary or stored records still need an authentication and integrity mechanism appropriate to the declared threat model. References to other artifacts are permissible only when their protected resolution and required availability are established.

A work authorization MUST preserve its approved task/profile, resource scope, baseline, budget, lifetime, revocation conditions, and controlling authority. An evidence item MUST preserve what was observed, by whom and by which approved method, for which candidate/operation, under what conditions, and within which interval. Observation sufficiency belongs to the particular predicate, not a blanket `trusted` field.

An acceptance record MUST preserve the obligation inventory and per-obligation results, evidence references, overall disposition, limitations, and governing revision. It cannot grant effects beyond the action policy. An action record MUST preserve permission, exact resource/subject, preconditions, executor, replay identity, and actual outcome or unresolved uncertainty. A receipt asserting a completed effect MUST refer to observation of that effect rather than the permission to attempt it.

The same transport envelope may hold several records, but their distinct origin and meaning MUST remain verifiable. A worker cannot create authority merely by producing an object with the correct field names. Schema validation is a parsing boundary; semantic verification and authorization remain separate decisions.

## 11. Illustrative acceptance cases

These examples demonstrate the requirements. They are not a replacement for a particular application's approved acceptance profile or evidence that the example tests have run.

### 11.1 Visible HTML correction

Suppose the approved requirement is to change the visible heading on `/account` from `Acount` to `Account`, preserve the heading's link target `/profile`, and leave a designated unrelated page unchanged. The task identifies the relevant template, rendering conditions, and independently controlled expected results.

The protected checker renders the exact candidate, selects the required heading, verifies its visible text and destination, and compares the designated unrelated output under those conditions. Changing a comment, hidden text, or another page does not satisfy that requirement. A parser-only observation can establish source structure, but not an untested claim about browser-visible behavior.

If the render cannot be performed, the required observation is unknown and completion is blocked. If the rendered heading is still wrong, the candidate is rejected. If all scoped conditions are established, that candidate can be accepted for the tested rendering conditions. Applying, merging, or deploying it remains a separate authorized action.

### 11.2 File-to-handler-to-receiver behavior

Suppose an approved local test profile defines a UTF-8 JSON configuration. When its `mode` member is the exact string `xyz`, the program must invoke the designated delivery handler and send the approved payload for that operation to a controlled receiver. The profile defines the payload transformation, recipient, expected final receiver state, deadline, and retry policy. Malformed input must produce the specified error without delivery. An absent or different mode must produce the specified no-delivery result.

For the positive case, the checker establishes the identity of the actual input, the applicable parsed condition, the designated handler invocation, the payload received for the same operation, and the required receiver state. A protected receiver-side query may establish the final effect without instrumenting every internal function. If persistence across restart is part of the requirement, that persistence is tested separately; a recorded receipt alone does not establish power-loss durability.

A worker-written `payload_received=true` line is not receipt evidence. An acknowledgement from another operation or recipient cannot fill the gap. Sender success followed by an unavailable receiver query leaves the required effect unknown. A timeout after a possible delivery requires outcome reconciliation before a retry that could duplicate the effect.

For the negative cases, no-delivery evidence must come from the controlled receiving boundary, sufficient observation of relevant routes, or enforced prevention. An empty partial log is insufficient. A passing set of cases establishes the specified test domain, not every configuration or deployment. A broader claim that all sends are mediated requires separate verification of the effective send boundary and alternative paths.

## 12. References

[1] Scott Bradner, RFC 2119, *Key words for use in RFCs to Indicate Requirement Levels*. Normative reference for requirement terminology.
https://www.rfc-editor.org/rfc/rfc2119.html

[2] Barry Leiba, RFC 8174, *Ambiguity of Uppercase vs Lowercase in RFC 2119 Key Words*. Normative reference for capitalization and interpretation.
https://www.rfc-editor.org/rfc/rfc8174.html

[3] NIST Computer Security Resource Center, *Reference monitor*. Informative background for protected mediation. The requirements in this contract are project-specific; this reference does not certify them or their implementation.
https://csrc.nist.gov/glossary/term/reference_monitor
