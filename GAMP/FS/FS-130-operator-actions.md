# FS: Operator Actions

Document: FS-130
Status: Stakeholder-approved functional baseline
Owner: Supplier
Source URS: `GAMP/URS/README.md`

## Scope

Operators require an explicit local development update and rollout action.

## Functional Requirement

The manager shall provide a bounded action equivalent to
`vm-update <vm> <local-flake-path>`. The action shall validate the managed VM
identity and local flake, capture and construct the immutable source, admit the
result through the shared candidate boundary, and authorize the normal
transactional rollout. If an explicit stop is issued after the action begins
but before candidate start, that later stop shall revoke rollout start authority
while leaving a successfully built candidate pending.

## Failure Conditions

- The action accepts an unmanaged VM or invalid local flake as successful input.
- Local construction bypasses shared admission, health, or rollback behavior.
- Build failure changes the running VM or known-good image.
- A later explicit stop cannot revoke candidate start.

## Downstream Handoff

HDS shall derive `FS-130-HDS-010` for operator access and local build context.
