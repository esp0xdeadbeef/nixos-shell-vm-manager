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
      printf '%s failed for %s (status %s)\n' "$action" "$config" "$status" >&2
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

# Debounce: a carrier transition must be observed on this many consecutive
# polls before it is acted on. Without it, the very first poll acts
# immediately, and at boot that poll races the interface the carrier is
# derived from -- the watcher sees up->down->up within a second and stops the
# router VM for a state that never existed. FS-920: a failure response needs a
# defined observation window, not a single sample. 3 polls * 5s = 15s.
DEBOUNCE_SAMPLES=${DEBOUNCE_SAMPLES:-3}
if ! [[ $DEBOUNCE_SAMPLES =~ ^[0-9]+$ ]] || (( DEBOUNCE_SAMPLES < 1 )); then
  printf 'invalid debounce samples: %s\n' "$DEBOUNCE_SAMPLES" >&2
  exit 2
fi

last_state=
pending_state=
pending_count=0
iterations=0
while true; do
  current_state=$(carrier_state)
  if [[ $current_state == "$last_state" ]]; then
    # Settled: drop any partially observed transition.
    pending_state=
    pending_count=0
  else
    if [[ $current_state == "$pending_state" ]]; then
      pending_count=$((pending_count + 1))
    else
      pending_state=$current_state
      pending_count=1
    fi
    if (( pending_count >= DEBOUNCE_SAMPLES )); then
      # Only record the observed carrier transition as handled once the
      # delegated action has actually taken effect. A failed (or transiently
      # unavailable) manager call must be retried on the next poll, otherwise a
      # flap that races the VM/interface becoming ready leaves the VM stuck in
      # the wrong state until the next unrelated transition.
      if apply_state "$current_state"; then
        printf '%s\n' "$current_state" >"$STATE_FILE"
        last_state=$current_state
        pending_state=
        pending_count=0
      fi
    fi
  fi

  iterations=$((iterations + 1))
  if (( max_iterations > 0 && iterations >= max_iterations )); then
    exit 0
  fi
  sleep "$POLL_INTERVAL_SECONDS"
done
