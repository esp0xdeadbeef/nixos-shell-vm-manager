#!/usr/bin/env bash
set -euo pipefail

manager=${1:?manager script required}
fake_runner=${2:-"$(dirname "$0")/fake-runner.sh"}
test_root=$(mktemp -d)
supervisor_pid=

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
case "${1:-}" in
  flake)
    source_ref=${*: -1}
    source_path=${source_ref#path:}
    rm -rf -- "$FAKE_ARCHIVE"
    cp -a "$source_path" "$FAKE_ARCHIVE"
    : >"$FAKE_ARCHIVE_READY"
    while [[ ! -e "$FAKE_ARCHIVE_RELEASE" ]]; do sleep 0.02; done
    jq -cn --arg path "$FAKE_ARCHIVE" '{path:$path}'
    ;;
  build)
    printf '%s\n' "$FAKE_BUILD_OUTPUT"
    ;;
  *) exit 64 ;;
esac
EOF
sed -i "1c#!$(command -v bash)" "$fake_nix"
chmod +x "$fake_nix"

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
JITTER_MIN_SECONDS=0
JITTER_MAX_SECONDS=0
EPHEMERAL_ROOT=1
ROOT_DISK_FILE='root.qcow2'
PERSISTENT_DISK_ENABLE=0
PERSISTENT_DISK_FILE='state.qcow2'
PERSISTENT_DISK_SIZE='1G'
STOP_GRACE_SECONDS=1
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

# Admission is non-activating and first explicit start promotes the baseline.
bash "$manager" register "$config" "$baseline" host-generation baseline-id
[[ $(jq -r '.candidate.sourceKind' "$test_root/state/state.json") == host-generation ]]
[[ ! -e "$observation/active" ]]
bash "$manager" prepare-start "$config"
bash "$manager" supervise "$config" &
supervisor_pid=$!
wait_for 'baseline promotion' "test \"\$(jq -r .current.image '$test_root/state/state.json')\" = '$baseline'"
[[ $(cat "$observation/active") == baseline ]]

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

printf 'all manager module tests passed\n'
