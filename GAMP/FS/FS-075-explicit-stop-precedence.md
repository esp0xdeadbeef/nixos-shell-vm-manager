# FS: Explicit-stop Precedence

Document: FS-075
Status: Stakeholder-approved functional baseline
Owner: Supplier
Source URS: `GAMP/URS/README.md`

## Scope

Explicit operator stop is a safety invariant rather than an optional activation
variable.

## Functional Requirement

An explicit operator stop shall revoke every earlier automatic or explicit start
authorization for the current host session. Candidate construction and
admission, including an enabled pin refresh, may complete after that stop, but
shall not start the VM. Every start transition shall re-evaluate stop authority
immediately before starting a candidate or known-good image.

A later explicit start or explicit rollout may provide new start authority. A
configured boot-start policy may provide new authority at the next host boot.
Host shutdown shall not be classified as guest-initiated shutdown and shall not
trigger guest-recovery behavior.

## Failure Conditions

- Candidate construction or admission clears explicit-stop state.
- Pin refresh clears or bypasses explicit-stop state.
- A stop issued during construction is ignored when construction completes.
- Automatic recovery overrides a later explicit stop.
- Host shutdown triggers guest-shutdown recovery.
- Explicit-stop precedence can be disabled by per-VM configuration.

## Downstream Handoff

HDS shall derive `FS-075-HDS-010` for stop-event observation and host-session
authority state.
