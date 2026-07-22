#!/usr/bin/env bash
set -euo pipefail

manager=${1:?manager script required}
fake_runner=${2:-"$(dirname "$0")/fake-runner.sh"}
test_root=$(mktemp -d)
supervisor_pid=
fake_update_failure="$test_root/fail-flake-update"
fake_archive_failure="$test_root/fail-flake-archive"
fake_build_failure="$test_root/fail-flake-build"

cleanup() {
  if [[ ${supervisor_pid:-} =~ ^[0-9]+$ ]] && kill -0 "$supervisor_pid" 2>/dev/null; then
    kill -TERM "$supervisor_pid" 2>/dev/null || true
    wait "$supervisor_pid" 2>/dev/null || true
  fi
  rm -rf -- "$test_root"
}
trap cleanup EXIT

wait_for() {
  local description=$1 command=$2 count=0
  until bash -c "$command"; do
    count=$((count + 1))
    if (( count > 200 )); then
      printf 'timeout waiting for %s\n' "$description" >&2
      return 1
    fi
    sleep 0.05
  done
}

make_image() {
  local label=$1
  local image="$test_root/images/$label"
  mkdir -p "$image/bin"
  sed -e "1c#!$(command -v bash)" -e "s/@LABEL@/$label/g" \
    "$fake_runner" >"$image/bin/run-test-vm-vm"
  chmod +x "$image/bin/run-test-vm-vm"
  printf '%s\n' "$image"
}

baseline=$(make_image baseline)
good=$(make_image good)
bad=$(make_image bad)
host_new=$(make_image host-new)
observation="$test_root/observation"
mkdir -p "$observation"

fake_systemctl="$test_root/systemctl"
cat >"$fake_systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${FAKE_SYSTEMCTL_LOG:?}"
if [[ ${1:-} == is-active ]]; then
  exit 3
fi
exit 0
EOF
sed -i "1c#!$(command -v bash)" "$fake_systemctl"
chmod +x "$fake_systemctl"

fake_nix="$test_root/nix"
cat >"$fake_nix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${FAKE_NIX_LOG:?}"
case "${1:-}:${2:-}" in
  flake:update)
    if [[ -e '@FAKE_UPDATE_FAILURE@' ]]; then
      exit 1
    fi
    source_ref=${*: -1}
    source_path=${source_ref#path:}
    cp "$source_path/flake.lock" "${FAKE_REFRESH_LOCK_BEFORE:?}"
    printf '%s\n' "${FAKE_UPDATED_LOCK_CONTENT:?}" >"$source_path/flake.lock"
    : >"${FAKE_REFRESH_READY:?}"
    ;;
  flake:archive)
    source_ref=${*: -1}
    source_path=${source_ref#path:}
    if [[ -n ${FAKE_PIN_SOURCE:-} && "$source_path" == "$FAKE_PIN_SOURCE" ]]; then
      jq -cn --arg path "$source_path" '{path:$path}'
    elif [[ "$source_path" == *'/.pin-refresh.'* ]]; then
      if [[ -e '@FAKE_ARCHIVE_FAILURE@' ]]; then
        exit 1
      fi
      rm -rf -- "${FAKE_PIN_ARCHIVE:?}"
      cp -a "$source_path" "$FAKE_PIN_ARCHIVE"
      jq -cn --arg path "$FAKE_PIN_ARCHIVE" '{path:$path}'
    else
      rm -rf -- "$FAKE_ARCHIVE"
      cp -a "$source_path" "$FAKE_ARCHIVE"
      : >"$FAKE_ARCHIVE_READY"
      while [[ ! -e "$FAKE_ARCHIVE_RELEASE" ]]; do sleep 0.02; done
      jq -cn --arg path "$FAKE_ARCHIVE" '{path:$path}'
    fi
    ;;
  build:*)
    if [[ "${*: -1}" == *"${FAKE_PIN_ARCHIVE:-/not-configured}"* ]]; then
      if [[ -e '@FAKE_BUILD_FAILURE@' ]]; then
        exit 1
      fi
      cat "${FAKE_PIN_BUILD_OUTPUT_FILE:?}"
    else
      printf '%s\n' "$FAKE_BUILD_OUTPUT"
    fi
    ;;
  *) exit 64 ;;
