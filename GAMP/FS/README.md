# Functional Specification: nixos-shell VM Manager

Document: nixos-shell VM Manager FS
Status: Stakeholder-approved functional baseline
Source: `GAMP/URS/README.md`
Scope: functional preparation, activation, and recovery of host-managed VMs

## Purpose

This FS translates the approved URS into independently testable functional
behavior. It does not define infrastructure placement, software architecture,
module boundaries, implementation code, or validation results.

## Functional Items

### FS-010 Required Baseline Construction

Fullspec: `GAMP/FS/FS-010-required-baseline-construction.md`.

A designated host generation shall become available only after all assigned
baseline VM images have been built completely. Completing those builds shall
not start or roll out a VM.

### FS-020 Offline Runtime Readiness

Fullspec: `GAMP/FS/FS-020-offline-runtime-readiness.md`.

A successful host generation shall contain every image and runtime dependency
required to start its assigned baseline VMs without build or network access.
An enabled pin-refresh attempt shall not remove this offline fallback.

### FS-030 Immutable Local Candidate

Fullspec: `GAMP/FS/FS-030-immutable-local-candidate.md`.

An operator-selected local source and its own dependency lock shall be captured
immutably before construction so later working-tree changes cannot alter the
built candidate.

### FS-040 Unified Candidate Admission

Fullspec: `GAMP/FS/FS-040-unified-candidate-admission.md`.

Baseline, local, and pin-refresh outputs shall pass the same admission
checks and enter the same candidate lifecycle without changing the running or
known-good image.

### FS-050 Non-disruptive Construction

Fullspec: `GAMP/FS/FS-050-non-disruptive-construction.md`.

Candidate construction shall leave a running VM, its known-good image, and any
previously admitted candidate unchanged until a replacement build succeeds.

### FS-060 Candidate Provenance and Precedence

Fullspec: `GAMP/FS/FS-060-candidate-provenance-and-precedence.md`.

Every candidate shall retain immutable provenance. Pin-refresh candidates shall
record their refreshed lock identity and follow the same explicit precedence
rules; candidate replacement shall never implicitly replace the known-good
image.

### FS-070 Per-VM Activation Variables

Fullspec: `GAMP/FS/FS-070-per-vm-activation-variables.md`.

Each VM shall independently configure boot start, guest-shutdown restart,
candidate selection on guest shutdown and explicit start, and the bounded
guest-shutdown jitter interval. It shall also independently opt into or out of
best-effort pre-start pin refresh.

### FS-075 Explicit-stop Precedence

Fullspec: `GAMP/FS/FS-075-explicit-stop-precedence.md`.

An explicit operator stop shall revoke earlier start authority and shall not be
overridden by construction, candidate admission, or automatic recovery.

### FS-080 Health-gated Promotion

Fullspec: `GAMP/FS/FS-080-health-gated-promotion.md`.

A candidate shall become known-good only after both runtime-process checks and
mandatory VM-specific functional health checks succeed within their configured
bounds.

### FS-090 Transactional Rollback

Fullspec: `GAMP/FS/FS-090-transactional-rollback.md`.

The prior known-good image shall remain available until promotion completes.
Candidate failure shall trigger verified recovery of that prior image or a
visible operator-intervention state.

### FS-100 Storage and Persistent-data Boundary

Fullspec: `GAMP/FS/FS-100-storage-and-persistent-data-boundary.md`.

Replaceable system state and persistent guest data shall remain separate, with
placement controlled by the host and without a manager-required persistence
mount.

### FS-110 Concurrency and Race Control

Fullspec: `GAMP/FS/FS-110-concurrency-and-race-control.md`.

Construction, registration, activation, and recovery shall be coordinated so
concurrent work and late stop requests cannot corrupt state or violate the most
recent operator intent.

### FS-120 Reusable Flake Integration

Fullspec: `GAMP/FS/FS-120-reusable-flake-integration.md`.

Consumer flakes shall supply assigned baseline image derivations and policy
without exposing repository layout or remote-source selection to the manager.

### FS-130 Operator Actions

Fullspec: `GAMP/FS/FS-130-operator-actions.md`.

Operators shall be able to build and transactionally roll out a candidate from
a named local flake while retaining the ability to revoke start authority with
a later explicit stop.

### FS-140 Verification Boundary

Fullspec: `GAMP/FS/FS-140-verification-boundary.md`.

The normal project check shall actively prove construction and integration
predicates, including optional pin-refresh failure and host-pinned fallback.
Live host and final system acceptance shall remain separately authorized
activities.

### FS-150 Stable Offline Interactive Console

Fullspec: `GAMP/FS/FS-150-stable-offline-interactive-console.md`.

Each running VM shall expose an attachable host-local interactive terminal that
does not depend on guest networking. Its configured endpoint shall be stable
across image selection, rollout, guest-shutdown recovery, and rollback.

### FS-160 Optional Pre-start Pin Refresh

Fullspec: `GAMP/FS/FS-160-optional-pre-start-pin-refresh.md`.

When explicitly enabled for a VM, each authorized normal start shall first
attempt to update the dependency pins of its declaratively approved VM flake
and construct a candidate. Successful results shall use the normal admission
and rollout transaction; failure shall preserve admitted state and continue
with the locally available host-pinned image.

## Boundaries

- Host generation construction, local development construction, and optional
  pre-start pin-refresh construction are distinct candidate sources with one
  shared admission and rollout lifecycle.
- VM startup from an accepted host generation is offline by default. Enabling
  pin refresh authorizes an online construction attempt, but its host-pinned
  fallback remains locally startable.
- Candidate admission does not imply activation or promotion.
- Explicit stop and guest-initiated shutdown are distinct lifecycle events.
- Image rollback preserves, but does not rewind, persistent guest data.
- Rollback and recovery starts never perform pin refresh.
- Console attachment is host-local and is not a guest-network health signal.
- HAT and SAT remain outside scope until explicitly authorized by the
  stakeholder.
