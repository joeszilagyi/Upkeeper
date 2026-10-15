#!/usr/bin/env python3
"""Pinned, offline validation execution; the only reusable-evidence writer.

Linux/bubblewrap certification is intentionally narrower than diagnostic runs.
Git objects supply coherent inputs. Each file is copied into a read-only mount,
not bound to a mutable checkout. The supervising producer and private evidence
key are outside the check's filesystem and PID namespaces. This does not defend
the trusted host producer/store against an administrator or hostile host peer
with the same account; worker capability policy remains a separate boundary.
"""
import contextlib
import fcntl
import hashlib
import hmac
import json
import math
import os
from pathlib import Path, PurePosixPath
import platform
import secrets
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time

SCHEMA = 'upkeeper.validation-evidence.v2'
POLICY = 'git-objects-ro-bind-data-whole-request-v2'
LIMIT = 1024 * 1024
MAX_AGE = 900
COMMANDS = {'tests': 'tools/run_tests.sh', 'phases': 'tools/run_validation_phases.sh',
            'validator': 'tools/validate_upkeeper.sh'}
ENV_INPUTS = ('CI', 'UPKEEPER_TEST_JOBS', 'UPKEEPER_TEST_TIMEOUT_SECONDS',
              'UPKEEPER_TEST_SERIAL_ONLY', 'UPKEEPER_SLOW_TEST_SECONDS',
              'UPKEEPER_TEST_SHOW_PASS_OUTPUT', 'UPKEEPER_VALIDATION_PHASES',
              'UPKEEPER_VALIDATION_PHASE_JOBS', 'UPKEEPER_VALIDATION_PHASE_TIMEOUT_SECONDS',
              'UPKEEPER_VALIDATION_PHASE_SHOW_PASS_OUTPUT',
              'VALIDATION_CHECK_TIMEOUT_SECONDS', 'VALIDATION_TEST_TIMEOUT_SECONDS',
              'VALIDATION_ISSUE_FIX_PRIVATE_PACKET_TIMEOUT_SECONDS',
              'VALIDATION_INTEGRATION_TIMEOUT_SECONDS', 'VALIDATION_FULL_TIMEOUT_SECONDS',
              'VALIDATION_FILE_MANIFEST_TIMEOUT_SECONDS')
TOOLS = ('bash', 'git', 'python3', 'jq', 'timeout', 'bwrap', 'age', 'screen',
         'awk', 'sed', 'find', 'sort', 'zip', 'script', 'stat', 'rg')
SYSTEM_FILES = ('/etc/ld.so.cache', '/etc/localtime', '/etc/passwd', '/etc/group',
                '/etc/os-release', '/var/lib/dpkg/status')
ISOLATION_FILES = ('/proc/sys/kernel/unprivileged_userns_clone',
                   '/proc/sys/kernel/apparmor_restrict_unprivileged_userns',
                   '/proc/sys/user/max_user_namespaces',
                   '/sys/module/apparmor/parameters/enabled',
                   '/etc/apparmor.d/bwrap-userns-restrict')


class Blocked(Exception):
    pass


def log(state, detail):
    print(f'validation_evidence: {state} {detail}', flush=True)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(root, *args, data=None, env=None):
    clean = {**os.environ, 'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null',
             'GIT_OPTIONAL_LOCKS': '0', 'GIT_NO_REPLACE_OBJECTS': '1'}
    for key in list(clean):
        if key.startswith(('GIT_CONFIG_KEY_', 'GIT_CONFIG_VALUE_')) or key in (
                'GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_CONFIG_COUNT',
                'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES'):
            clean.pop(key, None)
    clean.update(env or {})
    return subprocess.check_output(['/usr/bin/git', '-c', 'core.fsmonitor=false', '-C', str(root), *args], input=data,
                                   env=clean, stderr=subprocess.PIPE)


def resolve(root, ref):
    return git(root, 'rev-parse', '--verify', '--end-of-options', ref + '^{commit}').decode().strip()


def inventory(root, head):
    rows = []
    for line in git(root, 'ls-tree', '-rz', head).split(b'\0'):
        if not line:
            continue
        meta, raw = line.split(b'\t', 1)
        mode, kind, oid = meta.decode().split()
        name = raw.decode('utf-8', 'strict')
        path = PurePosixPath(name)
        if (mode not in ('100644', '100755') or kind != 'blob' or path.is_absolute()
                or any(p in ('', '.', '..', '.git') for p in path.parts)
                or name.startswith('runtime/') or name == 'Upkeeper.log'):
            raise Blocked('unsupported Git object/path: ' + repr(name))
        rows.append([name, mode, oid])
    if not rows:
        raise Blocked('empty Git input')
    return rows


