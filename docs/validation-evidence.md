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

The launcher-contamination and manifest-selection fixtures import independent
child copies before deliberately adding source-root files. This narrow change
keeps their existing behavioral assertions compatible with read-only validation;
it is not a repository-wide fixture-containment certification.

`upkeeper.validation-evidence.v2` binds the entire Git input, exact command and
arguments, requested scope and test inventory, resolved diff context, schema
and isolation policy, runner/checker versions through the Git tree, and bounded
execution conditions. The conditions include fixed locale/path policy, explicit
test/phase timeout and concurrency settings, selected validator budgets, system
tool hashes, Python/kernel/machine identity, and the installed-package manifest.
Hashes also bind the small mounted system-file set (including timezone and
loader configuration); their contents are not serialized into the record.
CPU affinity is included because automatic concurrency uses the available CPUs.
Visible namespace-policy files, the supervising process's security label and
effective capability/seccomp state are also identified without publishing their
contents. Unavailable diagnostics are recorded as unavailable, not evidence
that a host restriction is absent. These observations do not authenticate an
administrator or establish a complete host security-policy inventory.
The scratch filesystem type is also bound; memory-backed fixture validation
does not establish persistence across power loss on a deployment filesystem.
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
Pinned validators keep their timing output inside that scratch tree rather than
accepting an ambient host output path. CI uploads only those timing rows.

A durable pending-publication marker precedes passing bytes. A known final
directory-flush error quarantines the new record; even if quarantine fails,
the pending marker prevents reuse. A later fresh execution preserves the old
intent and publishes its own result. A complete flushed record whose caller
dies before acknowledgement can be recovered by the real consumer. An intent
left after interruption may conservatively require fresh execution. These are
process-crash and syscall-failure tests, not power-loss durability certification.

Diagnostics distinguish `executed`, `reused`, `reuse-rejected`, `passed`,
`failed`, and `blocked`. A cache rejection is not a test failure; a successful
shell exit from some other command is not reusable evidence.

## Checkpoint 1: execution and CI boundary

The isolated-development requirements are pinned to
[revision 4b3480af](https://github.com/joeszilagyi/Upkeeper/tree/4b3480af7d8dbbf36ddd43e36fa1a135c4fbeb60/docs/contracts/independent-claim-acceptance).
They are not installed operational authority. This implementation retains its
existing evidence representation, not the complete fourteen-record runtime
profile. Evidence is a scoped command-execution result, not task acceptance,
action permission, issue completion or a declaration of whole-contract conformance.

| Scoped cases | Actual boundary and observations |
| --- | --- |
| ICM-013/014 | Both attestation tests invoke real unit/phase producers and consumers with FIFO barriers, old/new Git subjects, exit-42 controls and edit/revert cases. Git objects and read-only mounts establish acquisition/stability, not equal endpoint hashes. |
| ICM-015/016 | Real consumers refuse dirty inputs; counters distinguish execution/reuse; source, command, checker, environment, tool and diff changes invalidate evidence. `--filesystem-only` must run on disk to establish disk-to-tmpfs rejection. |
| ICM-017/018/019/022 | Actual store rejects malformed, conflicting, legacy, wrong-subject, wrong-origin and incomplete evidence. Signed negative mutations are test-only fault injections; positive records always come from real execution. No Lattice row is accepted as proof. |
| ICM-021/025 | Actual publication faults and fresh consumer restarts distinguish preserved failed attempts, incomplete intent and complete unacknowledged publication. |
| ICM-023/024 | Existing syntax-fixture containment tests inspect external object content and identity; the new execution-boundary test checks source operations, private canaries, writable scratch and detached-child teardown. |
| ICM-030/038/041/052 | Fixed execution bounds, explicit failure propagation, exact PR/merge-test identities and honest unrun/blocked reporting. Local execution cannot replace failed hosted verification. No merge/continuation action is enabled by these tests. |

`tests/validation_execution_boundary_test.bash` runs both real evidence paths.
Its controlled TCP receiver acknowledges positive controls before and after the
candidate's denied connection; the receiver's actual received messages are
checked. Test-owned secret/key/source contents and nanosecond identity metadata
are compared, and a detached child must lose its held FIFO before supervisor
completion. This directly tests local IPv4 and named-path/process boundaries;
it does not claim an exhaustive external-network protocol or hostile-host audit.
The private namespace has no host network route, host socket mount or inherited
credential environment. PATH stubs are additional tripwires, not confinement.

CI uses the ordinary unprivileged pull-request job, read-only GitHub permission,
no persisted checkout credential and separately bounded package installation.
It forces fresh outer evidence execution, with passing-test output enabled;
dedicated positive reuse cases still test reuse. Required check names are unchanged.
The harmless 30-second preflight requires both outer and nested namespaces.

The newer hosted configurations failed: Ubuntu 24.04 image
20261012.334.1 / bubblewrap 0.9.0 denied loopback setup in run 38785050769;
supported Ubuntu 26.04 image 20261012.163.1 / bubblewrap 0.11.1 started the outer
namespace but denied nested execution in run 38785175279. The latter reached
real tests and failed three evidence tests; it was not a green compatibility
result. AppArmor restriction settings were observed, but those observations
alone do not establish the complete causal policy chain. The child security
label on 26.04 is `bwrap//&unpriv_bwrap (enforce)`; its visible profile denies
capabilities, consistent with the nested denial, but audit records are not
available to attribute the complete kernel decision.

The bounded corrective configuration selects `ubuntu-22.04`, which remains
supported until 2027-04-17 according to GitHub's
[retirement announcement](https://github.com/actions/runner-images/issues/14254).
It is already in deprecation, so this is a temporary compatibility target,
not a long-term platform policy. Migrate before the first 2027-03-23 brownout.
This selection must pass the same outer/nested preflight, fresh complete suite,
actual boundary regressions and full validator; an available image or a passing
preflight alone is not compatibility proof. Exact results belong to the tested
head/merge revision on the PR. A future image drift fails closed.
No security-policy change, root candidate execution, namespace removal or
unconfined fallback is permitted. If this final bounded attempt fails, another
environment decision is required, not waived verification.

Platform references: [supported runner images](https://github.com/actions/runner-images),
[Bubblewrap security model](https://github.com/containers/bubblewrap), and
[GitHub secure workflow use](https://docs.github.com/en/actions/reference/security/secure-use).
Supported image availability does not by itself establish executor compatibility.
