# Validation evidence

Status: experimental. Reusable evidence reports execution of a particular
trusted validation request. It does not prove arbitrary issue completion,
independent checker correctness, or unattended worker confinement.

## Execute a pinned request

On supported Linux hosts, set `UPKEEPER_TEST_ATTESTATION_FILE` for
`tools/run_tests.sh` or `tools/validate_upkeeper.sh`, or set
`UPKEEPER_VALIDATION_ATTESTATION_FILE` (or `--attestation FILE`) for
`tools/run_validation_phases.sh`. The parent directory must already exist,
belong to the caller, and have no group/other write access. Ancestors must be
trusted, non-symlink directories; root-owned sticky temporary directories are
permitted. Use a dedicated private directory, not a source checkout.

```sh
evidence_root="$(mktemp -d)"
UPKEEPER_VALIDATION_NO_REUSE=1 \
UPKEEPER_TEST_ATTESTATION_FILE="$evidence_root/tests.json" \
  tools/run_tests.sh --jobs 2

# The identical request may reuse the completed result.
UPKEEPER_TEST_ATTESTATION_FILE="$evidence_root/tests.json" \
  tools/run_tests.sh --jobs 2
```

`UPKEEPER_VALIDATION_NO_REUSE=1` forces actual execution. It does not bypass
checks or permit unsupported inputs. Without an evidence destination, the
existing commands remain ordinary fresh diagnostic runs in the working tree.
That mode is useful before commit, but publishes no reusable certification.

The evidence path requires a clean committed candidate, complete Git history,
regular tracked files, Linux sealed memory files, bubblewrap read-only data
mounts, and a dpkg toolchain manifest. Staged, unstaged, and nonignored untracked
inputs are rejected with exit 3, not silently replaced by HEAD. Submodules,
tracked symlinks, and tab/newline names in the top-level test-runner result
inventory are not certifiable. The syntax checker still supports unusual shell
filenames. Ignored state is never imported. No host permission/security setting
is changed to obtain isolation; unavailable isolation is a blocked result.

## What a record binds

The entrypoint resolves HEAD once and loads the producer from that Git object.
The producer reads Git blobs, verifies their identities, and constructs detached
Git context from the reachable objects. Diff references are resolved once; HEAD
expressions refer to that pinned HEAD. Diff phases require an explicit base or
a verified origin/main merge base. No owner Git config, hooks, credentials,
ignored state, or mutable index is copied into the execution environment.

Each source and Git-metadata file is copied to an independent read-only mount.
The source directories are also read-only. Tests write only to separate private
scratch, including runtime/log locations, and must create child fixtures for
intentional source mutation. The original checkout may advance during a run;
the completed result still belongs only to the pinned revision. Hashing the
live tree before and after is not the snapshot mechanism.

`upkeeper.validation-evidence.v2` binds the entire Git input, exact command and
arguments, requested scope and test inventory, resolved diff context, schema
and isolation policy, runner/checker versions through the Git tree, and bounded
execution conditions. The conditions include fixed locale/path policy, explicit
test/phase timeout and concurrency settings, selected validator budgets, system
tool hashes, Python/kernel/machine identity, and the installed-package manifest.
CPU affinity is included because automatic concurrency uses the available CPUs.
The complete allowlist is `ENV_INPUTS` in `tools/validation_evidence.py`; no
ambient environment dump is saved. Other environment variables are not inherited
by the checks. System toolchain administration is assumed quiescent during the
run; a detected change blocks publication, but that end check is not proof
against a hostile administrator changing and reverting system libraries.

The result certifies the completed command, not a claim that every test in the
dependency inventory was executed by every validator mode. Unit and phase
runners retain their per-check results; the whole request must return zero.
Whole-request reuse is intentionally conservative: a full validator does not
skip delegated tests using an earlier unit-run artifact. Its own identical full
request can be reused. Per-bug dirty/index validation always runs freshly and
does not publish reusable evidence.

## Trust and publication

The caller must trust the producer/checker version it invokes. Loading it from
a commit and hashing it does not make candidate-authored validation independent.
This contract assumes a reviewed producer and an exclusively controlled host
validation session/store. Protecting that choice from a maintenance worker is
separate #912 work; task-specific semantic acceptance is separate #910 work.

The supervisor keeps the signing key and store outside the checks' filesystem
and PID namespaces. Check processes have private home/state, blocked Codex and
GitHub transports, and disabled networking. PATH shims alone are not the
confinement mechanism. This is not protection from an administrator or a hostile
host process with the producer's own account and store access.

Each artifact has a private per-file custody key. Existing unrelated files
without that marker are refused. Records are bounded, authenticated, and tied
to their storage location; links, shared inodes, unsafe permissions, duplicate
JSON keys, legacy records, wrong requests, incomplete results, and records older
than 900 seconds cannot authorize reuse. Safe ineligible records cause fresh
execution. Unsafe output locations block rather than overwrite unrelated data.

Publication uses exclusive temporary files, fsync, and atomic directory-relative
replacement. A fresh attempt first preserves prior evidence under a private
previous-record name, so failure/interruption cannot leave it appearing current.
Failed checks or publication cannot generate PASS. Private scratch/failure
evidence is retained at the printed path; it is not a public artifact bundle.
Do not publish keys or scratch wholesale.

Diagnostics distinguish `executed`, `reused`, `reuse-rejected`, `passed`,
`failed`, and `blocked`. A cache rejection is not a test failure; a successful
shell exit from some other command is not reusable evidence.