def conditions():
    # Only these explicit values enter the sandbox; no ambient shell/Python/Git
    # configuration or credential variables are inherited or serialized.
    values = {k: os.environ[k] for k in ENV_INPUTS if k in os.environ}
    if any(len(v) > 1024 or '\0' in v for v in values.values()):
        raise Blocked('invalid bounded environment input')
    tools = {}
    for name in TOOLS:
        path = shutil.which(name, path='/usr/bin:/bin')
        tools[name] = digest(Path(path).read_bytes()) if path else 'unavailable'
    # Package versions cover shared libraries/standard modules not identified
    # by hashing the interpreter executable alone. Unknown hosts cannot certify.
    packages = Path('/var/lib/dpkg/status')
    if not packages.is_file():
        raise Blocked('unsupported toolchain manifest (requires dpkg status)')
    def visible_identity(name):
        try:
            return digest(Path(name).read_bytes())
        except OSError:
            return 'unavailable'
    status = Path('/proc/self/status').read_text().splitlines()
    capabilities = {line.split(':', 1)[0]: line.split(':', 1)[1].strip()
                    for line in status if line.startswith(('CapInh:', 'CapPrm:', 'CapEff:',
                                                           'CapBnd:', 'CapAmb:', 'NoNewPrivs:', 'Seccomp:'))}
    return {'values': values, 'tools': tools, 'packages': digest(packages.read_bytes()),
            'isolation_host': {'visible_policy': {p: visible_identity(p) for p in ISOLATION_FILES},
                               'security_label': visible_identity('/proc/self/attr/current'),
                               'capabilities': capabilities},
            'system_files': {name: digest(Path(name).read_bytes()) if Path(name).exists()
                             else 'unavailable' for name in SYSTEM_FILES},
            'kernel': platform.release(), 'machine': platform.machine(),
            'cpu_affinity': sorted(os.sched_getaffinity(0)),
            'scratch_filesystem': subprocess.check_output(
                ['/usr/bin/stat', '-f', '-c', '%T', tempfile.gettempdir()],
                env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'}).decode().strip(),
            'python': sys.version, 'isolation': POLICY, 'locale': 'C.UTF-8'}


def normalize(root, head, kind, args):
    args = list(args)
    resolved = {}
    def pinned(ref):
        if ref not in resolved:
            expression = head + ref[4:] if ref == 'HEAD' or ref.startswith(('HEAD^', 'HEAD~')) else ref
            resolved[ref] = resolve(root, expression)
        return resolved[ref]
    base = os.environ.get('UPKEEPER_VALIDATION_DIFF_BASE', '')
    diff_head = os.environ.get('UPKEEPER_VALIDATION_DIFF_HEAD', head)
    for index, arg in enumerate(args):
        if arg in ('--diff-base', '--diff-head'):
            if index + 1 >= len(args):
                raise Blocked('missing diff reference')
            value = pinned(args[index + 1])
            args[index + 1] = value
            if arg == '--diff-base':
                base = value
            else:
                diff_head = value
    base = pinned(base) if base else ''
    diff_head = pinned(diff_head)
    phases = os.environ.get('UPKEEPER_VALIDATION_PHASES',
                            'shell_syntax,unit_tests,public_docs,diff_whitespace,quick_validator')
    if '--phases' in args:
        position = args.index('--phases')
        if position + 1 >= len(args):
            raise Blocked('missing phase inventory')
        phases = args[position + 1]
    selected = [p.strip() for p in phases.split(',')]
    if kind == 'phases' and (not all(selected) or len(set(selected)) != len(selected)):
        raise Blocked('empty/duplicate phase inventory')
    if kind == 'phases' and 'diff_whitespace' in selected and not base:
        try:
            origin = pinned('origin/main')
            base = git(root, 'merge-base', head, origin).decode().strip()
        except subprocess.CalledProcessError:
            raise Blocked('committed diff phase requires explicit base or verified origin/main') from None
    if kind == 'phases' and '--attestation' in args:
        raise Blocked('internal unnormalized attestation argument')
    return args, {'base': base, 'head': diff_head}


def secure_directory(path):
    """Open each component without following links; never chmod owner paths."""
    absolute = Path(os.path.abspath(path))
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in absolute.parts[1:]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
            st = os.fstat(fd)
            sticky_root = st.st_uid == 0 and st.st_mode & stat.S_ISVTX
            if st.st_uid not in (0, os.getuid()) or (st.st_mode & 0o022 and not sticky_root):
                raise Blocked('unsafe evidence ancestor: ' + str(absolute))
        st = os.fstat(fd)
        if st.st_uid != os.getuid() or st.st_mode & 0o022:
            raise Blocked('evidence directory must be producer-owned and non-writable by others')
        return fd
    except BaseException:
        os.close(fd)
        raise


def read_private(fd, name, limit=LIMIT):
    f = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    try:
        st = os.fstat(f)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077 or st.st_nlink != 1:
            raise Blocked('unsafe evidence file: ' + name)
        data = os.read(f, limit + 1)
        if len(data) > limit:
            raise Blocked('oversize evidence: ' + name)
        return data
    finally:
        os.close(f)


def atomic(fd, name, data):
    if len(data) > LIMIT:
        raise Blocked('oversize publication')
    # A pre-existing link/nonregular destination is an error, not a target to
    # overwrite. renameat publishes to this held directory, never through it.
    try:
        read_private(fd, name)
    except FileNotFoundError:
        pass
    temp = '.' + name + '.' + secrets.token_hex(12)
    out = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=fd)
    try:
        with os.fdopen(out, 'wb') as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp, name, src_dir_fd=fd, dst_dir_fd=fd)
        try:
            os.fsync(fd)
        except OSError:
            # A known failed durability step is not an acknowledged PASS.
            # Preserve its bytes off the current path while the store lock is
            # held. If this also fails, report the custody failure explicitly.
            # Host/store administration remains outside candidate authority.
            try:
                os.rename(name, '.' + name + '.failed-' + secrets.token_hex(12),
                          src_dir_fd=fd, dst_dir_fd=fd)
            except OSError as exc:
                raise Blocked('publication and quarantine failed; evidence store requires reconciliation') from exc
            raise
    finally:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(temp, dir_fd=fd)


