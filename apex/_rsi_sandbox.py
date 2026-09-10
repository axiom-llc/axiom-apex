"""Private Linux execution boundary for RSI evaluations (Bubblewrap required)."""
from pathlib import Path
import os
import shutil
import signal
import subprocess
import sys


class IsolationError(RuntimeError):
    """Required candidate isolation could not be established."""


def run(cmd: list[str], scratch: str, timeout: float = 300) -> subprocess.CompletedProcess:
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
            '--tmpfs', '/tmp', '--tmpfs', '/home/sandbox']
    for path in mounts:
        args += ['--ro-bind', str(path), str(path)]
    if Path('/etc/ld.so.cache').exists():
        args += ['--ro-bind', '/etc/ld.so.cache', '/etc/ld.so.cache']
    args += ['--proc', '/proc', '--remount-ro', '/proc', '--dev', '/dev',
             '--bind', str(root), '/work', '--chdir', '/work']
    # Hide the worktree's pointer to the host Git database, even as metadata.
    if (root / '.git').exists():
        args += ['--ro-bind', '/dev/null', '/work/.git']
    args += ['--remount-ro', '/']
    env = {'PATH': f'{Path(sys.executable).parent}:/usr/bin:/bin',
           'HOME': '/home/sandbox', 'TMPDIR': '/tmp', 'LANG': 'C.UTF-8',
           'LC_ALL': 'C.UTF-8', 'TZ': 'UTC', 'PYTHONHASHSEED': '0',
           'PYTHONDONTWRITEBYTECODE': '1'}
    for key, value in env.items():
        args += ['--setenv', key, value]
    args += ['--', *cmd]
    try:
        # No terminal, host input, inherited sockets, proxy settings or credentials.
        with subprocess.Popen(args, cwd='/', env={}, stdin=subprocess.DEVNULL,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              text=True, close_fds=True, start_new_session=True) as process:
            try:
                stdout, stderr = process.communicate(timeout=timeout)
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
    if process.returncode and stderr.startswith('bwrap:'):
        raise IsolationError(f'RSI isolation setup failed: {stderr.strip()}')
    return subprocess.CompletedProcess(cmd, process.returncode, stdout, stderr)
