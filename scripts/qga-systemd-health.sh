#!/usr/bin/env bash
set -euo pipefail

socket=${1:?usage: qga-systemd-health SOCKET [GUEST-COMMAND [ARG ...]]}

if (( $# == 1 )); then
  guest_command=/run/current-system/sw/bin/bash
  # shellcheck disable=SC2016 # Expanded by bash inside the guest, not here.
  guest_arguments=(
    -c
    'failed_units=$(/run/current-system/sw/bin/systemctl list-units --state=failed --no-legend --plain --no-pager); if [[ -n "$failed_units" ]]; then printf "%s\n" "$failed_units"; exit 1; fi'
  )
else
  guest_command=$2
  shift 2
  guest_arguments=("$@")
fi

response_timeout_seconds=${QGA_RESPONSE_TIMEOUT_SECONDS:-5}
if [[ ! $response_timeout_seconds =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  printf 'invalid QGA_RESPONSE_TIMEOUT_SECONDS: %s\n' \
    "$response_timeout_seconds" >&2
  exit 2
fi

qga_pid=
qga_input_fd=
qga_output_fd=

# shellcheck disable=SC2329 # Invoked through the EXIT trap.
cleanup() {
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
}
trap cleanup EXIT

if [[ ! -S $socket ]]; then
  printf 'QEMU guest-agent socket is not available: %s\n' "$socket" >&2
  exit 1
fi

coproc QGA_CHANNEL { socat - "UNIX-CONNECT:$socket" 2>/dev/null; }
qga_input_fd=${QGA_CHANNEL[1]}
qga_output_fd=${QGA_CHANNEL[0]}
qga_pid=$QGA_CHANNEL_PID

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

# QEMU can retain responses written before a client connects. Synchronize on a
# unique token over one persistent channel before interpreting any response.
sync_id=$((($$ * 65536) + RANDOM))
sync_request=$(jq -cn --argjson id "$sync_id" '
  {
    execute: "guest-sync",
    arguments: { id: $id }
  }
  ')
qga_send_request "$sync_request"
synchronized=false
for _ in $(seq 1 64); do
  sync_response=$(qga_read_response) || break
  if jq -e --argjson id "$sync_id" '.return == $id' \
    >/dev/null <<<"$sync_response"; then
    synchronized=true
    break
  fi
done
if [[ $synchronized != true ]]; then
  printf 'failed to synchronize with the QEMU guest agent\n' >&2
  exit 1
fi

qga_call '{"execute":"guest-ping"}' >/dev/null

arguments_json='[]'
for argument in "${guest_arguments[@]}"; do
  arguments_json=$(jq -cn \
    --argjson current "$arguments_json" \
    --arg value "$argument" \
    '$current + [$value]')
done
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
execute_response=$(qga_call "$execute_request")
guest_pid=$(jq -er '.return.pid' <<<"$execute_response")

for _ in $(seq 1 480); do
  status_request=$(jq -cn --argjson pid "$guest_pid" '
    {
      execute: "guest-exec-status",
      arguments: { pid: $pid }
    }
  ')
  status_response=$(qga_call "$status_request")

  if jq -e '.return.exited == true' >/dev/null <<<"$status_response"; then
    if jq -e '.return.exitcode == 0' >/dev/null <<<"$status_response"; then
      exit 0
    fi

    guest_exit_code=$(jq -er '.return.exitcode' <<<"$status_response")
    printf 'guest command failed with exit code %s\n' "$guest_exit_code" >&2
    jq -r '.return["out-data"] // empty | @base64d' \
      <<<"$status_response" >&2
    jq -r '.return["err-data"] // empty | @base64d' \
      <<<"$status_response" >&2
    exit 1
  fi

  sleep 0.25
done

printf 'guest command did not finish within 120 seconds\n' >&2
exit 1