esac
EOF
sed -i \
  -e "1c#!$(command -v bash)" \
  -e "s|@FAKE_UPDATE_FAILURE@|$fake_update_failure|g" \
  -e "s|@FAKE_ARCHIVE_FAILURE@|$fake_archive_failure|g" \
  -e "s|@FAKE_BUILD_FAILURE@|$fake_build_failure|g" \
  "$fake_nix"
chmod +x "$fake_nix"

pin_source="$test_root/pin-source"
mkdir -p "$pin_source"
printf '{}\n' >"$pin_source/flake.nix"
printf '{"pins":"host"}\n' >"$pin_source/flake.lock"

config="$test_root/test-vm.conf"
cat >"$config" <<EOF
VM_NAME='test-vm'
STATE_DIR='$test_root/state'
RUNTIME_DIR='$test_root/runtime'
PERSISTENT_DIR='$test_root/persistent'
GC_ROOT_DIR='$test_root/gcroots'
CONTROL_DIR='$test_root/control'
LOCK_DIR='$test_root/locks'
BUILD_TOKEN_DIRECTORY='$test_root/locks/tokens'
PIN_REFRESH_SHARED_DIRECTORY='$test_root/shared-pin-refresh'
PIN_REFRESH_SHARED_LOCK_DIRECTORY='$test_root/locks/shared-pin-refresh'
MAX_CONCURRENT_BUILDS=1
RUNNER_RELATIVE_PATH='bin/run-test-vm-vm'
RUNNER_ARGUMENTS_JSON='[]'
QEMU_ARGUMENTS_JSON='[]'
HEALTH_COMMAND='label=\$(cat "$observation/active" 2>/dev/null || true); test -n "\$label" && test "\$label" != bad'
HEALTH_TIMEOUT_SECONDS=1
HEALTH_RETRIES=3
HEALTH_INTERVAL_SECONDS=0
START_ON_BOOT=0
RESTART_ON_GUEST_SHUTDOWN=1
ROLLOUT_CANDIDATE_ON_GUEST_SHUTDOWN=1
USE_CANDIDATE_ON_EXPLICIT_START=1
REFRESH_PINS=0
PIN_REFRESH_FLAKE_REF='path:$pin_source'
PIN_REFRESH_FLAKE_ATTRIBUTE='packages.test-vm'
PIN_REFRESH_LOCK_SCOPE='host'
JITTER_MIN_SECONDS=0
JITTER_MAX_SECONDS=0
EPHEMERAL_ROOT=1
ROOT_DISK_FILE='root.qcow2'
PERSISTENT_DISK_ENABLE=0
PERSISTENT_DISK_FILE='state.qcow2'
PERSISTENT_DISK_SIZE='1G'
STOP_GRACE_SECONDS=1
CONSOLE_ENABLE=0
CONSOLE_SOCKET='$test_root/console/test-vm.tmux'
CONSOLE_SESSION='vm'
LOCAL_FLAKE_ATTRIBUTE='packages.test-vm'
SYSTEMD_UNIT='test-vm-vm.service'
SYSTEMCTL_BIN='$fake_systemctl'
NIX_BIN='$fake_nix'
REQUIRE_STORE_IMAGES=0
ALLOW_UNPRIVILEGED=1
EOF

export TEST_OBSERVATION_DIR=$observation
export FAKE_SYSTEMCTL_LOG="$test_root/systemctl.log"
: >"$FAKE_SYSTEMCTL_LOG"

# Public help identifies the operator wrappers, and attach fails clearly when
# the per-VM console has been explicitly disabled.
bash "$manager" --help >"$test_root/help.out" 2>&1
grep -q '^  vm-attach VM$' "$test_root/help.out"
if bash "$manager" attach "$config" >"$test_root/attach.out" 2>"$test_root/attach.err"; then
  exit 1
fi
grep -q 'console.enable = false' "$test_root/attach.err"
[[ $(bash "$manager" dispatch-list "$test_root") == test-vm ]]

