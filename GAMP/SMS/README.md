# Software Module Specification: nixos-shell VM Manager

Document: nixos-shell VM Manager SMS
Status: Supplier implementation baseline
Source: `GAMP/SDS/README.md`
Scope: implementable modules

## Register

| SMS row | Source SDS | Module |
| --- | --- | --- |
| FS-120-HDS-010-SDS-010-SMS-010 | FS-120-HDS-010-SDS-010, FS-010-HDS-010-SDS-010 | `modules/default.nix` |
| FS-040-HDS-010-SDS-010-SMS-010 | FS-040-HDS-010-SDS-010, FS-110-HDS-010-SDS-010 | state/registry command module |
| FS-075-HDS-010-SDS-010-SMS-010 | FS-075-HDS-010-SDS-010 | authority command module |
| FS-070-HDS-010-SDS-010-SMS-010 | FS-070-HDS-010-SDS-010, FS-080-HDS-010-SDS-010, FS-090-HDS-010-SDS-010 | supervisor module |
| FS-030-HDS-010-SDS-010-SMS-010 | FS-030-HDS-010-SDS-010 | local-update module |
| FS-130-HDS-010-SDS-010-SMS-010 | FS-030-HDS-010-SDS-010, FS-120-HDS-010-SDS-010 | operator dispatcher module |
| FS-140-HDS-010-SDS-010-SMS-010 | FS-140-HDS-010-SDS-010 | test modules and evidence entrypoint |
| FS-150-HDS-010-SDS-010-SMS-010 | FS-150-HDS-010-SDS-010 | console configuration and supervisor adapter |
| FS-160-HDS-010-SDS-010-SMS-010 | FS-160-HDS-010-SDS-010 | optional pin-refresh construction module |
| FS-170-HDS-010-SDS-010-SMS-010 | FS-170-HDS-010-SDS-010 | `scripts/vm-logs.sh`, `scripts/vm-log-analyser-lib.sh`, `scripts/vm-log-artifacts.sh` |

The analysis module is a separate executable, `vm-logs`, because it operates on
an image file rather than on a managed instance and therefore consumes no
instance configuration. It is built once by `lib/mk-vm-logs.nix` and exported
both as `packages.<system>.vm-logs` and as a host package.

The lifecycle command modules are delivered by `scripts/nixos-shell-vm-manager.sh`
as one versioned executable with subcommands. The executable accepts only a generated,
root-owned instance configuration for mutating operations.
