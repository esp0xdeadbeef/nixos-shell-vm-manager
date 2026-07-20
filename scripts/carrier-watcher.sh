#!/usr/bin/env bash
set -euo pipefail

: "${INTERFACE:?}"
: "${VM_UNITS_JSON:?}"
: "${POLL_INTERVAL_SECONDS:?}"
: "${STATE_FILE:?}"
: "${DRY_RUN:?}"

carrier_file=${CARRIER_FILE:-/sys/class/net/$INTERFACE/carrier}
systemctl_bin=${SYSTEMCTL_BIN:-systemctl}
max_iterations=${MAX_ITERATIONS:-0}

[[ $POLL_INTERVAL_SECONDS =~ ^[0-9]+$ ]] || {
  printf 'invalid poll interval: %s\n' "$POLL_INTERVAL_SECONDS" >&2
  exit 64
}
[[ $max_iterations =~ ^[0-9]+$ ]] || {
  printf 'invalid iteration bound: %s\n' "$max_iterations" >&2
  exit 64
}
case "$DRY_RUN" in
  true | false) ;;
  *)
    printf 'invalid dry-run value: %s\n' "$DRY_RUN" >&2
    exit 64
    ;;
esac

mapfile -t vm_units < <(jq -er '.[] | strings' <<<"$VM_UNITS_JSON")
(( ${#vm_units[@]} > 0 )) || {
  printf 'carrier policy has no VM units\n' >&2
  exit 64
}

mkdir -p "$(dirname "$STATE_FILE")"

carrier_state() {
  if [[ -r "$carrier_file" ]] && [[ $(<"$carrier_file") == 1 ]]; then
    printf up
  else
    printf down
  fi
}

run_action() {
  local action=$1
  if [[ $DRY_RUN == true ]]; then
    printf 'dry-run: would run: systemctl %s --no-block' "$action"
    printf ' %q' "${vm_units[@]}"
    printf '\n'
  else
    "$systemctl_bin" "$action" --no-block "${vm_units[@]}"
  fi
}

apply_state() {
  local state=$1
  if [[ $state == up ]]; then
    printf '%s carrier is up; starting router VMs\n' "$INTERFACE"
    run_action start
  else
    printf '%s carrier is down; stopping router VMs\n' "$INTERFACE"
    run_action stop
  fi
}

last_state=
iterations=0
while true; do
  current_state=$(carrier_state)
  if [[ $current_state != "$last_state" ]]; then
    printf '%s\n' "$current_state" >"$STATE_FILE"
    apply_state "$current_state"
    last_state=$current_state
  fi

  iterations=$((iterations + 1))
  if (( max_iterations > 0 && iterations >= max_iterations )); then
    exit 0
  fi
  sleep "$POLL_INTERVAL_SECONDS"
done
