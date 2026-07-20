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

INTERFACE=eno1 \
VM_CONFIGS_JSON='["/etc/nixos-shell-vm-manager/instances/s-router-prod.conf"]' \
POLL_INTERVAL_SECONDS=1 \
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

printf 'carrier watcher tests passed\n'
