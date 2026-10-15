"""Real pinned entrypoints; protected outer observations and test-owned targets.

No external service: receiver reachability is proved in the outer test's own
network namespace. Inside it, the actual executor creates a different one.
The harness is proposed test evidence, not installed production authority.
"""
import errno
import json
import os
from pathlib import Path
import socket
import threading

from validation_evidence_test import Fixture


def identity(path):
    data = path.read_bytes()
    st = path.stat()
    return data, (st.st_dev, st.st_ino, st.st_mode, st.st_size, st.st_mtime_ns, st.st_ctime_ns)


def boundary(source, kind):
    f = Fixture(source, kind)
    secret = f.root / 'protected-secret'
    secret.write_text('test-owned-secret-not-a-credential\n')
    assert ' executed ' in f.run()
    key = f.store / '.proof.json.key'
    before = {p: identity(p) for p in (secret, key)}
    listener = socket.socket()
    listener.bind(('127.0.0.1', 0)); listener.listen(); listener.settimeout(.1)
    port = listener.getsockname()[1]
    received, stopped = [], threading.Event()
    def collect():
        while not stopped.is_set():
            try:
                client, _ = listener.accept()
            except socket.timeout:
                continue
            with client:
                client.settimeout(2)
                message = client.recv(100)
                received.append(message)
                client.sendall(b'ACK')
    thread = threading.Thread(target=collect)
    thread.start()
    def control(message):
        with socket.create_connection(('127.0.0.1', port), timeout=2) as client:
            client.sendall(message)
            assert client.recv(3) == b'ACK'
    try:
        control(b'before')
        f.write('tests/a.bash', '''#!/bin/bash
set -eu
python3 - <<'PY'
import os, socket
from pathlib import Path
for name in %r:
    for prefix in ('', '/proc/1/root'):
        try:
            with open(prefix + name, 'rb') as handle: handle.read(1)
        except OSError: pass
        else: raise AssertionError('protected path readable')
    try:
        with open(name, 'ab') as handle: handle.write(b'forbidden')
    except OSError: pass
    else: raise AssertionError('protected path writable')
try:
    with socket.create_connection(('127.0.0.1', %d), timeout=1) as client:
        client.sendall(b'forbidden')
except OSError: pass
else: raise AssertionError('outer receiver reachable')
target = Path('tests/b.bash')
for operation in (lambda: target.open('ab'), lambda: target.write_text('changed'),
                  lambda: target.unlink(), lambda: target.rename('tests/moved.bash'),
                  lambda: Path('tests/added.bash').touch()):
    try: operation()
    except OSError: pass
    else: raise AssertionError('authoritative source writable')
Path('runtime/scratch-positive').write_text('written')
PY
''' % ([str(secret), str(key), str(f.artifact)], port))
        f.write('tests/b.bash', '''#!/bin/bash
set -eu
python3 - <<'PY'
import os, subprocess, sys
from pathlib import Path
os.mkfifo('runtime/descendant-release')
reader, writer = os.pipe()
child = subprocess.Popen([sys.executable, '-c', "import os,sys; fd=os.open('runtime/descendant-release',os.O_RDWR); os.write(int(sys.argv[1]),b'R'); os.close(int(sys.argv[1])); os.read(fd,1); open('runtime/late-write','w').write('forbidden')", str(writer)], pass_fds=[writer], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
os.close(writer)
assert os.read(reader, 1) == b'R'
os.close(reader)
Path('runtime/descendant-ready').write_text(str(child.pid))
PY
''')
        head = f.commit()
        inputs = {p: identity(p) for p in (f.repo/'tests/a.bash', f.repo/'tests/b.bash')}
        output = f.run()
        scratch = Path(next(line for line in output.splitlines() if ' executed ' in line).split('scratch=', 1)[1])/'output'
        assert (scratch/'runtime/scratch-positive').read_text() == 'written'
        assert (scratch/'runtime/descendant-ready').is_file()
        try:
            fd = os.open(scratch/'runtime/descendant-release', os.O_WRONLY | os.O_NONBLOCK)
        except OSError as exc:
            assert exc.errno == errno.ENXIO, exc
        else:
            os.close(fd)
            raise AssertionError('descendant survived producer completion')
        assert not (scratch/'runtime/late-write').exists()
        assert json.loads(f.artifact.read_text())['record']['request']['head'] == head
        assert all(identity(p) == value for p, value in {**before, **inputs}.items())
        control(b'after')
        assert received == [b'before', b'after'], received
        print('executor boundary: PASS kind=' + kind + ' network=paired-receiver source=denied secret/custody=denied scratch=written descendant=terminated')
    finally:
        stopped.set(); thread.join(3); listener.close()
        assert not thread.is_alive(), 'test-owned receiver did not stop'


if __name__ == '__main__':
    for requested in ('tests', 'phases'):
        boundary(Path(__file__).resolve().parents[2], requested)