# systemd invokes ExecStop after a main process exits naturally with no live
# MAINPID. That cleanup path must not fabricate explicit stop authority.
bash "$manager" stop "$config"
[[ ! -e "$test_root/control/stopped" ]]

# Admission is non-activating and first explicit start promotes the baseline.
bash "$manager" register "$config" "$baseline" host-generation baseline-id
[[ $(jq -r '.candidate.sourceKind' "$test_root/state/state.json") == host-generation ]]
[[ ! -e "$observation/active" ]]
mkdir -p "$test_root/control"
printf 'stale guest-agent socket placeholder\n' >"$test_root/control/qga.sock"
bash "$manager" prepare-start "$config"
bash "$manager" supervise "$config" &
supervisor_pid=$!
wait_for 'baseline promotion' "test \"\$(jq -r .current.image '$test_root/state/state.json')\" = '$baseline'"
[[ $(cat "$observation/active") == baseline ]]
[[ ! -e "$test_root/control/qga.sock" ]]

# Carrier policy uses distinct automatic authority. Carrier-down blocks
# recovery without masquerading as an operator stop, and carrier-up may clear
# only that automatic reason.
: >"$FAKE_SYSTEMCTL_LOG"
epoch_before=$(cat "$test_root/control/epoch")
bash "$manager" carrier-stop "$config"
[[ $(cat "$test_root/control/stopped") == carrier-down ]]
[[ $(jq -r '.authority.explicitlyStopped' <(bash "$manager" status "$config")) == false ]]
[[ $(jq -r '.authority.stopReason' <(bash "$manager" status "$config")) == carrier-down ]]
[[ $(cat "$test_root/control/epoch") -eq $((epoch_before + 1)) ]]
grep -Fx 'kill --kill-whom=main --signal=USR2 test-vm-vm.service' "$FAKE_SYSTEMCTL_LOG" >/dev/null
[[ -e "$test_root/control/automatic-stop" ]]
bash "$manager" carrier-start "$config"
[[ ! -e "$test_root/control/stopped" ]]
[[ ! -e "$test_root/control/automatic-stop" ]]
[[ -e "$test_root/control/preauthorized" ]]
[[ $(cat "$test_root/control/preauthorized") -eq $((epoch_before + 2)) ]]
[[ $(cat "$test_root/control/start-reason") == carrier-up ]]
[[ $(cat "$test_root/control/epoch") -eq $((epoch_before + 2)) ]]
grep -Fx 'start test-vm-vm.service' "$FAKE_SYSTEMCTL_LOG" >/dev/null
bash "$manager" prepare-start "$config"
[[ ! -e "$test_root/control/preauthorized" ]]
: >"$FAKE_SYSTEMCTL_LOG"

# Admission does not interrupt the running runner; explicit rollout promotes.
bash "$manager" register "$config" "$good" local-working-tree local-good
[[ $(cat "$observation/active") == baseline ]]
kill -USR1 "$supervisor_pid"
wait_for 'good promotion' "test \"\$(jq -r .current.image '$test_root/state/state.json')\" = '$good'"
[[ $(jq -r '.previous.image' "$test_root/state/state.json") == "$baseline" ]]

# A functionally bad candidate is quarantined and current is health-checked back.
bash "$manager" register "$config" "$bad" local-working-tree local-bad
kill -USR1 "$supervisor_pid"
wait_for 'rollback' "test \"\$(jq -r .failed.image '$test_root/state/state.json')\" = '$bad' && test \"\$(jq -r .phase '$test_root/state/state.json')\" = running && test \"\$(cat '$observation/active' 2>/dev/null || true)\" = good"
[[ $(jq -r '.current.image' "$test_root/state/state.json") == "$good" ]]
[[ $(jq -r '.phase' "$test_root/state/state.json") == running ]]

# Host activation supersedes a pending local candidate, not current.
bash "$manager" register "$config" "$baseline" local-working-tree pending-local
bash "$manager" register "$config" "$host_new" host-generation host-generation-2
[[ $(jq -r '.candidate.image' "$test_root/state/state.json") == "$host_new" ]]
[[ $(jq -r '.candidate.sourceKind' "$test_root/state/state.json") == host-generation ]]
[[ $(jq -r '.current.image' "$test_root/state/state.json") == "$good" ]]

