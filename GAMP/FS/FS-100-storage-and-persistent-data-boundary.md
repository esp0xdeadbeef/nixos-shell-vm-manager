# FS: Storage and Persistent-data Boundary

Document: FS-100
Status: Stakeholder-approved functional baseline
Owner: Supplier
Source URS: `GAMP/URS/README.md`

## Scope

Replaceable VM system state and persistent guest data have separate lifecycles.

## Functional Requirement

Replacing, promoting, or rolling back an image shall not delete persistent guest
data. Runtime working storage and persistent data storage shall be independently
configurable by the host operator. The manager shall not require either class
to use a hard-coded persistence mount. Image rollback shall preserve the current
persistent guest data and shall not claim to rewind that data.

## Failure Conditions

- Replacing disposable system state deletes persistent guest data.
- Storage placement is fixed to one persistence directory.
- Image rollback silently restores, discards, or claims to restore guest data.
- Runtime and persistent storage cannot be configured independently.

## Downstream Handoff

HDS shall derive `FS-100-HDS-010` for runtime and persistent storage classes.
