#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'nixos-shell-vm-manager: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
internal usage:
  nixos-shell-vm-manager register CONFIG IMAGE SOURCE_KIND SOURCE_ID
  nixos-shell-vm-manager prepare-start CONFIG
  nixos-shell-vm-manager stop CONFIG [SUPERVISOR_PID]
  nixos-shell-vm-manager supervise CONFIG
  nixos-shell-vm-manager update CONFIG LOCAL_FLAKE
  nixos-shell-vm-manager rollout CONFIG
  nixos-shell-vm-manager status CONFIG
  nixos-shell-vm-manager dispatch-update CONFIG_DIR VM LOCAL_FLAKE
  nixos-shell-vm-manager dispatch-rollout CONFIG_DIR VM
  nixos-shell-vm-manager dispatch-status CONFIG_DIR VM
EOF
  exit 64
}

valid_vm_name() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]
}

config_for_name() {
  local config_dir=$1
  local name=$2
  valid_vm_name "$name" || die "invalid VM name: $name"
  local config="$config_dir/$name.conf"
  [[ -f "$config" ]] || die "unmanaged VM: $name"
  printf '%s\n' "$config"
}

load_config() {
  local config=$1
  [[ -f "$config" ]] || die "missing instance configuration: $config"
  # The module creates this as a root-owned Nix-store file. Tests use an
  # isolated, explicitly trusted equivalent.
  # shellcheck disable=SC1090
  source "$config"

  : "${VM_NAME:?}" "${STATE_DIR:?}" "${RUNTIME_DIR:?}" "${PERSISTENT_DIR:?}"
  : "${GC_ROOT_DIR:?}" "${CONTROL_DIR:?}" "${LOCK_DIR:?}"
  : "${RUNNER_RELATIVE_PATH:?}" "${HEALTH_COMMAND:?}" "${SYSTEMD_UNIT:?}"
  valid_vm_name "$VM_NAME" || die "invalid configured VM name: $VM_NAME"
}

require_mutation_authority() {
  if [[ ${ALLOW_UNPRIVILEGED:-0} != 1 && $EUID -ne 0 ]]; then
    die "this operation must run as root"
  fi
}

atomic_text() {
  local target=$1
  local value=$2
  local temporary="${target}.tmp.$$"
  printf '%s\n' "$value" >"$temporary"
  chmod 0600 "$temporary"
  mv -fT "$temporary" "$target"
}

ensure_directories() {
  mkdir -p "$STATE_DIR" "$RUNTIME_DIR" "$PERSISTENT_DIR" \
    "$GC_ROOT_DIR" "$CONTROL_DIR" "$LOCK_DIR" "$BUILD_TOKEN_DIRECTORY"
  chmod 0700 "$STATE_DIR" "$CONTROL_DIR"
}

initialize_state_unlocked() {
  local state_file="$STATE_DIR/state.json"
  [[ -e "$state_file" ]] && return 0
  local temporary="${state_file}.tmp.$$"
  jq -n '{
    schemaVersion: 1,
    phase: "idle",
    current: null,
    candidate: null,
    previous: null,
    failed: null,
    lastError: null
  }' >"$temporary"
  chmod 0600 "$temporary"
  mv -fT "$temporary" "$state_file"
}

lock_lifecycle() {
  ensure_directories
  exec {LIFECYCLE_FD}>"$LOCK_DIR/lifecycle.lock"
  flock "$LIFECYCLE_FD"
  initialize_state_unlocked
}

unlock_lifecycle() {
  flock -u "$LIFECYCLE_FD"
  exec {LIFECYCLE_FD}>&-
}

write_state_from_file_unlocked() {
  local source=$1
  chmod 0600 "$source"
  mv -fT "$source" "$STATE_DIR/state.json"
}

