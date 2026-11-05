#!/usr/bin/env bash
set -euo pipefail

# Offline log analysis for downed VM images.
#
# Usage:
#   vm-logs mount   IMAGE [--mountpoint DIR] [--no-mount]
#   vm-logs collect IMAGE [--dest DIR] [--path P]... [--no-mount]
#   vm-logs umount  IMAGE
#   vm-logs status  [IMAGE]
#   vm-logs list
#
# IMAGE is the path to a qcow2 (or raw) disk image on the host -- typically a
# nixos-shell root disk such as
#   /var/cache/nixos-shell-vm-manager/<vm>/<vm>.qcow2
# or the persistent disk at /var/lib/nixos-shell-vm-manager/persistent/<vm>.
#
# The image is NEVER booted and never networked. It is attached read-only over
# NBD and mounted read-only, so analysis cannot alter the evidence. Every
# session is recorded on disk, which makes `umount` deterministic even after an
# interrupted analysis.
#
# Use `mount` when you want to explore interactively, `collect` when you want a
# deterministic copy of the logs under a directory, and `umount` to release the
# device and mountpoint.

self_dir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")

# shellcheck source=./vm-log-analyser-lib.sh disable=SC1091
source "${VM_LOGS_LIBRARY:-$self_dir/vm-log-analyser-lib.sh}"
# shellcheck source=./vm-log-artifacts.sh disable=SC1091
source "${VM_LOGS_ARTIFACTS:-$self_dir/vm-log-artifacts.sh}"

state_root=${VM_LOGS_STATE_ROOT:-/run/vm-logs}
evidence_root=${VM_LOGS_DEST_ROOT:-/tmp/vm-logs}
nbd_max_retries=${VM_LOGS_NBD_ATTACH_RETRIES:-50}
nbd_retry_interval=${VM_LOGS_NBD_ATTACH_INTERVAL_SECONDS:-0.1}

usage() {
  cat >&2 <<'USAGE'
offline log analysis for downed VM images (the image is never booted):

  vm-logs mount   IMAGE [--mountpoint DIR]
  vm-logs collect IMAGE [--dest DIR] [--path ABS]... [--no-mount]
  vm-logs umount  IMAGE
  vm-logs status  [IMAGE]
  vm-logs list

IMAGE is a qcow2/raw disk image on this host, e.g.
  /var/cache/nixos-shell-vm-manager/<vm>/<vm>.qcow2
  /var/lib/nixos-shell-vm-manager/persistent/<vm>/state.qcow2

The image is attached read-only over NBD and mounted read-only, so analysis
cannot modify it. mount/copy/unmount are all deterministic and idempotent.

`collect` reuses an active `mount` instead of attaching the image twice, and
leaves that interactive mount in place; run `umount` when finished. With no
active session it attaches, collects, and releases everything itself.
USAGE
  exit "${1:-64}"
}

# ---------------------------------------------------------------------------
# Argument parsing helpers
# ---------------------------------------------------------------------------

