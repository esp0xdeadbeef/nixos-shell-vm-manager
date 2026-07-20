#!/usr/bin/env bash
set -euo pipefail

label='@LABEL@'
observation_dir=${TEST_OBSERVATION_DIR:-/run/fake-vm}
mkdir -p "$observation_dir"
printf '%s\n' "$label" >"$observation_dir/active"
printf '%s\n' "$label" >>"$observation_dir/starts"
if [[ -n ${NIX_DISK_IMAGE:-} ]]; then
  mkdir -p "$(dirname "$NIX_DISK_IMAGE")"
  : >"$NIX_DISK_IMAGE"
fi

cleanup() {
  if [[ -r "$observation_dir/active" ]] && [[ $(cat "$observation_dir/active") == "$label" ]]; then
    rm -f "$observation_dir/active"
  fi
  exit 0
}
trap cleanup TERM INT

while true; do
  if IFS= read -r -t 0.1 console_input; then
    printf '%s\n' "$console_input" >"$observation_dir/console-input"
  fi
done
