# APEX: Agent Process Executor
## Version 1.0
A pure functional CLI agent for deterministic task execution. Built for advanced users who automate everything.

## Features

APEX provides deterministic execution where identical inputs produce identical results, making it reliable for automation workflows and reproducible task sequences. The system maintains a minimal footprint of 395 lines of code with zero runtime configuration, eliminating the complexity typically associated with agent frameworks. The architecture is shell-centric, leveraging the full capabilities of the underlying shell for complex workflows while maintaining functional purity in the core execution logic. Memory persistence is implemented through SQLite-backed storage, enabling cross-session state management and long-term workflow coordination. The planning layer uses Gemini 2.5 Flash to generate execution plans from natural language input, translating user intent into deterministic tool invocations.

## Architecture

The system is organized into six primary modules that maintain strict separation of concerns. The binary entry point at `bin/apex` handles command-line invocation and delegates to the core execution logic. The core module contains the main execution loop in `loop.py`, the LLM-powered planner in `planner.py`, immutable state management in `state.py`, and type definitions in `types.py`. The LLM provider interface in `llm/providers.py` abstracts the Gemini integration to enable future provider extensions. Tool implementations reside in the tools module, with `basic.py` containing core effect implementations for shell execution, file operations, HTTP requests, and memory operations, while `registry.py` manages tool registration and discovery. The memory persistence layer in `memory/sqlite.py` handles all database operations for cross-session state storage. System prompts are maintained in the prompts directory, with `system.txt` providing core instructions to the LLM and `planner.txt` offering planning guidance for task decomposition.

```
apex/
├── bin/apex           # CLI entry point
├── core/              # Pure functional execution logic
│   ├── loop.py        # Main execution loop
│   ├── planner.py     # LLM plan generation
│   ├── state.py       # Immutable state management
│   └── types.py       # Type definitions
├── llm/               # LLM provider interface
│   └── providers.py   # Gemini integration
├── tools/             # Effect implementations
│   ├── basic.py       # Core tools (shell, file I/O, HTTP)
│   └── registry.py    # Tool registration
├── memory/            # Persistence layer
│   └── sqlite.py      # SQLite memory operations
└── prompts/           # System prompts
    ├── system.txt     # Core instructions
    └── planner.txt    # Planning guidance
```

## Installation

APEX requires Python 3.11 or later, runs on Arch Linux x86_64 systems, and needs a Google Gemini API key for LLM-powered planning. The installation process involves cloning the repository, creating a Python virtual environment, installing dependencies, and configuring environment variables. The binary must be added to the system PATH to enable global command access.

```bash
git clone https://github.com/axiom-llc/apex.git
cd apex
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt

export GEMINI_API_KEY='your-api-key-here'
export PATH="$PATH:$(pwd)/bin"
```

## Usage

APEX accepts natural language commands and translates them into deterministic execution plans. The system supports file operations for creating and manipulating documents, HTTP requests for data retrieval, data processing workflows for log analysis and transformation, system automation tasks for backups and maintenance, memory operations for persistent state storage, and GitHub integration for repository management and version control operations.

```bash
# File Operations
apex "create ~/report.txt with system info and today's date"
apex "read ~/config.json and display its contents"
apex "write performance metrics to ~/metrics.txt with timestamp header"
apex "copy all markdown files from ~/docs to ~/docs-backup preserving structure"

# HTTP Requests
apex "fetch https://api.github.com/users/octocat and save to ~/user.json"
apex "download the latest release info from https://api.github.com/repos/torvalds/linux/releases/latest"
apex "retrieve weather data from wttr.in for New York and save to ~/weather.txt"
apex "fetch cryptocurrency prices from coinbase API and extract Bitcoin value"

# Data Processing
apex "analyze ~/logs/app.log for ERROR lines and count them"
apex "parse ~/data.csv and calculate average of the third column"
apex "extract all email addresses from ~/contacts.txt and save to ~/emails.txt"
apex "count total lines of code in all Python files under ~/project directory"

# System Automation
apex "backup ~/documents to ~/backups with timestamp"
apex "archive all log files older than 7 days in ~/logs directory"
apex "monitor disk usage and write report to ~/disk-status.txt"
apex "compress ~/project directory into ~/archives with current date in filename"

# Memory Operations
apex "save current git branch to memory as active_branch"
apex "read from memory the active_branch value"
apex "store system hostname and kernel version in memory as system_identity"
apex "retrieve all stored memory keys and save list to ~/memory-index.txt"

# GitHub Integration
apex "create new public GitHub repository named project with description 'My Project'"
apex "list all repositories for authenticated user and count them"
apex "fetch open issues from repository torvalds/linux and save titles to ~/issues.txt"
apex "check GitHub authentication status and display user information"

# Development Workflows
apex "find all .py files in ~/project, count total lines, and save to memory"
apex "run pytest on ~/project/tests and capture pass/fail summary"
apex "generate requirements.txt from current Python environment"
apex "search all TODO comments in ~/project source files and compile to ~/todos.txt"

# Security and Validation
apex "generate SHA256 checksums for all files in ~/downloads and save manifest"
apex "verify GPG signature of ~/package.tar.gz using system keyring"
apex "scan ~/scripts directory for shell scripts and check for shellcheck violations"
apex "audit file permissions in ~/sensitive directory and report any world-readable files"
```

