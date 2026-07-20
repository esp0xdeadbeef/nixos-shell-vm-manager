#!/usr/bin/env bash
set -euo pipefail

: "${INTERFACE:?}"
: "${VM_CONFIGS_JSON:?}"
: "${POLL_INTERVAL_SECONDS:?}"
: "${STATE_FILE:?}"
: "${DRY_RUN:?}"
: "${MANAGER_BIN:?}"

carrier_file=${CARRIER_FILE:-/sys/class/net/$INTERFACE/carrier}
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

mapfile -t vm_configs < <(jq -er '.[] | strings' <<<"$VM_CONFIGS_JSON")
(( ${#vm_configs[@]} > 0 )) || {
  printf 'carrier policy has no VM configurations\n' >&2
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
  local config status
  for config in "${vm_configs[@]}"; do
    if [[ $DRY_RUN == true ]]; then
      printf 'dry-run: would run: %q %q %q\n' \
        "$MANAGER_BIN" "$action" "$config"
      continue
    fi
    status=0
    "$MANAGER_BIN" "$action" "$config" || status=$?
    if [[ $status -eq 75 && $action == carrier-start ]]; then
      printf 'carrier-up preserved explicit stop for %s\n' "$config" >&2
    elif [[ $status -ne 0 ]]; then
      return "$status"
    fi
  done
}

apply_state() {
  local state=$1
  if [[ $state == up ]]; then
    printf '%s carrier is up; starting router VMs\n' "$INTERFACE"
    run_action carrier-start
  else
    printf '%s carrier is down; stopping router VMs\n' "$INTERFACE"
    run_action carrier-stop
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
