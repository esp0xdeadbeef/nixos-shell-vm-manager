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

fake_systemctl="$test_root/systemctl"
printf '#!%s\n' "${BASH:?}" >"$fake_systemctl"
cat >>"$fake_systemctl" <<'EOF'
set -euo pipefail
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
EOF
chmod +x "$fake_systemctl"

carrier_file="$test_root/carrier"
state_file="$test_root/state"
systemctl_log="$test_root/systemctl.log"
: >"$systemctl_log"
printf '0\n' >"$carrier_file"

(
  sleep 1.5
  printf '1\n' >"$carrier_file"
  sleep 4
  printf '0\n' >"$carrier_file"
) &
transition_pid=$!

INTERFACE=eno1 \
VM_UNITS_JSON='["s-router-prod-vm.service"]' \
POLL_INTERVAL_SECONDS=1 \
STATE_FILE="$state_file" \
DRY_RUN=false \
CARRIER_FILE="$carrier_file" \
SYSTEMCTL_BIN="$fake_systemctl" \
SYSTEMCTL_LOG="$systemctl_log" \
MAX_ITERATIONS=8 \
  "$watcher" >"$test_root/watcher.log"
wait "$transition_pid"
transition_pid=

cat >"$test_root/expected.log" <<'EOF'
stop --no-block s-router-prod-vm.service
start --no-block s-router-prod-vm.service
stop --no-block s-router-prod-vm.service
EOF
cmp "$test_root/expected.log" "$systemctl_log"
[[ $(<"$state_file") == down ]]
grep -Fx 'eno1 carrier is up; starting router VMs' "$test_root/watcher.log" >/dev/null
grep -Fx 'eno1 carrier is down; stopping router VMs' "$test_root/watcher.log" >/dev/null

: >"$systemctl_log"
INTERFACE=eno1 \
VM_UNITS_JSON='["s-router-prod-vm.service"]' \
POLL_INTERVAL_SECONDS=0 \
STATE_FILE="$state_file" \
DRY_RUN=true \
CARRIER_FILE="$carrier_file" \
SYSTEMCTL_BIN="$fake_systemctl" \
SYSTEMCTL_LOG="$systemctl_log" \
MAX_ITERATIONS=1 \
  "$watcher" >"$test_root/dry-run.log"
[[ ! -s $systemctl_log ]]
grep -Fx 'dry-run: would run: systemctl stop --no-block s-router-prod-vm.service' \
  "$test_root/dry-run.log" >/dev/null

printf 'carrier watcher tests passed\n'