# A running VM is unchanged during immutable local construction. An explicit
# stop after capture wins the late race; completed admission remains pending.
mkdir -p "$test_root/persistent"
printf 'persistent-data\n' >"$test_root/persistent/marker"
local_source="$test_root/local-source"
mkdir -p "$local_source"
printf '{}\n' >"$local_source/flake.nix"
printf '{}\n' >"$local_source/flake.lock"
printf 'before\n' >"$local_source/content"
export FAKE_NIX_LOG="$test_root/nix.log"
export FAKE_ARCHIVE="$test_root/immutable-archive"
export FAKE_ARCHIVE_READY="$test_root/archive-ready"
export FAKE_ARCHIVE_RELEASE="$test_root/archive-release"
export FAKE_BUILD_OUTPUT="$baseline"
: >"$FAKE_NIX_LOG"
set +e
bash "$manager" update "$config" "$local_source" >"$test_root/update.out" 2>"$test_root/update.err" &
update_pid=$!
set -e
wait_for 'immutable archive' "test -e '$FAKE_ARCHIVE_READY'"
[[ $(cat "$observation/active") == good ]]
printf 'after\n' >"$local_source/content"
[[ $(cat "$FAKE_ARCHIVE/content") == before ]]
bash "$manager" stop "$config" "$supervisor_pid"
wait "$supervisor_pid"
supervisor_pid=
[[ -e "$test_root/control/stopped" ]]
[[ $(cat "$test_root/control/stopped") == explicit-stop ]]
: >"$FAKE_ARCHIVE_RELEASE"
update_status=0
wait "$update_pid" || update_status=$?
[[ $update_status -eq 75 ]]
grep -q -- '--no-update-lock-file' "$FAKE_NIX_LOG"
grep -q -- '--no-write-lock-file' "$FAKE_NIX_LOG"
[[ $(jq -r '.candidate.sourceKind' "$test_root/state/state.json") == local-working-tree ]]
[[ ! -s "$FAKE_SYSTEMCTL_LOG" ]]
[[ ! -e "$observation/active" ]]
[[ $(cat "$test_root/persistent/marker") == persistent-data ]]
[[ $(jq -r '.phase' "$test_root/state/state.json") == idle ]]

# Automatic carrier-up never overrides the later explicit operator stop. A
# preauthorization racing with that stop is rejected by ExecStartPre as well.
: >"$FAKE_SYSTEMCTL_LOG"
carrier_start_status=0
bash "$manager" carrier-start "$config" || carrier_start_status=$?
[[ $carrier_start_status -eq 75 ]]
[[ $(cat "$test_root/control/stopped") == explicit-stop ]]
[[ ! -s "$FAKE_SYSTEMCTL_LOG" ]]
cat "$test_root/control/epoch" >"$test_root/control/preauthorized"
prepare_status=0
bash "$manager" prepare-start "$config" || prepare_status=$?
[[ $prepare_status -eq 75 ]]
[[ ! -e "$test_root/control/preauthorized" ]]
[[ $(cat "$test_root/control/stopped") == explicit-stop ]]

