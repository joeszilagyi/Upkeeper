# Protected reference and owner adoption

**Revision:** Authority Deployment Draft 1.

**Status:** Deployment specification. Publishing these files does not install separation, authenticate adoption, or enable autonomous actions.

## 1. Purpose and authority

This document specifies the deployment boundary required by ICV-001, ICV-002, ICV-005 through ICV-008, ICV-021 through ICV-028, and ICV-034 through ICV-050 in [CONTRACT.md](CONTRACT.md). It uses [DATA-CONTRACT.md](DATA-CONTRACT.md) and the associated data schema without replacing their meanings. The rules below are deployment choices for this profile. An alternative must establish equivalent properties and receive separate owner approval; naming a different mechanism is not equivalence evidence.

Three independent conditions are necessary: approved reference bytes, a verifier that actually uses those bytes without worker substitution, and action boundaries that cannot be bypassed. Protecting the document alone satisfies none of the other two. A worker can read the specification, propose amendments, and implement candidate controls. It cannot adopt its proposal, promote its own judge, or grant itself permission to act.

The baseline must remain understandable and publicly reviewable when its owner permits publication. Confidentiality is not the primary protection. Write authority, identity, freshness, and complete mediation are the relevant properties. A Git repository can distribute approved artifacts; Git hosting does not itself prove a deployment uses them.

## 2. Reference arrangement for this profile

The initial profile uses a separate **owner-controlled reference store**, a **protected local reference installation**, and **disposable worker execution**. A reference repository is the normal distribution option; a separately administered local artifact store is an acceptable alternative under the same tests. The owner selects its actual location and visibility before installation. No existing client repository is repurposed implicitly.

The reference repository is excluded from every write-capable installation, account credential, service identity, and publication tool reachable by maintenance workers. For a public reference repository, workers may read it without a write credential. A private reference repository requires an independently restricted read channel. A worker-side copy is always a mirror, even when it has the correct filename and digest.

The protected supervisor obtains approved artifacts, verifies them against an independently installed approval anchor, and provides the worker a read-only view. The worker cannot write the supervisor's reference installation, select a replacement verifier, access promotion credentials, or call its privileged actuators directly. Untrusted candidate code and fixtures run on the restricted side of this boundary, not inside the privileged verifier's process merely because the supervisor started them.

A separate human browser session or operating-system account helps only when the worker cannot acquire that session's credentials or capabilities. The declared threat model may trust a host administrator outside worker reach. It may not exclude administrative access, writable shared dependencies, container-control sockets, credential helpers, or impersonation capabilities that the worker actually has.

### 2.1 Role and capability matrix

| Role | Permitted responsibility | Authority that must remain unavailable |
|---|---|---|
| Reference owner | Review exact artifacts; approve scope; administer reference storage and root approval; revoke or promote references. | Candidate code must not obtain this role's credentials or session. |
| Specification author | Produce review copies and amendment proposals. | Authorship does not confer adoption, runtime activation, or approval of the author's own evidence. |
| Trusted installer or promotion service | Install an exact approved set and atomically select it under a bounded owner authorization. | No permission to invent approval or widen the approved artifact set. |
| Supervisor and reference verifier | Load pinned reference inputs; execute approved checks; retain observations and scoped assessments. | No authority to rewrite the reference during an attempt or accept candidate-supplied facts without measurement. |
| Actuator and custodian | Perform individually authorized effects; retain their actual receipts and unresolved state. | No authority from worker markers, adjacent checksums, or arbitrary candidate scripts. |
| Maintenance worker | Read approved requirements; modify only the authorized candidate and scratch; propose amendments. | No reference-store writes, root approval, checker promotion, trusted evidence rewriting, or unmediated protected effects. |

Trusted roles may share a protected implementation when the required separation from the worker is demonstrable. They do not require separate services for every record type. A component's convenience in the existing implementation is not evidence that it belongs inside the trusted boundary.

### 2.2 Minimal scope before broader operation

The first operating profile should permit reference reads, bounded candidate work, controlled checks, and local draft reports. Apply, merge, issue resolution, public publication, and external effects remain disabled unless individually included in the approved scope and demonstrated at their actual action boundaries. Correct local behavior does not silently enable the other operations. An existing separately authorized maintenance process is not retroactively certified by this profile.

## 3. GitHub configuration and its limits

### AR-01: Separate the credential sets

