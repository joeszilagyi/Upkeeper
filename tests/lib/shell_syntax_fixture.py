"""File operations for private validation fixtures (Linux/Python stdlib).

No inherited links, hardlink copies, or pathname check followed by a truncating
open. Directory descriptors pin each parent; final opens use O_NOFOLLOW and are
validated before writing. Fixture roots are private and exclusively owned during
the test. This is not a sandbox against arbitrary same-UID actors who can move
open directories, create new hardlinks, or change the checker itself.
"""

import contextlib
import os
import stat
import subprocess
import sys

DIRECTORY = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
FILE = os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC
REQUIRED = (
    'testruns/manifest_refresh_dry_run.sh', 'lib/upkeeper/codex_io.bash',
    'tests/validation_attestation_test.bash', 'configurations/default.conf',
)


def parts(path):
    result = os.fspath(path).split('/')
    if any(p in ('', '.', '..') for p in result):
        raise ValueError(f'unsafe relative input: {path!r}')
    return result


@contextlib.contextmanager
def directory(path, private=False):
    # Walk absolute ancestors too, rather than resolving through a symlink.
    path = os.path.abspath(path)
    fd = os.open('/', DIRECTORY)
    try:
        for component in parts(path[1:]) if path != '/' else ():
            child = os.open(component, DIRECTORY, dir_fd=fd)
            os.close(fd)
            fd = child
        s = os.fstat(fd)
        if private and (s.st_uid != os.getuid() or s.st_mode & 0o077):
            raise ValueError(f'fixture directory must be private and owned: {path!r}')
        yield fd
    finally:
        os.close(fd)


@contextlib.contextmanager
def parent(root, path, create=False):
    names = parts(path)
    fd = os.dup(root)
    try:
        for name in names[:-1]:
            if create:
                try:
                    os.mkdir(name, 0o700, dir_fd=fd)
                except FileExistsError:
                    pass
            child = os.open(name, DIRECTORY, dir_fd=fd)
            os.close(fd)
            fd = child
        yield fd, names[-1]
    finally:
        os.close(fd)


def regular(fd, path, mutable=False):
    s = os.fstat(fd)
    if not stat.S_ISREG(s.st_mode):
        raise ValueError(f'nonregular input: {path!r}')
    if mutable and (s.st_uid != os.getuid() or s.st_nlink != 1):
        raise ValueError(f'mutation requires an owned, unshared file: {path!r}')
    return s


def import_tree(source, destination):
    # Staged additions are included; ignored evidence, credentials in untracked
    # files, and .git configuration are not part of this fixture source set.
    paths = subprocess.check_output(['git', '-C', source, 'ls-files', '-z', '--cached']).split(b'\0')[:-1]
    paths = [os.fsdecode(p) for p in paths]
    for required in REQUIRED:
        if required not in paths:
            raise ValueError(f'missing required inventory input: {required!r}')
    with directory(source) as src, directory(os.path.dirname(destination)) as outer:
        name = os.path.basename(destination)
        parts(name)
        os.mkdir(name, 0o700, dir_fd=outer)  # Never reuse a pre-existing destination.
        with directory(destination, private=True) as dst:
            for path in paths:
                try:
                    with parent(src, path) as (sp, leaf), parent(dst, path, create=True) as (dp, _):
                        read_fd = os.open(leaf, os.O_RDONLY | FILE, dir_fd=sp)
                        with os.fdopen(read_fd, 'rb') as incoming:
                            mode = regular(incoming.fileno(), path).st_mode
                            write_fd = os.open(leaf, os.O_WRONLY | os.O_CREAT | os.O_EXCL | FILE, 0o600, dir_fd=dp)
                            with os.fdopen(write_fd, 'wb') as outgoing:
                                while chunk := incoming.read(1024 * 1024):
                                    outgoing.write(chunk)
                                os.fchmod(outgoing.fileno(), 0o600 | (mode & 0o111))
                except (OSError, ValueError) as exc:
                    raise ValueError(f'unsafe import input {path!r}: {exc}') from exc


def edit(root, path, operation, data=b''):
    with directory(root, private=True) as root_fd, parent(root_fd, path) as (dp, leaf):
        flags = os.O_RDONLY if operation == 'read' else os.O_WRONLY
        if operation == 'create':
            flags |= os.O_CREAT | os.O_EXCL
        fd = os.open(leaf, flags | FILE, 0o600, dir_fd=dp)
        with os.fdopen(fd, 'rb' if operation == 'read' else 'wb') as stream:
            regular(stream.fileno(), path, mutable=operation != 'read')
            if operation == 'read':
                return stream.read()
            if operation == 'replace':
                os.ftruncate(stream.fileno(), 0)
            if operation == 'append':
                os.lseek(stream.fileno(), 0, os.SEEK_END)
            stream.write(data)


def main():
    try:
        command, root, path = sys.argv[1:]
        if command == 'import':
            import_tree(root, path)
        elif command in ('read', 'create', 'append', 'replace'):
            result = edit(root, path, command, b'' if command == 'read' else sys.stdin.buffer.read())
            if result is not None:
                sys.stdout.buffer.write(result)
        else:
            raise ValueError(f'unknown fixture operation: {command}')
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f'shell_syntax_fixture: rejected {sys.argv[1:]!r}: {exc}', file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
