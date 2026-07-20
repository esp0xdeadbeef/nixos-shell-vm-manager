# Software Design Specification: nixos-shell VM Manager

Document: nixos-shell VM Manager SDS
Status: Supplier design baseline
Source: `GAMP/HDS/README.md`
Scope: software interfaces and state transitions

## Register

| SDS row | Source HDS | Software contract |
| --- | --- | --- |
| FS-010-HDS-010-SDS-010 | FS-010-HDS-010, FS-020-HDS-010, FS-060-HDS-010 | Declarative baseline registrar |
| FS-030-HDS-010-SDS-010 | FS-030-HDS-010, FS-050-HDS-010, FS-130-HDS-010 | Immutable local candidate pipeline |
| FS-040-HDS-010-SDS-010 | FS-040-HDS-010, FS-060-HDS-010, FS-090-HDS-010 | Atomic image-state registry |
| FS-070-HDS-010-SDS-010 | FS-070-HDS-010, FS-080-HDS-010, FS-090-HDS-010 | Foreground lifecycle supervisor |
| FS-075-HDS-010-SDS-010 | FS-075-HDS-010, FS-110-HDS-010 | Session-authority protocol |
| FS-080-HDS-010-SDS-010 | FS-080-HDS-010 | Bounded health engine |
| FS-090-HDS-010-SDS-010 | FS-090-HDS-010 | Promotion and rollback transaction |
| FS-100-HDS-010-SDS-010 | FS-100-HDS-010 | Runtime/persistent storage adapter |
| FS-110-HDS-010-SDS-010 | FS-110-HDS-010 | Lifecycle and construction locks |
| FS-120-HDS-010-SDS-010 | FS-120-HDS-010 | NixOS module and generated instance configuration |
| FS-140-HDS-010-SDS-010 | FS-140-HDS-010 | Layered verification entrypoints |
| FS-150-HDS-010-SDS-010 | FS-150-HDS-010 | Stable tmux console adapter |
| FS-160-HDS-010-SDS-010 | FS-160-HDS-010, FS-050-HDS-010, FS-110-HDS-010 | Serialized pin-refresh pipeline |

## State Model

The registry is one atomically replaced JSON document per VM. Image records are
immutable and contain `image`, `sourceKind`, `sourceIdentity`, `lockIdentity`,
and `admittedAt`.
The slots are `current`, `candidate`, `previous`, and `failed`; `phase` is one
of `idle`, `activating`, `running`, `rolling-back`, or
`operator-intervention`. Slot images are independently retained as Nix GC roots.

The public `<vm>-vm.service` runs a foreground supervisor. It starts and
observes the exact selected image runner through a host-local terminal
multiplexer. Baseline and local candidate builds never run in that service. An
enabled pin refresh may construct a candidate before an eligible start while no
runner is being replaced. A natural runner exit is a guest shutdown; a
supervisor stop is an explicit/host stop and cannot enter guest recovery.

## Transaction

Candidate activation retains `current`, starts `candidate`, checks the exact
process and functional health, then atomically promotes candidate to current
and the old current to previous. Failure stops candidate, marks it failed,
starts unchanged current, and applies the same health engine. A failed recovery
is terminal and visible through service failure and registry phase.

## Boundary

Normal host-pinned startup does not call `nix`, resolve a flake, or refresh a
lock. Only the explicitly enabled FS-160 path may do so, and failure returns to
host-pinned selection. The local pipeline may construct. Registry admission and
activation remain distinct.
