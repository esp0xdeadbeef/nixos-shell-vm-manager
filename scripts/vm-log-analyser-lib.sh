# shellcheck shell=bash
# Offline QCOW log-analysis library used by the `vm-logs` operator command.
#
# Sourcing this file provides the primitives the `vm-logs` script composes into
# mount / collect / umount. Every path here is a HOST path: the guest image is
# never booted, never networked, and never handed to a guest agent. The disk is
# attached read-only, so analysis can never modify evidence.
#
# The caller must provide bash and coreutils. Optional-but-required-for-mount
# tools (qemu-img, qemu-nbd, mount, umount, debugfs) are resolved through
# $PATH and reported individually, because a host can legitimately analyse
# with a subset (e.g. debugfs extraction without any kernel mount support).

# ---------------------------------------------------------------------------
# Diagnostics
# ---------------------------------------------------------------------------

# All human-facing diagnostics go to stderr so stdout stays machine-readable
# (collect writes a JSON manifest there).
log_info() {
  printf 'vm-logs: %s\n' "$*" >&2
}

log_warn() {
  printf 'vm-logs: warning: %s\n' "$*" >&2
}

die() {
  printf 'vm-logs: %s\n' "$*" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Tool resolution
# ---------------------------------------------------------------------------

tool_available() {
  local tool=$1
  command -v "$tool" >/dev/null 2>&1
}

# Require a tool, naming the exact missing binary so the operator can add it to
# the host's `environment.systemPackages` instead of guessing.
require_tool() {
  local tool=$1 purpose=${2:-}
  if ! tool_available "$tool"; then
    if [[ -n $purpose ]]; then
      die "required tool '$tool' is not available on PATH ($purpose)"
    fi
    die "required tool '$tool' is not available on PATH"
  fi
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

# A qcow reference is a filesystem path to an existing regular file. We
# deliberately do NOT accept a block device: this analyser exists for images on
# disk, and pointing it at a live device invites writing to a mounted guest.
require_qcow_path() {
  local path=$1

  if [[ -z $path ]]; then
    die "a qcow image path is required"
  fi

  # Resolve symlinks once, so the rest of the pipeline (lock identity, state
  # records, umount) all agree on one canonical absolute path.
  local resolved
  if ! resolved=$(readlink -f -- "$path"); then
    die "cannot resolve qcow image path: $path"
  fi

  if [[ ! -e $resolved ]]; then
    die "qcow image does not exist: $resolved"
  fi

  if [[ ! -f $resolved ]]; then
    die "qcow image is not a regular file: $resolved (refusing to touch a block device or directory)"
  fi

  if [[ ! -r $resolved ]]; then
    die "qcow image is not readable: $resolved"
  fi

  printf '%s\n' "$resolved"
}

# ---------------------------------------------------------------------------
# Image introspection
# ---------------------------------------------------------------------------

# Report the whole backing chain. A nixos-shell root disk is a qcow2 overlay
# whose backing file is a read-only Nix-store image shared by every generation,
# so the chain (not just the top file) describes the analysed content. This is
# informational: qemu-nbd follows the chain itself.
qcow_backing_chain() {
  local image=$1

  if qemu-img info --backing-chain --output=json "$image" 2>/dev/null; then
    return 0
  fi

  # Some qemu-img builds cannot render the chain as JSON; a plain listing is
  # still useful, so degrade instead of failing the whole analysis.
  qemu-img info --backing-chain "$image" 2>/dev/null || \
    printf '{}\n'
}

# Emit `format<TAB>virtual-size<TAB>backing-file` for the top image. Values are
# validated where they are used, not trusted.
qcow_top_info() {
  local image=$1
  local json

  json=$(qemu-img info --output=json "$image") || \
    die "cannot read qcow metadata: $image"

  printf '%s\n' "$json"
}

# ---------------------------------------------------------------------------
# Filesystem / partition probing
# ---------------------------------------------------------------------------

# Enumerate partition start offsets and sizes from a partition table.
#
# CRITICAL: `device` must be the decoded block device (the NBD export), never
# the qcow2 file itself. parted and blkid read raw bytes and do not understand
# qcow2, so pointing them at the image file yields "unrecognised disk label"
# for a partitioned image and, worse, silently reports nothing for a bare
# filesystem. The NBD device presents the decoded virtual disk, which is what
# these tools need.
#
# `parted ... print` is used because it reads a partition table without any
# kernel partition-scanning or loop setup. The export is read-only, so even a
# tool that tried to write could not alter the image.
#
# Prints one "<offset-bytes>\t<size-bytes>" line per partition.
#
# nixos-shell images built WITHOUT a bootloader have no partition table at all
# (a bare filesystem), so "no partitions" is a normal, expected result.
partition_offsets() {
  local device=$1
  local output line

  if ! tool_available parted; then
    return 0
  fi

  # -m gives a machine-readable, stable `BYT;...;N:START:END:SIZE:...` layout.
  if ! output=$(parted -s -m "$device" unit B print 2>/dev/null); then
    return 0
  fi

  # Skip the header line ("BYT;...") and the partition rows begin with a
  # number. `START`/`SIZE` carry a trailing "B" in `unit B`.
  while IFS= read -r line; do
    [[ $line =~ ^[0-9]+: ]] || continue
    local start size
    start=$(cut -d: -f2 <<<"$line" | tr -d 'B')
    size=$(cut -d: -f4 <<<"$line" | tr -d 'B')
    [[ $start =~ ^[0-9]+$ ]] || continue
    printf '%s\t%s\n' "$start" "$size"
  done <<<"$output"
}

# Probe the filesystem that starts at `offset` (empty = whole device) and print
# "<offset>-or-dash<TAB><fstype><TAB><label>" when one is found.
#
# blkid exits non-zero when nothing matches, which is a normal result here (a
# partition holding swap or a bare ESP), so absence is not an error.
probe_filesystem_at() {
  local device=$1
  local offset=${2:-}
  local -a offset_args=()

  if [[ -n $offset && $offset != 0 ]]; then
    offset_args=( --offset "$offset" )
  fi

  local output
  if ! output=$(blkid --probe "${offset_args[@]}" --output export "$device" 2>/dev/null); then
    return 0
  fi

  local key value
  local fstype='' label=''
  while IFS='=' read -r key value; do
    case "$key" in
      TYPE) fstype=$value ;;
      LABEL) label=$value ;;
    esac
  done <<<"$output"

  if [[ -n $fstype ]]; then
    printf '%s\t%s\t%s\n' "${offset:--}" "$fstype" "$label"
  fi
}