The reference repository must not be granted to a write-capable GitHub App installation that the worker can use. Repository selection grants an app access; selecting another repository does not create an independent per-interface trust boundary [G1, G2]. Where an installation-token broker is used, explicitly restrict its repositories and permissions and keep the app key or other token-minting authority out of worker reach. A restricted child token is insufficient if the worker can obtain the unrestricted parent authority [G3].

The access inventory must include personal access tokens, SSH keys and agents, GitHub CLI sessions, credential helpers, application tools, CI tokens, deployment keys, organization/team access, and owner browser sessions reachable from the worker. The inventory records identities, scopes, expiry and storage boundaries, never token values. Revoking one path does not establish that another path is absent. A displayed account role such as administrator is not the same as an integration token's actual capability [G4].

Do not create the authority repository through a worker-accessible app and assume it is excluded afterward: GitHub documents automatic app access to repositories the app creates [G1]. Creation, exclusions and effective read/write checks must be done under owner control. Workers can submit proposals in the development repository or a nonauthoritative area; proposal access must not require authority-store write access.

### AR-02: Protect reference history without relying on review labels

Only owner-controlled principals may publish to the reference repository. Preserve non-fast-forward and deletion protection for its governing branches and references. Record the effective rules, their target patterns, applicable inherited policies and bypass identities. No worker-reachable identity may administer or bypass those controls. GitHub rules can restrict updates, creation and deletion by reference; their availability and bypass behavior must be verified for the selected account and repository [G5].

A mutable branch name, tag, release title, issue comment or CODEOWNERS entry is not an adoption anchor. Pin content independently. Required reviews may add scrutiny, but do not prescribe a review count that the available independent humans cannot satisfy, then invent a bypass. An owner-reviewed publication procedure with no worker write access is acceptable. It does not claim multi-person review where only one person reviewed.

A platform's verified commit badge authenticates its defined signing event, not a human's independent approval of these requirements. Names and account attribution are insufficient where automation can act on behalf of the same account. Adoption must originate through the protected owner channel defined in Section 5, not merely an issue comment bearing the owner's username.

### AR-03: Keep reference publication and candidate CI apart

For the initial reference-store profile, disable execution of repository workflows and do not register candidate runners or store action credentials there. Add execution only through a separately reviewed promotion of this profile. This is a choice of the profile, not a claim that all GitHub workflows are unsafe.

In the development repository, preserve existing protection while treating candidate workflows, artifacts and caches as untrusted inputs. Do not execute them in an owner-credentialed publication job. GitHub documents the risk of running untrusted pull-request code in privileged triggers and of trusting artifacts from untrusted runs [G6, G7]. Bind reference checks to the approved checker, workflow source and actual execution, not just the general producing app ID or a familiar check name. Any later CI integration must test these boundaries before it can issue authoritative evidence.

### AR-04: Do not substitute repository protection for runtime enforcement

Branch checks constrain the mutations they actually govern [G5, G8]. They do not prevent a local worker from changing an unprotected expectation, forging a local receipt, leaking a credential, or closing an issue through an independently authorized API. Each enabled action needs its own protected actuator and current permission. A successful build of this documentation is not a test of that mediation.

## 4. Exact artifact selection and protected loading

### AR-05: Identify the complete reference set

[authority-reference.json](authority-reference.json) inventories exact bytes of the six authored contract/data artifacts and this deployment specification. It includes SHA-256, byte count, file mode, role, and Git blob identity for transfer checking. The six source artifacts are pinned to their published source commit. This inventory contains no self-digest, signature, operational adoption record, secret, executable installer, or claimed test result.

The inventory's own exact SHA-256 must be retained or authenticated outside worker control. An adjacent digest alone is not that anchor. The deployment additionally identifies its actual reference-policy artifact, checker and observer implementations, required dependencies, action brokers, relevant configuration, and custody/epoch policy. Those implementation artifacts are not supplied or approved by a document inventory. The owner's adopted-artifact list includes each actual artifact needed by the declared scope; example data remains nonoperational regardless of its byte identity.

A referenced artifact must be available through an approved resolver with limits and an assigned interpretation. Neither a digest of missing content nor an unchecked URL can substitute for its actual definition. Hashes identify bytes, not permissions, authenticity of events, or conformance.

### AR-06: Install from data without executing candidates

The trusted installer obtains exact approved bytes into a private staging directory, using a read-only credential or approved unauthenticated public read. It does not execute repository hooks, filters, build scripts, package installation instructions, embedded links or workflow artifacts while collecting the reference. Archive extraction, when used, rejects unexpected members, traversal, duplicate paths, links, device files and unapproved modes before publication. The required manifest paths are relative and uniquely identify regular files.

