# Authority installation readiness

**Record date:** 2026-10-15.

**Status:** Git-side deployment artifacts prepared. Protected-reference installation and operational adoption are **not established**.

This is an informational setup and evidence record for [AUTHORITY-DEPLOYMENT.md](AUTHORITY-DEPLOYMENT.md). It is not an adoption record, active configuration, passing conformance report or instruction to resume maintenance. The dated observations below are not permanent claims about future repository state.

## 1. Reference candidate

The six contract/data artifacts are pinned at development commit `cf55c4513c476d304656bcb93d2f74acc1529a6d` in `joeszilagyi/Upkeeper`, under `docs/contracts/independent-claim-acceptance/`. Contract Draft 3, Matrix Draft 1 and Data Draft 1 are retained unchanged.

[authority-reference.json](authority-reference.json) records those six files and Authority Deployment Draft 1 by exact bytes. It deliberately excludes itself and this informational readiness record. The proposed deployment specification is identified by its file digest and Git blob; the six previously published source files additionally name their source commit. There is no self-referential hash and no invented future commit identity.

The exact inventory SHA-256 for this publication is:

```text
1a0a1db8cc2b7616c1b20de8b9252508016bf451bc9c13a58f159c9637097679
```

The owner must retain or authenticate the chosen digest outside worker write authority. Copying this number into another worker-writable file is not installation of a protected anchor. Retaining this reference inventory does not approve an implementation that has not been selected and tested.

## 2. Observed repository and connection state

| Observation | Supported finding | What it does not establish |
|---|---|---|
| PR #924 metadata | Draft, open and unmerged at `cf55c4513c476d304656bcb93d2f74acc1529a6d` before the authority-document update. | Owner adoption or operational enforcement. |
| Main branch read | Main is `7886b35da837497b350f58694c8eb3a8f3e7da06`; `protected` is true. | Protection of all other refs, issue actions, local files or credentials. |
| Repository ruleset 16041986 | Active for `refs/heads/main`; deletion and non-fast-forward restrictions; PR requirement; strict required checks `Local validation`, `Analyze (actions)` and `Analyze (python)` bound to integration 15368; no listed bypass actors; current read reports bypass `never`. | An independent owner approval gate for contract adoption or a protected checker source. |
| Installation inventory | The inspected connection uses installation 171745016, selected repositories, owner account `joeszilagyi`. No separately designated authority repository is present in that returned selection. | That no authority repository exists elsewhere, or the complete set of credentials available on a worker host. |
| Connector app metadata | App 1144995, `chatgpt-codex-connector`, advertises contents, issues, pull-request and workflow writes; the source-authoring connection can publish to Upkeeper. | That another coding environment has the identical token, or that two interfaces have distinct effective authority. |
| Legacy branch-protection API read | `GET /repos/joeszilagyi/Upkeeper/branches/main/protection` returned HTTP 403, `Resource not accessible by integration`. | An empty protection configuration. The accessible ruleset is separate positive evidence. |
| Available operations | Repository content/PR/issue writes are available. Ruleset/branch-protection access through the available fetch action is GET-only; no administrative mutator was found in the available action discovery or targeted integration search. | Authority to create credentials, install host separation or change app/repository administration. |

No live worker-identity denial probe, protected-reference installation, key creation, app-repository selection change, repository administration change, checker activation or owner adoption was performed for this publication. Repository contents and tracking updates are not reported as those operations.

Source anchors for the dated observations:

- https://github.com/joeszilagyi/Upkeeper/pull/924
- https://api.github.com/repos/joeszilagyi/Upkeeper/branches/main
- https://api.github.com/repos/joeszilagyi/Upkeeper/rulesets/16041986
- https://api.github.com/repos/joeszilagyi/Upkeeper/issues/925

The installation inventory was returned by the authorized GitHub connection. Its account settings may be inspected by the owner at https://github.com/settings/installations/171745016. No token, private repository content or private host inventory is included here.

## 3. Decisions that must come from the owner

The deployment profile specifies the required properties; these instance-specific values remain unset. They are not delegated to the maintenance worker to choose and then approve.

| Required choice | Current value | Acceptance evidence |
|---|---|---|
| Reference location and visibility | Not selected | Owner-created/selected store with stable identity and a documented worker read path. |
| Independent owner administration/approval channel | Not selected | Actual principal and protected trust-anchor installation; worker impersonation denied. |
| Worker principal and available capabilities | Not verified | Effective GitHub/host credential and permission inventory, with scoped negative and positive probes. |
| Trusted host, loader and isolation boundary | Not installed by this work | Actual object/process/service controls protecting references, executable dependencies and keys. |
| Reference-policy, checker and observer versions | Not selected or approved here | Exact implementation/configuration artifacts and applicable real-boundary test evidence. |
| Enabled operating scope | No new operations enabled | Explicit repository/resource/mode/action allowlist, budgets, validity and revocation rules. |
| Operational adoption | Not recorded | Independently authenticated Data Draft 1 adoption with real supporting owner evidence. |

