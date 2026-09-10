"""Finite adversarial probes for aggregate candidate resource enforcement."""
import dataclasses
from pathlib import Path
import subprocess
import sys

import pytest
from apex import rsi, _rsi_sandbox as sandbox

pytestmark = pytest.mark.host_isolation


@pytest.fixture
def limits(monkeypatch):
    policy = dataclasses.replace(sandbox.DEFAULT_LIMITS, cpu_percent=25,
                                 memory_bytes=128 * 1024**2, tasks=16,
                                 storage_bytes=16 * 1024**2, output_bytes=32768)
    monkeypatch.setattr(sandbox, 'DEFAULT_LIMITS', policy)
    return policy


def execute(root, code, timeout=10):
    return sandbox.run([sys.executable, '-c', code], str(root), timeout=timeout)


def test_cpu_workers_share_quota(tmp_path, limits):
    # At most 2 CPU seconds even without enforcement; four workers cannot
    # finish within this wall deadline under an aggregate 25% CPU quota.
    child = 'import time; end=time.process_time()+0.5\nwhile time.process_time()<end: pass'
    code = f"import subprocess,sys; children=[subprocess.Popen([sys.executable,'-c',{child!r}]) for _ in range(4)]; [p.wait() for p in children]"
    with pytest.raises(subprocess.TimeoutExpired):
        execute(tmp_path, code, timeout=2)
    assert list(tmp_path.iterdir()) == []


@pytest.mark.parametrize('probe', ['memory', 'processes', 'storage'])
def test_exhaustion_rejects_and_preserves_source(tmp_path, limits, probe):
    source = tmp_path / 'source'
    source.write_text('unchanged')
    code = {
        # Each probe is finite even if enforcement regresses.
        'memory': "blocks=[bytearray(8*1024**2) for _ in range(32)]",
        'processes': "import subprocess,sys; children=[subprocess.Popen([sys.executable,'-c','import time; time.sleep(3)'],start_new_session=True) for _ in range(32)]",
        'storage': "from pathlib import Path; f=Path('large').open('wb'); [f.write(b'x'*1024**2) for _ in range(64)]; f.close()",
    }[probe]
    result = execute(tmp_path, code)
    assert result.returncode != 0, result.stdout
    assert source.read_text() == 'unchanged'
    assert sorted(p.name for p in tmp_path.iterdir()) == ['source']


def test_output_flood_is_bounded(tmp_path, limits):
    with pytest.raises(sandbox.ResourceLimitError, match='output'):
        execute(tmp_path, "import os; [(os.write(1,b'x'*4096),os.write(2,b'y'*4096)) for _ in range(256)]")
    assert list(tmp_path.iterdir()) == []


def test_limit_setup_failure_executes_nothing(tmp_path, monkeypatch):
    original = sandbox.shutil.which
    monkeypatch.setattr(sandbox.shutil, 'which', lambda name, **kw: None if name == 'systemd-run' else original(name, **kw))
    with pytest.raises(sandbox.IsolationError, match='systemd'):
        execute(tmp_path, "from pathlib import Path; Path('executed').touch()")
    assert list(tmp_path.iterdir()) == []


def test_normal_candidate_has_private_bounded_storage(tmp_path):
    (tmp_path / 'source').write_text('original')
    result = execute(tmp_path, "from pathlib import Path; assert Path('source').read_text()=='original'; Path('source').write_text('private'); print('ok')")
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == 'ok'
    assert (tmp_path / 'source').read_text() == 'original'


def test_unapplied_kernel_limits_fail_closed(tmp_path, monkeypatch):
    # A launcher that claims success but does not create a cgroup must never
    # reach Bubblewrap or candidate code. The trusted verifier catches it.
    wrapper = tmp_path / 'false-scope'
    wrapper.write_text('#!/bin/sh\nwhile [ "$1" != "--" ]; do shift; done\nshift\nexec "$@"\n')
    wrapper.chmod(0o700)
    original = sandbox.shutil.which
    monkeypatch.setattr(sandbox.shutil, 'which', lambda name, **kw: str(wrapper) if name == 'systemd-run' else original(name, **kw))
    with pytest.raises(sandbox.IsolationError, match='resource scope'):
        execute(tmp_path, "from pathlib import Path; Path('executed').touch()")
    assert not (tmp_path / 'executed').exists()


