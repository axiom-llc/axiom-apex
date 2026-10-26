# APEX rsi

[← Project overview](../README.md) · Commands below run from the repository root.

## RSI experiment

Run RSI from a clean source checkout with development dependencies installed (`pip install -e ".[dev]"`); its regression gate requires pytest. Use a working tree you can discard or review. Let each cycle benchmark a baseline, ask the configured LLM provider for candidate unified diffs, use Git’s patch parser to reject candidates outside the allowed files, binary changes, file creation/deletion, renames/copies, mode changes, or blocked shell patterns, require each candidate to pass offline regression tests before benchmarking in a scratch worktree, and commit the selected candidate to `rsi/cycle-N`.

Candidate tests and each benchmark invocation have a 300-second timeout. Failed tests, failed benchmark processes, and invalid/non-finite scores are ineligible for selection. Candidate regressions and benchmarks share a Linux Bubblewrap boundary; install Bubblewrap 0.9+ with `--size` support (for example, `sudo apt-get install bubblewrap` on Ubuntu 24.04) and enable unprivileged user namespaces. Isolation setup failures abort RSI with a diagnostic; there is no unrestricted fallback.

The sandbox exposes the disposable worktree read-only at `/source` and copies it into private, size-limited tmpfs at `/work`, with read-only system executable/library directories and the active Python runtime's `bin`, `lib`, and venv configuration. Install dependencies as packages in that runtime: editable dependencies pointing to other checkouts are deliberately inaccessible. The real repository, host home contents, credentials, and privileged sockets are not mounted. `/tmp` and `HOME` are private temporary filesystems; the sandbox root and `/proc` are read-only. A positive environment allowlist supplies deterministic runtime settings, and inherited descriptors and standard input are closed.

Separate network and PID namespaces block host loopback/external connections and contain descendants, including detached children. Bubblewrap's PID-1 reaper and parent-death handling tear down descendants on exit; the executor also kills the process group on timeout or Python interruption. Candidate benchmarks are offline: provider credentials and network access are never forwarded. Network-enabled evaluation would need a separately designed capability.

The host suite and APEX CI run real isolation probes, including a full valid-candidate regression/benchmark smoke test. Tests marked `host_isolation` require a host outside the boundary and are excluded only from recursive candidate regression runs; all other offline regressions remain mandatory. This boundary relies on the Linux kernel, systemd user manager, and trusted installed runtime/Bubblewrap.

Each regression or benchmark invocation starts in its own unprivileged systemd scope on cgroup v2. The trusted launcher verifies the actual kernel limits before executing Bubblewrap; missing user-manager access, controller delegation, or limits fail closed. Operators must provide a running user manager with `cpu`, `memory`, and `pids` delegated, and the cgroup-v2 mount must enable `nsdelegate` so nested namespaces cannot rewrite their resource limits. On a dedicated CI host, configure a `user@UID.service` drop-in with `[Service]` and `Delegate=cpu memory pids`, reload systemd, and start/restart that user manager. The workflow uses a temporary `/run/systemd/system` drop-in and Ubuntu 24.04 for the required Bubblewrap version. It also loads a bwrap-specific AppArmor user-namespace allowance so the trusted sandbox builder can configure its namespaces. Candidate code never receives the manager's socket or credentials.

| Resource | Default per invocation |
| --- | --- |
| Aggregate CPU rate | 100% of one CPU, shared by all workers |
| Wall time | 300 seconds, including setup and output draining |
| Cgroup memory | 1 GiB including descendants and charged kernel/tmpfs memory |
| Swap | Disabled for the candidate cgroup |
| Processes and threads | 256 total tasks, including sandbox helpers |
| Writable candidate files | 256 MiB private `/work` tmpfs |
| Temporary files | 64 MiB private `/tmp` tmpfs |
| Home / shared memory | 16 MiB each at `HOME` and `/dev/shm` |
| Captured stdout + stderr | 1 MiB combined, then termination and rejection |
| Open descriptors / core dumps | 1,024 per process / disabled |

A group OOM kills the whole evaluation. Timeouts, output excess, exceptions, and controller death retain descendant cleanup. Nonzero resource failures and output-limit exceptions cannot produce eligible scores. Source worktrees remain unchanged during execution and are removed by RSI afterward; writable changes in tmpfs are discarded after each invocation. Benchmarks therefore begin from the same patched source, rather than retaining regression or prior-benchmark writes.

CPU quota bounds aggregate rate, not exclusive CPU access; the wall timeout bounds duration, with normal scheduler/period granularity. There is no separate numeric inode quota: tmpfs metadata is charged to the cgroup memory limit and covered by a small-file exhaustion probe. The trusted Git snapshot and installed read-only runtime remain host-managed storage. Additional private mounts, if created in nested namespaces, remain subject to the aggregate 1 GiB cgroup memory ceiling; the table lists the initial tmpfs capacities. Limits apply per invocation, not across independent RSI controllers. No network-enabled or unrestricted resource bypass is provided.

Do not auto-merge RSI branches. Review every candidate manually. Keep `apex/core/safety.py` outside the patchable set.

