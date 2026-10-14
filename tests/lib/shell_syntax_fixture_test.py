"""Bounded real-setup probes; never launch a nested suite or a model backend.

--fixture-script selects an older shell fixture for the containment red test.
Minimal source sets reach the old import/first mutation, not the later suite;
sentinel damage is asserted before judging the child's exit or diagnostic.
"""

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from unittest import mock

import shell_syntax_fixture as fixture

ROOT = Path(__file__).resolve().parents[2]
TARGET = fixture.REQUIRED[0]


def identity(path):
    s = path.stat()
    return (hashlib.sha256(path.read_bytes()).hexdigest(), s.st_dev, s.st_ino,
            s.st_mode, s.st_uid, s.st_gid, s.st_nlink, s.st_size, s.st_mtime_ns, s.st_ctime_ns)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--fixture-script', type=Path, default=ROOT / 'tests/shell_syntax_validation_test.bash')
    args = parser.parse_args()
    os.umask(0o077)
    runtime = ROOT / 'runtime'
    if runtime.is_symlink():
        raise ValueError('fixture runtime must not be a symlink')
    runtime.mkdir(exist_ok=True)
    outer = Path(tempfile.mkdtemp(prefix='syntax-containment.', dir=runtime))
    env = dict(PATH='/usr/bin:/bin', HOME=str(outer / 'home'), TMPDIR=str(outer / 'tmp'),
               GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null',
               LANG='C.UTF-8', PYTHONDONTWRITEBYTECODE='1')
    for name in ('home', 'tmp', 'state', 'cache', 'config', 'codex', 'gh', 'obligations',
                 'ledger', 'backups', 'logs', 'locks', 'bin'):
        (outer / name).mkdir(mode=0o700)
    for key, name in (('XDG_STATE_HOME', 'state'), ('XDG_CACHE_HOME', 'cache'),
                      ('XDG_CONFIG_HOME', 'config'), ('CODEX_HOME', 'codex'), ('GH_CONFIG_DIR', 'gh'),
                      ('UPKEEPER_OBLIGATION_DIR', 'obligations'), ('UPKEEPER_AUTOMATION_LEDGER_DIR', 'ledger'),
                      ('UPKEEPER_PRECONTACT_BACKUP_ROOT', 'backups'), ('UPKEEPER_ACTIVE_LOCK_DIR', 'locks')):
        env[key] = str(outer / name)
    for name in ('codex', 'gh'):
        stub = outer / 'bin' / name
        stub.write_text('#!/bin/bash\nprintf "unexpected transport\\n" >>"$FIXTURE_TRANSPORT_LOG"\nexit 97\n')
        stub.chmod(0o700)
    env['PATH'] = str(outer / 'bin') + ':' + env['PATH']
    env['FIXTURE_TRANSPORT_LOG'] = str(outer / 'transport.log')

    def invoke(command, cwd, **kwargs):
        return subprocess.run(command, cwd=cwd, env=env, capture_output=True, timeout=40, **kwargs)

    def source_case(name):
        case = outer / name
        source = case / 'source'
        source.mkdir(parents=True, mode=0o700)
        for path in fixture.REQUIRED:
            f = source / path
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_text(':\n')
        (source / 'tests/lib').mkdir()
        shutil.copyfile(args.fixture_script, source / 'tests/shell_syntax_validation_test.bash')
        shutil.copyfile(ROOT / 'tests/lib/shell_syntax_fixture.py', source / 'tests/lib/shell_syntax_fixture.py')
        invoke(['git', 'init', '-q'], source, check=True)
        invoke(['git', 'add', '.'], source, check=True)
        sentinel = case / 'sentinel.sh'
        sentinel.write_text(': # external sentinel\n')
        return case, source, sentinel

    def prepare(source):
        result = invoke(['bash', 'tests/shell_syntax_validation_test.bash', '--prepare-only'], source)
        (source.parent / 'prepare.stdout').write_bytes(result.stdout)
        (source.parent / 'prepare.stderr').write_bytes(result.stderr)
        return result

    def rejected(label, source, sentinel, expected=TARGET):
        before = identity(sentinel)
        result = prepare(source)
        after = identity(sentinel)
        assert before == after, f'{label}: external sentinel was changed by fixture setup/mutation: {before!r} -> {after!r}'
        assert result.returncode == 2, f'{label}: expected import rejection 2, got {result.returncode}'
        assert b'unsafe import input' in result.stderr and os.fsencode(expected) in result.stderr, result.stderr
        assert b'fixture_prepared=' not in result.stdout
        print(f'{label}: rejected=2 sentinel_unchanged=1 before_mutation=1')

    try:
        for kind in ('absolute', 'relative', 'parent', 'dangling', 'fifo', 'directory', 'missing', 'unreadable'):
            case, source, sentinel = source_case(kind)
            target = source / TARGET
            if kind == 'parent':
                target.unlink()
                target.parent.rmdir()
                linked = case / 'external-directory'
                linked.mkdir()
                sentinel.rename(linked / target.name)
                sentinel = linked / target.name
                target.parent.symlink_to(linked)
            elif kind == 'unreadable':
                assert os.getuid() != 0, 'permission case requires an ordinary unprivileged account'
                target.chmod(0)
            else:
                target.unlink()
                if kind == 'absolute': target.symlink_to(sentinel)
                if kind == 'relative': target.symlink_to('../../sentinel.sh')
                if kind == 'dangling': target.symlink_to(case / 'absent.sh')
                if kind == 'fifo': os.mkfifo(target)
                if kind == 'directory': target.mkdir()
            rejected(kind, source, sentinel)

        case, source, sentinel = source_case('valid')
        # A source hardlink is read-only input; the imported file must be new.
        (source / TARGET).unlink()
        os.link(sentinel, source / TARGET)
        (source / 'untracked-private-sentinel').write_text('test-owned private material\n')
        before = identity(sentinel)
        result = prepare(source)
        assert result.returncode == 0, result.stderr
        copied = Path(os.fsdecode(result.stdout).strip().removeprefix('fixture_prepared='))
        assert copied.is_relative_to(source / 'runtime')
        assert not (copied / 'untracked-private-sentinel').exists()
        assert not (copied / '.git').exists()
        assert (copied / TARGET).stat().st_ino != sentinel.stat().st_ino
        assert (copied / TARGET).stat().st_nlink == 1
        # Deliberate failure immediately after mutation, with NO restoration.
        result = invoke(['bash', '-c',
            'printf "\\nif then\\n" | python3 "$1" append "$2" "$3" || exit $?; exit 42',
            'bash', str(ROOT / 'tests/lib/shell_syntax_fixture.py'), str(copied), TARGET], source)
        assert result.returncode == 42, result.stderr
        assert b'\nif then\n' in (copied / TARGET).read_bytes()
        assert identity(sentinel) == before
        print('valid/failure: mutation_then_exit=42 independent_copy=1 source_and_sentinel_unchanged=1 no_restore=1')

        for kind in ('symlink', 'hardlink', 'existing-regular'):
            destination = case / ('destination-' + kind)
            if kind == 'symlink': destination.symlink_to(sentinel)
            elif kind == 'hardlink': os.link(sentinel, destination)
            else: destination.write_text('do not overwrite\n')
            saved = identity(sentinel)
            try:
                fixture.import_tree(str(source), str(destination))
            except (OSError, ValueError):
                pass
            else:
                raise AssertionError('pre-existing import destination accepted')
            assert identity(sentinel) == saved
        print('pre-existing import destinations: rejected without sentinel writes')

        # Every edit path must reject an inherited replacement BEFORE truncating.
        for kind in ('symlink', 'hardlink', 'parent'):
            private = case / ('edit-' + kind)
            private.mkdir(mode=0o700)
            if kind == 'parent':
                (private / 'link').symlink_to(case)
                relative = 'link/sentinel.sh'
            else:
                relative = 'item.sh'
                if kind == 'symlink': (private / relative).symlink_to(sentinel)
                else: os.link(sentinel, private / relative)
            saved = identity(sentinel)
            for op in ('append', 'replace', 'create'):
                try:
                    fixture.edit(private, relative, op, b'if then\n')
                except (OSError, ValueError):
                    pass
                else:
                    raise AssertionError(f'{kind} {op} unexpectedly accepted')
                assert identity(sentinel) == saved
        print('mutation boundaries: symlink/parent/hardlink rejected without writes')

        # A deterministic replacement at the open boundary: the write must use
        # its already opened independent inode, never reopen the replacement.
        private = case / 'open-boundary'
        private.mkdir(mode=0o700)
        (private / 'item.sh').write_bytes(b':\n')
        saved = identity(sentinel)
        actual_open = os.open
        def swap_after_open(path, flags, *a, **kw):
            fd = actual_open(path, flags, *a, **kw)
            if path == 'item.sh' and flags & os.O_WRONLY:
                (private / 'item.sh').rename(private / 'held.sh')
                (private / 'item.sh').symlink_to(sentinel)
            return fd
        with mock.patch.object(fixture.os, 'open', side_effect=swap_after_open):
            fixture.edit(private, 'item.sh', 'append', b'if then\n')
        assert (private / 'held.sh').read_bytes() == b':\nif then\n'
        assert identity(sentinel) == saved
        print('controlled post-open replacement: held private inode mutated; sentinel unchanged')
        assert not (outer / 'transport.log').exists(), 'unexpected backend/GitHub transport'
    except BaseException:
        print(f'containment evidence retained: {outer}', file=sys.stderr)
        raise
    else:
        shutil.rmtree(outer)
    print('shell_syntax_fixture_containment_test: ok')


if __name__ == '__main__':
    main()
