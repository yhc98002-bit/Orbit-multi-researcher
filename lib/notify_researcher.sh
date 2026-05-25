#!/usr/bin/env bash
set -euo pipefail

target="${ORBIT_RESEARCHER_TMUX_TARGET:-${ORBIT_RESEARCHER_SESSION:-researcher}:0.0}"
expected_commands="${ORBIT_RESEARCHER_EXPECTED_COMMANDS:-codex node}"
submit_keys="${ORBIT_NOTIFY_SUBMIT_KEYS:-Enter}"
submit_wait_seconds="${ORBIT_NOTIFY_SUBMIT_WAIT_SECONDS:-1}"
allow_nonempty_composer="${ORBIT_NOTIFY_ALLOW_NONEMPTY_COMPOSER:-1}"
buffer_name=""

cleanup() {
  if [ -n "$buffer_name" ]; then
    tmux delete-buffer -b "$buffer_name" 2>/dev/null || true
  fi
}
trap cleanup EXIT

usage() {
  printf 'Usage: %s "single-line notice message"\n' "$0" >&2
}

if [ "$#" -ne 1 ]; then
  usage
  exit 2
fi

message="$1"
message="$(printf '%s' "$message" | tr '\r\n' '  ' | sed 's/[[:space:]][[:space:]]*/ /g')"
if [ -z "$message" ]; then
  printf 'orbit_notify_researcher: empty message\n' >&2
  exit 2
fi

if ! command -v tmux >/dev/null 2>&1; then
  printf 'orbit_notify_researcher: tmux is not available\n' >&2
  exit 3
fi

if ! tmux has-session -t "${target%%:*}" 2>/dev/null; then
  printf 'orbit_notify_researcher: tmux session missing for target %s\n' "$target" >&2
  exit 3
fi

pane_info="$(tmux display-message -p -t "$target" '#{session_name}:#{window_index}.#{pane_index}:#{pane_current_command}' 2>/dev/null || true)"
if [ -z "$pane_info" ]; then
  printf 'orbit_notify_researcher: tmux pane missing for target %s\n' "$target" >&2
  exit 3
fi

pane_command="${pane_info##*:}"
command_ok=0
for expected_command in $expected_commands; do
  if [ "$pane_command" = "$expected_command" ]; then
    command_ok=1
    break
  fi
done

if [ "$command_ok" -ne 1 ]; then
  printf 'orbit_notify_researcher: target command %s not in expected set [%s] for pane %s\n' "$pane_command" "$expected_commands" "$pane_info" >&2
  exit 3
fi

current_composer() {
  tmux capture-pane -pt "$target" -S -80 2>/dev/null \
    | awk '
      /^› / { block=$0 ORS; in_composer=1; next }
      in_composer && $0 == "" { in_composer=0; next }
      in_composer && /^  / { block=block $0 ORS; next }
      in_composer { in_composer=0; next }
      END { printf "%s", block }
    '
}

composer_text="$(current_composer | sed -E 's/[[:space:]]+/ /g; s/^› ?//; s/^ //; s/ $//')"
if [ "$allow_nonempty_composer" != "1" ] && [ -n "$composer_text" ]; then
  printf 'orbit_notify_researcher: composer not empty for target %s; refusing to append notice without ORBIT_NOTIFY_ALLOW_NONEMPTY_COMPOSER=1\n' "$target" >&2
  exit 4
fi

buffer_name="orbit_notify_${USER:-user}_$$"
tmux set-buffer -b "$buffer_name" -- "$message"
tmux paste-buffer -t "$target" -b "$buffer_name"
tmux delete-buffer -b "$buffer_name" 2>/dev/null || true
buffer_name=""
sleep 0.1
for submit_key in $submit_keys; do
  tmux send-keys -t "$target" "$submit_key"
done
sleep "$submit_wait_seconds"

needle="$(printf '%s' "$message" | cut -c1-80)"
if current_composer | grep -F -- "$needle" >/dev/null 2>&1; then
  printf 'orbit_notify_researcher: notice still visible in composer after submit keys [%s] for target %s; not submitted_or_queued\n' "$submit_keys" "$target" >&2
  exit 5
fi

printf 'orbit_notify_researcher: sent target=%s submit_keys=%s mode=submit_or_queue_verified\n' "$target" "$submit_keys"