set_phase_unlocked() {
  local phase=$1
  local error=${2:-}
  local temporary="$STATE_DIR/state.json.tmp.$$"
  if [[ -n "$error" ]]; then
    jq --arg phase "$phase" --arg error "$error" \
      '.phase = $phase | .lastError = $error' \
      "$STATE_DIR/state.json" >"$temporary"
  else
    jq --arg phase "$phase" \
      '.phase = $phase | .lastError = null' \
      "$STATE_DIR/state.json" >"$temporary"
  fi
  write_state_from_file_unlocked "$temporary"
}

slot_image_unlocked() {
  local slot=$1
  jq -r --arg slot "$slot" '.[$slot].image // empty' "$STATE_DIR/state.json"
}

retain_image_unlocked() {
  local image=$1
  local root_id
  root_id=$(printf '%s' "$image" | sha256sum | cut -d ' ' -f 1)
  local target="$GC_ROOT_DIR/$root_id"
  local temporary="$GC_ROOT_DIR/.${root_id}.tmp.$$"
  ln -s "$image" "$temporary"
  mv -fT "$temporary" "$target"
}

prune_roots_unlocked() {
  local retained
  retained=$(jq -r '[.current, .candidate, .previous, .failed][] | .image? // empty' \
    "$STATE_DIR/state.json")
  local link image keep
  shopt -s nullglob
  for link in "$GC_ROOT_DIR"/*; do
    [[ -L "$link" ]] || continue
    image=$(readlink -f "$link" 2>/dev/null || true)
    keep=0
    while IFS= read -r retained_image; do
      if [[ -n "$retained_image" && "$image" == "$retained_image" ]]; then
        keep=1
        break
      fi
    done <<<"$retained"
    if [[ $keep -eq 0 ]]; then
      rm -f -- "$link"
    fi
  done
  shopt -u nullglob
}

validate_image() {
  local image
  image=$(readlink -f "$1") || die "image does not exist: $1"
  if [[ ${REQUIRE_STORE_IMAGES:-1} == 1 && "$image" != /nix/store/* ]]; then
    die "image is not an immutable Nix store path: $image"
  fi
  [[ -x "$image/$RUNNER_RELATIVE_PATH" ]] || \
    die "image lacks executable $RUNNER_RELATIVE_PATH: $image"
  printf '%s\n' "$image"
}

register_image() {
  local config=$1 image_arg=$2 source_kind=$3 source_identity=$4
  load_config "$config"
  require_mutation_authority
  case "$source_kind" in
    host-generation|local-working-tree) ;;
    *) die "invalid candidate source kind: $source_kind" ;;
  esac

  local image admitted_at record current failed temporary
  image=$(validate_image "$image_arg")
  admitted_at=$(date --utc +%Y-%m-%dT%H:%M:%SZ)
  record=$(jq -cn \
    --arg image "$image" \
    --arg sourceKind "$source_kind" \
    --arg sourceIdentity "$source_identity" \
    --arg admittedAt "$admitted_at" \
    '{image:$image,sourceKind:$sourceKind,sourceIdentity:$sourceIdentity,admittedAt:$admittedAt}')

  lock_lifecycle
  retain_image_unlocked "$image"
  current=$(slot_image_unlocked current)
  failed=$(slot_image_unlocked failed)
  temporary="$STATE_DIR/state.json.tmp.$$"

  if [[ "$image" == "$current" ]]; then
    jq '.candidate = null' "$STATE_DIR/state.json" >"$temporary"
    printf '%s: baseline/local output is already current; pending candidate cleared\n' "$VM_NAME"
  elif [[ "$source_kind" == host-generation && "$image" == "$failed" ]]; then
    jq '.candidate = null' "$STATE_DIR/state.json" >"$temporary"
    printf '%s: failed baseline remains quarantined and will not be retried automatically\n' "$VM_NAME" >&2
  else
    jq --argjson record "$record" '.candidate = $record' \
      "$STATE_DIR/state.json" >"$temporary"
    printf '%s: admitted %s candidate %s\n' "$VM_NAME" "$source_kind" "$image"
  fi
  write_state_from_file_unlocked "$temporary"
  prune_roots_unlocked
  unlock_lifecycle
}

intent_lock() {
  ensure_directories
  exec {INTENT_FD}>"$CONTROL_DIR/intent.lock"
  flock "$INTENT_FD"
}

intent_unlock() {
  flock -u "$INTENT_FD"
  exec {INTENT_FD}>&-
}

current_epoch_unlocked() {
  local epoch=0
  if [[ -r "$CONTROL_DIR/epoch" ]]; then
    read -r epoch <"$CONTROL_DIR/epoch"
  fi
  [[ "$epoch" =~ ^[0-9]+$ ]] || epoch=0
  printf '%s\n' "$epoch"
}

authorize_start() {
  local reason=$1
  intent_lock
  local epoch
  epoch=$(current_epoch_unlocked)
  epoch=$((epoch + 1))
  atomic_text "$CONTROL_DIR/epoch" "$epoch"
  rm -f -- "$CONTROL_DIR/stopped"
  atomic_text "$CONTROL_DIR/start-reason" "$reason"
  intent_unlock
  printf '%s\n' "$epoch"
}

mark_stopped() {
  intent_lock
  local epoch
  epoch=$(current_epoch_unlocked)
  epoch=$((epoch + 1))
  atomic_text "$CONTROL_DIR/epoch" "$epoch"
  atomic_text "$CONTROL_DIR/stopped" "explicit-stop"
  rm -f -- "$CONTROL_DIR/preauthorized" "$CONTROL_DIR/force-candidate"
  intent_unlock
}

prepare_start() {
  local config=$1
  load_config "$config"
  require_mutation_authority
  ensure_directories
  if [[ -e "$CONTROL_DIR/preauthorized" && ! -e "$CONTROL_DIR/stopped" ]]; then
    rm -f -- "$CONTROL_DIR/preauthorized"
  else
    authorize_start explicit-start >/dev/null
  fi
}

stop_service() {
  local config=$1 supervisor_pid=${2:-}
  load_config "$config"
  require_mutation_authority
  mark_stopped
  if [[ "$supervisor_pid" =~ ^[0-9]+$ ]] && kill -0 "$supervisor_pid" 2>/dev/null; then
    kill -TERM "$supervisor_pid" 2>/dev/null || true
  fi
}

authority_matches() {
  local expected=$1 actual
  intent_lock
  actual=$(current_epoch_unlocked)
  if [[ "$actual" == "$expected" && ! -e "$CONTROL_DIR/stopped" ]]; then
    intent_unlock
    return 0
  fi
  intent_unlock
  return 1
}

random_jitter() {
  local minimum=$1 maximum=$2 span
  if (( maximum == minimum )); then
    printf '%s\n' "$minimum"
    return
  fi
  span=$((maximum - minimum + 1))
  printf '%s\n' $((minimum + RANDOM % span))
}

qmp_powerdown() {
  [[ -S "$CONTROL_DIR/qmp.sock" ]] || return 0
  printf '%s\n%s\n' \
    '{"execute":"qmp_capabilities"}' \
    '{"execute":"system_powerdown"}' | \
    socat -t 1 - "UNIX-CONNECT:$CONTROL_DIR/qmp.sock" >/dev/null 2>&1 || true
}

stop_child() {
  local child_pid=$1
  kill -0 "$child_pid" 2>/dev/null || return 0
  qmp_powerdown
  kill -TERM "$child_pid" 2>/dev/null || true
  local count=0
  while kill -0 "$child_pid" 2>/dev/null && (( count < STOP_GRACE_SECONDS * 10 )); do
    sleep 0.1
    count=$((count + 1))
  done
  if kill -0 "$child_pid" 2>/dev/null; then
    kill -KILL "$child_pid" 2>/dev/null || true
  fi
  wait "$child_pid" 2>/dev/null || true
}

prepare_storage_unlocked() {
  mkdir -p "$RUNTIME_DIR" "$PERSISTENT_DIR" "$CONTROL_DIR"
  if [[ "$EPHEMERAL_ROOT" == 1 ]]; then
    rm -f -- "$RUNTIME_DIR/$ROOT_DISK_FILE"
  fi
  rm -f -- "$CONTROL_DIR/qmp.sock"
  if [[ "$PERSISTENT_DISK_ENABLE" == 1 && ! -e "$PERSISTENT_DIR/$PERSISTENT_DISK_FILE" ]]; then
    local temporary="$PERSISTENT_DIR/.${PERSISTENT_DISK_FILE}.tmp.$$"
    qemu-img create -f qcow2 "$temporary" "$PERSISTENT_DISK_SIZE" >/dev/null
    chmod 0600 "$temporary"
    mv -fT "$temporary" "$PERSISTENT_DIR/$PERSISTENT_DISK_FILE"
  fi
}

launch_image_unlocked() {
  local image=$1
  prepare_storage_unlocked
  local runner="$image/$RUNNER_RELATIVE_PATH"
  local -a arguments qemu_arguments
  mapfile -t arguments < <(jq -r '.[]' <<<"$RUNNER_ARGUMENTS_JSON")
  mapfile -t qemu_arguments < <(jq -r '.[]' <<<"$QEMU_ARGUMENTS_JSON")
  qemu_arguments+=( -qmp "unix:$CONTROL_DIR/qmp.sock,server=on,wait=off" )
  if [[ "$PERSISTENT_DISK_ENABLE" == 1 ]]; then
    qemu_arguments+=( -drive "file=$PERSISTENT_DIR/$PERSISTENT_DISK_FILE,if=virtio,format=qcow2,cache=none" )
  fi
  (
    cd "$RUNTIME_DIR"
    export NIX_DISK_IMAGE="$RUNTIME_DIR/$ROOT_DISK_FILE"
    exec "$runner" "${arguments[@]}" "${qemu_arguments[@]}"
  ) &
  CHILD_PID=$!
  atomic_text "$CONTROL_DIR/runner.pid" "$CHILD_PID"
}

health_check_unlocked() {
  local child_pid=$1 attempt=1
  while (( attempt <= HEALTH_RETRIES )); do
    if ! kill -0 "$child_pid" 2>/dev/null; then
      printf '%s: runner process exited before health succeeded\n' "$VM_NAME" >&2
      return 1
    fi
    if timeout --foreground "$HEALTH_TIMEOUT_SECONDS" bash -c "$HEALTH_COMMAND"; then
      kill -0 "$child_pid" 2>/dev/null || return 1
      return 0
    fi
    if (( attempt < HEALTH_RETRIES )); then
      sleep "$HEALTH_INTERVAL_SECONDS"
    fi
    attempt=$((attempt + 1))
  done
  printf '%s: functional health failed after %s attempts\n' "$VM_NAME" "$HEALTH_RETRIES" >&2
  return 1
}

select_image_unlocked() {
  local event=$1 current candidate use_candidate=0
  current=$(slot_image_unlocked current)
  candidate=$(slot_image_unlocked candidate)
  case "$event" in
    force-candidate) use_candidate=1 ;;
    explicit-start) [[ "$USE_CANDIDATE_ON_EXPLICIT_START" == 1 ]] && use_candidate=1 ;;
    guest-shutdown) [[ "$ROLLOUT_CANDIDATE_ON_GUEST_SHUTDOWN" == 1 ]] && use_candidate=1 ;;
    boot) use_candidate=0 ;;
    *) die "invalid supervisor event: $event" ;;
  esac
  if [[ $use_candidate -eq 1 && -n "$candidate" ]]; then
    SELECTED_SLOT=candidate
    SELECTED_IMAGE=$candidate
  elif [[ -n "$current" ]]; then
    SELECTED_SLOT=current
    SELECTED_IMAGE=$current
  elif [[ "$event" == force-candidate && -n "$candidate" ]]; then
    SELECTED_SLOT=candidate
    SELECTED_IMAGE=$candidate
  else
    return 1
  fi
}

promote_candidate_unlocked() {
  local expected=$1 temporary="$STATE_DIR/state.json.tmp.$$"
  jq --arg expected "$expected" '
    if .candidate.image != $expected then error("candidate changed during activation")
    else .previous = .current | .current = .candidate | .candidate = null |
      .phase = "running" | .lastError = null end
  ' "$STATE_DIR/state.json" >"$temporary"
  write_state_from_file_unlocked "$temporary"
  prune_roots_unlocked
}

fail_candidate_unlocked() {
  local expected=$1 error=$2 temporary="$STATE_DIR/state.json.tmp.$$"
  jq --arg expected "$expected" --arg error "$error" '
    if .candidate.image != $expected then error("candidate changed during activation")
    else .failed = .candidate | .candidate = null | .phase = "rolling-back" |
      .lastError = $error end
  ' "$STATE_DIR/state.json" >"$temporary"
  write_state_from_file_unlocked "$temporary"
  prune_roots_unlocked
}

activate_event() {
  local event=$1
  lock_lifecycle
  if [[ -e "$CONTROL_DIR/stopped" ]]; then
    unlock_lifecycle
    printf '%s: start blocked by explicit-stop authority\n' "$VM_NAME" >&2
    return 75
  fi
  if ! select_image_unlocked "$event"; then
    set_phase_unlocked operator-intervention "no selectable image for $event"
    unlock_lifecycle
    return 1
  fi

  local selected_slot=$SELECTED_SLOT selected_image=$SELECTED_IMAGE
  set_phase_unlocked activating
  launch_image_unlocked "$selected_image"
  local candidate_pid=$CHILD_PID
  if health_check_unlocked "$candidate_pid"; then
    if [[ "$selected_slot" == candidate ]]; then
      promote_candidate_unlocked "$selected_image"
      printf '%s: candidate promoted to current\n' "$VM_NAME"
    else
      set_phase_unlocked running
    fi
    unlock_lifecycle
    return 0
  fi

  stop_child "$candidate_pid"
  rm -f -- "$CONTROL_DIR/runner.pid"
  if [[ "$selected_slot" != candidate ]]; then
    set_phase_unlocked operator-intervention "known-good image failed health"
    unlock_lifecycle
    return 1
  fi

  fail_candidate_unlocked "$selected_image" "candidate failed health"
  local recovery
  recovery=$(slot_image_unlocked current)
  if [[ -z "$recovery" ]]; then
    set_phase_unlocked operator-intervention "candidate failed and no recovery image exists"
    unlock_lifecycle
    return 1
  fi

  launch_image_unlocked "$recovery"
  local recovery_pid=$CHILD_PID
  if health_check_unlocked "$recovery_pid"; then
    set_phase_unlocked running
    printf '%s: candidate failed; healthy current image restored\n' "$VM_NAME" >&2
    unlock_lifecycle
    return 0
  fi
  stop_child "$recovery_pid"
  rm -f -- "$CONTROL_DIR/runner.pid"
  set_phase_unlocked operator-intervention "candidate and recovery image failed health"
  unlock_lifecycle
  return 1
}

supervise() {
  local config=$1
  load_config "$config"
  require_mutation_authority
  ensure_directories

  local stopping=0 rollout_requested=0 child_status=0 event
  CHILD_PID=

  on_term() {
    stopping=1
    mark_stopped
    if [[ ${CHILD_PID:-} =~ ^[0-9]+$ ]]; then
      stop_child "$CHILD_PID"
    fi
  }
  on_rollout() {
    rollout_requested=1
    if [[ ${CHILD_PID:-} =~ ^[0-9]+$ ]]; then
      stop_child "$CHILD_PID"
    fi
  }
  trap on_term TERM INT
  trap on_rollout USR1

  event=explicit-start
  if [[ -r "$CONTROL_DIR/start-reason" ]]; then
    read -r event <"$CONTROL_DIR/start-reason"
  fi
  if [[ -e "$CONTROL_DIR/force-candidate" ]]; then
    event=force-candidate
    rm -f -- "$CONTROL_DIR/force-candidate"
  fi

  while true; do
    activate_event "$event" || return $?
    local active_pid=$CHILD_PID
    child_status=0
    while kill -0 "$active_pid" 2>/dev/null; do
      set +e
      wait "$active_pid"
      child_status=$?
      set -e
      if ! kill -0 "$active_pid" 2>/dev/null; then
        break
      fi
    done
    rm -f -- "$CONTROL_DIR/runner.pid" "$CONTROL_DIR/qmp.sock"

    if [[ $stopping -eq 1 ]]; then
      return 0
    fi
    if [[ $rollout_requested -eq 1 ]]; then
      rollout_requested=0
      event=force-candidate
      continue
    fi

    lock_lifecycle
    set_phase_unlocked idle "guest runner exited with status $child_status"
    unlock_lifecycle
    if [[ "$RESTART_ON_GUEST_SHUTDOWN" != 1 ]]; then
      printf '%s: guest stopped; restart policy is disabled\n' "$VM_NAME"
      return 0
    fi
    local delay
    delay=$(random_jitter "$JITTER_MIN_SECONDS" "$JITTER_MAX_SECONDS")
    printf '%s: guest stopped; restarting after %s seconds\n' "$VM_NAME" "$delay"
    sleep "$delay"
    if [[ -e "$CONTROL_DIR/stopped" ]]; then
      printf '%s: guest restart revoked by explicit stop\n' "$VM_NAME" >&2
      return 0
    fi
    event=guest-shutdown
  done
}

acquire_build_token() {
  local token
  while true; do
    for ((token = 1; token <= MAX_CONCURRENT_BUILDS; token++)); do
      exec {candidate_fd}>"$BUILD_TOKEN_DIRECTORY/token-$token.lock"
      if flock -n "$candidate_fd"; then
        BUILD_TOKEN_FD=$candidate_fd
        return 0
      fi
      exec {candidate_fd}>&-
    done
    sleep 0.2
  done
}

request_rollout_with_epoch() {
  local expected_epoch=$1
  authority_matches "$expected_epoch" || return 75
  lock_lifecycle
  local candidate
  candidate=$(slot_image_unlocked candidate)
  unlock_lifecycle
  [[ -n "$candidate" ]] || die "$VM_NAME has no pending candidate"
  atomic_text "$CONTROL_DIR/force-candidate" "1"
  if "$SYSTEMCTL_BIN" is-active --quiet "$SYSTEMD_UNIT"; then
    "$SYSTEMCTL_BIN" kill --kill-whom=main --signal=USR1 "$SYSTEMD_UNIT"
  else
    atomic_text "$CONTROL_DIR/preauthorized" "1"
    "$SYSTEMCTL_BIN" reset-failed "$SYSTEMD_UNIT" >/dev/null 2>&1 || true
    "$SYSTEMCTL_BIN" start "$SYSTEMD_UNIT"
  fi
}

rollout() {
  local config=$1
  load_config "$config"
  require_mutation_authority
  local epoch
  epoch=$(authorize_start explicit-rollout)
  request_rollout_with_epoch "$epoch"
}

update_from_local_flake() {
  local config=$1 source_path=$2
  load_config "$config"
  require_mutation_authority
  [[ -d "$source_path" ]] || die "local flake directory does not exist: $source_path"
  source_path=$(realpath "$source_path")
  [[ -f "$source_path/flake.nix" ]] || die "local source lacks flake.nix: $source_path"
  [[ -f "$source_path/flake.lock" ]] || die "local source lacks required flake.lock: $source_path"

  ensure_directories
  local epoch
  epoch=$(authorize_start local-update)
  exec {CONSTRUCTION_FD}>"$LOCK_DIR/construction.lock"
  flock "$CONSTRUCTION_FD"
  acquire_build_token

  local archive_json archive output_lines output
  archive_json=$("$NIX_BIN" flake archive --json --no-update-lock-file \
    --no-write-lock-file "path:$source_path")
  archive=$(jq -r '.path // empty' <<<"$archive_json")
  if [[ ${REQUIRE_STORE_IMAGES:-1} == 1 ]]; then
    [[ "$archive" == /nix/store/* ]] || die "Nix did not return an immutable source archive"
  else
    [[ -d "$archive" ]] || die "test archive path does not exist"
  fi

  output_lines=$("$NIX_BIN" build --no-link --print-out-paths \
    --no-update-lock-file --no-write-lock-file \
    "path:$archive#$LOCAL_FLAKE_ATTRIBUTE")
  if [[ $(grep -c . <<<"$output_lines") -ne 1 ]]; then
    die "local image build returned an unexpected number of outputs"
  fi
  output=$(head -n 1 <<<"$output_lines")
  register_image "$config" "$output" local-working-tree "$archive"

  flock -u "$BUILD_TOKEN_FD"
  exec {BUILD_TOKEN_FD}>&-
  flock -u "$CONSTRUCTION_FD"
  exec {CONSTRUCTION_FD}>&-

  local rollout_status=0
  request_rollout_with_epoch "$epoch" || rollout_status=$?
  if [[ $rollout_status -ne 0 ]]; then
    local status=$rollout_status
    if [[ $status -eq 75 ]]; then
      printf '%s: candidate is pending; a later explicit stop revoked rollout\n' "$VM_NAME" >&2
    fi
    return "$status"
  fi
}

show_status() {
  local config=$1
  load_config "$config"
  ensure_directories
  lock_lifecycle
  local stopped=false epoch running_pid=
  [[ -e "$CONTROL_DIR/stopped" ]] && stopped=true
  epoch=$(current_epoch_unlocked)
  [[ -r "$CONTROL_DIR/runner.pid" ]] && read -r running_pid <"$CONTROL_DIR/runner.pid"
  jq --argjson stopped "$stopped" --arg epoch "$epoch" --arg runnerPid "$running_pid" \
    '. + {authority:{explicitlyStopped:$stopped,epoch:($epoch|tonumber)},runnerPid:(if $runnerPid == "" then null else ($runnerPid|tonumber) end)}' \
    "$STATE_DIR/state.json"
  unlock_lifecycle
}

dispatch_update() {
  [[ $# -eq 3 ]] || usage
  local config
  config=$(config_for_name "$1" "$2")
  update_from_local_flake "$config" "$3"
}

dispatch_rollout() {
  [[ $# -eq 2 ]] || usage
  local config
  config=$(config_for_name "$1" "$2")
  rollout "$config"
}

dispatch_status() {
  [[ $# -eq 2 ]] || usage
  local config
  config=$(config_for_name "$1" "$2")
  show_status "$config"
}

[[ $# -ge 1 ]] || usage
command_name=$1
shift
case "$command_name" in
  register) [[ $# -eq 4 ]] || usage; register_image "$@" ;;
  prepare-start) [[ $# -eq 1 ]] || usage; prepare_start "$@" ;;
  stop) [[ $# -ge 1 && $# -le 2 ]] || usage; stop_service "$@" ;;
  supervise) [[ $# -eq 1 ]] || usage; supervise "$@" ;;
  update) [[ $# -eq 2 ]] || usage; update_from_local_flake "$@" ;;
  rollout) [[ $# -eq 1 ]] || usage; rollout "$@" ;;
  status) [[ $# -eq 1 ]] || usage; show_status "$@" ;;
  dispatch-update) dispatch_update "$@" ;;
  dispatch-rollout) dispatch_rollout "$@" ;;
  dispatch-status) dispatch_status "$@" ;;
  *) usage ;;
esac
