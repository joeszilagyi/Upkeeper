# Owner authority, publication and activation

Version: **1.0.0-rc.1**. This is the deployment specification for the authority boundary, not a claim the boundary has been installed.

## Current publication is not protection

This bundle was authored in the owner's ChatGPT conversation, not by the Codex worker implementing Upkeeper. That gives it separate authorship and preserves the discussion's requirements. It does not make an AI-authored document infallible or make two interfaces different security principals.

The GitHub connection in this conversation has demonstrated repository writes. The Codex workspace has also had substantial GitHub authority. No separately protected specification repository or read-only Codex identity has been selected and verified in this task. Therefore the Upkeeper draft branch is a **review/distribution mirror**, and the bundle's adoption status remains **UNADOPTED**.

A file named CONTRACT.md, a repository flag, a checksum committed next to the file, a comment telling Codex not to edit it, or a second repository reachable with the same write token is not the required boundary. Code-review independence, authorship independence and permission independence are different claims. Only the first two are partly addressed by writing and reviewing material separately; actual permission enforcement still needs installation and tests.

## Required authority arrangement

The authoritative package and approval anchor must be held by an owner-controlled principal that maintenance workers cannot impersonate, write as, or administer. Suitable deployments may use a separate repository with genuinely different credentials and protected release authority, an owner-controlled read-only artifact store, or a local authority service under a distinct operating-system account with enforced read-only worker access. The choice does not require secrecy of the requirements; workers should be able to read them.

The authority owner controls the adopted manifest digest, approved scope/profile, reference validator and observer versions, trust anchors, revocation state and promotion mechanism. The worker controls only proposed implementation and explicitly permitted scratch. The acceptance supervisor obtains the approved package from a fixed, protected location and refuses unapproved substitutions. The actuator obtains decisions from the approved authority, not whatever checkout-local code asks to act.

The same restriction applies to credentials, workflow definitions, environment/config overrides, plugin connections, executable paths and the file or variable selecting the authority location. A worker able to replace the authority's loader has authority over the reference even if the reference file is read-only. A GitHub App's selected repository access can be reviewed independently [A1]; selection alone does not create different write capabilities for two clients using the same credential.

## Permission matrix required at activation

| Resource/action | Authority owner | Acceptance/observer services | Maintenance worker |
|---|---|---|---|
| Read contract and public cases | Allowed | Allowed | Allowed |
| Propose amendment in nonauthoritative area | Allowed | Policy-limited | Allowed if delegated |
| Change adopted baseline, trust anchors or revocation | Allowed through reviewed promotion | Read/verify only, unless separately delegated | Denied |
| Modify reference checker/expected outputs for active attempt | Promotion only | Denied during execution | Denied |
| Write candidate code | By separate work policy | Apply only via grant where applicable | In scoped candidate area only |
| Create authoritative observation | Not by unverified assertion | Only approved measurement scope | Denied; claims may be collected |
| Issue action grant | Through approved authority | Acceptance role only | Denied |
| Merge, resolve issue, write external service | Explicitly authorized route | Actuator with matching grant only | Direct access denied |
| Change rules protecting the above | Owner administration only | Denied | Denied |

Roles may share machinery only when their required separation from the worker remains enforced. An owner manually approving everything is not required for routine tasks: reviewed profiles may delegate bounded repeated actions without delegating authority to redefine the profile.

## Artifact identity and approval

`MANIFEST.json` lists exact SHA-256 digests and byte counts. Its own SHA-256 is supplied separately in the delivery receipt. This detects changed bytes when compared with an independently retained digest. It does not prove who approved them, authenticate a future replacement manifest, or prevent deletion. The owner should retain the delivered package and its digest outside the maintenance environment.

Adoption is an independently authenticated owner action referring to the exact manifest digest, contract version, intended supported scope, approved reference checker identity, trust policy, effective time, expiration/review policy and revocation epoch. `adoption-template.json` is deliberately pending and cannot serve as approval. `examples.json` contains toy digests and no authentic proofs. No generated key or example record in this package confers authority.

A public Git commit identifies a review copy's content and history, but a branch name is mutable. The independently held adoption must pin content and approved enforcement artifacts. The owner, not the worker, decides whether a future revision replaces them. Availability of an old artifact is not automatic permission to roll back to it.

## Activation sequence and required evidence

1. Review this authored normative package. Decide unresolved deployment choices and the initial scope; do not silently convert these choices into model-selected defaults.
2. Select the authority location and distinct principals. Restrict the worker's effective permissions, including any credentials already available through its host, tools or CI. Do not weaken existing main protections to accomplish separation.
3. Install or identify the trusted reference checker, adapters, issuer and actuators. Bind their versions and actual capabilities. This package supplies their contract and test cases, **not their complete implementation**.
4. Verify negative operations under the actual worker identity: attempts to change contract and adjacent digest; alter loader or expected results; impersonate observer/issuer; edit reference workflows or rules; read private signing credentials; bypass actuator; promote a candidate checker. Each must be denied or prevent operational activation. Mock arguments alone do not establish this.
5. Verify legitimate operations too: worker reads requirements, creates a scoped candidate, trusted checks evaluate it, a matched grant reaches the actuator, and readback produces a truthful receipt. Prove safe rejection of missing evidence, stale identity, revocation and unknown external outcome.
6. Record owner adoption outside worker reach. Atomically activate one consistent bundle/reference set. Authorize only the tested operating scope and keep unimplemented modes disabled or explicitly nonconforming.

No actual authority location, approver credential, production checker, platform confinement or permission denial is certified by this document. If installation cannot enforce a required boundary, remain unadopted for operational use or explicitly restrict work to diagnostic/review mode under separate authorization.

## Changing the requirements without moving the goalposts

A worker can propose an amendment with rationale, affected requirement IDs, compatibility impact, new negative cases and supporting observations. The proposal does not modify the active reference. The owner reviews it outside the candidate's authority, obtains appropriate independent evidence and adopts a new exact bundle when warranted. A deliberate new requirement may make a new candidate acceptable; it cannot transform a previous failed claim into proof that the old requirement was met.

For checker self-maintenance, use the existing approved checker/control boundary and an independently approved migration test set to judge the proposed checker. If the current checker is known defective, the owner establishes a restricted replacement-review procedure; the worker does not pick its own replacement judge. In-flight operations remain version-bound and are either completed under valid old authorization or explicitly revoked. Mixed versions and interrupted activation fail closed.

## Relationship to the active repository

The new contract should be tracked as an owner-adoption/reference-protection deliverable linked to #910, #912, #715 and #915. It should not duplicate their runtime implementation or become a blanket excuse to restart the full backlog. A future implementation proposal must map its changes to the requirements and cases here and name any unimplemented portions; it must not rewrite these requirements to describe existing behavior.

Publication of the draft or completion of specification authorship does not authorize a merge, a production run, continuation of a paused GOAL, the #715 CI workaround, a client pilot or the optional community-contribution feature. Those remain separately scoped decisions.

[A1] GitHub Docs, Reviewing and modifying installed GitHub Apps: https://docs.github.com/en/apps/using-github-apps/reviewing-and-modifying-installed-github-apps