# Classify what the image actually contains. nixos-shell VMs default to
# `useDefaultFilesystems = true` with no bootloader, which produces a BARE ext4
# filesystem with no partition table; other VMs (and images built by
# make-disk-image with a bootloader) carry GPT/MBR partitions. Rather than
# assume one layout, probe the device and every partition, and let the result
# drive mounting.
#
# Prints one line per usable filesystem in the form:
#   <offset-bytes-or-'-'> <fstype> <label>
# where '-' means "the whole device" (no partition table).
probe_filesystems() {
  local device=$1

  local -a partitions=()
  mapfile -t partitions < <(partition_offsets "$device")

  if (( ${#partitions[@]} == 0 )); then
    # No partition table: the whole device may be the filesystem itself.
    probe_filesystem_at "$device" ""
    return 0
  fi

  local partition partition_offset partition_size
  for partition in "${partitions[@]}"; do
    IFS=$'\t' read -r partition_offset partition_size <<<"$partition"
    # A zero-length partition cannot hold a filesystem worth mounting.
    [[ ${partition_size:-0} -gt 0 ]] || continue
    probe_filesystem_at "$device" "$partition_offset"
  done
}

# The mountable filesystems we are willing to touch. Refusing everything else
# keeps a typo from halting on an unexpected type (swap, LVM, LUKS, ...).
supported_fstype() {
  case "$1" in
    ext2 | ext3 | ext4 | xfs | btrfs | f2fs | vfat | exfat) return 0 ;;
    *) return 1 ;;
  esac
}

# Find the guest root filesystem among the probe candidates. nixos-shell labels
# its root `nixos`; we prefer that label, then a Linux root-capable filesystem,
# and never fall back to a FAT partition (which would be an ESP, not the root).
select_root_filesystem() {
  local candidates=$1
  local offset fstype label

  local labelled=
  local fallback=
  while IFS=$'\t' read -r offset fstype label; do
    [[ -n $fstype ]] || continue
    supported_fstype "$fstype" || continue

    case "$label" in
      nixos | NIXOS | root | ROOT)
        [[ $offset == - ]] && offset=
        labelled="$offset"$'\t'"$fstype"$'\t'"$label"
        break
        ;;
    esac

    case "$fstype" in
      ext2 | ext3 | ext4 | xfs | btrfs | f2fs)
        if [[ -z $fallback ]]; then
          [[ $offset == - ]] && offset=
          fallback="$offset"$'\t'"$fstype"$'\t'"$label"
        fi
        ;;
    esac
  done <<<"$candidates"

  if [[ -n $labelled ]]; then
    printf '%s\n' "$labelled"
    return 0
  fi
  if [[ -n $fallback ]]; then
    printf '%s\n' "$fallback"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Session state
