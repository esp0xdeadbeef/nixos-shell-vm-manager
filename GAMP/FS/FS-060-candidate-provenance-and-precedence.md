# FS: Candidate Provenance and Precedence

Document: FS-060
Status: Stakeholder-approved functional baseline
Owner: Supplier
Source URS: `GAMP/URS/README.md`

## Scope

Candidate origin and replacement order shall remain explicit and deterministic.

## Functional Requirement

Every admitted candidate shall identify whether it came from a host generation,
an operator-selected local source, or an enabled pin refresh and shall retain
the immutable identity of that source, its effective lock, and its output.
Candidate replacement shall follow successful admission order and the
initiating lifecycle event. Actions excluded from pin refresh by FS-160 shall
not replace their explicitly selected candidate with a pin-refresh result. No
candidate source shall replace a running or known-good image without the normal
rollout transaction.

## Failure Conditions

- Candidate origin or immutable identity cannot be determined.
- Pin-refresh provenance omits the refreshed lock identity.
- Build completion order silently changes the known-good image.
- Host activation bypasses rollout to replace a local known-good image.
- An older candidate overwrites a later admitted candidate without an explicit
  lifecycle event.

## Downstream Handoff

HDS shall derive `FS-060-HDS-010` for candidate metadata retention and host
generation boundaries.