def unique_object(pairs):
    obj = {}
    for key, value in pairs:
        if key in obj:
            raise ValueError('duplicate JSON key')
        obj[key] = value
    return obj


class Store:
    def __init__(self, artifact):
        path = Path(os.path.abspath(artifact))
        if not path.name or path.name.startswith('.'):
            raise Blocked('invalid evidence filename')
        self.name = path.name
        self.pending_name = '.' + self.name + '.pending'
        self.fd = secure_directory(path.parent)
        self.key_name = '.' + self.name + '.key'
        try:
            self.key = read_private(self.fd, self.key_name, 32)
        except FileNotFoundError:
            # Do not claim an existing arbitrary file as an evidence output.
            # A per-artifact key is the custody marker for subsequent refreshes.
            try:
                os.stat(self.name, dir_fd=self.fd, follow_symlinks=False)
            except FileNotFoundError:
                pass
            else:
                raise Blocked('existing output has no trusted custody marker')
            key = secrets.token_bytes(32)
            try:
                key_fd = os.open(self.key_name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                                 0o600, dir_fd=self.fd)
            except FileExistsError:
                self.key = read_private(self.fd, self.key_name, 32)
            else:
                with os.fdopen(key_fd, 'wb') as handle:
                    handle.write(key); handle.flush(); os.fsync(handle.fileno())
                self.key = key
        if len(self.key) != 32:
            raise Blocked('incomplete evidence key')
        st = os.fstat(self.fd)
        self.location = [st.st_dev, st.st_ino, self.name]
        # Serialize cooperative producers/consumers. This lock is not the input
        # immutability boundary (the copied read-only mounts are).
        self.lock = os.open('.' + self.name + '.lock', os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW,
                            0o600, dir_fd=self.fd)
        lock_stat = os.fstat(self.lock)
        if (not stat.S_ISREG(lock_stat.st_mode) or lock_stat.st_nlink != 1
                or lock_stat.st_uid != os.getuid() or lock_stat.st_mode & 0o077):
            raise Blocked('unsafe evidence lock')
        deadline = time.monotonic() + 30
        while True:
            try:
                fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise Blocked('evidence store busy (30 second bound)')
                time.sleep(.05)
        try:
            read_private(self.fd, self.name)
        except FileNotFoundError:
            pass

    def invalidate(self):
        try:
            read_private(self.fd, self.name)
        except FileNotFoundError:
            return
        os.rename(self.name, '.' + self.name + '.previous-' + secrets.token_hex(8),
                  src_dir_fd=self.fd, dst_dir_fd=self.fd)
        os.fsync(self.fd)

    def load(self, request):
        try:
            try:
                read_private(self.fd, self.pending_name)
            except FileNotFoundError:
                pass
            else:
                return False, 'incomplete_publication'
            envelope = json.loads(read_private(self.fd, self.name), object_pairs_hook=unique_object)
            if not isinstance(envelope, dict) or set(envelope) != {'record', 'mac'}:
                return False, 'malformed_or_legacy'
            row = envelope['record']
            expected = hmac.new(self.key, canonical(row), hashlib.sha256).hexdigest()
            if not isinstance(envelope['mac'], str) or not hmac.compare_digest(expected, envelope['mac']):
                return False, 'untrusted_record'
            if (not isinstance(row, dict) or set(row) != {
                    'schema', 'request', 'location', 'started', 'finished', 'result'}
                    or row.get('schema') != SCHEMA
                    or row.get('request') != request or row.get('location') != self.location):
                return False, 'identity_mismatch'
            if (row.get('result') != {'exit': 0, 'completed_command': request['command']}
                    or type(row['result']['exit']) is not int):
                return False, 'incomplete_result'
            if any(type(row.get(k)) not in (int, float) or not math.isfinite(row[k])
                   for k in ('started', 'finished')):
                return False, 'invalid_time'
            age = time.time() - row['finished']
            if not 0 <= age <= MAX_AGE or row['started'] > row['finished']:
                return False, 'stale_or_invalid_time'
            return True, 'identical_pinned_request'
        except FileNotFoundError:
            return False, 'missing'
        except (OSError, ValueError, TypeError, KeyError, OverflowError, RecursionError, Blocked):
            return False, 'malformed_or_unsafe'

    def publish(self, request, started):
        # Durable intent precedes the passing bytes. If publication AND its
        # quarantine fail, consumers still cannot reuse the incomplete result.
        # Retain an earlier interrupted intent rather than overwrite its history.
        try:
            read_private(self.fd, self.pending_name)
        except FileNotFoundError:
            pass
        else:
            os.rename(self.pending_name, self.pending_name + '.previous-' + secrets.token_hex(8),
                      src_dir_fd=self.fd, dst_dir_fd=self.fd)
        atomic(self.fd, self.pending_name, canonical({'request_sha256': digest(canonical(request)),
                                                     'started': started}))
        row = {'schema': SCHEMA, 'request': request, 'location': self.location,
               'started': started, 'finished': time.time(),
               'result': {'exit': 0, 'completed_command': request['command']}}
        atomic(self.fd, self.name, canonical({'record': row,
               'mac': hmac.new(self.key, canonical(row), hashlib.sha256).hexdigest()}))
        # The evidence file and directory have now been flushed. Removing the
        # intent makes that completed record eligible. A crash before removal
        # may conservatively require fresh execution; no partial PASS is used.
        os.unlink(self.pending_name, dir_fd=self.fd)