# ---------------------------------------------------------------------------

# One session per analysed image, keyed by the canonical image path, so two
# concurrent analyses of the same qcow cannot both attach it and neither can
# steal the other's NBD device or mountpoint. The key is a hash because image
# paths are not guaranteed to be short or free of `/`.
session_key_for() {
  local image=$1
  printf '%s' "$image" | sha256sum | cut -d ' ' -f 1
}

session_dir_for() {
  local state_root=$1 image=$2
  printf '%s/%s\n' "$state_root" "$(session_key_for "$image")"
}

# State is written to disk (not held only in memory) so that a crashed or
# interrupted analysis can still be unmounted deterministically by a later
# `vm-logs umount`, which is the whole point of a mount/analyse/unmount cycle.
session_write_metadata() {
  local dir=$1
  local image=$2
  local device=${3:-}
  local mountpoint=${4:-}
  local offset=${5:-}
  local fstype=${6:-}
  local label=${7:-}
  local created_at

  # Preserve the original attach time across re-writes (e.g. when collect adds
  # the mountpoint to an existing session).
  created_at=$(session_read_metadata "$dir" createdAt 2>/dev/null || true)
  if [[ -z $created_at ]]; then
    created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  fi

  mkdir -p "$dir"
  chmod 0700 "$dir"

  jq -n \
    --arg image "$image" \
    --arg device "$device" \
    --arg mountpoint "$mountpoint" \
    --arg offset "$offset" \
    --arg filesystem "$fstype" \
    --arg label "$label" \
    --arg createdAt "$created_at" \
    '{
      schemaVersion: 1,
      image: $image,
      device: $device,
      mountpoint: $mountpoint,
      offset: $offset,
      filesystem: $filesystem,
      label: $label,
      createdAt: $createdAt
    }' >"$dir/session.json.tmp"
  chmod 0600 "$dir/session.json.tmp"
  mv -fT "$dir/session.json.tmp" "$dir/session.json"
}

session_read_metadata() {
  local dir=$1
  local field=$2
  [[ -r "$dir/session.json" ]] || return 0
  jq -r --arg field "$field" '.[$field] // empty' "$dir/session.json" 2>/dev/null || true
}

session_exists() {
  local dir=$1
  [[ -r "$dir/session.json" ]]
}

