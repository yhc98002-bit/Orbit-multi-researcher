#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  tmux_comm.sh status
  tmux_comm.sh peek helper|executor|researcher
  tmux_comm.sh send helper|executor "message"
  tmux_comm.sh send-file helper|executor /path/to/message.md
  tmux_comm.sh queue helper|executor "message"
  tmux_comm.sh queue-file helper|executor /path/to/message.md
  tmux_comm.sh spool-only helper|executor "message"
  tmux_comm.sh broadcast "message"
  tmux_comm.sh check-push-target
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_tmux() {
  command -v tmux >/dev/null 2>&1 || die "tmux is not available"
}

role_session() {
  case "${1:-}" in
    researcher) printf '%s\n' "${ORBIT_RESEARCHER_SESSION:-researcher}" ;;
    executor) printf '%s\n' "${ORBIT_EXECUTOR_SESSION:-executor}" ;;
    helper) printf '%s\n' "${ORBIT_HELPER_SESSION:-helper}" ;;
    *) die "unknown role '$1'; expected researcher, executor, or helper" ;;
  esac
}

target_for() {
  local session
  session="$(role_session "$1")"
  printf '%s:0.0\n' "$session"
}

writable_target_for() {
  case "${1:-}" in
    helper|executor) target_for "$1" ;;
    researcher) die "refusing to send to researcher; use orbit notify for worker-to-researcher notices" ;;
    *) die "unknown writable role '$1'; expected helper or executor" ;;
  esac
}

require_message() {
  local message="$1"
  [[ -n "$message" ]] || die "message must not be empty"
}

message_size() {
  printf '%s' "$1" | wc -c | tr -d '[:space:]'
}

comm_root() {
  printf '%s\n' "${ORBIT_COMM_ROOT:-${ORBIT_HOME:-$HOME/.codex/orbit}/comm}"
}

submit_keys() {
  local keys="${ORBIT_COMM_SUBMIT_KEYS:-C-m}"
  local key
  IFS=',' read -r -a key_list <<< "$keys"
  for key in "${key_list[@]}"; do
    [[ -n "$key" ]] || continue
    case "$key" in
      Enter|ENTER|Return|RETURN) key="C-m" ;;
    esac
    printf '%s\n' "$key"
  done
}

maybe_retry_submit() {
  local target="$1"
  local message="$2"
  [[ "${ORBIT_COMM_RETRY_STUCK_SUBMIT:-1}" == "1" ]] || return 0

  local delay="${ORBIT_COMM_SUBMIT_VERIFY_DELAY_SEC:-0.75}"
  sleep "$delay"

  local marker recent tail_recent
  marker="$(printf '%s' "$message" | tr '\r\n' '  ' | cut -c1-72)"
  [[ -n "$marker" ]] || return 0

  recent="$(tmux capture-pane -t "$target" -p -S -30 2>/dev/null || true)"
  tail_recent="$(printf '%s\n' "$recent" | tail -n 10)"

  if printf '%s\n' "$tail_recent" | grep -Fq "$marker" \
    && ! printf '%s\n' "$tail_recent" | grep -Eq 'Working|Explored|Ran |ACK:|ACK '; then
    tmux send-keys -t "$target" C-m
  fi
}

send_inline_message() {
  local target="$1"
  local message="$2"
  case "$message" in
    *$'\n'*|*$'\r'*) die "inline message must be a single line" ;;
  esac

  local buffer_name="orbit_comm_${USER:-user}_$$"
  tmux set-buffer -b "$buffer_name" -- "$message"
  tmux paste-buffer -t "$target" -b "$buffer_name"
  tmux delete-buffer -b "$buffer_name" 2>/dev/null || true

  local key submitted_with_cm=0
  sleep "${ORBIT_COMM_POST_PASTE_DELAY_SEC:-0.15}"
  while IFS= read -r key; do
    [[ "$key" == "C-m" ]] && submitted_with_cm=1
    tmux send-keys -t "$target" "$key"
    sleep "${ORBIT_COMM_BETWEEN_KEYS_DELAY_SEC:-0.05}"
  done < <(submit_keys)
  [[ "$submitted_with_cm" == "1" ]] && maybe_retry_submit "$target" "$message"
}

spool_message() {
  local agent="$1"
  local message="$2"
  local root dir ts chars message_sha file tmp file_sha file_chars
  root="$(comm_root)"
  dir="$root/inbox/$agent"
  mkdir -p "$dir"

  ts="$(date +%Y%m%d_%H%M%S)"
  chars="$(message_size "$message")"
  message_sha="$(printf '%s' "$message" | sha256sum | awk '{print $1}')"
  file="$dir/${ts}_${USER:-researcher}_$$_payload.md"
  tmp="${file}.tmp"

  {
    printf '# ORBIT delegated message\n\n'
    printf 'from: researcher\n'
    printf 'to: %s\n' "$agent"
    printf 'created_at: %s\n' "$(date -Is)"
    printf 'message_chars: %s\n' "$chars"
    printf 'message_sha256: %s\n\n' "$message_sha"
    printf '%s\n' "$message"
  } > "$tmp"
  mv "$tmp" "$file"
  chmod 600 "$file" 2>/dev/null || true
  file_sha="$(sha256sum "$file" | awk '{print $1}')"
  file_chars="$(wc -c < "$file" | tr -d '[:space:]')"
  printf '%s\t%s\t%s\n' "$file" "$file_sha" "$file_chars"
}

