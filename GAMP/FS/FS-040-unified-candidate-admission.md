# FS: Unified Candidate Admission

Document: FS-040
Status: Stakeholder-approved functional baseline
Owner: Supplier
Source URS: `GAMP/URS/README.md`

## Scope

All candidate sources enter one lifecycle through the same admission boundary.

## Functional Requirement

A baseline or local build output shall be admitted only after construction
completed successfully and the output can provide the expected named VM runtime
artifact. Admission shall register an immutable candidate and its provenance.
It shall not change the known-good image or affect a running VM. Both source
types shall use the same later activation, health, promotion, and rollback
behavior.

## Failure Conditions

- One source type bypasses candidate admission checks.
- A partial or unusable output is admitted.
- Candidate admission changes the running or known-good image.
- Baseline and local candidates use different safety rules.

## Downstream Handoff

HDS shall derive `FS-040-HDS-010` for retained candidate artifacts and
provenance records.