# Split `IMAGE [--option VALUE]...` into a canonical image path plus options.
# Kept explicit (rather than getopt) so the positional IMAGE may appear first
# and unknown options fail loudly instead of being ignored.
parse_image_and_options() {
  local -n _image_out=$1
  local -n _options_out=$2
  shift 2

  if (( $# == 0 )); then
    usage
  fi

  local first=$1
  if [[ $first == -* ]]; then
    usage
  fi
  _image_out=$first
  shift

  _options_out=()
  while (( $# > 0 )); do
    case "$1" in
      --mountpoint | --dest | --path)
        (( $# >= 2 )) || die "option $1 requires a value"
        _options_out+=( "$1" "$2" )
        shift 2
        ;;
      --no-mount)
        _options_out+=( "$1" )
        shift
        ;;
      -h | --help)
        usage 0
        ;;
      *)
        die "unknown option: $1"
        ;;
    esac
  done
}

option_value() {
  local name=$1
  shift
  local -a options=("$@")
  local index
  for (( index = 0; index < ${#options[@]}; index++ )); do
    if [[ ${options[index]} == "$name" ]]; then
      printf '%s\n' "${options[index + 1]}"
      return 0
    fi
  done
  return 1
}

has_flag() {
  local name=$1
  shift
  local option
  for option in "$@"; do
    [[ $option == "$name" ]] && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------
# Attachment lifecycle
# ---------------------------------------------------------------------------

# Wait for the kernel to expose the NBD device's size. `qemu-nbd --connect`
# returns before the block device is necessarily usable, so a mount performed
# immediately afterwards can race and fail with a confusing "no medium" error.
wait_for_nbd_ready() {
  local device=$1
  local attempt size

  for (( attempt = 1; attempt <= nbd_max_retries; attempt++ )); do
    size=$(cat "/sys/block/$(basename "$device")/size" 2>/dev/null || true)
    if [[ ${size:-0} -gt 0 ]]; then
      return 0
    fi
    sleep "$nbd_retry_interval"
  done

  return 1
}

# Attach the image and pick its guest root filesystem, without mounting it.
# Records the session so umount can always clean up.
attach_session() {
  local image=$1
  local session_dir=$2
  local device

  require_tool qemu-img "reads qcow metadata"
  require_tool qemu-nbd "attaches the image read-only"
  require_tool blkid "detects the guest filesystem"

  if ! device=$(choose_nbd_device); then
    local attached
    attached=$(list_attached_nbd_devices)
    if [[ -n $attached ]]; then
      # A leaked attachment is the usual cause, so name it rather than blaming
      # the module: the operator can then detach or raise nbds_max knowingly.
      die "no free NBD device: $(tr '\n' ' ' <<<"$attached")still attached. Detach it (qemu-nbd --disconnect DEV) or raise nbds_max."
    fi
    die "no NBD device available; load the nbd module (modprobe nbd nbds_max=16)"
  fi

  nbd_attach_readonly "$image" "$device"

  if ! wait_for_nbd_ready "$device"; then
    nbd_detach "$device" || true
    die "attached image did not become readable on $device"
  fi

  local candidates root
  candidates=$(probe_filesystems "$device")

  if ! root=$(select_root_filesystem "$candidates"); then
    nbd_detach "$device" || true
    if [[ -z $candidates ]]; then
      die "no filesystem found in $image; is this really a VM disk image?"
    fi
    die "no supported root filesystem found in $image (candidates: $(tr '\n' ' ' <<<"$candidates"))"
  fi

  local offset fstype label
  IFS=$'\t' read -r offset fstype label <<<"$root"

  session_write_metadata "$session_dir" "$image" "$device" "" "$offset" "$fstype" "$label"
  printf '%s\n' "$fstype"
}

command_mount() {
  local image options
  parse_image_and_options image options "$@"
  image=$(require_qcow_path "$image")

  local session_dir
  session_dir=$(session_dir_for "$state_root" "$image")

  if session_exists "$session_dir"; then
    local existing_mountpoint
    existing_mountpoint=$(session_read_metadata "$session_dir" mountpoint)
    if [[ -n $existing_mountpoint ]] && is_mountpoint "$existing_mountpoint"; then
      printf '%s\n' "$existing_mountpoint"
      return 0
    fi
    # A stale session record (host rebooted, or the previous run crashed before
    # mounting) must not block a new analysis.
    log_warn "discarding stale session for $image"
    teardown_session "$session_dir" || true
  fi

  require_tool mount "mounts the guest root read-only"

  local mountpoint
  if ! mountpoint=$(option_value --mountpoint "${options[@]}"); then
    mountpoint="${evidence_root}/$(session_key_for "$image").mount"
  fi
  [[ $mountpoint == /* ]] || die "--mountpoint must be an absolute path: $mountpoint"

  mkdir -p "$session_dir"
  chmod 0700 "$session_dir"

  local fstype
  fstype=$(attach_session "$image" "$session_dir")

  local offset
  offset=$(session_read_metadata "$session_dir" offset)

  if ! mount_guest_root "$(session_read_metadata "$session_dir" device)" \
    "$mountpoint" "$offset" "$fstype"; then
    # The image is attached but not mounted. The session record still holds the
    # device, so release it rather than leaking an attachment the operator
    # cannot see.
    teardown_session "$session_dir" || true
    die "could not mount the guest root from $image; the image was detached again"
  fi

  session_write_metadata "$session_dir" "$image" \
    "$(session_read_metadata "$session_dir" device)" \
    "$mountpoint" "$offset" "$fstype" \
    "$(session_read_metadata "$session_dir" label)"

  log_info "guest root of $image is mounted read-only at $mountpoint"
  printf '%s\n' "$mountpoint"
}

# Release everything a session holds. Order is deliberate: unmount the guest
# first, then disconnect the device, so no mount can outlive its backing.
teardown_session() {
  local session_dir=$1
  local failed=0

  if ! session_exists "$session_dir"; then
    return 0
  fi

  local mountpoint device
  mountpoint=$(session_read_metadata "$session_dir" mountpoint)
  device=$(session_read_metadata "$session_dir" device)

  if [[ -n $mountpoint ]] && is_mountpoint "$mountpoint"; then
    log_info "unmounting $mountpoint"
    if ! umount "$mountpoint"; then
      log_warn "busy: could not unmount $mountpoint; leaving the session in place"
      failed=1
    fi
  fi

  if (( failed == 0 )) && [[ -n $mountpoint ]] && [[ -d $mountpoint ]]; then
    rmdir -- "$mountpoint" 2>/dev/null || true
  fi

  if (( failed == 0 )) && [[ -n $device ]]; then
    log_info "detaching $device"
    if ! nbd_detach "$device"; then
      failed=1
    fi
  fi

  if (( failed == 0 )); then
    rm -f -- "$session_dir/session.json"
    rmdir -- "$session_dir" 2>/dev/null || true
  fi

  return "$failed"
}

command_umount() {
  (( $# == 1 )) || usage
  local image
  image=$(require_qcow_path "$1")

  local session_dir
  session_dir=$(session_dir_for "$state_root" "$image")

  if ! session_exists "$session_dir"; then
    # Idempotent by design: a second umount is a statement of the desired end
    # state, not an error.
    log_info "no active session for $image"
    return 0
  fi

  if ! teardown_session "$session_dir"; then
    die "could not release $image; resolve the busy mountpoint and retry"
  fi

  log_info "released $image"
}

# ---------------------------------------------------------------------------
# Collection
# ---------------------------------------------------------------------------

# Render arguments as a JSON array of strings. An empty argument list must
# produce [] -- piping an empty line into `jq -R -s` would instead yield [""].
json_string_array() {
  if (( $# == 0 )); then
    printf '[]\n'
    return 0
  fi
  printf '%s\n' "$@" | jq -R . | jq -s .
}

# Build the JSON manifest describing what was collected and from where. This is
# the deterministic part of the tool: given the same image, the same artifact
# paths produce the same layout under --dest.
write_manifest() {
  local destination=$1
  local image=$2
  local filesystem=$3
  local collected_json=$4
  local missing_json=$5

  jq -n \
    --arg image "$image" \
    --arg filesystem "$filesystem" \
    --arg collectedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson collected "$collected_json" \
    --argjson missing "$missing_json" \
    '{
      schemaVersion: 1,
      image: $image,
      filesystem: $filesystem,
      collectedAt: $collectedAt,
      collected: $collected,
      missing: $missing
    }' >"$destination/manifest.json"
}

command_collect() {
  local image options
  parse_image_and_options image options "$@"
  image=$(require_qcow_path "$image")

  local destination
  if ! destination=$(option_value --dest "${options[@]}"); then
    destination="${evidence_root}/$(session_key_for "$image")"
  fi
  [[ $destination == /* ]] || die "--dest must be an absolute path: $destination"

  # An explicit --path list replaces (rather than extends) the defaults, so a
  # caller can target a single file deterministically.
  local -a artifacts=()
  local index
  for (( index = 0; index < ${#options[@]}; index++ )); do
    if [[ ${options[index]} == --path ]]; then
      artifacts+=( "${options[index + 1]}" )
    fi
  done
  if (( ${#artifacts[@]} == 0 )); then
    mapfile -t artifacts < <(default_artifact_paths)
  fi

  local artifact
  for artifact in "${artifacts[@]}"; do
    [[ $artifact == /* ]] || die "--path must be absolute: $artifact"
    [[ $artifact != *'..'* ]] || die "--path must not contain '..': $artifact"
  done

  local session_dir
  session_dir=$(session_dir_for "$state_root" "$image")

  local cleanup_after_mount=false
  local fstype
  if session_exists "$session_dir"; then
    fstype=$(session_read_metadata "$session_dir" filesystem)
  else
    mkdir -p "$session_dir"
    chmod 0700 "$session_dir"
    fstype=$(attach_session "$image" "$session_dir")
    cleanup_after_mount=true
  fi

  mkdir -p "$destination"
  chmod 0700 "$destination"

  local -a collected=()
  local -a missing=()
  local device mountpoint offset
  device=$(session_read_metadata "$session_dir" device)
  offset=$(session_read_metadata "$session_dir" offset)

  local use_debugfs=false
  mountpoint=
  if ! has_flag --no-mount "${options[@]}"; then
    if tool_available mount; then
      mountpoint=$(session_read_metadata "$session_dir" mountpoint)
      if [[ -z $mountpoint ]]; then
        if ! mountpoint=$(option_value --mountpoint "${options[@]}"); then
          mountpoint="${evidence_root}/$(session_key_for "$image").mount"
        fi
        [[ $mountpoint == /* ]] || die "--mountpoint must be an absolute path: $mountpoint"
      fi
      if ! is_mountpoint "$mountpoint"; then
        if mount_guest_root "$device" "$mountpoint" "$offset" "$fstype"; then
          session_write_metadata "$session_dir" "$image" "$device" \
            "$mountpoint" "$offset" "$fstype" \
            "$(session_read_metadata "$session_dir" label)"
        else
          mountpoint=
          use_debugfs=true
        fi
      fi
    else
      use_debugfs=true
    fi
  else
    use_debugfs=true
  fi

  if [[ $use_debugfs == true ]]; then
    require_tool debugfs "extracts files without mounting"
  fi

  for artifact in "${artifacts[@]}"; do
    local extracted=false
    if [[ -n $mountpoint ]]; then
      extracted=true
      collect_artifact "$mountpoint" "$artifact" "$destination" || extracted=false
    fi
    if [[ $extracted == false && $use_debugfs == true ]]; then
      extracted=true
      debugfs_extract "$device" "$artifact" "$destination" || extracted=false
    fi

    if [[ $extracted == true ]]; then
      collected+=( "$artifact" )
    else
      missing+=( "$artifact" )
    fi
  done

  local collected_json missing_json
  collected_json=$(json_string_array "${collected[@]+"${collected[@]}"}")
  missing_json=$(json_string_array "${missing[@]+"${missing[@]}"}")

  write_manifest "$destination" "$image" "$fstype" "$collected_json" "$missing_json"

  log_info "collected ${#collected[@]} artifact(s), ${#missing[@]} absent, into $destination"
  list_collected "$destination" >&2 || true

  if [[ $cleanup_after_mount == true ]]; then
    teardown_session "$session_dir" || true
  fi

  printf '%s\n' "$destination"
}

# ---------------------------------------------------------------------------
# Introspection
# ---------------------------------------------------------------------------

command_status() {
  if (( $# == 0 )); then
    command_list
    return 0
  fi
  (( $# == 1 )) || usage

  local image
  image=$(require_qcow_path "$1")
  local session_dir
  session_dir=$(session_dir_for "$state_root" "$image")

  if ! session_exists "$session_dir"; then
    jq -n --arg image "$image" \
      '{image:$image, active:false, mounted:false}' 
    return 0
  fi

  local mountpoint device
  mountpoint=$(session_read_metadata "$session_dir" mountpoint)
  device=$(session_read_metadata "$session_dir" device)

  local mounted=false
  if [[ -n $mountpoint ]] && is_mountpoint "$mountpoint"; then
    mounted=true
  fi

  jq -n \
    --arg image "$image" \
    --argjson active true \
    --argjson mounted "$mounted" \
    --arg device "$device" \
    --arg mountpoint "$mountpoint" \
    --arg filesystem "$(session_read_metadata "$session_dir" filesystem)" \
    --arg createdAt "$(session_read_metadata "$session_dir" createdAt)" \
    '{
      image: $image,
      active: $active,
      mounted: $mounted,
      device: (if $device == "" then null else $device end),
      mountpoint: (if $mountpoint == "" then null else $mountpoint end),
      filesystem: (if $filesystem == "" then null else $filesystem end),
      attachedAt: (if $createdAt == "" then null else $createdAt end)
    }'
}

command_list() {
  local found=false dir
  if [[ -d $state_root ]]; then
    for dir in "$state_root"/*; do
      [[ -d $dir ]] || continue
      session_exists "$dir" || continue
      found=true
      command_status "$(session_read_metadata "$dir" image)"
    done
  fi
  if [[ $found == false ]]; then
    printf 'no active sessions under %s\n' "$state_root" >&2
  fi
}

# ---------------------------------------------------------------------------

[[ $# -ge 1 ]] || usage
command_name=$1
shift
case "$command_name" in
  help | -h | --help) usage 0 ;;
  mount) command_mount "$@" ;;
  collect) command_collect "$@" ;;
  umount | unmount) command_umount "$@" ;;
  status) command_status "$@" ;;
  list) (( $# == 0 )) || usage; command_list ;;
  *) usage ;;
esac
