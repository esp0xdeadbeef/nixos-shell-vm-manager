#!/usr/bin/env bash
set -euo pipefail

socket=${1:?usage: qga-systemd-health SOCKET [GUEST-COMMAND [ARG ...]]}

# shellcheck source=./qga-client.sh disable=SC1091
source "${QGA_CLIENT_LIBRARY:-$(dirname "$0")/qga-client.sh}"
trap qga_disconnect EXIT

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

qga_connect "$socket"
qga_run "$guest_command" "${guest_arguments[@]}"

# Assigned by qga_run in the sourced client.
# shellcheck disable=SC2154
if [[ $qga_last_exit_code -eq 0 ]]; then
  exit 0
fi

# shellcheck disable=SC2154
printf 'guest command failed with exit code %s\n' "$qga_last_exit_code" >&2
# shellcheck disable=SC2154
[[ -n $qga_last_stdout ]] && printf '%s\n' "$qga_last_stdout" >&2
# shellcheck disable=SC2154
[[ -n $qga_last_stderr ]] && printf '%s\n' "$qga_last_stderr" >&2
exit 1
