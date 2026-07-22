# High-Level Design: nixos-shell VM Manager

Document: nixos-shell VM Manager HDS
Status: Supplier design baseline
Source: `GAMP/FS/README.md`
Scope: host resources and external design boundaries

## Purpose

This HDS allocates each approved functional requirement to host resources. It
does not prescribe shell functions, Nix module internals, or test results.

## Register

| HDS row | Source FS | Design target |
| --- | --- | --- |
| FS-010-HDS-010 | FS-010 | Host-generation image closure |
| FS-020-HDS-010 | FS-020 | Offline runtime closure |
| FS-030-HDS-010 | FS-030 | Immutable local-source capture environment |
| FS-040-HDS-010 | FS-040 | Candidate registry and admission boundary |
| FS-050-HDS-010 | FS-050 | Independent construction and runtime resources |
| FS-060-HDS-010 | FS-060 | Provenance and host-activation precedence |
| FS-070-HDS-010 | FS-070 | Per-VM activation-policy inputs |
| FS-075-HDS-010 | FS-075 | Host-session start-authority state |
| FS-080-HDS-010 | FS-080 | Runtime and functional-health observations |
| FS-090-HDS-010 | FS-090 | Retained recovery artifact and visible failure |
| FS-100-HDS-010 | FS-100 | Independent runtime and persistent storage classes |
| FS-110-HDS-010 | FS-110 | Per-VM coordination and shared build capacity |
| FS-120-HDS-010 | FS-120 | Consumer-flake integration surface |
| FS-130-HDS-010 | FS-130 | Root operator command environment |
| FS-140-HDS-010 | FS-140 | Construction, integration, and acceptance environments |
| FS-150-HDS-010 | FS-150 | Stable host-local interactive terminal endpoint |
| FS-160-HDS-010 | FS-160 | Optional pin-refresh construction environment |

The corresponding controlled fullspec is named
`GAMP/HDS/<full-HDS-ID>.md`.

## Host Allocation

The consumer flake designates hosts and supplies complete image derivations.
The initial authorized HAT host is `s-tau`; no design depends on that hostname.
Images, manager executables, health commands, and runner closures are retained
by the host generation. Runtime startup consumes local objects only unless a VM
explicitly enables online pin refresh. Such a VM supplies an approved flake
reference that is resolved into an immutable archive at refresh time; refresh
failure retains the local host-pinned startup path.

A host may obtain external connectivity from a managed VM. That VM's cold-boot
path uses only the retained local closure and host-local interface readiness.
Network-dependent refresh and upgrade services remain outside its bootstrap
dependency chain.

Host-controlled state is divided into `/var/lib` image metadata and optional
persistent guest state, `/var/cache` replaceable runtime disks, `/run` session
authority and locks, and Nix GC roots for admitted immutable images. Every base
directory remains configurable. No `/persist` path is required by the manager.
The attachable VM terminal is a transient host-local `/run` endpoint and does
not cross the guest network boundary.

## Boundary

The consumer owns VM definitions, baseline dependency pins, approved refresh
sources and build targets, image derivations, network configuration, and
functional-health meaning. The manager owns refresh isolation, admission,
authority, activation, promotion, rollback, and concurrency. HAT and SAT do not
follow from design or construction evidence.
