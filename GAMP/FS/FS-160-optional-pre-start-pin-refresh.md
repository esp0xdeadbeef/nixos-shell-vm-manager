# FS: Optional Pre-start Pin Refresh

Document: FS-160
Status: Stakeholder-approved functional baseline
Owner: Supplier
Source URS: `GAMP/URS/README.md`

## Scope

A VM may explicitly request updated dependency pins before a normal start while
retaining its host-pinned image as the offline fallback.

## Functional Requirement

The manager shall expose the per-VM `activation.refreshPins` flag defined by
FS-070. It shall default to `false`. When it is absent or disabled, startup
shall use the normal host-pinned image selection without dependency resolution,
lock updates, construction, or network access.

When the flag is enabled, an authorized normal start shall update the dependency
lock of the declaratively approved VM flake according to that flake's declared
inputs before image selection and launch. The refreshed source and effective
lock shall be captured as an immutable construction input, and the configured
VM image target shall be built from that capture. The refresh action shall not
modify the consumer's host-generation source or its approved lock.

A normal start for this policy shall mean a configured boot start, an ordinary
explicit service start, carrier-up start, or a guest-shutdown restart. The
policy shall not run for `vm-update`, rollout of an already admitted candidate,
rollback, or recovery.

A successfully built output shall be admitted with pin-refresh provenance
through the same candidate boundary used by host-generation and local
candidates. It shall then use the normal candidate selection, functional-health
verification, promotion, and rollback transaction. Pin refresh shall never
directly replace the known-good image or start a mutable source.

Pin refresh shall be best effort. Failure to update or capture the lock or to
construct the image shall leave `current`, `candidate`, `previous`, and `failed`
unchanged. If a locally available host-pinned image can be selected and start
authority remains valid, the manager shall continue the requested start using
that image. If no host-pinned image is available, startup shall fail visibly.

If the VM is still running while pin-refresh construction occurs, it shall
remain running until a complete candidate is available. Immediately before any
image launch, the manager shall re-evaluate explicit-stop authority. Pin-refresh
work shall use the normal per-VM construction serialization and shared build
limit.

## Failure Conditions

- Pin refresh occurs while `activation.refreshPins` is absent or disabled.
- Pin refresh occurs for an excluded action.
- Pin refresh mutates the consumer's host-generation source or approved lock.
- A lock-update, capture, or build failure changes an admitted image slot.
- Failed pin refresh prevents an available host-pinned image from starting.
- A pin-refresh result bypasses candidate admission, health checks, or rollback.
- Rollback or recovery waits for dependency resolution, construction, or
  network access.
- A mutable or undeclared source or build target is used.
- A later explicit stop is ignored after pin-refresh construction completes.
- Concurrent pin-refresh transactions corrupt candidate or recovery state.

## Downstream Handoff

HDS shall derive resources for the approved VM flake, immutable refreshed
capture, online/offline boundary, and construction capacity. SDS and SMS shall
define pin-refresh triggering, provenance, lock ordering, failure fallback, and
start-authority revalidation.