## Design Principles

The architecture maintains functional purity in the core logic while isolating all effects to tool implementations. This separation ensures that the execution engine remains deterministic and testable while delegating impure operations to well-defined boundaries. State management is explicit through immutable state objects, with updates performed using `dataclasses.replace()` to create new state instances rather than mutating existing ones. The system enforces determinism by prohibiting dynamic configuration, plugin discovery, and runtime extension mechanisms that would introduce non-deterministic behavior. Minimalism is maintained through a constraint of fifteen or fewer public functions across nine modules, ensuring that the codebase remains comprehensible and maintainable.

## Tools

The tool registry provides six core capabilities that cover the majority of automation workflows. The shell tool executes arbitrary commands in the underlying shell environment, enabling access to the full Unix toolchain. The read_file and write_file tools handle file system operations for content retrieval and persistence. The http_get tool performs HTTP GET requests for external data retrieval. The memory_read and memory_write tools interface with the SQLite persistence layer for cross-session state management.

| Tool | Purpose | Example |
|------|---------|---------|
| `shell` | Execute commands | `ls -la`, `grep ERROR logs.txt`, `gh repo create` |
| `read_file` | Read file contents | `/home/user/config.json` |
| `write_file` | Write file contents | Save data to disk |
| `http_get` | HTTP GET requests | Fetch API data |
| `memory_read` | Query memory DB | Retrieve stored values |
| `memory_write` | Store to memory | Persist state |

## GitHub Integration

APEX integrates with GitHub through the GitHub CLI (`gh`), enabling comprehensive repository management, issue tracking, pull request workflows, and automation tasks directly from natural language commands. The system leverages your pre-configured GitHub authentication stored in the shell environment, requiring no additional credential management. Repository creation, cloning, and remote configuration are handled automatically through the shell tool's execution of git and gh commands.

The GitHub CLI provides access to the complete GitHub API surface through structured subcommands organized by resource type. Repository operations are available through `gh repo`, issue management through `gh issue`, pull request workflows through `gh pr`, and release operations through `gh release`. Each subcommand supports JSON output via the `--json` flag, enabling precise data extraction when combined with shell tools like `jq` for structured data processing.

Common GitHub workflows can be automated through single-command invocations. Repository initialization and setup can be completed by creating the remote repository, initializing the local git directory, and establishing the tracking relationship between them. Issue management workflows can fetch open issues, filter by labels or assignees, and compile reports for team review. Pull request automation can check approval status, run tests on PR branches, and compile validation results into structured reports. Release operations can tag versions, generate changelogs from commit history, and publish artifacts to GitHub releases.

## Constraints

The system enforces several architectural constraints to maintain determinism and simplicity. Execution plans are limited to a maximum of 32 steps to prevent unbounded computation and ensure reasonable completion times. Each tool invocation has a hard timeout of 300 seconds to prevent hanging operations from blocking the execution loop. Tool outputs are limited to 10 megabytes per invocation to prevent memory exhaustion from unbounded data retrieval. The architecture prohibits inter-step state passing, requiring that each step execute independently with no shared mutable state between invocations.

## Extending APEX

New tools can be added to the system by editing three files that define the tool implementation, register it in the global registry, and update the planner prompts to inform the LLM about the new capability. Tool definitions in `tools/basic.py` specify the effect function, input specification, and output specification. The registry in `tools/registry.py` maps tool names to their implementations for runtime lookup. The planner prompts in `prompts/planner.txt` document the tool's purpose and usage patterns for the LLM to reference during plan generation.

**Define tool in `tools/basic.py`:**

