# FS: Candidate Provenance and Precedence

Document: FS-060
Status: Stakeholder-approved functional baseline
Owner: Supplier
Source URS: `GAMP/URS/README.md`

## Scope

Candidate origin and replacement order shall remain explicit and deterministic.

## Functional Requirement

Every admitted candidate shall identify whether it came from a host generation
or an operator-selected local source and shall retain the immutable identity of
that source and output. A successfully admitted local candidate shall be the
pending candidate until activation or until a later successful host activation
provides a new baseline candidate. That host candidate may replace the pending
local candidate but shall not replace a running or known-good image without the
normal rollout transaction. A local candidate admitted after host activation
shall become the pending candidate.

## Failure Conditions

- Candidate origin or immutable identity cannot be determined.
- Build completion order silently changes the known-good image.
- Host activation bypasses rollout to replace a local known-good image.
- An older candidate overwrites a later admitted candidate without an explicit
  lifecycle event.

## Downstream Handoff

HDS shall derive `FS-060-HDS-010` for candidate metadata retention and host
generation boundaries.
