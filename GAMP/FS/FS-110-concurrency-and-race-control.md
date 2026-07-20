# FS: Concurrency and Race Control

Document: FS-110
Status: Stakeholder-approved functional baseline
Owner: Supplier
Source URS: `GAMP/URS/README.md`

## Scope

Concurrent lifecycle work shall not corrupt image state or stale operator intent.

## Functional Requirement

For one VM, candidate construction requests, admission, activation, promotion,
and rollback shall not perform conflicting transitions concurrently. Shared
construction capacity across VMs shall be bounded. Before any start transition,
the manager shall re-evaluate start authority so an explicit stop issued while
construction or admission was in progress remains effective.

## Failure Conditions

- Two operations write one VM's candidate or recovery state concurrently.
- Concurrent rollouts replace each other's recovery reference.
- Construction concurrency exceeds the configured shared bound.
- A stale pre-build decision overrides a later explicit stop.

## Downstream Handoff

HDS shall derive `FS-110-HDS-010` for coordination state and shared construction
capacity.