def test_all_writable_mounts_have_capacity_limits(tmp_path, limits):
    result = execute(tmp_path, f'''
import os
from pathlib import Path
for mount in ('/work', '/tmp', '/home/sandbox', '/dev/shm'):
    stat = os.statvfs(mount)
    assert 0 < stat.f_blocks * stat.f_frsize <= {limits.storage_bytes}
for path in ('/outside', '/source/outside', '/dev/outside'):
    try:
        Path(path).touch()
    except OSError:
        pass
    else:
        raise AssertionError(path)
''')
    assert result.returncode == 0, result.stderr


@pytest.mark.parametrize('probe', ['cpu', 'memory', 'processes', 'storage', 'output'])
def test_resource_failures_cannot_score(tmp_path, monkeypatch, probe):
    repo = tmp_path / 'repo'
    (repo / 'apex/core').mkdir(parents=True)
    (repo / 'tests').mkdir()
    (repo / 'apex/core/loop.py').write_text('VALUE = 1\n')
    (repo / 'tests/test_ok.py').write_text('def test_ok(): assert True\n')
    subprocess.run(['git', 'init', '-q', str(repo)], check=True)
    subprocess.run(['git', 'add', '.'], cwd=repo, check=True)
    subprocess.run(['git', '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-qm', 'fixture'], cwd=repo, check=True)
    tasks = tmp_path / 'tasks.json'
    tasks.write_text('[]')
    code = {
        'cpu': 'import time; end=time.process_time()+3\nwhile time.process_time()<end: pass',
        'memory': 'blocks=[bytearray(8*1024**2) for _ in range(32)]',
        'processes': "import subprocess,sys; children=[subprocess.Popen([sys.executable,'-c','import time; time.sleep(3)'],start_new_session=True) for _ in range(32)]",
        'storage': "f=open('large','wb'); [f.write(b'x'*1024**2) for _ in range(64)]; f.close()",
        'output': "print(' '*65536)",
    }[probe] + '\nprint(\'{"apex_score": 0.9}\')'
    monkeypatch.setattr(rsi, 'REPO_ROOT', repo)
    monkeypatch.setattr(rsi, 'BENCH_CMD', [sys.executable, '-c', code])
    calls, scratches = [], []
    original_run = sandbox.run

    def run(command, scratch, **kwargs):
        calls.append(command)
        scratches.append(scratch)
        if command[1:3] == ['-m', 'pytest']:
            return original_run(command, scratch, **kwargs)
        with monkeypatch.context() as patcher:
            patcher.setattr(sandbox, 'DEFAULT_LIMITS', dataclasses.replace(
                sandbox.DEFAULT_LIMITS, cpu_percent=25, memory_bytes=128*1024**2,
                tasks=16, storage_bytes=16*1024**2, output_bytes=32768))
            return original_run(command, scratch, timeout=2 if probe == 'cpu' else 10)

    monkeypatch.setattr(rsi, '_run_candidate_process', run)
    patch = '--- a/apex/core/loop.py\n+++ b/apex/core/loop.py\n@@ -1 +1 @@\n-VALUE = 1\n+VALUE = 2\n'
    assert rsi._run_candidate(0, patch, str(tasks), True, k=1) is None
    assert len(calls) == 2, 'regressions must pass before the exhaustion probe'
    assert all(not Path(scratch).exists() for scratch in scratches)
    assert (repo / 'apex/core/loop.py').read_text() == 'VALUE = 1\n'
    assert subprocess.check_output(['git', 'status', '--porcelain'], cwd=repo) == b''
    assert subprocess.check_output(['git', 'worktree', 'list', '--porcelain'], cwd=repo).count(b'worktree ') == 1