def sealed(data, name):
    fd = os.memfd_create(name, os.MFD_ALLOW_SEALING)
    with os.fdopen(os.dup(fd), 'wb') as f:
        f.write(data)
    os.lseek(fd, 0, os.SEEK_SET)
    fcntl.fcntl(fd, fcntl.F_ADD_SEALS, fcntl.F_SEAL_WRITE | fcntl.F_SEAL_GROW |
                fcntl.F_SEAL_SHRINK | fcntl.F_SEAL_SEAL)
    return fd


def git_context(root, request, prep):
    """Copy reachable immutable objects, not live refs/config/hooks/credentials."""
    target = prep / 'git'
    target.mkdir()
    (target / 'objects/pack').mkdir(parents=True)
    (target / 'refs/heads').mkdir(parents=True)
    (target / 'HEAD').write_text('ref: refs/heads/validation\n')
    (target / 'refs/heads/validation').write_text(request['head'] + '\n')
    (target / 'config').write_text('[core]\nrepositoryformatversion = 0\nbare = false\nfilemode = true\n')
    refs = sorted(set([request['head'], *filter(None, request['diff'].values())]))
    pack = git(root, 'pack-objects', '--stdout', '--revs', data=('\n'.join(refs) + '\n').encode())
    pack_path = target / 'objects/pack/input.pack'
    pack_path.write_bytes(pack)
    subprocess.run(['/usr/bin/git', 'index-pack', '--strict', str(pack_path)], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    subprocess.run(['/usr/bin/git', '--git-dir=' + str(target), 'read-tree', request['head']],
                   check=True, env={'PATH': '/usr/bin:/bin', 'GIT_CONFIG_NOSYSTEM': '1',
                                    'GIT_CONFIG_GLOBAL': '/dev/null'}, stderr=subprocess.PIPE)
    return {'.git/' + str(p.relative_to(target)): (p.read_bytes(), 0o644)
            for p in target.rglob('*') if p.is_file()}


def execute(root, request, scratch):
    if not shutil.which('bwrap', path='/usr/bin:/bin') or not hasattr(os, 'memfd_create'):
        raise Blocked('pinned certification requires Linux memfd and bubblewrap')
    prep = scratch / 'preparation'; prep.mkdir()
    files = git_context(root, request, prep)
    for name, mode, oid in request['inventory']:
        data = git(root, 'cat-file', 'blob', oid)
        if git(root, 'hash-object', '--stdin', data=data).decode().strip() != oid:
            raise Blocked('Git blob identity mismatch: ' + name)
        files[name] = (data, 0o755 if mode == '100755' else 0o644)
    work = scratch / 'output'; work.mkdir()
    for name in ('home', 'tmp', 'state', 'cache', 'config', 'codex', 'gh', 'obligations',
                 'ledger', 'backups', 'logs', 'locks', 'runtime'):
        (work / name).mkdir(mode=0o700)
    (work / 'Upkeeper.log').touch(mode=0o600)
    env = {'PATH': '/validation/transports:/usr/bin:/bin', 'LANG': 'C.UTF-8',
           'HOME': '/scratch/home', 'TMPDIR': '/scratch/tmp',
           'XDG_STATE_HOME': '/scratch/state', 'XDG_CACHE_HOME': '/scratch/cache',
           'XDG_CONFIG_HOME': '/scratch/config', 'CODEX_HOME': '/scratch/codex',
           'GH_CONFIG_DIR': '/scratch/gh', 'UPKEEPER_OBLIGATION_DIR': '/scratch/obligations',
           'UPKEEPER_AUTOMATION_LEDGER_DIR': '/scratch/ledger',
           'UPKEEPER_PRECONTACT_BACKUP_ROOT': '/scratch/backups',
           'UPKEEPER_ACTIVE_LOCK_DIR': '/scratch/locks/active',
           'UPKEEPER_LOCAL_ENV_DISABLE': '1', 'GIT_CONFIG_NOSYSTEM': '1',
           'GIT_CONFIG_GLOBAL': '/dev/null', 'GIT_OPTIONAL_LOCKS': '0',
           'PYTHONPYCACHEPREFIX': '/scratch/cache/python',
           'UPKEEPER_VALIDATION_DIFF_BASE': request['diff']['base'],
           'UPKEEPER_VALIDATION_DIFF_HEAD': request['diff']['head']}
    env.update(request['conditions']['values'])
    command = ['/usr/bin/bwrap', '--die-with-parent', '--new-session', '--unshare-net',
               '--unshare-pid', '--tmpfs', '/', '--ro-bind', '/usr', '/usr']
    for name in ('bin', 'sbin', 'lib', 'lib64'):
        path = Path('/') / name
        if path.is_symlink():
            command += ['--symlink', os.readlink(path), '/' + name]
        elif path.exists():
            command += ['--ro-bind', str(path), str(path)]
    for name in (*SYSTEM_FILES, '/etc/alternatives'):
        if Path(name).exists():
            command += ['--ro-bind', name, name]
    command += ['--dev', '/dev', '--proc', '/proc', '--tmpfs', '/run',
                '--perms', '0700', '--tmpfs', '/validation', '--dir', '/validation/repo',
                '--dir', '/validation/repo/runtime']
    descriptors = []
    try:
        for name, (data, mode) in files.items():
            fd = sealed(data, 'validation-input'); descriptors.append(fd)
            command += ['--perms', oct(mode)[2:], '--ro-bind-data', str(fd), '/validation/repo/' + name]
        blocked = b'#!/bin/sh\nprintf "unexpected transport\\n" >>/scratch/transport.log\nexit 97\n'
        for name in ('gh', 'codex'):
            fd = sealed(blocked, name); descriptors.append(fd)
            command += ['--perms', '0755', '--ro-bind-data', str(fd), '/validation/transports/' + name]
        command += ['--bind', str(work), '/scratch',
                    '--bind', str(work / 'runtime'), '/validation/repo/runtime',
                    '--bind', str(work / 'Upkeeper.log'), '/validation/repo/Upkeeper.log',
                    '--remount-ro', '/validation', '--bind', str(work / 'tmp'), '/tmp',
                    '--clearenv']
        for key, value in env.items():
            command += ['--setenv', key, value]
        command += ['--chdir', '/validation/repo', '--', '/usr/bin/bash',
                    COMMANDS[request['kind']], *request['args']]
        proc = subprocess.Popen(command, pass_fds=descriptors, start_new_session=True)
        try:
            rc = proc.wait(timeout=3600)
        except BaseException:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
            raise
        if (work / 'transport.log').exists():
            raise Blocked('unexpected backend/GitHub transport attempt')
        return rc if rc >= 0 else 128 - rc
    finally:
        for fd in descriptors:
            os.close(fd)


def main():
    os.umask(0o077)
    root, head, kind, artifact, *args = sys.argv[1:]
    if kind not in COMMANDS:
        raise Blocked('unsupported request kind')
    root = Path(root)
    # Cleanliness is an eligibility policy, not the snapshot acquisition method.
    # Execution uses only immutable objects below, so edit/revert races cannot
    # splice mutable worktree bytes into the certified input.
    if git(root, 'status', '--porcelain=v1', '--untracked-files=all'):
        log('blocked', 'dirty/staged/untracked candidate: no reusable certification; run without attestation for diagnostics')
        return 3
    if git(root, 'rev-parse', '--is-shallow-repository').strip() != b'false':
        raise Blocked('shallow Git history is unsupported for reusable certification')
    args, diff = normalize(root, head, kind, args)
    rows = inventory(root, head)
    tests = sorted(n for n, _, _ in rows if n.startswith('tests/') and n.count('/') == 1 and n.endswith('.bash'))
    if not tests:
        raise Blocked('empty test inventory')
    if any('\n' in name or '\t' in name for name in tests):
        raise Blocked('test runner result format cannot certify tab/newline test names')
    request = {'policy': POLICY, 'head': head, 'tree': git(root, 'rev-parse', head + '^{tree}').decode().strip(),
               'inventory': rows, 'scope': {'kind': kind, 'test_inventory': tests, 'args': args},
               'kind': kind, 'args': args, 'command': ['/usr/bin/bash', COMMANDS[kind], *args],
               'diff': diff, 'conditions': conditions()}
    store = Store(artifact)
    try:
        eligible, reason = store.load(request)
        if eligible and os.environ.get('UPKEEPER_VALIDATION_NO_REUSE') != '1':
            log('reused', f'head={head} kind={kind} reason={reason}')
            return 0
        log('reuse-rejected', 'reason=' + ('forced_fresh' if eligible else reason))
        store.invalidate()
        started = time.time()
        # Retain failed outputs for diagnosis; successful scratch is also kept
        # at the named private path, never confused with reusable evidence.
        scratch = Path(tempfile.mkdtemp(prefix='upkeeper-pinned-validation-'))
        log('executed', f'head={head} kind={kind} scratch={scratch}')
        rc = execute(root, request, scratch)
        if rc:
            log('failed', f'exit={rc} head={head}; no evidence published')
            return rc
        if conditions() != request['conditions']:
            raise Blocked('host toolchain/conditions changed during execution; no evidence published')
        store.publish(request, started)
        log('passed', f'head={head} kind={kind} evidence={artifact}')
        return 0
    finally:
        os.close(store.lock)
        os.close(store.fd)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (Blocked, OSError, ValueError, subprocess.SubprocessError) as exc:
        log('blocked', str(exc))
        sys.exit(3)
