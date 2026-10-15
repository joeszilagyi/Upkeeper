# Independent verification: structured data contract

**Revision:** Data Draft 1 (`upkeeper.verification-data.v1-draft.1`).

**Basis:** Contract Draft 3 and Acceptance Matrix Draft 1. Unadopted specification, not an installed verifier.

## 1. What this profile supplies

`verification-spec.json` fixes the state vocabulary, decision order, action-specific requirements, retained-condition lifecycle, concrete fixture parameters and requirement/case crosswalk. `verification.schema.json` supplies local JSON Schema Draft 2020-12 definitions for the specification, example suite and fourteen record kinds. `verification-examples.json` supplies linked synthetic records and positive/negative data vectors.

The prose in [CONTRACT.md](CONTRACT.md) remains the governing requirements baseline under ICV-002. This profile instantiates its Section 10 minimum records. Field names, serialization limits and the transport form below are explicit profile choices, not claims that the prose mandates JSON, a signature for every local operation, or a new service. An implementation using another internal representation must preserve these meanings and expose a lossless mapping when it claims compatibility. An unresolved discrepancy blocks the affected use; changing an example cannot override the contract or matrix.

The source bindings in `verification-spec.json` identify exact contract/matrix bytes. No self-referential package digest is used. An adopted artifact set must independently identify this profile, schema and relevant checker as well. These adjacent digests detect changes relative to an independently retained reference; they do not create adoption or permission separation.

Examples occupy the `EXAMPLE-NOT-ADOPTED` realm, have no authenticated operational origin, and must never be loaded as production authority. They test the representation and declared semantics. Even a completely consistent record graph is not proof that its alleged observations occurred. The actual ICM scenarios still require the independent boundaries and effect observations specified in [ACCEPTANCE-MATRIX.md](ACCEPTANCE-MATRIX.md).

## 2. Parse, resolve, verify, then decide

An authority consumer performs distinct stages in this order:

1. **Bound and parse:** enforce encoded size, nesting and value limits; decode UTF-8; reject duplicate decoded member names, malformed Unicode, unsupported numeric forms and trailing data. Do not execute content or fetch schemas while parsing.
2. **Validate structure:** select the exact locally pinned schema version. All record fields are closed; unknown authority fields and versions reject the record. Format checks for UTC timestamps are assertions, not ignored annotations.
3. **Authenticate origin:** establish the actual issuer, realm, governing policy and permitted measurement/action scope through an approved protected channel. Neither `issuer_id`, a checksum, a signature under an unapproved key nor this schema establishes that authority.
4. **Resolve relationships:** verify referenced bytes and kinds; bind task, attempt, candidate, obligation-set revision, method, input, operation and current authority. Apply the semantic rules in Sections 4 through 8.
5. **Evaluate independently:** derive per-obligation states from the approved expected inventory and actual observations. Preserve unknowns, judgment requirements, conflicts and rejected optional claims.
6. **Retain and act:** record the decision before a dependent action consumes it. The actuator separately rechecks current permission, subject, target, budgets, holds and replay conditions. Observe the actual effect afterward.

A rejected sole source for a required fact leaves that fact unknown. An irrelevant malformed optional message does not invalidate a complete independent evidence set. Do not feed raw worker records directly into the decision algorithm after merely validating their shape.

### 2.1 Serialization profile

Record metadata is UTF-8 without a BOM. Reject duplicate names after JSON escape decoding; do not silently take the first or last. Reject unpaired surrogates and invalid encoding. IDs compare exactly without Unicode normalization, case folding or whitespace cleanup. Text is data, including shell-looking text. Resource IDs are opaque names resolved by protected adapters, never paths or URLs to execute or follow automatically.

