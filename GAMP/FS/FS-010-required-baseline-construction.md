# FS: Required Baseline Construction

Document: FS-010
Status: Stakeholder-approved functional baseline
Owner: Supplier
Source URS: `GAMP/URS/README.md`

## Scope

Assigned baseline images are required products of a designated host generation.

## Functional Requirement

The host-generation build shall require successful, complete construction of
every VM image assigned to that host. A host generation with a missing, failed,
or incomplete required VM image shall not become an available generation.
Successful image construction shall make the image available to the generation
without starting or rolling out its VM.

## Failure Conditions

- A host generation becomes available while an assigned baseline image failed.
- An incomplete output is presented as a baseline candidate.
- Completing the host build starts or restarts a VM.

## Downstream Handoff

HDS shall derive `FS-010-HDS-010` for designated hosts and required image
assignments.