# FS-160-HDS-010-SDS-010-SMS-010: an enabled ordinary start updates only an
# isolated copy, admits refreshed provenance, and promotes the complete output.
export FAKE_PIN_ARCHIVE="$test_root/pin-archive"
export FAKE_PIN_BUILD_OUTPUT_FILE="$test_root/pin-build-output"
export FAKE_PIN_SOURCE="$pin_source"
printf '%s\n' "$host_new" >"$FAKE_PIN_BUILD_OUTPUT_FILE"
export FAKE_REFRESH_LOCK_BEFORE="$test_root/refresh-lock-before"
export FAKE_REFRESH_READY="$test_root/refresh-ready"
export FAKE_UPDATED_LOCK_CONTENT='{"pins":"refreshed"}'
rm -f -- "$fake_update_failure" "$fake_archive_failure" "$fake_build_failure"
: >"$FAKE_NIX_LOG"
sed -i 's/^REFRESH_PINS=0$/REFRESH_PINS=1/' "$config"
bash "$manager" prepare-start "$config"
bash "$manager" supervise "$config" &
supervisor_pid=$!
wait_for 'pin-refresh promotion' "test \"\$(jq -r .current.image '$test_root/state/state.json')\" = '$host_new'"
[[ $(cat "$observation/active") == host-new ]]
[[ $(cat "$pin_source/flake.lock") == '{"pins":"host"}' ]]
[[ $(cat "$FAKE_REFRESH_LOCK_BEFORE") == '{"pins":"host"}' ]]
[[ $(cat "$FAKE_PIN_ARCHIVE/flake.lock") == '{"pins":"refreshed"}' ]]
[[ $(cat "$test_root/shared-pin-refresh/host.flake.lock") == '{"pins":"refreshed"}' ]]
[[ $(jq -r '.current.sourceKind' "$test_root/state/state.json") == pin-refresh ]]
expected_lock_identity="sha256:$(sha256sum "$FAKE_PIN_ARCHIVE/flake.lock" | cut -d ' ' -f 1)"
[[ $(jq -r '.current.lockIdentity' "$test_root/state/state.json") == "$expected_lock_identity" ]]
grep -q '^flake update --refresh --flake path:' "$FAKE_NIX_LOG"
grep -q "^flake archive --json --no-update-lock-file --no-write-lock-file path:$pin_source" "$FAKE_NIX_LOG"
grep -q '^flake archive --json --no-update-lock-file --no-write-lock-file path:.*/\.pin-refresh\.' "$FAKE_NIX_LOG"
grep -q '^build --no-link --print-out-paths --no-update-lock-file --no-write-lock-file path:' "$FAKE_NIX_LOG"

# A different VM in the same host scope starts from the lock published above,
# rather than from the older lock retained in its immutable host source.
second_config="$test_root/second-vm.conf"
cp -- "$config" "$second_config"
sed -i \
  -e "s|VM_NAME='test-vm'|VM_NAME='second-vm'|" \
  -e "s|STATE_DIR='$test_root/state'|STATE_DIR='$test_root/second-state'|" \
  -e "s|RUNTIME_DIR='$test_root/runtime'|RUNTIME_DIR='$test_root/second-runtime'|" \
  -e "s|PERSISTENT_DIR='$test_root/persistent'|PERSISTENT_DIR='$test_root/second-persistent'|" \
  -e "s|GC_ROOT_DIR='$test_root/gcroots'|GC_ROOT_DIR='$test_root/second-gcroots'|" \
  -e "s|CONTROL_DIR='$test_root/control'|CONTROL_DIR='$test_root/second-control'|" \
  -e "s|LOCK_DIR='$test_root/locks'|LOCK_DIR='$test_root/second-locks'|" \
  -e "s|SYSTEMD_UNIT='test-vm-vm.service'|SYSTEMD_UNIT='second-vm-vm.service'|" \
  "$second_config"
bash "$manager" construct-pin-refresh "$second_config"
[[ $(cat "$FAKE_REFRESH_LOCK_BEFORE") == '{"pins":"refreshed"}' ]]
[[ $(jq -r '.candidate.sourceKind' "$test_root/second-state/state.json") == pin-refresh ]]
[[ $(cat "$test_root/shared-pin-refresh/host.flake.lock") == '{"pins":"refreshed"}' ]]

# A failed lock update leaves registry state unchanged and starts current.
bash "$manager" stop "$config" "$supervisor_pid"
wait "$supervisor_pid"
supervisor_pid=
: >"$fake_update_failure"
: >"$FAKE_NIX_LOG"
bash "$manager" prepare-start "$config"
bash "$manager" supervise "$config" &
supervisor_pid=$!
wait_for 'failed-refresh fallback' "test \"\$(cat '$observation/active' 2>/dev/null || true)\" = host-new"
[[ $(jq -r '.current.image' "$test_root/state/state.json") == "$host_new" ]]
[[ $(jq -r '.candidate' "$test_root/state/state.json") == null ]]
grep -q '^flake update --refresh --flake path:' "$FAKE_NIX_LOG"
if [[ $(grep -c '^flake archive ' "$FAKE_NIX_LOG") -ne 1 ]]; then
  exit 1