Metadata numbers are bounded integer tokens, at most 2^53-1, with no decimal/exponent/nonfinite forms or Boolean coercion. Negative metadata values are allowed only where a field explicitly permits them. Large or fractional measurements belong in an identified measurement artifact with its own approved type semantics, not a silently rounded metadata field. Process exit codes retain native signed or unsigned 32-bit results where applicable; unsupported or unavailable termination status is explicit, never truncated into zero. This transport restriction does not alter the controlled F-X application's distinct input rules.

The profile limits each record to 1 MiB, container nesting to 32, arrays to 4,096 elements, and text values to 4,096 Unicode code points. Schemas apply smaller field-specific bounds where shown. Enforce the byte and depth limits before unrestricted materialization. A deployment may choose stricter limits under its approved scope but cannot silently truncate required facts. Raising limits requires review of the affected parser/resource contract.

JSON Schema alone cannot reliably distinguish a lexically integral decimal token from an integer token after decoding, nor discover duplicate keys discarded by a parser. These checks precede schema evaluation. RFC 8259 defines JSON syntax and interoperability considerations; the project's duplicate rejection and tighter numeric/size rules are choices of this profile [1]. JSON Schema describes structural validation; its `format` vocabulary requires explicit assertion support where relied on [2].

### 2.2 Reference identity without hash cycles

An `artifact` is `{sha256, media_type}`. It identifies exact retained bytes; the trusted adapter supplies location, size limits, interpretation and permitted access. A `record_ref` is `{id, sha256}`: its digest covers the exact separately retained UTF-8 record bytes, including its envelope. A consumer must not reserialize a record and assume it has the same byte identity. A different serialization is a new artifact unless an independently approved equivalence rule applies.

For records embedded in the example suite, and only those examples, compute reference digests using UTF-8 JSON with sorted object keys, no optional spaces, unescaped Unicode and no trailing newline. This is a fixture serialization rule, not a newly required production signing format. Actual artifact references in the examples may be descriptive fixture placeholders; external authenticity and production backing are explicitly absent.

An obligation key is `{id, version}` inside an exact referenced `obligation_set`. The set's record digest pins the entire definition, including expected results, applicability and method. There is no digest of an object containing its own digest. A matching obligation ID/version from a different set is not interchangeable.

Reference fields resolve only through approved stores. Unknown IDs, wrong kinds, digest mismatch, unavailable required content, duplicate IDs with different bytes, reference cycles where prior history is required, or resource limits leave affected use blocked. No automatic HTTP, local file, shell, template or code resolution is allowed. Authentication must cover the complete content and kind; signing a worker claim authenticates that claim's origin, not its subject's truth.

## 3. Record catalog

The common envelope includes `document_type`, exact `schema_version`, `record_type`, `record_id`, `realm`, `issuer_id`, `issued_at`, `contract_sha256`, `privacy` and `payload`. All are required. Their presence is not verification. PRIVATE/RESTRICTED/PUBLIC_SAFE describe handling requirements, not a worker-selectable permission to publish. Actual origin/authentication evidence is maintained by the trusted transport or store, outside the claimant's control, and must be available when the record is used.

