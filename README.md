# Orbit Multi Researcher

Reusable tmux-backed Codex multi-agent framework for Linux servers.

Orbit packages a practical fixed three-agent workflow:

- `researcher`: decomposes user/PI goals, assigns work, checks rigor, and reports decisions.
- `executor`: runs implementation, experiments, environment fixes, and monitoring.
- `helper`: prepares verification, analysis, audit packets, templates, and summaries.

The framework is intentionally conservative. It standardizes communication,
durable inbox/outbox records, ACKs, low-frequency monitoring, and Claude review
policy without baking in project-specific experiment logic.

## Requirements

- Linux server with `bash`, `tmux`, `python3`, `awk`, `sed`, and `sha256sum`.
- Codex CLI installed and authenticated on that server.
- Optional but recommended: Claude CLI for independent review workflows.

Orbit does **not** copy or manage Codex authentication. Each server should have
its own working Codex login before launching agents.

## Install

Clone this repository:

```bash
git clone https://github.com/yhc98002-bit/Orbit-multi-researcher.git
cd Orbit-multi-researcher
```

Use Orbit directly from the checkout:

```bash
export PATH="$PWD/bin:$PATH"
```

Or install a symlink into `~/.local/bin`:

```bash
./install.sh
export PATH="$HOME/.local/bin:$PATH"
```

## Quick Start

Initialize Orbit for a project workspace:

```bash
orbit init --workspace /path/to/project
```

Run deployment checks:

```bash
orbit doctor
```

Preview tmux launches without starting anything:

```bash
orbit launch --dry-run
```

Start the three Codex sessions:

```bash
orbit launch
```

Check sessions:

```bash
orbit status
```

Send a task:

```bash
orbit send executor "Please ACK and inspect the current failing job."
```

Send a longer task from a file:

```bash
orbit send-file helper /path/to/task.md
```

Worker-style notification back to Researcher:

```bash
orbit notify researcher --from helper --type task_completion "analysis completed"
```

## Core Commands

```bash
orbit init --workspace PATH [--orbit-home PATH] [--codex-home PATH] [--force]
orbit launch [--dry-run]
orbit status
orbit peek researcher|executor|helper
orbit send executor|helper "message"
orbit send-file executor|helper /path/to/message.md
orbit queue executor|helper "message"
orbit notify researcher --from helper|executor|watcher [--type TYPE] [--severity LEVEL] "message"
orbit doctor
orbit role-prompt researcher|executor|helper
```

## Directory Layout

After `orbit init`, the default state directory is:

```text
~/.codex/orbit/
  config.toml
  comm/
    inbox/
      executor/
      helper/
    outbox/
  logs/
  payloads/
  state/
  templates/
```

Override the state directory with:

```bash
export ORBIT_HOME=/path/to/orbit-state
```

## Message Delivery Model

Orbit is designed around durable communication, because terminal UI delivery can
fail or leave text stuck in a composer.

- Short single-line messages may be sent directly to the target tmux pane.
- `[Task assigned by Researcher]`, multiline, and long messages are always
  written to `$ORBIT_HOME/comm/inbox/<agent>/..._payload.md`.
- Workers receive only a short pointer containing `file_sha256` and `file_bytes`.
- Worker notifications append JSONL records under `$ORBIT_HOME/comm/outbox/`
  before attempting tmux delivery.
- Durable inbox/outbox files are the source of truth if tmux delivery is blocked.

## Agent Workflow

Recommended Researcher flow:

1. Convert user intent into a bounded task.
2. Use `orbit send` or `orbit send-file` to assign it.
3. Require a one-line ACK before worker action for important tasks.
4. Poll fast only for fresh tasks or active debugging.
5. For stable long-running jobs, wait for completion/P0 outbox notifications.
6. Report unfinished work as unfinished; do not overstate conclusions.

Recommended worker flow:

1. Read the task pointer file from inbox.
2. ACK the task and boundaries.
3. Do only the assigned work.
4. Write durable reports/artifacts.
5. Notify Researcher with `orbit notify researcher --from <role> ...`.

## Claude Review Policy

The default profile records this Claude CLI review command:

```bash
claude -p \
  --dangerously-skip-permissions \
  --output-format json \
  --model opus \
  --effort max \
  "your prompt"
```

Use Claude review for substantive implementation, experiment execution, metric
computation, or result interpretation. For simple low-risk status checks or
file inspection, workers may skip review but should state the skip reason.

## Deploying On A New Server

1. Install and authenticate Codex CLI on the new server.
2. Clone this repository.
3. Add `bin/` to `PATH` or run `./install.sh`.
4. Run `orbit init --workspace /path/to/project`.
5. Run `orbit doctor`.
6. Run `orbit launch --dry-run`.
7. Run `orbit launch`.

Do **not** copy machine-local Codex state such as `auth.json`, Codex session
databases, old inbox/outbox logs, or experiment outputs between servers.

## Project-Specific Watchers

Orbit core does not know about GPUs, paper constraints, reward definitions,
evaluation splits, or experiment schemas. Keep those as project-specific
watchers or profiles.

A watcher can report through:

```bash
orbit notify researcher --from watcher --type watcher_event --severity stage "checkpoint reached"
```

See `examples/watchers/` for the intended pattern.

## Troubleshooting

Check basic health:

```bash
orbit doctor
orbit status
```

Inspect a worker pane:

```bash
orbit peek executor
orbit peek helper
```

If a notification does not appear in the Researcher pane, inspect durable
outbox files:

```bash
ls -lt "$ORBIT_HOME/comm/outbox"
tail -n 20 "$ORBIT_HOME/comm/outbox/helper_to_researcher.jsonl"
```

If a long task was sent, inspect the worker inbox:

```bash
find "$ORBIT_HOME/comm/inbox" -type f -maxdepth 3 -print
```

If `git` or other commands fail because of a server proxy, fix the server
network configuration outside Orbit; Orbit does not manage network proxies.