def test_memory_limit_is_aggregate_across_workers(tmp_path, limits):
    child = 'import time; block=bytearray(64*1024**2); time.sleep(3)'
    result = execute(tmp_path, f"import subprocess,sys; children=[subprocess.Popen([sys.executable,'-c',{child!r}]) for _ in range(4)]; [p.wait() for p in children]")
    assert result.returncode != 0, 'group OOM must reject even when only descendants allocate'
    assert list(tmp_path.iterdir()) == []


def test_task_limit_includes_threads(tmp_path, limits):
    result = execute(tmp_path, "import threading,time; [threading.Thread(target=time.sleep,args=(3,),daemon=True).start() for _ in range(32)]")
    assert result.returncode != 0
    assert list(tmp_path.iterdir()) == []


def test_small_file_metadata_is_memory_accounted(tmp_path, monkeypatch):
    monkeypatch.setattr(sandbox, 'DEFAULT_LIMITS', dataclasses.replace(
        sandbox.DEFAULT_LIMITS, memory_bytes=64*1024**2, storage_bytes=16*1024**2))
    # Zero-length files consume metadata, not data blocks. Finite upper bound
    # prevents this probe becoming a fork/disk bomb if enforcement regresses.
    result = execute(tmp_path, "import os\nfor n in range(200000): os.close(os.open(str(n),os.O_CREAT|os.O_WRONLY,0o600))", timeout=30)
    assert result.returncode != 0, 'tmpfs metadata must stay within cgroup memory'
    assert list(tmp_path.iterdir()) == []


def test_ignored_cpu_quota_fails_before_candidate(tmp_path, monkeypatch, limits):
    wrapper = tmp_path / 'wrong-quota'
    wrapper.write_text('''#!/bin/bash
args=("$@")
for i in "${!args[@]}"; do
  if [[ ${args[i]} == CPUQuota=* ]]; then args[i]=CPUQuota=100%; fi
done
exec /usr/bin/systemd-run "${args[@]}"
''')
    wrapper.chmod(0o700)
    original = sandbox.shutil.which
    monkeypatch.setattr(sandbox.shutil, 'which', lambda name, **kw: str(wrapper) if name == 'systemd-run' else original(name, **kw))
    with pytest.raises(sandbox.IsolationError, match='CPU quota was not applied'):
        execute(tmp_path, "print('candidate must not run')")


def test_control_socket_and_descriptors_are_not_inherited(tmp_path):
    result = execute(tmp_path, '''
import os
from pathlib import Path
assert 'DBUS_SESSION_BUS_ADDRESS' not in os.environ
assert 'XDG_RUNTIME_DIR' not in os.environ
assert not Path('/run').exists()
for name in os.listdir('/proc/self/fd'):
    if int(name) > 2:
        try:
            target = os.readlink('/proc/self/fd/' + name)
        except FileNotFoundError:
            continue  # listdir's temporary descriptor has already closed.
        raise AssertionError('inherited descriptor: ' + target)
''')
    assert result.returncode == 0, result.stderr


def test_nested_namespace_cannot_rewrite_cgroup_limits(tmp_path):
    # No dangerous allocation: attempt only to write the existing limit values.
    # nsdelegate must reject even these no-op writes at the namespace root.
    result = execute(tmp_path, '''
import ctypes, os
from pathlib import Path
libc = ctypes.CDLL(None, use_errno=True)
# NEWUSER | NEWNS | NEWCGROUP; privilege gained here must not bypass limits.
if libc.unshare(0x10000000 | 0x00020000 | 0x02000000) == 0:
    Path('cgroup').mkdir()
    if libc.mount(b'none', b'/work/cgroup', b'cgroup2', 0, None) == 0:
        for name in ('cpu.max', 'memory.max', 'pids.max'):
            path = Path('cgroup', name)
            value = path.read_text()
            try:
                path.write_text(value)
            except PermissionError:
                pass
            else:
                raise AssertionError('candidate can rewrite ' + name)
print('resource limits protected')
''')
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == 'resource limits protected'
