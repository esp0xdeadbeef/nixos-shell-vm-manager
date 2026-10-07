# shellcheck shell=bash
# Shared QEMU guest-agent client used by the manager's guest helpers.
#
# Sourcing this file provides:
#   qga_connect SOCKET                 - open one synchronized channel
#   qga_run PATH [ARG ...]             - run a guest command, capture output
#   qga_last_stdout / qga_last_stderr  - captured output of the last run
#   qga_last_exit_code                 - exit status of the last run
#
# The caller must provide bash, jq and socat, and is responsible for calling
# qga_disconnect (or simply exiting, thanks to the EXIT trap) when finished.

response_timeout_seconds=${QGA_RESPONSE_TIMEOUT_SECONDS:-5}
if [[ ! $response_timeout_seconds =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  printf 'invalid QGA_RESPONSE_TIMEOUT_SECONDS: %s\n' \
    "$response_timeout_seconds" >&2
  return 64
fi

# Guest commands are polled until they exit. 480 * 0.25s == 120s.
qga_poll_attempts=${QGA_POLL_ATTEMPTS:-480}
qga_poll_interval_seconds=${QGA_POLL_INTERVAL_SECONDS:-0.25}

qga_pid=
qga_input_fd=
qga_output_fd=
qga_last_stdout=
qga_last_stderr=
qga_last_exit_code=

# shellcheck disable=SC2329 # Invoked through the EXIT trap.
qga_disconnect() {
  if [[ ${qga_input_fd:-} =~ ^[0-9]+$ ]]; then
    exec {qga_input_fd}>&- 2>/dev/null || true
  fi
  if [[ ${qga_output_fd:-} =~ ^[0-9]+$ ]]; then
    exec {qga_output_fd}<&- 2>/dev/null || true
  fi
  if [[ ${qga_pid:-} =~ ^[0-9]+$ ]]; then
    kill "$qga_pid" 2>/dev/null || true
    wait "$qga_pid" 2>/dev/null || true
  fi
  qga_pid=
  qga_input_fd=
  qga_output_fd=
}

qga_read_response() {
  local response

  while IFS= read -r -t "$response_timeout_seconds" \
    -u "$qga_output_fd" response; do
    if jq -e . >/dev/null 2>&1 <<<"$response"; then
      printf '%s\n' "$response"
      return 0
    fi
  done

  printf 'QEMU guest agent did not return a JSON response within %s seconds\n' \
    "$response_timeout_seconds" >&2
  return 1
}

qga_send_request() {
  printf '%s\n' "$1" >&"$qga_input_fd"
}

qga_call() {
  local request=$1 response error_description

  qga_send_request "$request"
  response=$(qga_read_response) || return 1
  if ! jq -e 'has("return") and (has("error") == false)' \
    >/dev/null <<<"$response"; then
    error_description=$(jq -r '.error.desc // "QEMU guest-agent request failed"' \
      <<<"$response")
    printf '%s\n' "$error_description" >&2
    return 1
  fi
  printf '%s\n' "$response"
}

qga_connect() {
  local socket=$1

  if [[ ! -S $socket ]]; then
    printf 'QEMU guest-agent socket is not available: %s\n' "$socket" >&2
    return 1
  fi

  coproc QGA_CHANNEL { socat - "UNIX-CONNECT:$socket" 2>/dev/null; }
  qga_input_fd=${QGA_CHANNEL[1]}
  qga_output_fd=${QGA_CHANNEL[0]}
  qga_pid=$QGA_CHANNEL_PID

  # QEMU can retain responses written before a client connects. Synchronize on
  # a unique token over one persistent channel before interpreting responses.
  local sync_id=$((($$ * 65536) + RANDOM)) sync_request sync_response
  sync_request=$(jq -cn --argjson id "$sync_id" '
    {
      execute: "guest-sync",
      arguments: { id: $id }
    }
    ')
  qga_send_request "$sync_request"
  local synchronized=false
  for _ in $(seq 1 64); do
    sync_response=$(qga_read_response) || return 1
    if jq -e --argjson id "$sync_id" '.return == $id' \
      >/dev/null <<<"$sync_response"; then
      synchronized=true
      break
    fi
  done
  if [[ $synchronized != true ]]; then
    printf 'failed to synchronize with the QEMU guest agent\n' >&2
    return 1
  fi

  qga_call '{"execute":"guest-ping"}' >/dev/null
}

qga_run() {
  local guest_command=$1
  shift
  local -a guest_arguments=("$@")

  local arguments_json='[]' argument
  for argument in "${guest_arguments[@]}"; do
    arguments_json=$(jq -cn \
      --argjson current "$arguments_json" \
      --arg value "$argument" \
      '$current + [$value]')
  done
  local execute_request execute_response guest_pid
  execute_request=$(jq -cn \
    --arg path "$guest_command" \
    --argjson arguments "$arguments_json" '
      {
        execute: "guest-exec",
        arguments: {
          path: $path,
          arg: $arguments,
          "capture-output": true
        }
      }
    ')
  execute_response=$(qga_call "$execute_request") || return 1
  guest_pid=$(jq -er '.return.pid' <<<"$execute_response") || return 1

  local status_request status_response
  for _ in $(seq 1 "$qga_poll_attempts"); do
    status_request=$(jq -cn --argjson pid "$guest_pid" '
      {
        execute: "guest-exec-status",
        arguments: { pid: $pid }
      }
    ')
    status_response=$(qga_call "$status_request") || return 1

    if jq -e '.return.exited == true' >/dev/null <<<"$status_response"; then
      # These results are consumed by callers after qga_run returns.
      # shellcheck disable=SC2034
      qga_last_exit_code=$(jq -er '.return.exitcode' <<<"$status_response")
      # shellcheck disable=SC2034
      qga_last_stdout=$(jq -r '.return["out-data"] // empty | @base64d' \
        <<<"$status_response")
      # shellcheck disable=SC2034
      qga_last_stderr=$(jq -r '.return["err-data"] // empty | @base64d' \
        <<<"$status_response")
      return 0
    fi

    sleep "$qga_poll_interval_seconds"
  done

  printf 'guest command did not finish after %s polls (interval %ss)\n' \
    "$qga_poll_attempts" "$qga_poll_interval_seconds" >&2
  return 1
}
