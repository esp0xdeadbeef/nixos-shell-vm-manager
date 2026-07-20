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

When a host depends on a managed VM for external connectivity, cold-boot
activation of that VM shall not depend on connectivity supplied by the VM. An
automatic activation policy may wait for its declaratively required host-local
network interfaces or bridges to exist, but shall not wait for internet access.
Network-dependent maintenance units, including dependency refresh and host
upgrade, shall remain independent of and shall not gate the local bootstrap
path.

## Failure Conditions

- Starting an accepted baseline with pin refresh disabled invokes image
  construction or network access.
- Network unavailability prevents launch of a complete local host-pinned image
  after an enabled pin-refresh attempt fails.
- A missing local artifact causes an implicit remote fetch or source update.
- A self-hosted connectivity VM cannot start after cold boot because its start
  path requires the external connectivity that the VM is responsible for
  providing.
- Automatic activation runs before a declared host-local interface or bridge
  exists, or waits for internet access instead of local device readiness.
- A network-dependent maintenance unit is an ordering requirement for the
  offline VM bootstrap path.

## Downstream Handoff

HDS shall derive `FS-020-HDS-010` for the offline artifact and runtime closure.