The installer verifies every file against the independent anchor and the artifact's permitted interpretation. It refuses missing, extra active or mismatched authority inputs. Diagnostic files outside the active reference are allowed only when they cannot influence authority and are explicitly excluded from loading. Line-ending conversion, substitutions and reserialization change exact-byte identity and require a new verified artifact, not quiet normalization.

The destination and all parent paths, mount configuration and selectors must be controlled outside worker reach. File mode 0444 alone is insufficient where the worker owns the file, its parent or the account that can replace it. Installation is atomic with respect to the active selector. Consumers see a complete approved old or new set, never a mixture. The installer retains the result before declaring reference installation complete.

### AR-07: Protect the loader and actual execution

The root anchor, resolver, configuration, interpreter/module paths, executable dependencies and reference selector are protected just like the contract. Candidate environment variables, current directories, relative imports, tool wrappers, writable caches or dynamic dependencies must not replace them. The controlled execution input must be coherent and remain the approved input for the run; an ending checkout hash cannot identify what ran.

A separate process is not automatically confined. The implementation must demonstrate the actual filesystem, process, service and credential restrictions under the worker identity. It must prevent candidate code from modifying the trusted process or reading its keys through available host capabilities. Candidate test results enter through validated measurement channels. Signing a candidate's string does not make the alleged observation true.

### AR-08: Keep freshness independent of downloadable content

The protected owner policy defines validity windows, revocation epochs, trusted time and offline-cache behavior. A still-valid pinned local reference may be used during a distribution outage when that policy permits it. Unavailable required current authority information blocks the dependent action; it does not authorize switching to an old signed baseline, the current development branch or an editable local file.

Record the current accepted epoch or checkpoint independently enough to detect the rollback or deletion the deployment claims detectable. A fresh empty database cannot declare itself a clean continuation. Clock uncertainty, expired leases and restart into a different clock epoch must not renew authorization. A remote owner with no live connection cannot guarantee instantaneous revocation on an offline host; the approved offline lifetime and resulting exposure must be explicit.

## 5. Approval, installation and activation

### AR-09: Bootstrap outside the system being approved

The initial trust anchor must be installed by the owner through a channel the worker cannot write, administer or impersonate. The installer cannot derive trust solely from a manifest it has just downloaded. An owner's authenticated local administration under a separate effective principal or an owner-controlled signing channel can supply the root. The deployment records which mechanism is used and tests it. Do not generate a key inside the worker environment and then call it independent.

A requirements-review decision can occur before a verifier exists. It records that particular requirements are the intended target; it does not activate a nonexistent or untested verifier. Installation work and isolated testing receive separate bounded authorization. This avoids requiring an already-operational acceptance engine to bootstrap its own existence without abandoning owner control.

### AR-10: Use the existing adoption record with real evidence

When operational adoption is justified, use the `adoption` record from Data Draft 1. Do not invent a competing approval schema or turn a pending checklist into that record. The required mappings are:

| Data field | Required real-world binding |
|---|---|
| Envelope realm and issuer | Protected deployment realm and actual owner-channel identity, not a worker-selected name. |
| `contract_sha256` | Exact approved CONTRACT.md bytes from the reference inventory. |
| `owner_id` | Authorized principal established by the independently installed trust anchor. |
| `adopted_artifacts` | Exact selected contract, matrix, data profile, schema, deployment profile, reference policy and necessary implementation artifacts. Roles are explicit; examples cannot become operational evidence. |
| `scope` | Approved repositories/resources, allowed writes, operating mode, prohibitions and bounded profile. Nothing is enabled merely by omission. |
| `reference_policy` | Protected policy identifying verifier/observer/actuator versions, trust anchors, relevant environment, freshness, revocation, bootstrap and promotion rules. |
| `effective_epoch` and `validity` | Owner-approved epoch and real valid lifetime under SD-05; no fabricated dates or restarting lease. |
| `authorization_evidence` | Retained independent owner decision covering the exact content and scope, authenticated by the protected channel. |

The approval evidence cannot authenticate itself. One acceptable non-circular arrangement is an independently authenticated owner decision naming the reference-inventory digest, policy/checker digests, realm, scope and epoch, followed by an adoption record referring to that already retained decision. A signature over a defined decision body excludes its own signature field and is verified against the preinstalled owner key. A protected local administration journal may instead establish origin. The actual mechanism and exact covered bytes must be specified and tested before use.