The recommended initial arrangement is an owner-controlled reference repository outside all worker write-capable app selections, with public anonymous or separately restricted private reads, and a protected local loader under a genuinely separate authority boundary. The owner chooses the repository name and visibility. Do not create it through the shared write app merely to fill in this table; app-created repositories may be automatically accessible to that app [G1 in AUTHORITY-DEPLOYMENT.md].

The current six authored requirements/data artifacts can be reviewed before any runtime checker exists. A review decision is recorded as a review, not operational adoption. Installation can then be commissioned against that exact baseline without making the implementation worker the author or approver of its requirements.

## 4. Installation gates and work ownership

| Gate | Primary tracking owner | Current evidence state | Completion requires |
|---|---|---|---|
| Exact reference package and deployment specification | #925 with draft #924 | Written for review; seven referenced artifacts identified | Owner review of exact bytes and any explicit amendments. |
| Separate reference storage and owner channel | #925 | Not selected or established | Stages P2-P4; AP-01 through AP-04 under actual identities. |
| Effective worker/supervisor/checker separation | #912; mutation evidence in #679 | Not demonstrated by this publication | Real protection of credentials, loader, expectations and executable dependencies; no alternate authority route. |
| Pinned execution and applicable evidence | #715 | Separate implementation work; not certified here | Actual exact-input producer/consumer behavior in the approved environment. |
| Common acceptance and action mediation | #910; action-specific owners #805/#913/#136 | Not implemented by these documents | Real positive/negative entrypoint and actuator demonstrations, including AP-05 through AP-08 and AP-13. |
| Integrated-main gate and bounded continuation | #908 and #913 | Main ruleset readback exists; authority separation remains a separate requirement | Actual approved identities, required work execution, current subject and relevant continuation gate. |
| Protected custody, unresolved conditions and recovery | #912/#913 with existing evidence work | Specified, not probed here | AP-09 through AP-12; independently anchored state and honest effect reconciliation. |
| Operational adoption and activation | #925, coordinated in #915 | Not authorized or performed here | Real applicable gate evidence, exact policy/checker set, authenticated owner adoption and bounded positive control. |

This table assigns responsibilities without starting their implementation or duplicating their trackers. A closed issue or a merged PR does not automatically fill an evidence gate. Conversely, documenting these gates does not reopen already demonstrated narrow repairs. Existing issue bodies and exact implementation evidence remain authoritative for their own scope.

## 5. Safe owner-side setup sequence

First select the store and independent owner/worker channels, retaining the reviewed inventory outside worker reach. Inspect all existing paths of authority before revoking or replacing any credential. Preserve working repository protections, owner changes and the evidence of previous attempts.

Next commission installation under an explicit bounded owner authorization. Apply the selected repository exclusions and host isolation using the owner's administrative access, not credentials made available to the worker. Record before/after settings and execute controlled paired denial/read tests. A copied file, a local chmod, a different repository name or an unsigned checklist is not the proof requested.

Then identify and test the reference loader, actual checkers, custody and each enabled actuator under the deployment specification. Keep unsupported actions unavailable. Authenticate operational adoption only after the required real controls exist. Document the exact state of every unmet gate rather than selecting a convenient accepting status.

No live permission-changing commands are embedded in this record because the target store, principals, host and approval method remain unset. The deployment specification supplies the required configuration properties, record mapping, transition rules and proof procedure. It does not ask the worker to design replacement requirements or supply a pretend owner approval.

## 6. Verification class for this publication

The authoring checks verify source-byte preservation, reference-inventory digests, document links, AR/AP inventories, ICV/ICM mappings, rejection of the inventory as an operational adoption record, and Git whitespace. Those are package and specification checks, not executions of AP or ICM runtime scenarios. Their actual output is retained in the delivery checking material and summarized in PR #924; no result is fabricated here.

The available local Git transport could not resolve github.com during this work. Repository-wide local validators therefore were not run. Hosted CI remains a separate exact-revision result. Successful documentation CI cannot fill any pending authority-installation gate in this record.

Issue #925 remains open. Completion of the Git-side documentation is explicitly different from completion of item 3's installed protection. The adopted reference, protected loader and real permission denials remain necessary before that stronger claim can be made.
