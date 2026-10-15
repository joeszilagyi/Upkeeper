# Upkeeper independent acceptance contract package

**Version 1.0.0-rc.1 | Authored 2026-10-15 | Pending owner adoption**

This is the finished requirement package authored in the owner's ChatGPT conversation. It is not a prompt asking the coding worker to invent the requirements. It defines how an untrusted worker's claims become independently supported assessments and, separately, narrowly authorized actions.

## Read in this order

1. `CONTRACT.md`: the normative requirements and two worked examples. There are 50 stable requirements, ICV-001 through ICV-050.
2. `verification-spec.json`: requirement registry, record field contracts, semantic checks, decision precedence, action preconditions, 28 normalized decision vectors and traceability to the 62 acceptance cases.
3. `ADVERSARIAL-MATRIX.md`: concrete positive and forbidden-success scenarios with the independent observations required to judge them.
4. `AUTHORITY.md`: how the adopted reference must be held outside the worker's write and administrative authority, and what activation still requires.

`records.schema.json` and `verification-spec.schema.json` constrain structural data. `examples.json` contains synthetic nonoperational examples. `adoption-template.json` is explicitly pending, not a signed or valid approval. `check_bundle.py` checks package consistency and the finite normalized decision model; it does not run Upkeeper or establish provenance, sandboxing, business correctness or actual conformance.

## The important distinction

The worker can say “done.” A trusted authority must separately determine what was actually established, on which code, through which observations, within what scope. A valid assessment still does not authorize every side effect. Action grants and actual receipts remain separate.

A unit test for every function does not establish every handoff. A signed log may authenticate a statement without proving the statement. An old passing result cannot certify new code. A missing observation cannot become success because the system cannot explain its absence. The contract makes those distinctions operationally explicit.

## Publication and protection

A copy published under `docs/contracts/independent-claim-acceptance/1.0.0-rc.1/` in Upkeeper is a review/distribution mirror. A separate protected authority location has not been installed in this task. Do not describe the mirror as inaccessible to Codex when its credentials can edit the repository.

The owner retains this package and the manifest digest separately, approves the exact baseline and scope, and installs the authority boundary described in AUTHORITY.md before operational adoption. A file hash is an integrity reference, not a substitute for permission separation or owner approval.

No production code, active acceptance policy, existing PR or paused GOAL is changed by these documents. The current Upkeeper issues remain implementation owners; this package is a normative target rather than a declaration that those issues are fixed.

## Local package check

With Python 3 and a Draft 2020-12-capable `jsonschema` package already available:

```sh
python3 check_bundle.py
```

The check rejects duplicate JSON keys, validates schemas and synthetic records, checks requirement/case coverage and decision-vector outcomes, exhaustively checks the finite normalized input model, checks action-precondition inventories, and verifies manifest byte identities. It makes no external calls. Its passing result is **package/model consistency only**. The real adversarial cases remain specified, not executed by this check.

See `PACKAGE-VALIDATION.json` for exactly what was run when this bundle was built. No package self-check result is a production PASS, owner adoption or an action grant.