### AR-11: Require separate readiness facts

Track these as distinct facts: requirements reviewed; reference bytes retained; permissions installed; loader/checker installed; applicable boundary probes demonstrated; operational adoption authenticated; approved scope activated. A review or installation success cannot fill the other fields. [AUTHORITY-READINESS.md](AUTHORITY-READINESS.md) is an operator-facing readiness record, not a source of runtime authority.

Activation requires all necessary facts for the particular enabled scope and an exact consistent reference set. Every applicable prerequisite needs independently verifiable evidence; unknowns remain blockers. Authoring this specification, passing data examples or merging a documentation PR never activates it. The production verifier's runtime cases remain required under the acceptance matrix. A reference-only installation may be completed and reported separately while runtime acceptance is still disabled.

## 6. Operating, stopping and changing the reference

### AR-12: Make current action authority unavoidable

Before a protected operation, its actual actuator verifies the current scope, subject, baseline, applicable acceptance record, active epoch, holds, lifetime, budget and replay identity. Starting an attempt or performing a bounded safe stop uses its own authorization, not an accepted result for unfinished work. Authority approval is not a wildcard to execute every method in an available tool integration.

Admission and effect must have a defined atomicity or reconciliation boundary. A revocation established before admission prevents the operation. An operation already admitted may be in flight; later revocation stops new admissions and triggers safe reconciliation, not a claim that the prior effect was undone. Record the admission point and its policy version. Do not promise revocation of an irreversible effect after it occurred.

### AR-13: Persist unresolved authority and custody failures

A missing reference, failed integrity check, unverifiable producer, unsupported confinement or lost required checkpoint creates an unresolved condition with its affected scope. That condition survives restart, retry, cache selection and compaction. Shared-authority failure blocks all actions relying on it; independent work may proceed only under an independently intact policy. New IDs, issue-state changes and record deletion cannot clear it.

A retained authorized resolution must name the condition and establish its satisfaction or an approved requirement change. Replacement policy cannot retroactively make old failing behavior conformant. Known successful effects with missing retained receipts remain known effects plus custody failure; reconcile through actual destination state without blindly executing again.

### AR-14: Promote amendments without self-approval

Workers submit candidate requirements/checker changes as proposals. The owner compares exact prior/proposed bytes, affected ICV/ICM definitions, compatibility, scope and necessary new negative tests. The currently approved control boundary or an independently established replacement-review procedure evaluates them. The candidate cannot promote its checker, expectations or trust anchors in the same uncontrolled operation that it asks them to judge.

Stage the complete new set, verify it, record an authenticated promotion with its new epoch, and switch the protected selector atomically. Preserve the old identity and failures. During interruption, consumers use only an explicitly still-valid complete prior set or block. Rollback needs current owner approval and consideration of known defects; an earlier signature alone is insufficient. Reinstallation and root-key rotation must address existing leases, unresolved conditions and replayable old approvals.

### AR-15: Recovery must not depend on a forged success

A separately protected owner stop/recovery channel remains available when ordinary custody or acceptance fails. It permits only the specified stop, diagnosis, reference restoration or evidence collection. It does not resume backlog work, authorize arbitrary deletion, reset unknown history, or erase failures. If restoration cannot be independently authenticated, leave dependent operations stopped and request owner intervention through the existing bounded channel.

## 7. Installation and conformance procedure

Each stage has a concrete output. A blocked stage is recorded without pretending that later installation happened. The owner can approve narrower scope; missing infrastructure does not become a passing test or proof that an enabled route is excluded.

| Stage | Action | Required output before proceeding |
|---|---|---|
| P1 | Review exact reference inventory and deployment profile. | Retained requirements-review decision, separately identified from runtime adoption. |
| P2 | Select reference storage, owner principal, worker principal and trusted host. Inspect all credential paths. | Location, visibility, effective identity/capability inventory and owner-authorized installation scope. |
| P3 | Exclude worker writes/admin access; configure reference-history protection. | Sanitized setting readback plus actual read/denial probes. |
| P4 | Install protected anchor, resolver and exact reference bytes without candidate execution. | Verified file inventory, installed selector identity and permission observations. |
| P5 | Install the approved supervisor/checker, custody and individually enabled actuator paths. | Pinned implementation/configuration inventory and actual scope map. |
| P6 | Execute the relevant probe pairs below and mapped ICM cases under real identities. | Retained observed results, admitted effects and honest remaining limitations. |
| P7 | Authenticate adoption and activate only the demonstrated scope. | Adoption record, active epoch, current readiness record and successful bounded positive control. |