```python
def list_dir_effect(args: dict) -> dict:
    from pathlib import Path
    items = list(Path(args['path']).iterdir())
    return {'items': [str(i) for i in items], 'count': len(items)}

LIST_DIR = Tool(
    name='list_dir',
    input_spec={'path': str},
    output_spec={'items': list, 'count': int},
    effect=list_dir_effect
)
```

**Register tool in `tools/registry.py`:**

```python
REGISTRY = {
    'shell': SHELL,
    'list_dir': LIST_DIR,
    # ...
}
```

**Update prompts in `prompts/planner.txt`:**

```
- Use list_dir to enumerate directory contents when the user requests file listing operations
```

## Testing

The test suite validates 42 distinct scenarios covering core functionality, multi-step workflows, error handling, and edge cases. Basic functionality tests verify file creation, reading, and shell command execution. Multi-step workflow tests validate complex sequences such as creating multiple files, archiving them, and verifying the archive integrity. Error handling tests ensure that operations fail gracefully when encountering permission errors, missing files, or invalid input. GitHub integration tests validate repository creation, commit operations, and remote push workflows.

```bash
# Core functionality
apex "write hello to ~/test.txt"
apex "read ~/test.txt"

# Multi-step workflows
apex "create 5 files, archive them, verify archive"

# Error handling
apex "attempt to read /root/file.txt and handle the error"

# GitHub operations
apex "create new repository named test-repo with MIT license"
apex "initialize git in current directory and push to remote"
```

## Performance

Plan generation consumes approximately 1,000 tokens and completes in 100 to 500 milliseconds depending on query complexity and network latency to the Gemini API. Tool execution is bounded by the 300-second timeout per tool invocation, with most operations completing in under 5 seconds for typical file and shell operations. The SQLite memory layer supports a theoretical limit of 140 terabytes of persistent storage, though practical usage patterns typically consume less than 1 megabyte for workflow state management.

## Limitations

The architecture imposes several limitations that stem from the functional purity and determinism requirements. Inter-step data passing is not supported, requiring that complex workflows either use shell logic to chain operations within a single step or break tasks into multiple independent command invocations. The planner cannot generate conditional execution plans, requiring that conditional logic be implemented through shell constructs such as `[ -f file ] || create_file` rather than explicit branching in the plan. Workflow execution is strictly linear with no support for branching, asynchronous operations, or multi-agent coordination patterns.

## Workarounds

Several common workflow patterns can be achieved through shell composition despite the architectural limitations. Multi-step data flow operations that would typically require passing data between plan steps can be implemented by composing shell commands with pipes to perform the entire transformation in a single step. Conditional logic that would normally require branching in the execution plan can be implemented using shell test operators and logical combinators to achieve the same outcome within a single tool invocation.

**Multi-step data flow:**
```bash
# Instead of: fetch → extract → save (requires inter-step passing)
apex "fetch URL and pipe through jq to extract field into file"
```

**Conditional logic:**
```bash
# Instead of: if file exists then read else create (requires branching)
apex "check if file exists using shell test, create if missing with appropriate message"
```

## Production Use

APEX has been validated for cron jobs and scheduled automation where deterministic execution and minimal resource overhead are critical. The system is suitable for CI/CD pipeline tasks that require shell-centric operations and version control integration. System administration scripts benefit from the natural language interface while maintaining the full power of the underlying shell toolchain. Data processing workflows can leverage the HTTP and file tools for ETL operations with persistent state management through the memory layer.

The system is not suitable for interactive applications that require real-time user feedback or stateful sessions. Browser automation is not supported as the tool set does not include headless browser capabilities. Multi-user systems would require additional isolation mechanisms that are not present in the current architecture. Real-time event processing is constrained by the synchronous execution model and would be better served by event-driven architectures.

## License

MIT

## Contributing

Contributions follow a standard fork and pull request workflow. Fork the repository to your GitHub account, create a feature branch for your changes, add comprehensive tests for new functionality to maintain the 42+ test validation standard, and submit a pull request with a clear description of the changes and their rationale. All contributions must maintain the functional purity and determinism constraints documented in the design principles section.

## Credits

APEX is architected around a functional core with explicit effects and deterministic LLM orchestration, reflecting Axiom-LLC's adherence to [Arch Linux](https://archlinux.org/) and [suckless](https://suckless.org/) design principles: minimalism, composability, and explicit control.

---

**Status**: Production-ready v1.0 | 42/43 tests passing | 395 LOC | GitHub integration validated