send_pointer_for_payload() {
  local agent="$1"
  local payload_path="$2"
  local sha="$3"
  local chars="$4"
  local target notice
  target="$(writable_target_for "$agent")"
  notice="[Task assigned by Researcher] Long/multiline payload stored at ${payload_path} file_sha256=${sha} file_bytes=${chars}. Read that file from disk and ACK with a one-line summary before acting. This short pointer intentionally replaces direct large paste."
  send_inline_message "$target" "$notice"
}

print_target_status() {
  local role="$1"
  local session target
  session="$(role_session "$role")"
  target="${session}:0.0"
  if ! tmux has-session -t "$session" 2>/dev/null; then
    printf '%s missing\n' "$target"
    return 1
  fi
  tmux display-message -p -t "$target" \
    '#{session_name}:#{window_index}.#{pane_index} pid=#{pane_pid} active=#{pane_active} cmd=#{pane_current_command} title=#{pane_title}' \
    2>/dev/null || {
      printf '%s missing-pane\n' "$target"
      return 1
    }
}

send_message() {
  local agent="$1"
  shift
  local message="$*"
  require_message "$message"

  local session target
  session="$(role_session "$agent")"
  target="$(writable_target_for "$agent")"
  tmux has-session -t "$session" 2>/dev/null || die "tmux session '$session' for role '$agent' is not available"

  local max_inline chars payload_path sha
  max_inline="${ORBIT_COMM_MAX_INLINE_CHARS:-900}"
  chars="$(message_size "$message")"
  if [[ "$message" == "[Task assigned by Researcher]"* \
    || "$message" == "[Task update by Researcher]"* \
    || "$message" == *$'\n'* \
    || "$message" == *$'\r'* \
    || "$chars" -gt "$max_inline" ]]; then
    IFS=$'\t' read -r payload_path sha chars < <(spool_message "$agent" "$message")
    send_pointer_for_payload "$agent" "$payload_path" "$sha" "$chars"
  else
    send_inline_message "$target" "$message"
  fi
}

send_file() {
  local agent="$1"
  local path="$2"
  [[ -r "$path" ]] || die "cannot read payload file '$path'"
  tmux has-session -t "$(role_session "$agent")" 2>/dev/null || die "tmux session for role '$agent' is not available"
  local sha chars
  sha="$(sha256sum "$path" | awk '{print $1}')"
  chars="$(wc -c < "$path" | tr -d '[:space:]')"
  send_pointer_for_payload "$agent" "$path" "$sha" "$chars"
}

require_tmux

cmd="${1:-}"
case "$cmd" in
  status)
    print_target_status researcher || true
    print_target_status executor || true
    print_target_status helper || true
    ;;
  peek)
    [[ $# -eq 2 ]] || die "peek requires exactly one role"
    target="$(target_for "$2")"
    tmux capture-pane -t "$target" -p -S "${ORBIT_PEEK_LINES:--120}"
    ;;
  send)
    [[ $# -ge 3 ]] || die "send requires a role and message"
    agent="$2"
    shift 2
    send_message "$agent" "$*"
    ;;
  send-file)
    [[ $# -eq 3 ]] || die "send-file requires a role and readable path"
    send_file "$2" "$3"
    ;;
  queue)
    [[ $# -ge 3 ]] || die "queue requires a role and message"
    agent="$2"
    shift 2
    ORBIT_COMM_SUBMIT_KEYS=Tab send_message "$agent" "$*"
    ;;
  queue-file)
    [[ $# -eq 3 ]] || die "queue-file requires a role and readable path"
    ORBIT_COMM_SUBMIT_KEYS=Tab send_file "$2" "$3"
    ;;
  spool-only)
    [[ $# -ge 3 ]] || die "spool-only requires a role and message"
    agent="$2"
    shift 2
    require_message "$*"
    case "$agent" in helper|executor) ;; *) die "unknown target '$agent'; expected helper or executor" ;; esac
    IFS=$'\t' read -r payload_path sha chars < <(spool_message "$agent" "$*")
    printf 'payload=%s\nfile_sha256=%s\nfile_bytes=%s\n' "$payload_path" "$sha" "$chars"
    ;;
  broadcast)
    [[ $# -ge 2 ]] || die "broadcast requires a message"
    shift
    message="$*"
    require_message "$message"
    send_message executor "$message"
    send_message helper "$message"
    ;;
  check-push-target)
    target="$(target_for researcher)"
    session="$(role_session researcher)"
    tmux has-session -t "$session" 2>/dev/null || die "researcher session '$session' is not available"
    pane="$(tmux display-message -p -t "$target" '#{session_name}:#{window_index}.#{pane_index}')"
    pane_cmd="$(tmux display-message -p -t "$target" '#{pane_current_command}')"
    printf '%s cmd=%s\n' "$pane" "$pane_cmd"
    case " ${ORBIT_RESEARCHER_EXPECTED_COMMANDS:-codex node} " in
      *" $pane_cmd "*) ;;
      *) die "$target is running '$pane_cmd', not an expected researcher command" ;;
    esac
    ;;
  -h|--help|help|'')
    usage
    ;;
  *)
    usage >&2
    die "unknown command '$cmd'"
    ;;
esac
