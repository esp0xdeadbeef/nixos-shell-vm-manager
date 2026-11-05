# FS: Post-mortem Log Analysis of a Stopped VM Image

Document: FS-170
Status: Stakeholder-approved functional baseline
Owner: Supplier
Source URS: `GAMP/URS/README.md`

## Scope

An operator needs the diagnostic record of a VM that is not running.

## Functional Requirement

The manager shall provide a bounded offline action, equivalent to
`vm-logs <mount|collect|umount> IMAGE`, that makes the recorded diagnostic
artifacts of a stopped VM's disk image readable on the host.

The image is a host file. The action shall not start, boot, connect to, or
execute anything in the guest, and shall not require guest networking. The
image shall be attached and mounted read-only, and the recorded evidence shall
be preserved byte-for-byte.

The action shall identify the guest root filesystem from the image itself
rather than assume one layout, because the manager's own VMs use a bare
filesystem while other images place the root inside a partition.

The action shall support both an interactive read-only mount and a
deterministic copy of a defined artifact set to an operator-chosen directory.
The copy shall record which artifacts were present and which were absent.

A recorded attachment shall be releasable deterministically and repeatably.
Attachment state shall survive the failure of the process that created it, so a
later release action can always restore the host to an unattached state.

Choosing an unmanaged path, a non-image file, or a non-regular file shall fail
explicitly. Concurrent actions on the same image shall not attach it twice.

## Failure Conditions

- Analysis starts, boots, or executes code in the guest.
- Analysis requires guest networking or a running VM.
- The analysed image, its backing file, or the recorded evidence is modified.
- An image whose root filesystem is inside a partition is reported as
  unanalysable.
- Attachment survives the analysis with no deterministic way to release it.
- A non-image or non-regular input is accepted as a VM image.

## Downstream Handoff

HDS shall derive `FS-170-HDS-010` for the read-only attachment and extraction
environment. FS-140 shall require active evidence for these predicates.