| Record kind | Meaning and authority |
|---|---|
| `adoption` | Owner approval of the exact artifact set, reference policy, scope, epoch and lifetime. Its approval evidence must be authenticated independently; it cannot authenticate itself. |
| `work_authorization` | Permission for a bounded task attempt, not a result. Names adoption, repository/baseline, scope, approved obligation set, budget, lifetime and delegation. Discovery may lack a finalized repair obligation set. |
| `obligation_set` | Approved expected inventory. Each definition names a scoped property, version, applicability rule, evaluation method, required observations and deadline. Approval is not created by the worker writing this record. |
| `candidate` | A coherently captured proposed input with baseline, source/input manifests, capture method and evidence. No end-of-run branch name can substitute for the actual tested inputs. |
| `attempt_result` | Supervisor-observed process outcome, execution identity, check inventory and any remaining candidate. The bounded worker claim is kept explicitly separate. |
| `observation` | A particular measured fact or unavailable observation, bound to method, scope, input, execution, interval and optional causal handoff. It is not itself an obligation verdict. |
| `assessment` | Protected obligation evaluations, supported/unverified claims and task disposition. Nullable references permit honest blocked diagnostics when context or a candidate could not be established; null never means success. |
| `action_authorization` | Permission for one identified logical effect, with actuator/resource/subject, separate action preconditions, budget, lifetime and replay identity. It is not proof the effect occurred. |
| `action_receipt` | Confirmed, failed or uncertain actual effect, with observations and any prior receipt it reconciles. Existence in memory is not successful durable retention. |
| `unresolved_condition` | Immutable creation of a required unknown/violation, pending review, coverage, authority or custody condition, including effective hold scope and permitted next step. No editable `resolved` Boolean is provided. |
| `condition_resolution` | Specific, authenticated, retained evidence of satisfaction, or an approved changed/withdrawn requirement. It references exactly one condition and does not erase its history. |
| `coverage_gap` | Material property, scope, available evidence class, missing coverage and automation consequence. Recording the gap does not fix or automatically accept the uncovered behavior. |
| `custody_checkpoint` | A protected store epoch/sequence and inventories of retained records and unresolved conditions, linked to the prior checkpoint or independently authorized initialization. A rewritten database cannot announce itself clean. |
| `case_result` | Actual result of one ICM case variant, including expected/observed artifacts, real components, doubles, observations, effects and limitations. No such runtime result is established by the example suite. |

These are data roles, not fourteen services or databases. An existing ledger may store them. A protected local call can provide origin without a signature field in every payload. Ordinary workspace writes allowed by a work authorization do not each require a new completed-repair assessment or action record.

## 4. Cross-record consistency

The following rules apply in addition to the schema. A structure-valid record violating a rule cannot authorize the affected action. An integration must enforce the rules; the schema is not advertised as implementing them.

### SD-01: Versions, realms and typed references

Every governing chain must use the adopted contract/data identities and approved realm. Referenced records must have the required kind and matching IDs/digests. References to `work_ref`, `adoption_ref`, `candidate_ref`, `attempt_ref`, `obligation_set_ref`, `condition_ref`, `action_ref` and assessment fields resolve respectively to their named record kinds. `evidence_refs`, `observation_refs`, `predecessors` and case `observations` refer to observations. `previous_receipt_ref` refers to a receipt for the same action/operation; `previous_checkpoint_ref` refers to the prior checkpoint of the same store epoch unless an approved migration explains the change. History links cannot point to themselves or form cycles.

`authorization_ref` on a resolution may refer to owner adoption or an appropriately delegated work authorization; permission to perform ordinary code repair is not automatically permission to withdraw its requirements. `initialization_authorization_ref` may name an owner-approved adoption/work authorization specifically permitting store initialization. Exact authority scope is still checked, not inferred from the record type.

### SD-02: Subject and inventory

A work/candidate/attempt/assessment chain must agree on repository, task, baseline and applicable attempt, or carry an approved explicit mapping for a new salvage or resolution assessment. Actual source/checker/input conditions must match the execution being cited. Reuse requires property-specific compatibility, not matching strings alone.

The assessment's obligation-set reference must match its approved work authorization. Required definitions are loaded from that set, not from the returned evaluations or optional claims. Definition keys must be unique within the set. Assessment keys must be unique and correspond to that exact set; duplicates cannot select a favorable result. Missing required results are normalized to `UNKNOWN` with a retained reason. Extra optional claims remain separately supported, contradicted or unverified. A malformed authoritative inventory prevents establishing the governing context, while a missing result in an otherwise valid inventory is a required unknown.

A repair, no-change, administrative or salvage completion needs at least one approved completion predicate. Administrative observation can satisfy that predicate without pretend unit tests. Discovery may run without an accepted repair specification, but cannot yield accepted repair completion by using an empty obligation set.

### SD-03: Method and applicability

