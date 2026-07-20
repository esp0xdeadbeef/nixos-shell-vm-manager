# User Requirements Specification: nixos-shell VM Manager

Document: nixos-shell VM Manager URS
Status: Stakeholder-approved requirements baseline
Owner: VM host operator
Scope: reliable preparation, activation, and recovery of host-managed virtual machines

## Purpose

The VM manager should allow designated NixOS hosts to prepare complete virtual
machine images in advance, keep running workloads available during image
construction, and safely activate replacement images without depending on
internet access at VM startup.

The manager should support both reproducible baseline deployments and deliberate
local development or test deployments while applying the same safety and
recovery expectations to both.

This URS records stakeholder intent only. Later specifications shall define the
functional behavior, infrastructure, interfaces, and implementation.

## Requirements

Designated VM hosts shall build all assigned baseline VM images as part of their
host software generation. Building these images shall not start the VMs.

A baseline VM image shall be derived from the dependency pins approved for the
host generation. An incomplete or failed required VM build shall not be exposed
as an available baseline.

All artifacts required to start a baseline VM shall already be present on the
host after a successful host build. Starting a previously prepared VM shall not
require internet access, dependency resolution, or image construction.

A host whose external connectivity is supplied by one of its managed VMs shall
be able to cold-boot that VM from local artifacts before that connectivity
exists. Host-local interfaces and bridges required by an automatic activation
policy shall be declared and available before the policy starts the VM.
Network-dependent maintenance, including dependency refresh and host upgrade,
shall not gate this offline bootstrap path.

A VM may independently opt into refreshing the dependency pins of its
declaratively approved VM flake before an authorized normal start. Without this
policy, the VM shall start from the image built with the host-approved pins.

Pin refresh shall be best effort. Failure shall leave admitted images unchanged
and fall back to the locally available host-pinned image. Pin refresh shall not
alter the host generation's approved pins, override an explicit stop, or delay
rollback and recovery.

An operator shall be able to attach an interactive terminal to each running VM
through a stable host-local endpoint. Console access shall not depend on guest
network connectivity. The endpoint shall remain the same when the manager
starts another image during explicit start, rollout, guest-shutdown recovery,
or rollback.

Operators shall also be able to prepare a candidate from an explicitly selected
local development source. The local source and its dependency pins shall be
captured as an immutable build input. Later changes to that source shall not
alter an already built candidate.

A running VM shall remain active and unchanged while either a baseline or local
candidate is being built. Build failure shall leave the running VM and the last
known-good image unchanged.

Baseline and local candidates shall use the same transactional activation and
recovery process. A candidate shall not replace the known-good image merely
because its build completed.

Candidate activation may occur following a guest-initiated shutdown or an
explicit operator rollout request. Automated image preparation or activation
shall not override an explicit operator stop. Only a later explicit start,
explicit rollout, or configured host-boot policy may authorize another start.
A configured carrier policy may automatically stop a VM while carrier is down
and restore it when carrier returns, but shall not treat that automatic stop as
an operator stop or override a later explicit operator stop.

Before a candidate is accepted, the manager shall verify both that its virtual
machine process remains operational and that the guest satisfies VM-specific
functional health criteria. Process presence alone shall not be sufficient
evidence of health.

When candidate activation succeeds, the candidate shall become the new
known-good image and the prior known-good image shall remain available as a
recovery reference.

When candidate activation or health verification fails, the manager shall stop
the failed candidate and attempt to restore the prior known-good image. If the
prior image also cannot be restored to a healthy state, the manager shall leave
the failure visible and require operator intervention.

Persistent guest data shall remain separate from replaceable system images and
shall not be discarded by normal image construction, activation, or rollback.
Runtime and persistent storage placement shall remain under host-operator
control; the manager shall not require a hard-coded persistence mount.

Concurrent candidate builds and rollouts shall be coordinated so that they
cannot corrupt image state, replace each other's recovery references, or create
uncontrolled build contention.

The manager shall be reusable by independent Nix flakes and shall not depend on
the internal layout of one host-configuration repository.

Construction and integration tests shall provide current evidence for image
selection, build isolation, offline startup, explicit-stop preservation,
health-gated promotion, rollback behavior, and offline interactive console
access. Live host acceptance and final system acceptance require separate
stakeholder authorization.

## Later Specifications

FS shall split these requirements into independently testable functional
behaviors.

HDS shall define the designated hosts, local artifact availability, storage
classes, runtime environment, and offline boundary.

SDS and SMS shall define candidate registration, lifecycle state transitions,
health-check interfaces, stop authority, promotion, rollback, provenance, and
concurrency control.
