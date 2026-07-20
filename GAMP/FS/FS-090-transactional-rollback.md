# FS: Transactional Rollback

Document: FS-090
Status: Stakeholder-approved functional baseline
Owner: Supplier
Source URS: `GAMP/URS/README.md`

## Scope

Candidate activation retains a verified recovery path until promotion succeeds.

## Functional Requirement

Before candidate start, the known-good image shall be retained as the recovery
image. Candidate start or health failure shall stop the failed candidate,
restore the recovery image, start it, and apply the required health checks. A
healthy recovery shall restore known-good operation and mark the candidate
failed so it is not retried automatically. If recovery cannot be started or
verified, the transaction shall report a visible terminal failure requiring
operator intervention.

## Failure Conditions

- The recovery image is released before candidate promotion completes.
- A failed candidate remains selected for automatic restart.
- Rollback success is claimed without functional health evidence.
- Recovery failure is hidden by a successful service exit.

## Downstream Handoff

HDS shall derive `FS-090-HDS-010` for retained recovery artifacts and visible
failure reporting.