`AUTOMATED`, `HUMAN` and `UNDETERMINED` describe the approved evaluation method. A method's referenced checker/parameters/expected artifacts identify executable or human evaluation definitions; `completion_predicate` is explanatory text, never a string to eval. Missing approved criteria yield `PENDING_REVIEW`. Approved criteria whose measurements were not completed yield `UNKNOWN`. A human judgment cannot replace an unperformed required automated measurement without a separately approved prospective requirement change.

A `SATISFIED` or `VIOLATED` evaluation must cite adequate authentic evidence from its approved method for this subject and scope. A `NOT_APPLICABLE` evaluation needs evidence that the preapproved applicability rule actually excludes it. A skipped job or unavailable dependency is not that evidence. Expected-negative subprocess exits are interpreted under the approved test definition; unexpected nonzero worker exit remains failed history. An attempt declared SUCCEEDED requires supervisor-observed completion and exit zero; these facts do not alone establish the repair.

### SD-04: Observation and handoff

Observation `availability=OBSERVED` means a defined measurement result exists, not that the application met its requirement. `UNAVAILABLE` has no measured result. Coverage is predicate-specific; a partial interval cannot prove no prohibited effects, but unrelated missing diagnostics need not erase a separately sufficient positive observation.

A handoff requiring causal proof must bind the exact operation, protected sender/receiver identities, input and payload/transformation, and applicable predecessor observations. Reference edges describe a partial order, not a fictional total clock order. Receipt cannot stand for committed state unless its approved measurement actually includes that state. Input/operation IDs, result digests and producer names must be independently verified. Candidate-authored traces alone remain claims even when a collector signs them.

### SD-05: Time and resource bounds

Validate UTC timestamps as real RFC3339 UTC instants. For every validity window, start must precede expiry. For a recorded interval, start may equal but cannot exceed end. Compare ticks only within an established clock ID and epoch. The approved adapter defines tick units. A restarted process cannot restart a lease or use a new clock epoch to extend authority. When validity cannot be established, permission is unavailable.

Budget counts are upper bounds, not suggestions. A zero allowance permits zero of that operation; it does not mean unlimited. Scope resources and writable resources must be unique, and every writable resource must be in scope. READ_ONLY may permit named scratch/evidence output but never source/reference writes. Permission for candidate writes is not permission for the owner worktree, a production receiver or a protected reference. Resource IDs must resolve to the actual bounded object at use time.

## 5. Deriving the decision

The `context` and evaluation fields are outputs of protected verification, not values the worker can set to obtain acceptance. The state rules in `verification-spec.json` use named predicates whose meanings are fixed below. They must be derived from the approved inventory and actual measurements.

Retain all material reasons. `D1` means independently verified cancellation/revocation. `D2` includes unknown cancellation status, invalid or unestablished governing authorization, verifier integrity or subject binding, and unavailable/malformed authoritative inventory. Within that valid context, `D3` tests whether any required evaluation is `VIOLATED`. `D4` tests any required `UNKNOWN`, including a result omitted from the returned set. `D5` tests required `PENDING_REVIEW`. `D6` and `D7` require the complete nonempty required set to be `SATISFIED` or evidence-backed `NOT_APPLICABLE`; only an approved NO_CHANGE task uses D6.

Evaluation of unknowns does not outrank an already established required violation in a valid governing context. Untrusted optional junk is rejected as authority without inventing cancellation or poisoning independently complete proof. A contradictory authoritative measurement requires reconciliation; choose `UNKNOWN` if the property is genuinely unestablished, or retain `VIOLATED` if a valid violation is independently established despite other unknowns.

The recorded disposition must agree with those results. A mismatch is an invalid decision record, not an opportunity to silently rewrite it into a favorable one. Corrected assessments are new linked records. An assessment and its required evidence must be durably available before a dependent effect uses it. A clean schema result is neither an acceptance decision nor proof that these normalized states were measured.

## 6. Authorizing effects without circular requirements

