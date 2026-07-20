#!/usr/bin/env bash
set -euo pipefail

socket=${1:?usage: qga-systemd-health SOCKET GUEST-COMMAND [ARG ...]}
guest_command=${2:?usage: qga-systemd-health SOCKET GUEST-COMMAND [ARG ...]}
shift 2

qga_call() {
  local request=$1 response
  response=$(printf '%s\n' "$request" \
    | socat -t 2 - "UNIX-CONNECT:$socket") || return 1
  jq -e . >/dev/null <<<"$response" || return 1
  printf '%s\n' "$response"
}

qga_call '{"execute":"guest-ping"}' >/dev/null

arguments_json='[]'
for argument in "$@"; do
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

    jq -r '.return["err-data"] // empty | @base64d' \
      <<<"$status_response" >&2
    exit 1
  fi

  sleep 0.25
done

printf 'guest command did not finish within 120 seconds\n' >&2
exit 1
