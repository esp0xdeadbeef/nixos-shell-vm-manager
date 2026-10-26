#!/usr/bin/env bash
set -euo pipefail

watcher=${1:?usage: test-carrier-watcher.sh WATCHER}
test_root=$(mktemp -d)
transition_pid=
cleanup() {
  if [[ ${transition_pid:-} =~ ^[0-9]+$ ]]; then
    kill "$transition_pid" 2>/dev/null || true
    wait "$transition_pid" 2>/dev/null || true
  fi
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fake_manager="$test_root/nixos-shell-vm-manager"
printf '#!%s\n' "${BASH:?}" >"$fake_manager"
cat >>"$fake_manager" <<'EOF'
set -euo pipefail
printf '%s\n' "$*" >>"$MANAGER_LOG"
EOF
chmod +x "$fake_manager"

carrier_file="$test_root/carrier"
state_file="$test_root/state"
manager_log="$test_root/manager.log"
: >"$manager_log"
printf '0\n' >"$carrier_file"

(
  sleep 1.5
  printf '1\n' >"$carrier_file"
  sleep 4
  printf '0\n' >"$carrier_file"
) &
transition_pid=$!

# DEBOUNCE_SAMPLES=1 keeps this case testing the transition logic itself;
# the debounce has its own case below.
INTERFACE=eno1 \
VM_CONFIGS_JSON='["/etc/nixos-shell-vm-manager/instances/s-router-prod.conf"]' \
POLL_INTERVAL_SECONDS=1 \
DEBOUNCE_SAMPLES=1 \
STATE_FILE="$state_file" \
DRY_RUN=false \
MANAGER_BIN="$fake_manager" \
CARRIER_FILE="$carrier_file" \
MANAGER_LOG="$manager_log" \
MAX_ITERATIONS=8 \
  "$watcher" >"$test_root/watcher.log"
wait "$transition_pid"
transition_pid=

cat >"$test_root/expected.log" <<'EOF'
carrier-stop /etc/nixos-shell-vm-manager/instances/s-router-prod.conf
carrier-start /etc/nixos-shell-vm-manager/instances/s-router-prod.conf
carrier-stop /etc/nixos-shell-vm-manager/instances/s-router-prod.conf
EOF
cmp "$test_root/expected.log" "$manager_log"
[[ $(<"$state_file") == down ]]
grep -Fx 'eno1 carrier is up; starting router VMs' "$test_root/watcher.log" >/dev/null
grep -Fx 'eno1 carrier is down; stopping router VMs' "$test_root/watcher.log" >/dev/null

: >"$manager_log"
INTERFACE=eno1 \
VM_CONFIGS_JSON='["/etc/nixos-shell-vm-manager/instances/s-router-prod.conf"]' \
POLL_INTERVAL_SECONDS=0 \
DEBOUNCE_SAMPLES=1 \
STATE_FILE="$state_file" \
DRY_RUN=true \
MANAGER_BIN="$fake_manager" \
CARRIER_FILE="$carrier_file" \
MANAGER_LOG="$manager_log" \
MAX_ITERATIONS=1 \
  "$watcher" >"$test_root/dry-run.log"
[[ ! -s $manager_log ]]
grep -Fx "dry-run: would run: $fake_manager carrier-stop /etc/nixos-shell-vm-manager/instances/s-router-prod.conf" \
  "$test_root/dry-run.log" >/dev/null

# A manager call that fails transiently must not be recorded as handled: the
# carrier transition stays uncommitted and is retried on the next poll. This
# reproduces the flap race where a start failed once and the watcher then left
# the VM stopped although carrier was physically up.
fail_manager="$test_root/nixos-shell-vm-manager-failing"
printf '#!%s\n' "${BASH:?}" >"$fail_manager"
cat >>"$fail_manager" <<'EOF'
set -euo pipefail
printf '%s\n' "$*" >>"$MANAGER_LOG"
if [[ $1 == carrier-start && ! -e "$FAIL_ONCE_MARKER" ]]; then
  touch "$FAIL_ONCE_MARKER"
  exit 1
fi
EOF
chmod +x "$fail_manager"

fail_state="$test_root/retry-state"
fail_log="$test_root/retry-manager.log"
fail_marker="$test_root/retry-marker"
: >"$fail_log"
printf '1\n' >"$carrier_file"

INTERFACE=eno1 \
VM_CONFIGS_JSON='["/etc/nixos-shell-vm-manager/instances/s-router-prod.conf"]' \
POLL_INTERVAL_SECONDS=0 \
DEBOUNCE_SAMPLES=1 \
STATE_FILE="$fail_state" \
DRY_RUN=false \
MANAGER_BIN="$fail_manager" \
CARRIER_FILE="$carrier_file" \
MANAGER_LOG="$fail_log" \
FAIL_ONCE_MARKER="$fail_marker" \
MAX_ITERATIONS=3 \
  "$watcher" >"$test_root/retry.log"

# carrier-start was attempted twice: the first failed, the second succeeded.
[[ $(grep -c 'carrier-start' "$fail_log") -ge 2 ]]
[[ $(<"$fail_state") == up ]]
grep -Fx 'eno1 carrier is up; starting router VMs' "$test_root/retry.log" >/dev/null

# --- debounce: a carrier blip must not stop or start a VM --------------------
# Regression for the boot flap: the carrier is derived from an interface that
# comes up late, so the first polls can read up->down->up within a second. With
# DEBOUNCE_SAMPLES=3 a state that does not persist is never acted on.
blip_carrier="$test_root/blip-carrier"
blip_log="$test_root/blip.log"
blip_state="$test_root/blip-state"
: >"$blip_log"
printf '0\n' >"$blip_carrier"
(
  sleep 1; printf '1\n' >"$blip_carrier"   # 1 sample up  -> blip
  sleep 1; printf '0\n' >"$blip_carrier"   # back down    -> blip
  sleep 1; printf '1\n' >"$blip_carrier"   # settles up
) &
blip_pid=$!

INTERFACE=eno1 \
VM_CONFIGS_JSON='["/etc/nixos-shell-vm-manager/instances/s-router-prod.conf"]' \
POLL_INTERVAL_SECONDS=1 \
DEBOUNCE_SAMPLES=3 \
STATE_FILE="$blip_state" \
DRY_RUN=false \
MANAGER_BIN="$fake_manager" \
CARRIER_FILE="$blip_carrier" \
MANAGER_LOG="$blip_log" \
MAX_ITERATIONS=25 \
  "$watcher" >"$test_root/blip-watcher.log"
wait "$blip_pid"

# Only the settled transition is acted on: exactly one carrier-start, no
# carrier-stop, because the down readings never persisted for 3 samples.
[[ $(grep -c 'carrier-start' "$blip_log") -eq 1 ]]
[[ $(grep -c 'carrier-stop' "$blip_log" || true) -eq 0 ]]
[[ $(<"$blip_state") == up ]]

printf 'carrier watcher tests passed\n'
