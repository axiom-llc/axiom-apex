"""Private Linux execution boundary for RSI evaluations (Bubblewrap required)."""
from pathlib import Path
from dataclasses import dataclass, asdict
import base64
import json
import selectors
import time
import uuid
import os
import shutil
import signal
import subprocess
import sys


class IsolationError(RuntimeError):
    """Required candidate isolation could not be established."""


@dataclass(frozen=True)
class ResourceLimits:
    cpu_percent: int = 100
    memory_bytes: int = 1024**3
    tasks: int = 256
    storage_bytes: int = 256 * 1024**2
    output_bytes: int = 1024**2


DEFAULT_LIMITS = ResourceLimits()


class ResourceLimitError(RuntimeError):
    """The candidate exceeded a resource limit."""


def _capture(process, cmd, timeout, limit):
    deadline = time.monotonic() + timeout
    output = [bytearray(), bytearray()]
    total = 0
    with selectors.DefaultSelector() as selector:
        for index, stream in enumerate((process.stdout, process.stderr)):
            selector.register(stream, selectors.EVENT_READ, index)
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(cmd, timeout)
            for key, _ in selector.select(min(remaining, 0.1)):
                chunk = os.read(key.fd, min(65536, limit - total + 1))
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                total += len(chunk)
                if total > limit:
                    raise ResourceLimitError(f'RSI candidate output exceeded {limit} bytes')
                output[key.data].extend(chunk)
        process.wait(timeout=max(0, deadline - time.monotonic()))
    return tuple(data.decode('utf-8', errors='replace') for data in output)


def run(cmd: list[str], scratch: str, timeout: float = 300) -> subprocess.CompletedProcess:
    policy = DEFAULT_LIMITS
    if any(type(value) is not int or value <= 0 for value in asdict(policy).values()):
        raise IsolationError('RSI resource limits must be positive integers')
    systemd = shutil.which('systemd-run', path='/usr/bin:/bin')
    if systemd is None:
        raise IsolationError('RSI requires systemd user scopes and cgroup v2; no unrestricted fallback')
    bwrap = shutil.which('bwrap', path='/usr/bin:/bin')
    if sys.platform != 'linux' or bwrap is None:
        raise IsolationError('RSI requires Linux and Bubblewrap; no unsandboxed fallback')
    try:
        root = Path(scratch).resolve(strict=True)
    except OSError as exc:
        raise IsolationError('RSI scratch directory is unavailable') from exc
    if not root.is_dir():
        raise IsolationError('RSI scratch directory is unavailable')
    # System executables/libraries and this interpreter's installed runtime only.
    # Never bind /, /home, /tmp, /run, /etc, or a source checkout wholesale.
    runtime = [Path(p) for p in ('/usr/bin', '/usr/lib', '/usr/lib64', '/bin', '/lib', '/lib64')]
    runtime += [Path(prefix) / part for prefix in (sys.base_prefix, sys.prefix)
                for part in ('bin', 'lib', 'lib64')]
    # A venv needs its configuration, but never its containing checkout.
    runtime += [Path(sys.prefix) / 'pyvenv.cfg']
    mounts = []
    for path in runtime:
        if path.exists() and path not in mounts:
            resolved = path.resolve(strict=True)
            if resolved in (Path('/'), Path('/home'), Path('/tmp'), Path.home()) or root.is_relative_to(resolved):
                raise IsolationError('RSI requires a runtime separate from the candidate checkout')
            mounts.append(path)
    args = [bwrap, '--unshare-user', '--unshare-pid', '--unshare-net', '--unshare-ipc',
            '--unshare-uts', '--unshare-cgroup', '--die-with-parent', '--new-session',
            '--cap-drop', 'ALL', '--clearenv',
            '--size', str(policy.storage_bytes), '--tmpfs', '/work',
            '--size', str(min(policy.storage_bytes, 64 * 1024**2)), '--tmpfs', '/tmp',
            '--size', str(min(policy.storage_bytes, 16 * 1024**2)), '--tmpfs', '/home/sandbox']
    for path in mounts:
        args += ['--ro-bind', str(path), str(path)]
    if Path('/etc/ld.so.cache').exists():
        args += ['--ro-bind', '/etc/ld.so.cache', '/etc/ld.so.cache']
    args += ['--proc', '/proc', '--remount-ro', '/proc', '--dev', '/dev',
             '--remount-ro', '/dev', '--size', str(min(policy.storage_bytes, 16 * 1024**2)),
             '--tmpfs', '/dev/shm', '--ro-bind', str(root), '/source', '--chdir', '/work']
    # Hide the worktree's pointer to the host Git database, even as metadata.
    if (root / '.git').exists():
        args += ['--ro-bind', '/dev/null', '/source/.git']
    args += ['--remount-ro', '/']
    env = {'PATH': f'{Path(sys.executable).parent}:/usr/bin:/bin',
           'HOME': '/home/sandbox', 'TMPDIR': '/tmp', 'LANG': 'C.UTF-8',
           'LC_ALL': 'C.UTF-8', 'TZ': 'UTC', 'PYTHONHASHSEED': '0',
           'PYTHONDONTWRITEBYTECODE': '1'}
    for key, value in env.items():
        args += ['--setenv', key, value]
    # Copy only into size-limited private tmpfs. No writable host bind remains.
    bootstrap = (
        "import os,shutil,sys; "
        "shutil.copytree('/source','/work',dirs_exist_ok=True,symlinks=True,"
        "ignore=shutil.ignore_patterns('.git')); "
        "os.execv(sys.argv[1],sys.argv[1:])"
    )
    args += ['--', sys.executable, '-I', '-S', '-c', bootstrap, *cmd]
    config = dict(asdict(policy), systemd=systemd, unit=f'axiom-rsi-{uuid.uuid4().hex}.scope',
                  parent=os.getpid(), cmd=args)
    encoded = base64.b64encode(json.dumps(config).encode()).decode()
    launch = [sys.executable, '-I', '-S', str(Path(__file__).with_name('_rsi_scope.py')),
              'launch', encoded]
    try:
        # No terminal, host input, inherited sockets, proxy settings or credentials.
        with subprocess.Popen(launch, cwd='/', env={}, stdin=subprocess.DEVNULL,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              close_fds=True, start_new_session=True) as process:
            try:
                stdout, stderr = _capture(process, cmd, timeout, policy.output_bytes)
            except BaseException:
                # Bubblewrap's trusted PID-1 reaper anchors all descendants, including
                # setsid children. Killing it tears down the entire PID namespace.
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
                raise
    except OSError as exc:
        raise IsolationError('RSI could not start Bubblewrap') from exc
    banner = 'axiom-rsi: limits established\n'
    if not stderr.startswith(banner):
        raise IsolationError(f'RSI resource setup failed: {stderr.strip()}')
    stderr = stderr[len(banner):]
    if process.returncode and stderr.startswith('bwrap:'):
        raise IsolationError(f'RSI isolation setup failed: {stderr.strip()}')
    return subprocess.CompletedProcess(cmd, process.returncode, stdout, stderr)
