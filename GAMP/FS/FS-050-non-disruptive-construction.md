# FS: Non-disruptive Construction

Document: FS-050
Status: Stakeholder-approved functional baseline
Owner: Supplier
Source URS: `GAMP/URS/README.md`

## Scope

Candidate construction is independent from current runtime availability.

## Functional Requirement

While either candidate source is being constructed, the running VM shall remain
active on its current image. Construction shall not stop, restart, or reattach
the VM. A failed build shall not change the known-good image, recovery image,
or previously admitted candidate and shall not schedule activation.

## Failure Conditions

- Beginning or completing a build interrupts the running VM.
- Build failure alters an image slot or recovery reference.
- A failed build schedules or authorizes rollout.

## Downstream Handoff

HDS shall derive `FS-050-HDS-010` for independent build and runtime execution.
