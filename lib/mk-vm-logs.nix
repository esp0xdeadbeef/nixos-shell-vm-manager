# Builds the `vm-logs` offline VM log analyser.
#
# Kept in one place because both the flake (as `packages.<system>.vm-logs`) and
# the NixOS module (installed on VM hosts) must ship the exact same tool. A
# second copy would drift from the scripts it wraps.
{ pkgs }:
let
  library = pkgs.writeText "vm-log-analyser-lib.sh" (
    builtins.readFile ../scripts/vm-log-analyser-lib.sh
  );
  artifacts = pkgs.writeText "vm-log-artifacts.sh" (builtins.readFile ../scripts/vm-log-artifacts.sh);
in
pkgs.writeShellApplication {
  name = "vm-logs";
  runtimeInputs = with pkgs; [
    coreutils
    e2fsprogs
    gnugrep
    gnused
    jq
    parted
    qemu
    util-linux
  ];
  # The library and artifact list are referenced by absolute store path so the
  # tool also works when invoked directly rather than via $PATH.
  text = ''
    export VM_LOGS_LIBRARY=${library}
    export VM_LOGS_ARTIFACTS=${artifacts}
    ${builtins.readFile ../scripts/vm-logs.sh}
  '';
}
