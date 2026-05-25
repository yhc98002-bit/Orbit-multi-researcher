# ORBIT Agent Deployment

ORBIT Agent packages the tmux-backed Codex multi-agent workflow into a reusable
Linux deployment. Version 1 targets a fixed three-role topology:
Researcher, Executor, and Helper.

## Requirements

- Linux shell environment.
- `bash`, `tmux`, `python3`, `sha256sum`, `awk`, `sed`.
- Codex CLI installed and authenticated on the target server.
- Claude CLI is optional but recommended for review-gated workflows.

## Install From This Checkout

```bash
export PATH="/path/to/AudioDiffusion/tools/orbit-agent/bin:$PATH"
orbit init --workspace /path/to/project
orbit doctor
orbit launch --dry-run
orbit launch
```

Or install a symlink into `~/.local/bin`:

```bash
/path/to/AudioDiffusion/tools/orbit-agent/install.sh
export PATH="$HOME/.local/bin:$PATH"
```

The default state directory is `~/.codex/orbit`. Override it with:

```bash
export ORBIT_HOME=/path/to/orbit-state
```

## Core Commands

```bash
orbit status
orbit peek executor
orbit send executor "Please inspect the failing test and ACK first."
orbit send-file helper /path/to/task.md
orbit notify researcher --from helper --type task_completion "analysis completed"
orbit role-prompt researcher
```

## Message Delivery Model

- Short single-line messages can be pasted directly into the target Codex pane.
- `[Task assigned by Researcher]`, multiline, and long messages are always written
  to `$ORBIT_HOME/comm/inbox/<agent>/..._payload.md`.
- Workers receive only a pointer containing `file_sha256` and `file_bytes`.
- Worker notifications append durable records under
  `$ORBIT_HOME/comm/outbox/` before attempting tmux delivery.

Durable inbox/outbox files are the source of truth when tmux delivery is blocked
or uncertain.

## What Not To Copy Between Servers

Do not copy machine-local Codex state such as `auth.json`, session databases,
experiment outputs, or old outbox logs. Install the framework scripts and run
`orbit init` on each server.

## Project-Specific Watchers

Keep experiment watchers as project profiles or examples. The core framework
does not know about GPUs, paper constraints, reward definitions, or experiment
schemas.
