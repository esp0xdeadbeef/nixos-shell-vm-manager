# FS: Health-gated Promotion

Document: FS-080
Status: Stakeholder-approved functional baseline
Owner: Supplier
Source URS: `GAMP/URS/README.md`

## Scope

Process survival alone is not sufficient evidence that a candidate is usable.

## Functional Requirement

Every managed VM shall define functional health criteria with bounded attempt
duration and retry behavior. Candidate activation shall first establish that
the VM runtime process remains operational and shall then evaluate the VM's
functional criteria. The candidate shall be promoted only when both checks
succeed within the configured bounds. The same functional criteria shall be
used when verifying rollback recovery.

## Failure Conditions

- A candidate is promoted only because its process exists.
- A VM has no functional health criteria but can still promote a candidate.
- Timeout or retry exhaustion is reported as healthy.
- Rollback is called healthy without applying the VM-specific criteria.

## Downstream Handoff

HDS shall derive `FS-080-HDS-010` for the health-observation environment and
per-VM health inputs.