### Probe protocol

The following AP identifiers are deployment probes mapped to existing ICM cases, not a new umbrella test system. Each applicable variant must name actual identities, target resources, versions, command/request, expected and observed state, evidence origin and time, positive control, effect/custody observations and limits. Retain the first failure. A permission error caused by a bad URL, nonexistent target or malformed command does not establish denial on a valid protected target. Verify target existence and permitted reads independently first.

Negative writes target owner-authorized disposable sentinels or test references governed by the same actual rules, not the adopted reference or live client data. If no faithful safe probe target exists, use the available configuration evidence but mark the active denial property untested. Creating a Git blob can safely demonstrate broad contents-write capability, but does not by itself test protected-ref updates. Equivalent production coverage must be justified, not assumed from an unrelated test repository.

#### AP-01: Reference identity and owner origin

Try modified reference bytes with the old independent digest; a rewritten manifest and adjacent digest; an owner-shaped approval from the worker; a mixed revision; and a valid pinned reference. Invalid substitutions do not alter adoption or authorize an operation. The valid read succeeds. Observe the actual root anchor, loaded file identities and attempted downstream effects. Maps to ICM-009 and ICM-017 through ICM-019.

#### AP-02: Real GitHub worker capability

Under every reachable worker GitHub identity, attempt controlled reference creation/update/deletion, tag movement, Contents/Git API writes and a merge into the protected publication target. Repeat relevant Git, API and connected-tool paths. Worker reads remain possible; ungranted writes must be denied before effects. Owner publication under the actual separate identity must succeed in the controlled target. Observe actual reference/content readback and effective bypass identities. A 403 or 404 alone is not the whole proof. Maps to ICM-007 through ICM-009 and ICM-033.

#### AP-03: Ambient credentials and host authority

Attempt protected local reference and selector writes through direct file access, replaceable parents, links, writable shared dependencies and alternate tools. Test reachable privilege escalation, process-inspection and credential-agent paths within the owner's probe authorization. No real secrets are printed; use designated test credentials/sentinels where necessary. Reference reads and authorized candidate writes must work. Any demonstrated worker access to controlling credentials or reference administration fails the boundary. Maps to ICM-007, ICM-010, ICM-015 and ICM-023/024.

#### AP-04: Actual loader and checker selection

Substitute a candidate-local verifier, configuration override, interpreter/module path or cache artifact; alter the public mirror after a run starts; try changing the trusted execution inputs. The reference remains the approved pinned version or the affected operation blocks. Genuine positive checks still run against the actual candidate. Record loaded dependency identities and protected observations, not only a proposed command line. Maps to ICM-010, ICM-013/014 and ICM-018.

#### AP-05: Candidate CI cannot impersonate authority

Offer a passing candidate-controlled workflow, forged artifact, signed collection of worker text and result from the right app but wrong approved checker/revision. None supplies missing authoritative observations or promotion. A genuine approved result is accepted only within its measurement scope. Exercise the real importer/consumer and, where enabled, actual producer-bound server gate. Mocking GitHub does not prove GitHub enforcement. Maps to ICM-017/018, ICM-022 and ICM-038.

#### AP-06: No alternate action route

Run false success and valid authorized controls through each actual supported route: ordinary, direct issue, fast path, cache, fallback, recovery, restart and cleanup. Check both call counters and destination state for apply, merge, issue closure, publication and subsequent launch. Invalid work cannot confer its own authority. Excluded routes must actually be unreachable. Maps to ICM-002, ICM-008 and ICM-032/034.

#### AP-07: Owner adoption is neither a checklist nor a signature label

Supply absent approval, an example-realm record, wrong scope, future/expired validity, unknown epoch and valid independently authenticated adoption. Only the complete valid chain permits the independently enabled scope. Required human judgment remains distinct from failed or unperformed machine verification. Record the independent owner channel and approved bytes, not a passed schema alone. Maps to ICM-009, ICM-030/031 and ICM-050.

#### AP-08: Revocation and concurrent admission

Pause before the actual action-admission boundary, revoke permission, then release. The effect is refused. Race two consumers of one effect authorization: no duplicate effect is admitted. Separately revoke after a single admission; retain and reconcile any in-flight result without authorizing a second one. Test fresh-process recovery and expired leases. Observe the actual reservation or equivalent destination boundary. Maps to ICM-029, ICM-033, ICM-035/036 and ICM-049.

#### AP-09: Interruption during install and promotion

