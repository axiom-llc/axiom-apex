"""Real kernel-boundary probes; use synthetic files and credentials only."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time

import pytest
from apex import rsi

# These probes need a host outside the boundary; CI always runs them.
pytestmark = pytest.mark.host_isolation


def execute(scratch, code, timeout=10):
    return rsi._run_candidate_process([sys.executable, '-c', code], str(scratch), timeout=timeout)


def test_files_environment_network_and_fds(tmp_path, monkeypatch):
    scratch = tmp_path / 'candidate'
    scratch.mkdir()
    outside = tmp_path / 'host-sentinel'
    outside.write_text('synthetic private data')
    (scratch / 'escape').symlink_to(outside)
    names = ['OPENAI_API_KEY', 'ANTHROPIC_API_KEY', 'GEMINI_API_KEY', 'GITHUB_TOKEN',
             'AWS_SECRET_ACCESS_KEY', 'SSH_AUTH_SOCK', 'AXIOM_TEST_SECRET']
    for name in names:
        monkeypatch.setenv(name, 'synthetic-secret-only')
    # A synthetic file at the real repository boundary, removed even on failure.
    import tempfile
    with tempfile.NamedTemporaryFile(dir=rsi.REPO_ROOT, prefix='.rsi-sentinel-') as real:
        with socket.socket() as listener, outside.open() as fd:
            listener.bind(('127.0.0.1', 0))
            listener.listen()
            os.set_inheritable(fd.fileno(), True)
            paths = [str(outside), '../host-sentinel', 'escape', real.name,
                     str(Path.home() / '.ssh'), '/run/docker.sock', '/var/run/docker.sock']
            result = execute(scratch, f'''
import os, socket, json
from pathlib import Path
paths = {paths!r}
leaks = []
for p in paths:
    try:
        Path(p).read_bytes()
        leaks.append('read:' + p)
    except OSError: pass
for p in { [str(outside), real.name, '../host-write', 'escape']!r}:
    try:
        Path(p).write_text('synthetic mutation')
        leaks.append('write:' + p)
    except OSError: pass
leaks += [n for n in {names!r} if n in os.environ]
try:
    socket.create_connection(('127.0.0.1', {listener.getsockname()[1]}), timeout=0.3).close()
    leaks.append('network')
except OSError: pass
try:
    os.fstat({fd.fileno()})
    leaks.append('inherited-fd')
except OSError: pass
print(json.dumps(leaks))
''')
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout) == []
    assert outside.read_text() == 'synthetic private data'
    assert not (tmp_path / 'host-write').exists()


@pytest.mark.parametrize('outcome', ['success', 'failure', 'timeout'])
def test_descendants_die_with_evaluation(tmp_path, outcome):
    scratch = tmp_path / 'candidate'
    scratch.mkdir()
    # Writing into the permitted scratch bind after evaluation would prove survival.
    child = "import time; from pathlib import Path; time.sleep(1); Path('survived').write_text('bad')"
    code = f'''
import subprocess, sys, time
for detached in (False, True):
    subprocess.Popen([sys.executable, '-c', {child!r}], start_new_session=detached,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
{'time.sleep(10)' if outcome == 'timeout' else 'raise SystemExit(7)' if outcome == 'failure' else ''}
'''
    if outcome == 'timeout':
        with pytest.raises(subprocess.TimeoutExpired):
            execute(scratch, code, timeout=0.3)
    else:
        assert execute(scratch, code).returncode == (7 if outcome == 'failure' else 0)
    time.sleep(1.3)
    assert not (scratch / 'survived').exists()


@pytest.mark.parametrize('mode', ['missing', 'setup_failure'])
def test_isolation_failure_never_runs_candidate(tmp_path, monkeypatch, mode):
    from apex import _rsi_sandbox as sandbox
    marker = tmp_path / 'executed'
    if mode == 'missing':
        monkeypatch.setattr(sandbox.shutil, 'which', lambda *a, **kw: None)
    else:
        # Force the real primitive to fail a required mount before exec.
        wrapper = tmp_path / 'bwrap-failure'
        wrapper.write_text('#!/bin/sh\nexec /usr/bin/bwrap --ro-bind /nonexistent-rsi-runtime /runtime "$@"\n')
        wrapper.chmod(0o700)
        monkeypatch.setattr(sandbox.shutil, 'which', lambda *a, **kw: str(wrapper))
    with pytest.raises(sandbox.IsolationError):
        sandbox.run(['/bin/sh', '-c', 'touch /work/executed'], str(tmp_path))
    assert not marker.exists()


@pytest.mark.parametrize('termination', ['interrupt', 'parent_death'])
def test_controller_termination_kills_detached_children(tmp_path, termination):
    import signal
    scratch = tmp_path / 'candidate'
    scratch.mkdir()
    child = "import time; from pathlib import Path; time.sleep(2); Path('survived').touch()"
    candidate = f"import subprocess,sys,time; subprocess.Popen([sys.executable,'-c',{child!r}],start_new_session=True); time.sleep(30)"
    controller = f"from apex._rsi_sandbox import run; run([{sys.executable!r}, '-c', {candidate!r}], {str(scratch)!r})"
    process = subprocess.Popen([sys.executable, '-c', controller], stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        deadline = time.monotonic() + 10
        child_pids = []
        while not child_pids and time.monotonic() < deadline:
            assert process.poll() is None
            for proc in Path('/proc').glob('[0-9]*'):
                try:
                    argv = (proc / 'cmdline').read_bytes().split(b'\0')
                    if len(argv) >= 3 and argv[1] == b'-c' and argv[2] == child.encode():
                        child_pids.append(proc)
                except OSError:
                    pass
            time.sleep(0.02)
        assert child_pids, 'detached child did not start'
        process.send_signal(signal.SIGINT if termination == 'interrupt' else signal.SIGKILL)
        process.wait(timeout=5)
        time.sleep(2.3)
        for proc in child_pids:
            if proc.exists():
                assert proc.joinpath('stat').read_text().split()[2] == 'Z'
        assert not (scratch / 'survived').exists()
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()


def test_real_apex_candidate_regressions_and_benchmark(tmp_path, monkeypatch):
    import shutil
    repo = tmp_path / 'repo'
    shutil.copytree(rsi.REPO_ROOT, repo, ignore=shutil.ignore_patterns(
        '.git', '.venv*', '__pycache__', '.pytest_cache', 'build', '*.egg-info'))
    subprocess.run(['git', 'init', '-q', str(repo)], check=True)
    subprocess.run(['git', 'add', '.'], cwd=repo, check=True)
    subprocess.run(['git', '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                    'commit', '-qm', 'candidate fixture'], cwd=repo, check=True)
    source = repo / 'apex/core/loop.py'
    source.write_text(source.read_text() + '\n# Valid RSI candidate smoke probe.\n')
    patch = subprocess.check_output(['git', 'diff'], cwd=repo, text=True)
    monkeypatch.setattr(rsi, 'REPO_ROOT', repo)
    score = rsi._run_candidate(0, patch, str(repo / 'benchmarks/tasks.json'), True, k=1)
    assert score is not None and 0 <= score <= 1


def test_runtime_readonly_privileges_and_unix_socket(tmp_path):
    scratch = tmp_path / 'candidate'
    scratch.mkdir()
    (scratch / '.git').write_text('gitdir: synthetic-host-git-metadata')
    socket_path = str(tmp_path / 'agent.sock')
    with socket.socket(socket.AF_UNIX) as listener:
        listener.bind(socket_path)
        listener.listen()
        result = execute(scratch, f'''
import os, socket, sys
from pathlib import Path
try:
    assert Path('.git').read_bytes() == b''
except OSError:
    pass
assert not os.access(sys.executable, os.W_OK)
status = Path('/proc/self/status').read_text().splitlines()
assert 'NoNewPrivs:\\t1' in status
assert 'CapEff:\\t0000000000000000' in status
assert os.readlink('/proc/self/ns/net') != {os.readlink('/proc/self/ns/net')!r}
assert os.readlink('/proc/self/ns/pid') != {os.readlink('/proc/self/ns/pid')!r}
with socket.socket(socket.AF_UNIX) as client:
    try:
        client.connect({socket_path!r})
    except OSError:
        pass
    else:
        raise AssertionError('host agent socket reachable')
Path('/tmp/allowed').touch()
Path(os.environ['HOME'], 'allowed').touch()
Path('/work/allowed').touch()
''')
    assert result.returncode == 0, result.stderr
    assert not (scratch / 'allowed').exists()  # Writable state is private tmpfs.
    assert (scratch / '.git').read_text() == 'gitdir: synthetic-host-git-metadata'
