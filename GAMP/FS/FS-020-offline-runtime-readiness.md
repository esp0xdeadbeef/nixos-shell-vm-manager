# FS: Offline Runtime Readiness

Document: FS-020
Status: Stakeholder-approved functional baseline
Owner: Supplier
Source URS: `GAMP/URS/README.md`

## Scope

An accepted host generation contains the complete runtime basis for its VMs.

## Functional Requirement

After successful host-generation construction, each assigned baseline image and
every dependency required to launch it shall be locally retained. Starting the
VM with pin refresh disabled shall consume only those local artifacts and shall
not perform source resolution, dependency updates, image construction, or
network access. Enabling pin refresh may add an online construction attempt,
but shall not remove or mutate the local host-pinned image. If that attempt
fails, the host-pinned image shall remain startable without network access. A
missing local image shall produce an explicit start failure rather than an
unconfigured online recovery attempt.

## Failure Conditions

- Starting an accepted baseline with pin refresh disabled invokes image
  construction or network access.
- Network unavailability prevents launch of a complete local host-pinned image
  after an enabled pin-refresh attempt fails.
- A missing local artifact causes an implicit remote fetch or source update.

## Downstream Handoff

HDS shall derive `FS-020-HDS-010` for the offline artifact and runtime closure.