Every action has independently approved current preconditions. `precondition_set_ref` and `precondition_assessment_ref` describe that action's readiness, not the future repair's acceptance. For START_ATTEMPT, this can be an administrative preflight over permission, scope, health, hold and budget. No accepted repair result is required to start that repair. Its new invocation gets its own attempt identity.

APPLY_CANDIDATE and MERGE_CANDIDATE additionally require the exact local candidate's acceptance, matching current target baseline and an atomic use-time condition. RESOLVE_ISSUE needs issue-specific approved completion and appropriate durable state. It may legitimately refer to a verified no-change/already-fixed or approved design assessment; a generic successful repair elsewhere is insufficient. PUBLISH_REPORT can refer to a failed/blocked repair, or have no repair assessment, while its own privacy/destination/content authorization must be established. A grant for one kind never grants another. EXTERNAL_EFFECT needs its separately approved effect/observation/recovery profile.

SAFE_STOP may use a separately protected owner stop policy without requiring the failed task's work or assessment records. Its precondition references may be null when that approved procedure directly checks bounded owned targets; it must not depend on successful retention in the store it is trying to stop safely. This is not permission to delete arbitrary state, forge a successful receipt, or bypass restrictions for new work. Other action kinds require their precondition records and current checks.

The explicit action subject identifies the exact payload or candidate being acted on. A use-time checker must compare actual kind, executor, repository/resource, subject, relevant baseline, expiry/epoch, budget and idempotency identity with the retained grant. A current operator hold or invalid shared boundary prevents dependent effects even if an earlier grant looks valid. Safe-stop authorization remains separately scoped. Checks and mutation must not be separated by an unprotected substitution window.

`max_effects=1` refers to one logical authorized effect, not to a guarantee supplied by that field. Concurrent consumers must atomically reserve/consume that authority or rely on an actual equivalent destination guarantee. Lost acknowledgement leads to reconciliation, not a second effect. Reusing old passing evidence does not reuse expired action authority.

A receipt keeps actual effect outcome separate from custody. Confirmed effect plus failed receipt storage remains known effect and failed custody. An emergency receipt-shaped diagnostic is not an authenticated retained receipt merely because it validates. Before dependent continuation, the trusted store/checkpoint or authoritative destination must establish the missing result. `OUTCOME_UNKNOWN` stays uncertain until approved readback resolves it; a timeout cannot be rewritten as proof of nonexecution.

## 7. Persistent conditions and coverage

`unresolved_condition` creates historical state. Its effective unresolved status survives process restart, timer expiry, queue reorder, new attempt IDs, cache lookup, tracker closure and retention. `condition_resolution` is a new append-only record. It has no authority until its own origin, scope, subject mapping and required evidence are verified and retained.

An EVIDENCE_SATISFIED resolution names applicable new evidence and assessment for the one condition. It does not imply that every other condition is resolved. If a new fixed candidate establishes a property, record the transition explicitly; do not reattribute its evidence to the older failing code. REQUIREMENT_CHANGED and REQUIREMENT_WITHDRAWN reference the approved replacement obligation set and keep the previous result intact. A legitimate withdrawal can preserve the old obligation as nonrequired with the explicit new owner-approved rule; it is not old-version satisfaction. New requirements remain subject to their own assessments.

A custody checkpoint identifies its store, epoch, predecessor and current retained-record/unresolved-condition inventories. The checkpoint itself must be protected and retained independently enough to detect the rollback or deletion being claimed detectable. An empty new database cannot generate its own trusted clean checkpoint. Compaction may discard permitted old detail only while preserving required unresolved state and approved provenance. Initial checkpoint sequence zero requires explicit initialization authority; later checkpoints require a valid predecessor. This profile does not implement a new ledger or claim power-loss durability.