fi

# Failed immutable capture also leaves the current image unchanged and skips
# construction. It also cannot publish its updated temporary lock into the
# shared host scope.
bash "$manager" stop "$config" "$supervisor_pid"
wait "$supervisor_pid"
supervisor_pid=
rm -f -- "$fake_update_failure"
: >"$fake_archive_failure"
export FAKE_UPDATED_LOCK_CONTENT='{"pins":"failed-archive"}'
: >"$FAKE_NIX_LOG"
bash "$manager" prepare-start "$config"
bash "$manager" supervise "$config" &
supervisor_pid=$!
wait_for 'failed-archive fallback' "test \"\$(cat '$observation/active' 2>/dev/null || true)\" = host-new"
[[ $(jq -r '.current.image' "$test_root/state/state.json") == "$host_new" ]]
[[ $(jq -r '.candidate' "$test_root/state/state.json") == null ]]
grep -q '^flake archive ' "$FAKE_NIX_LOG"
if grep -q '^build ' "$FAKE_NIX_LOG"; then
  exit 1
fi
[[ $(cat "$test_root/shared-pin-refresh/host.flake.lock") == '{"pins":"refreshed"}' ]]

# Failed refreshed construction has the same unchanged-slot fallback.
bash "$manager" stop "$config" "$supervisor_pid"
wait "$supervisor_pid"
supervisor_pid=
rm -f -- "$fake_archive_failure"
: >"$fake_build_failure"
export FAKE_UPDATED_LOCK_CONTENT='{"pins":"guest-refresh"}'
: >"$FAKE_NIX_LOG"
bash "$manager" prepare-start "$config"
bash "$manager" supervise "$config" &
supervisor_pid=$!
wait_for 'failed-build fallback' "test \"\$(cat '$observation/active' 2>/dev/null || true)\" = host-new"
[[ $(jq -r '.current.image' "$test_root/state/state.json") == "$host_new" ]]
[[ $(jq -r '.candidate' "$test_root/state/state.json") == null ]]
grep -q '^build ' "$FAKE_NIX_LOG"
[[ $(cat "$test_root/shared-pin-refresh/host.flake.lock") == '{"pins":"refreshed"}' ]]

# Explicit rollout of an admitted candidate bypasses pin refresh.
bash "$manager" register "$config" "$baseline" local-working-tree explicit-local
: >"$FAKE_NIX_LOG"
kill -USR1 "$supervisor_pid"
wait_for 'excluded explicit rollout' "test \"\$(jq -r .current.image '$test_root/state/state.json')\" = '$baseline'"
[[ ! -s "$FAKE_NIX_LOG" ]]

# A guest shutdown is eligible and refreshes pins before the restart.
rm -f -- "$fake_build_failure"
printf '%s\n' "$good" >"$FAKE_PIN_BUILD_OUTPUT_FILE"
export FAKE_UPDATED_LOCK_CONTENT='{"pins":"guest-refresh"}'
: >"$FAKE_NIX_LOG"
kill -TERM "$(cat "$test_root/control/runner.pid")"
wait "$supervisor_pid"
supervisor_pid=
bash "$manager" prepare-start "$config"
bash "$manager" supervise "$config" &
supervisor_pid=$!
wait_for 'guest pin refresh' "test \"\$(jq -r .current.image '$test_root/state/state.json')\" = '$good'"
[[ $(jq -r '.current.sourceKind' "$test_root/state/state.json") == pin-refresh ]]
grep -q '^flake update --refresh --flake path:' "$FAKE_NIX_LOG"
[[ $(cat "$FAKE_REFRESH_LOCK_BEFORE") == '{"pins":"refreshed"}' ]]
[[ $(cat "$test_root/shared-pin-refresh/host.flake.lock") == '{"pins":"guest-refresh"}' ]]

bash "$manager" stop "$config" "$supervisor_pid"
wait "$supervisor_pid"
supervisor_pid=

printf 'all manager module tests passed\n'
