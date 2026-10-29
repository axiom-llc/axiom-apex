# AXIOM Platform Packages

APEX integrates advanced AI execution, policy enforcement, durable orchestration and HTTP transport in one engineering workspace.

| Package | Responsibility | Version |
| --- | --- | --- |
| [ASON](ason/) | Pre-execution policy and exact-plan authorization |0.3.0 |
| [Harness](harness/) | Durable task/lease/attempt orchestration and accepted-result commits |0.1.0 |
| [API](api/) | HTTP transport, retry policy, throttling and credential-header controls |0.1.1 |

Each package retains its installation metadata, import names, tests and MIT license. [Source provenance](SOURCES.json) records every imported file and its original revision.

## Install the platform from source

Use matching sibling RAG1.5.0 and this APEX3.2.0 source checkout with Python3.11 or3.12:

```bash
python -m pip install ../axiom-rag -e . -e packages/ason -e packages/harness -e packages/api 'pytest>=8' 'responses>=0.25'
python -m pip check
```

Run each suite in a separate process:

```bash
python -m pytest packages/ason/ason/tests -q
python -m unittest discover -s packages/harness/tests -v
python -m pytest packages/api/tests -q
```

The [platform workflow](../.github/workflows/platform.yml) builds and installs matching wheels and runs the packages outside source directories. APEX remains the execution owner; ASON owns plan policy, Harness owns task orchestration and RAG owns storage.