Interrupt after staging, verification, activation-record publication, selector switch and before acknowledgement. A fresh process selects only a complete currently authorized set or blocks. An in-flight request remains bound to its allowed prior revision or is revoked. Candidate-proposed promotion never authenticates itself; a valid owner promotion succeeds. Observe actual installed bytes, selector, epoch and records after each cut. Maps to ICM-011 and ICM-025.

#### AP-10: Offline cache, rollback and missing custody

Deny distribution access with a still-authorized protected cache, then separately expire/revoke its permission or lose required current-epoch knowledge. Only the policy-permitted valid cache works. Roll back or delete required custody while retaining the independent checkpoint; restart must not initialize clean history. Restore through an authorized path without erasing unresolved conditions. Maps to ICM-009, ICM-016, ICM-026 through ICM-028 and ICM-039.

#### AP-11: Failed boundary and legitimate resolution

Persist two unresolved conditions, exit and restart, then provide valid resolution evidence for one. Only that condition is resolved; the other still blocks its dependent effect. Repeat with a worker explanation, another subject's evidence, timer expiry and owner-approved requirement withdrawal. Withdrawal is not old-version satisfaction. A valid restoration can resume only its separately authorized scope. Maps to ICM-026/027, ICM-029 and ICM-041.

#### AP-12: Known effect and uncertain effect remain different

Observe a controlled destination commit and fail receipt retention; separately lose all confirmation of whether a commit happened. The first preserves known effect plus custody failure. The second remains outcome-unknown. Both block dependent continuation until the appropriate reconciliation, without blind duplicate writes. Restore authoritative readback and verify the one actual effect. Maps to ICM-035/036 and ICM-049.

#### AP-13: Positive bounded operation and honest reporting

Under the installed scope, execute a legitimate F-C repair, a safe no-change case, an authorized failed-result report, and a bounded stop. Correct supported work succeeds without unnecessary per-edit owner approval; ungranted apply/merge/deploy remain denied. A system that refuses every positive case fails functional conformance. Reports distinguish real probes, mocked boundaries, exclusions, unavailable tests and data-only checks. Maps to ICM-001, ICM-005, ICM-034, ICM-039 and ICM-051/052.

## 8. Completion criteria and tracking

The Git-side authoring deliverable is a reviewable deployment specification, exact transferable artifact inventory, and truthful setup record. It is complete as documentation when internally consistent with the contract/data/matrix and published without altering their requirements. This does not complete deployment.

Reference protection is installed only after actual identities, controls and applicable negative/positive probes establish the stored reference and loader boundary. Operational adoption additionally requires the real verifier, enabled actuators, custody, runtime evidence and authenticated owner decision. The public tracking issue records those stages independently and remains open until its actual acceptance conditions are met. No field in the authoring package can mark its own prerequisite satisfied.

Implementation ownership remains with the existing acceptance, execution-identity, worker-authority, custody and merge-health work. Missing controls become specific unresolved items under those owners rather than a duplicate runtime framework. A public version of the deployment's record contains safe evidence references, not private keys, host paths, customer data or raw credential inventories.

## References

The AR rules are this profile's engineering requirements. The following primary sources describe GitHub mechanisms and their limits; they do not certify this deployment.

[G1] GitHub Docs, Installing a GitHub App from a third party. Repository selection and automatic app access to app-created repositories.
https://docs.github.com/en/apps/using-github-apps/installing-a-github-app-from-a-third-party

[G2] GitHub Docs, Reviewing and modifying installed GitHub Apps. Reviewing permissions, selected-repository access and blocking access.
https://docs.github.com/en/apps/using-github-apps/reviewing-and-modifying-installed-github-apps

[G3] GitHub Docs, Authenticating as a GitHub App installation. Explicit repository/permission narrowing and token lifetime.
https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation

[G4] GitHub Docs, REST API endpoints for GitHub App installations. User repository permissions versus installation access.
https://docs.github.com/en/rest/apps/installations

[G5] GitHub Docs, Available rules for rulesets. Reference restrictions, bypass identities, required checks and supported plans.
https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets

[G6] GitHub Docs, Securely using pull_request_target. Separation of trusted workflows from untrusted candidate code and artifacts.
https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target

[G7] GitHub Docs, Secure use reference. Workflow, credential and runner isolation guidance.
https://docs.github.com/en/actions/reference/security/secure-use

[G8] GitHub Docs, About protected branches. Branch enforcement and its actual required-check scope.
https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches
