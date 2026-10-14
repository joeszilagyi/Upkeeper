"""Real producers and consumers in private fixtures, never a fabricated PASS.

The optional --source selects a historical runner for the two red baselines.
Inputs are imported as independent regular files via the reviewed descriptor
operations. Deterministic FIFO barriers own every concurrent edit/process.
"""
import argparse
import importlib.util
import hashlib
import hmac
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time

from shell_syntax_fixture import directory, parent, regular, FILE, edit

SOURCE = Path(__file__).resolve().parents[2]
FILES = ('tools/run_tests.sh', 'tools/test_attestation_lib.bash',
         'tools/validation_attestation_lib.bash', 'tools/run_validation_phases.sh',
         'tools/git_diff_validation.bash', 'tools/validation_evidence.py')


def imported(source, destination, names):
    with directory(source) as src, directory(destination, private=True) as dst:
        for name in names:
            with parent(src, name) as (sp, leaf), parent(dst, name, create=True) as (dp, _):
                fd = os.open(leaf, os.O_RDONLY | FILE, dir_fd=sp)
                with os.fdopen(fd, 'rb') as incoming:
                    mode = regular(incoming.fileno(), name).st_mode
                    out = os.open(leaf, os.O_CREAT | os.O_EXCL | os.O_WRONLY | FILE, 0o600, dir_fd=dp)
                    with os.fdopen(out, 'wb') as handle:
                        handle.write(incoming.read()); os.fchmod(handle.fileno(), 0o600 | mode & 0o111)


class Fixture:
    def __init__(self, source, kind, legacy=False):
        self.root = Path(tempfile.mkdtemp(prefix='evidence-regression-'))
        self.repo = self.root / 'repo'; self.repo.mkdir(mode=0o700)
        self.store = self.root / 'store'; self.store.mkdir(mode=0o700)
        self.artifact = self.store / 'proof.json'
        self.kind = kind
        self.legacy = legacy
        imported(source, self.repo, FILES[:-1] if legacy else FILES)
        for name in ('tests', 'runtime'):
            (self.repo / name).mkdir(mode=0o700)
        for name in ('home', 'tmp', 'state', 'cache', 'config', 'codex', 'gh', 'bin'):
            (self.root / name).mkdir(mode=0o700)
        self.env = {'PATH': str(self.root/'bin') + ':/usr/bin:/bin',
                    'HOME': str(self.root/'home'), 'TMPDIR': str(self.root/'tmp'),
                    'XDG_STATE_HOME': str(self.root/'state'), 'XDG_CACHE_HOME': str(self.root/'cache'),
                    'XDG_CONFIG_HOME': str(self.root/'config'), 'CODEX_HOME': str(self.root/'codex'),
                    'GH_CONFIG_DIR': str(self.root/'gh'), 'GIT_CONFIG_NOSYSTEM': '1',
                    'GIT_CONFIG_GLOBAL': '/dev/null', 'LANG': 'C.UTF-8', 'UPKEEPER_TEST_JOBS': '1'}
        for name in ('codex', 'gh'):
            p = self.root/'bin'/name
            p.write_text('#!/bin/sh\nexit 97\n'); p.chmod(0o700)
        self.command = (['bash', 'tools/run_tests.sh', '--serial'] if kind == 'tests' else
                        ['bash', 'tools/run_validation_phases.sh', '--phases', 'unit_tests', '--serial'])
        self.key = 'UPKEEPER_TEST_ATTESTATION_FILE' if kind == 'tests' else 'UPKEEPER_VALIDATION_ATTESTATION_FILE'
        self.env[self.key] = str(self.artifact)
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.name', 'Evidence Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.write('.gitignore', 'runtime/\n')
        self.write('tests/a.bash', '#!/bin/bash\nprintf executed >>runtime/count\n')
        self.write('tests/b.bash', '#!/bin/bash\nexit 0\n')
        self.commit()

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], env=self.env).decode().strip()

    def write(self, path, data):
        operation = 'replace' if (self.repo/path).exists() else 'create'
        edit(str(self.repo), path, operation, data.encode())

    def commit(self):
        self.git('add', '-A'); self.git('commit', '-qm', 'Private regression input')
        return self.git('rev-parse', 'HEAD')

    def run(self, expected=0, args=None, extra=None):
        env = {**self.env, **(extra or {})}
        result = subprocess.run(args or self.command, cwd=self.repo, env=env,
                                text=True, capture_output=True, timeout=90)
        (self.root / ('run-' + str(time.time_ns()) + '.log')).write_text(result.stdout + result.stderr)
        assert result.returncode == expected, (result.returncode, expected, result.stdout, result.stderr, self.root)
        return result.stdout + result.stderr

    def race(self, revert=False, interrupt=False, publication_fail=False):
        self.write('tests/b.bash', '#!/bin/bash\nmkfifo runtime/release\nprintf ready >runtime/ready\nread -r reply <runtime/release\n')
        old = self.commit()
        proc = subprocess.Popen(self.command, cwd=self.repo, env=self.env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
        lines = []
        scratch = self.repo
        try:
            if not self.legacy:
                while True:
                    line = proc.stdout.readline(); lines.append(line)
                    assert line, ('producer exited before barrier', lines)
                    if ' executed ' in line:
                        scratch = Path(line.split('scratch=', 1)[1].strip()) / 'output'
                        break
            deadline = time.monotonic() + 30
            while not (scratch/'runtime/ready').exists():
                assert proc.poll() is None, (lines, proc.communicate())
                assert time.monotonic() < deadline, ('barrier timeout', self.root)
                time.sleep(.01)
            original = (self.repo/'tests/a.bash').read_bytes()
            self.write('tests/a.bash', '#!/bin/bash\nexit 42\n')
            if revert:
                self.write('tests/a.bash', original.decode())
                new = old
            else:
                new = self.commit()
            if interrupt:
                os.killpg(proc.pid, signal.SIGTERM)
                proc.wait(timeout=5)
                assert not self.artifact.exists(), 'interrupted producer published PASS'
                return
            if publication_fail:
                self.store.chmod(0o500)
            with (scratch/'runtime/release').open('w') as release:
                release.write('continue\n')
            rest = proc.communicate(timeout=60)[0]; lines.append(rest)
            if publication_fail:
                assert proc.returncode == 3, lines
                assert not self.artifact.exists(), 'failed publication exposed PASS'
                return
            assert proc.returncode == 0, lines
            proof = json.loads(self.artifact.read_text())
            if self.legacy:
                recorded = proof['git_head']
                if self.kind == 'tests':
                    consumer = ['bash', '-c', 'source tools/test_attestation_lib.bash; upkeeper_test_attestation_load "$PWD" "$UPKEEPER_TEST_ATTESTATION_FILE"']
                    accepted = self.run(args=consumer)
                else:
                    accepted = self.run()
                assert recorded == new and old != new
                assert self.run(expected=42, args=['bash', 'tests/a.bash']) == ''
                raise AssertionError('OLD DEFECT: real consumer accepted unexecuted exit-42 revision')
            assert proof['record']['request']['head'] == old
            assert (scratch/'runtime/count').read_text() == 'executed'
            if revert:
                assert ' reused ' in self.run()
            else:
                # Replace waiting test only in the NEW candidate; the old input
                # and its genuine PASS stay legitimate but cannot certify it.
                self.write('tests/b.bash', '#!/bin/bash\nexit 0\n'); self.commit()
                result = self.run(expected=42)
                assert 'reuse-rejected' in result and ' executed ' in result
        finally:
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGKILL); proc.wait()
            (self.root/'barrier.log').write_text(''.join(lines))
            if publication_fail:
                self.store.chmod(0o700)

    def corrupt_signed(self, mutate):
        # Negative-only transformations of a genuine executed result. These
        # never serve as the positive proof or bypass the production producer.
        envelope = json.loads(self.artifact.read_text())
        mutate(envelope['record'])
        payload = json.dumps(envelope['record'], sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()
        key = (self.store/'.proof.json.key').read_bytes()
        envelope['mac'] = hmac.new(key, payload, hashlib.sha256).hexdigest()
        self.artifact.write_text(json.dumps(envelope))
        assert 'reuse-rejected' in self.run()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--kind', choices=('tests', 'phases'), required=True)
    parser.add_argument('--source', type=Path, default=SOURCE)
    parser.add_argument('--legacy', action='store_true')
    parser.add_argument('--race-only', action='store_true')
    args = parser.parse_args()
    if args.legacy or args.race_only:
        Fixture(args.source, args.kind, args.legacy).race()
        return
    f = Fixture(args.source, args.kind)
    assert ' executed ' in f.run()
    assert ' reused ' in f.run()
    assert ' executed ' in f.run(extra={'UPKEEPER_VALIDATION_NO_REUSE': '1'})
    assert ' executed ' in f.run(extra={'UPKEEPER_TEST_TIMEOUT_SECONDS': '179'})
    assert ' executed ' in f.run(args=f.command + ['--jobs', '2'])
    # Change the actual tool bytes visible to producer AND execution, without
    # touching the host installation or fabricating an eligible record.
    assert ' executed ' in f.run()
    altered = f.root/'jq-altered'
    altered.write_bytes(Path('/usr/bin/jq').read_bytes() + b'\nfixture-toolchain-change\n')
    altered.chmod(0o700)
    altered_command = ['bwrap', '--die-with-parent', '--ro-bind', '/', '/',
                       '--dev', '/dev',
                       '--bind', str(f.root), str(f.root),
                       '--ro-bind', str(altered), '/usr/bin/jq', '--', *f.command]
    assert ' executed ' in f.run(args=altered_command)
    assert ' reused ' in f.run(args=altered_command)
    assert ' executed ' in f.run()
    runner = 'tools/run_tests.sh'
    f.write(runner, (f.repo/runner).read_text() + '\n# Changed checker version.\n'); f.commit()
    assert ' executed ' in f.run()
    f.write('source.txt', 'source changed without changing a test\n'); f.commit()
    assert ' executed ' in f.run()
    for state in ('unstaged', 'staged', 'untracked'):
        path = 'new.txt' if state == 'untracked' else 'source.txt'
        f.write(path, state + '\n')
        if state == 'staged': f.git('add', path)
        assert 'blocked' in f.run(expected=3)
        f.commit()
    # Deliberate attempts to write, rename, delete, or add authoritative input
    # must fail. Only the separate runtime scratch may change.
    f.write('tests/a.bash', '''#!/bin/bash
set -e
if printf broken >>tests/b.bash 2>/dev/null; then exit 91; fi
if rm tests/b.bash 2>/dev/null; then exit 92; fi
if mv tests/b.bash tests/moved.bash 2>/dev/null; then exit 93; fi
if touch tests/new.bash 2>/dev/null; then exit 94; fi
printf executed >>runtime/count
'''); f.commit()
    assert ' executed ' in f.run()
    # No handcrafted record is used as positive proof.
    for content in ('{}', '{bad', '{"schema":"upkeeper.test-attestation.v1"}',
                    '{"record":{},"record":{},"mac":"bad"}'):
        f.artifact.write_text(content)
        assert 'reuse-rejected' in f.run()
    f.corrupt_signed(lambda row: row.update(finished=time.time()-901))
    f.corrupt_signed(lambda row: row['request']['scope'].update(test_inventory=[]))
    f.corrupt_signed(lambda row: row['result'].update(exit=42))
    f.corrupt_signed(lambda row: row['request']['conditions']['tools'].update(bash='wrong-toolchain'))
    f.corrupt_signed(lambda row: row.update(schema='legacy'))
    # Copying an otherwise genuine artifact to another storage boundary cannot
    # carry its producer authority with it.
    other = f.root/'other-store'; other.mkdir(mode=0o700)
    replay = other/'replay.json'
    assert ' executed ' in f.run(extra={f.key: str(replay)})
    replay.write_bytes(f.artifact.read_bytes())
    assert 'reuse-rejected' in f.run(extra={f.key: str(replay)})
    sentinel = f.root/'sentinel'; sentinel.write_text('untouched\n')
    before = sentinel.stat()
    unsafe = f.store/'unsafe.json'; unsafe.symlink_to(sentinel)
    assert 'blocked' in f.run(expected=3, extra={f.key: str(unsafe)})
    after = sentinel.stat()
    assert sentinel.read_text() == 'untouched\n'
    assert (before.st_ino, before.st_mode, before.st_size, before.st_mtime_ns, before.st_ctime_ns) == (
            after.st_ino, after.st_mode, after.st_size, after.st_mtime_ns, after.st_ctime_ns)
    Fixture(args.source, args.kind).race()
    Fixture(args.source, args.kind).race(revert=True)
    Fixture(args.source, args.kind).race(interrupt=True)
    Fixture(args.source, args.kind).race(publication_fail=True)
    # Publication's atomic boundary is tested separately from the real-process
    # interruption above. A simulated interrupted rename must leave no partial
    # destination; no PASS record is fabricated for a positive consumer.
    spec = importlib.util.spec_from_file_location('publication', args.source/'tools/validation_evidence.py')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    fd = module.secure_directory(f.store)
    original_replace = module.os.replace
    def interrupted(*args, **kwargs):
        raise InterruptedError('controlled publication interruption')
    module.os.replace = interrupted
    try:
        try:
            module.atomic(fd, 'interrupted.json', b'not a passing record')
        except InterruptedError:
            pass
        else:
            raise AssertionError('publication interruption did not propagate')
        assert not (f.store/'interrupted.json').exists()
    finally:
        module.os.replace = original_replace
        os.close(fd)
    print('validation evidence real-entrypoint regressions: ok kind=' + args.kind)


if __name__ == '__main__':
    main()
