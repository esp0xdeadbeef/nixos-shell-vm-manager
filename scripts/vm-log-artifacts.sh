# shellcheck shell=bash
# The default evidence set collected by `vm-logs collect`.
#
# These are the artifacts an operator actually reads after a VM has died:
#
#   * the systemd journal (the authoritative record of unit failures, OOM
#     kills, and the last shutdown sequence),
#   * the classic syslog-family text logs (still written by some services and
#     by rsyslog-configured guests),
#   * kernel ring buffer snapshots, which survive a crash that kills the
#     journal writer before it can flush.
#
# `/var/log/journal` is a directory and is copied recursively, preserving the
# machine-id subdirectory. The rest are plain files; absent ones are reported in
# the manifest as "missing" rather than treated as failures, because no guest
# writes all of them.
#
# An unprivileged or partial copy is still useful, so every path is collected
# independently: one unreadable artifact never aborts the run.
default_artifact_paths() {
  printf '%s\n' \
    /var/log/journal \
    /var/log/dmesg \
    /var/log/messages \
    /var/log/syslog \
    /var/log/kern.log \
    /var/log/boot.log \
    /var/log/nixos-boot.log \
    /var/log/daemon.log \
    /var/log/auth.log \
    /var/log/Xorg.0.log \
    /var/crash
}