# ---------------------------------------------------------------------------
# NBD attachment (read-only)
# ---------------------------------------------------------------------------

# Report the NBD devices that are currently attached, as "<device> <size>".
# Used both to skip busy devices and to explain *why* no device was free.
list_attached_nbd_devices() {
  local candidate

  for candidate in /dev/nbd*; do
    [[ -b $candidate ]] || continue
    local size
    size=$(cat "/sys/block/$(basename "$candidate")/size" 2>/dev/null || true)
    if [[ ${size:-0} -gt 0 ]]; then
      printf '%s %s\n' "$candidate" "$size"
    fi
  done
}

# Pick a free NBD device. A device is only usable when the kernel exposes the
# node AND no other client holds it, so a device left connected by an earlier
# run is skipped rather than silently shared.
choose_nbd_device() {
  local candidate

  for candidate in /dev/nbd*; do
    [[ -b $candidate ]] || continue
    # `size` reads 0 for a device with no active export; pid is empty unless a
    # client is attached. Either signal means "hold on, do not reuse blindly".
    local pid size
    pid=$(cat "/sys/block/$(basename "$candidate")/pid" 2>/dev/null || true)
    size=$(cat "/sys/block/$(basename "$candidate")/size" 2>/dev/null || true)
    if [[ -z $pid && ${size:-0} -eq 0 ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

# Attach the image read-only. `-r` makes the export itself read-only, so the
# kernel NBD client cannot write even if a later mount option were wrong; the
# Nix-store backing file additionally cannot be written because it is a
# read-only store path.
nbd_attach_readonly() {
  local image=$1
  local device=$2
  local format

  format=$(jq -r '.format // empty' <<<"$(qcow_top_info "$image")")
  [[ -n $format ]] || die "cannot determine image format: $image"

  log_info "attaching $image read-only as $device"

  # `--fork` leaves the server running in the background; `--pid-file` gives
  # the umount path an exact handle to stop.
  if ! qemu-nbd \
    --read-only \
    --format "$format" \
    --connect "$device" \
    "$image" 2>/dev/null; then
    die "failed to attach the image read-only on $device"
  fi
}

nbd_detach() {
  local device=$1

  [[ -b $device ]] || return 0

  if ! qemu-nbd --disconnect "$device" >/dev/null 2>&1; then
    log_warn "qemu-nbd --disconnect $device failed; device may still be attached"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Mounting
# ---------------------------------------------------------------------------

# Mount the guest root read-only. `ro` is requested explicitly as well as
# relying on the read-only export: defence in depth, and it makes the intent
# legible in `mount` output for the operator.
mount_guest_root() {
  local device=$1
  local mountpoint=$2
  local offset=$3
  local fstype=$4
  local -a options=( ro nosuid nodev noexec )

  # An image with a partition table exposes the root at a byte offset; the
  # whole-device case has no offset at all.
  if [[ -n $offset && $offset != 0 ]]; then
    options+=( "offset=$offset" )
  fi

  mkdir -p "$mountpoint"

  local spec=$device
  # A loop device is not needed here: the NBD device IS the block device.

  log_info "mounting $spec as $fstype read-only on $mountpoint"

  if ! mount -t "$fstype" -o "$(IFS=,; printf '%s' "${options[*]}")" \
    "$spec" "$mountpoint"; then
    log_warn "read-only mount failed; falling back to offline debugfs extraction"
    return 1
  fi
  return 0
}

# Is `path` a mountpoint right now?
#
# Deliberately answers from /proc/self/mounts instead of the `mountpoint`
# binary: teardown must never detach the NBD device before unmounting, and it
# must reach that decision even on a host where the binary is unavailable.
# /proc/self/mounts is kernel truth and needs no external tool.
is_mountpoint() {
  local path=$1
  [[ -d $path ]] || return 1

  # Mount entries are escaped with octal sequences (  for space, ...), so
  # decode them before comparing.
  local escaped
  escaped=$(printf '%s' "$path" | sed -e 's/\\/\\\\/g' -e 's/ /\\040/g' -e 's/\t/\\011/g')

  awk -v target="$escaped" '$2 == target { found = 1 } END { exit !found }' \
    /proc/self/mounts 2>/dev/null
}

# ---------------------------------------------------------------------------
# debugfs extraction (no kernel mount at all)
# ---------------------------------------------------------------------------

# Pull a path out of an ext filesystem via debugfs, without mounting anything.
# debugfs is read-only unless asked to write, and it dereferences the qcow2's
# backing chain through qemu-nbd, so this path never needs CAP_SYS_ADMIN for
# mounting and never needs the NBD kernel client write access.
#
# Note: debugfs needs a BLOCK DEVICE, so this still attaches read-only via NBD;
# what it avoids is the mount(2) syscall and its namespace requirements.
debugfs_extract() {
  local device=$1
  local source_path=$2
  local destination_root=$3

  local destination="$destination_root$source_path"

  local stat_output
  if ! stat_output=$(debugfs -R "stat \"$source_path\"" "$device" 2>/dev/null); then
    return 1
  fi
  grep -q '^Inode:' <<<"$stat_output" || return 1

  # debugfs reports the file type as a word ("directory", "regular", ...),
  # which avoids decoding its octal mode string.
  local file_type
  file_type=$(sed -n 's/^Inode:.*Type: *\([a-z]*\).*/\1/p' <<<"$stat_output" | head -n1)

  mkdir -p "$(dirname "$destination")"

  if [[ $file_type == directory ]]; then
    # `rdump PATH DEST` recreates PATH's basename under DEST, so per-path dumps
    # would scatter the tree. Dump the filesystem root once, anchored so that
    # absolute paths survive, then keep only the requested subtree.
    local staging
    staging=$(mktemp -d)
    # `rdump` also tries to reproduce the guest's uid/gid, which an unprivileged
    # host cannot do; that chown failure is printed on stderr while the file
    # DATA is still extracted correctly, so judge success by the bytes.
    debugfs -R "rdump \"/\" \"$staging\"" "$device" >/dev/null 2>&1 || true

    if [[ -e "$staging$source_path" ]]; then
      cp -a --reflink=auto --no-preserve=mode,ownership \
        "$staging$source_path" "$destination" 2>/dev/null || true
    fi
    rm -rf -- "$staging"
  else
    debugfs -R "dump \"$source_path\" \"$destination\"" "$device" \
      >/dev/null 2>&1 || true
  fi

  if [[ -d $destination ]]; then
    find "$destination" -type f -print -quit 2>/dev/null | grep -q .
    return
  fi
  [[ -e $destination ]]
}

# ---------------------------------------------------------------------------
# Collection
# ---------------------------------------------------------------------------

# Copy one artifact from the (read-only) mounted guest into the evidence
# directory. Paths that do not exist are reported, not treated as failures:
# a VM that never logged to /var/log/messages is not a broken analysis.
collect_artifact() {
  local guest_root=$1
  local artifact=$2
  local destination_root=$3

  local target="$destination_root$artifact"

  if [[ ! -e "$guest_root$artifact" ]]; then
    return 1
  fi

  mkdir -p "$(dirname "$target")"

  if [[ -d "$guest_root$artifact" ]]; then
    cp -a --reflink=auto -- "$guest_root$artifact" "$target" 2>/dev/null || return 1
  else
    cp -a --reflink=auto -- "$guest_root$artifact" "$target" 2>/dev/null || return 1
  fi

  return 0
}

# Human-readable summary of evidence that is present, so an operator sees what
# they got without parsing the manifest.
list_collected() {
  local root=$1
  find "$root" -type f -printf '%s\t%p\n' 2>/dev/null | sort -k2 | \
    awk -F'\t' '{ printf "%12d  %s\n", $1, $2 }'
}
