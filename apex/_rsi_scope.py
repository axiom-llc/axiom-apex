"""Trusted pre-exec cgroup verification; invoked with Python -I -S, never imported by candidates."""
import base64
import ctypes
import json
import os
from pathlib import Path
import resource
import signal
import sys


def main():
    mode, encoded = sys.argv[1:]
    config = json.loads(base64.b64decode(encoded))
    parent = os.getppid()
    if parent == 1 or (mode == 'launch' and parent != config['parent']):
        raise RuntimeError('controller exited during resource setup')
    # Preserve the parent-death chain across systemd-run and exec into Bubblewrap.
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(1, signal.SIGKILL, 0, 0, 0) != 0 or os.getppid() != parent:
        raise RuntimeError('cannot establish parent-death cleanup')
    if mode == 'launch':
        args = [config['systemd'], '--user', '--scope', '--quiet', '--collect',
                '--unit=' + config['unit'], '--description=APEX RSI candidate',
                '-p', f"CPUQuota={config['cpu_percent']}%",
                '-p', f"MemoryMax={config['memory_bytes']}",
                '-p', 'MemorySwapMax=0', '-p', f"TasksMax={config['tasks']}",
                '--', sys.executable, '-I', '-S', __file__, 'verify', encoded]
        os.execve(args[0], args, {'XDG_RUNTIME_DIR': f'/run/user/{os.getuid()}',
                                 'DBUS_SESSION_BUS_ADDRESS': f'unix:path=/run/user/{os.getuid()}/bus',
                                 'LANG': 'C.UTF-8'})
    if mode != 'verify':
        raise RuntimeError('invalid resource setup mode')
    membership = Path('/proc/self/cgroup').read_text().strip()
    if not membership.startswith('0::/') or '\n' in membership:
        raise RuntimeError('RSI requires unified cgroup v2')
    mounts = [line.split() for line in Path('/proc/self/mountinfo').read_text().splitlines()]
    if not any(fields[4] == '/sys/fs/cgroup' and 'cgroup2' in fields
               and 'nsdelegate' in fields[-1].split(',') for fields in mounts):
        raise RuntimeError('RSI requires cgroup v2 nsdelegate to protect resource limits')
    group = Path('/sys/fs/cgroup') / membership[4:]
    if group.name != config['unit']:
        raise RuntimeError('candidate was not placed in its resource scope')
    quota, period = (group / 'cpu.max').read_text().split()
    if quota == 'max' or int(quota) * 100 > config['cpu_percent'] * int(period):
        raise RuntimeError('aggregate CPU quota was not applied')
    for name, expected in [('memory.max', config['memory_bytes']),
                           ('memory.swap.max', 0), ('pids.max', config['tasks'])]:
        actual = (group / name).read_text().strip()
        if actual == 'max' or int(actual) > expected:
            raise RuntimeError(f'{name} limit was not applied')
    # A cgroup OOM must terminate the whole evaluation, not just one worker.
    (group / 'memory.oom.group').write_text('1')
    if (group / 'memory.oom.group').read_text().strip() != '1':
        raise RuntimeError('group OOM termination was not applied')
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    resource.setrlimit(resource.RLIMIT_NOFILE, (1024, 1024))
    os.write(2, b'axiom-rsi: limits established\n')
    os.execve(config['cmd'][0], config['cmd'], {})


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(f'RSI resource setup failed: {exc}', file=sys.stderr)
        sys.exit(125)