A coverage gap distinguishes protected checks, worker-only evidence and no adequate method. It records the material uncovered property and the permitted automation consequence. Protected checks can still leave a coverage gap outside their tested scope. Logging a gap, omitting an optional claim, or changing a dashboard cannot resolve it. Task-local holds and shared-authority holds remain distinct; separately authorized remediation can collect evidence without declaring the original requirement already satisfied.

## 8. What artifact references must preserve

Opaque digests are not placeholders for unspecified requirements. When referenced content is needed, its approved adapter must expose at least the following information, reject missing content and keep private material within scope:

| Referenced content | Required interpretation |
|---|---|
| Source/input manifest | Exact objects/bytes, modes/links policy, tracked/staged/untracked treatment, applicable repository/base context and coherent capture result. No ending-HEAD substitution. |
| Method/checker definition | Approved implementation/version and observation scope; expected results and parameters; execution completion semantics; origin independent of candidate. |
| Execution conditions | Actual command/arguments, checker/tool versions, effective relevant config/environment, clock/limits, diff context and material storage/service assumptions. No secret dumping. |
| Measurement result | Actual value, type/units, subject/operation, relevant interval and completeness. A sentence claiming an event is not its observation. |
| Applicability/approval policy | Versioned conditions, authorized approver/delegation and the permitted consequence; not inferred from record shape. |
| Receipt/resulting state | Actual destination operation and resulting resource/version, observed time and result; distinguish attempt, receipt and effect. |
| Custody inventories | Exact retained record identities and unresolved conditions, checkpoint sequence/epoch, approved compaction and recovery mapping. |
| Case artifacts | Actual invocation, candidate/reference/environment, expected and observed outcomes, real/double boundaries, effects, resources, cleanup and limitations. |

This permits existing Git objects, approved local records and retained artifacts without prescribing their databases or signature systems. A consumer cannot treat unresolved content as optional merely because its digest is present. Approved adapters are separately versioned trusted dependencies and must be tested at the actual boundaries before runtime conformance is claimed.

## 9. Validation boundaries and remaining deployment work

The example suite's expected data outcomes are fixed here, not chosen by the implementation worker. Its record examples cover every kind. Three named local input templates avoid repeating full synthetic decision/action/condition inputs: a vector either supplies an input directly or applies a bounded list of SET/DELETE field-path changes to its named template. Expand only these embedded data objects, reject unknown templates or paths, and validate the expanded input against the layer-specific schema. No include, shell expression or remote reference is evaluated. Data vectors cover decision distinctions, malformed/binding failures, F-X token rules, action substitution and condition/custody behavior. Resolution vector field `resolved_as` distinguishes current-scope satisfaction from supersession and from no resolution; it never asserts that an earlier failing candidate passed. The original 52 ICM families remain the behavioral conformance requirements. A data vector linked to a family does not replace all its variants or prove OS, GitHub, browser, receiver or persistence behavior.

Required data checks include local meta-schema validation, positive records, omitted/unknown fields, duplicate IDs/keys, wrong references, invalid time/intervals, inconsistent dispositions, unsupported applicability, stale subjects, failed-worker success and valid no-change/report/launch exceptions. Results must distinguish byte/schema consistency, semantic model checks and actual runtime tests. Do not inflate a count of Boolean combinations into a claim of real mediation.

No runtime consumer, cryptographic issuer, private authority store, credential boundary or owner adoption is installed by these files. Their exact identities and semantics are ready for independent review and implementation mapping. A mirror in the writable project cannot prevent the implementation worker from editing the governing reference; effective protection remains a separate deployment requirement under ICV-045.

## References

[1] Tim Bray, RFC 8259, *The JavaScript Object Notation (JSON) Data Interchange Format*. Syntax and interoperability background; the stricter parsing rules above are this profile's requirements.
https://www.rfc-editor.org/rfc/rfc8259.html

[2] JSON Schema, *Draft 2020-12 Validation*. Structural assertions and format behavior, not authenticity or application truth.
https://json-schema.org/draft/2020-12/json-schema-validation
