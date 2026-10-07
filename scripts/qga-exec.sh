#!/usr/bin/env bash
set -euo pipefail

# Run a command inside a running nixos-shell VM over the QEMU guest agent.
#
# Usage: qga-exec SOCKET GUEST-COMMAND [ARG ...]
#
# The guest command's stdout and stderr are forwarded to this process's
# respective streams, and its exit status becomes this process's exit status.
# Unlike qga-systemd-health, a non-zero guest exit code is not itself an error:
# the helper communicates the guest's own status to calling scripts.

socket=${1:?usage: qga-exec SOCKET GUEST-COMMAND [ARG ...]}
shift
guest_command=${1:?usage: qga-exec SOCKET GUEST-COMMAND [ARG ...]}
shift
guest_arguments=("$@")

# shellcheck source=./qga-client.sh disable=SC1091
source "${QGA_CLIENT_LIBRARY:-$(dirname "$0")/qga-client.sh}"
trap qga_disconnect EXIT

qga_connect "$socket"
qga_run "$guest_command" "${guest_arguments[@]}"

# Assigned by qga_run in the sourced client.
# shellcheck disable=SC2154
if [[ -n $qga_last_stdout ]]; then
  # shellcheck disable=SC2154
  printf '%s' "$qga_last_stdout"
fi
# shellcheck disable=SC2154
if [[ -n $qga_last_stderr ]]; then
  # shellcheck disable=SC2154
  printf '%s' "$qga_last_stderr" >&2
fi

# shellcheck disable=SC2154
exit "$qga_last_exit_code"
