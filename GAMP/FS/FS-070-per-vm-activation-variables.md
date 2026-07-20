# FS: Per-VM Activation Variables

Document: FS-070
Status: Stakeholder-approved functional baseline
Owner: Supplier
Source URS: `GAMP/URS/README.md`

## Scope

Each VM independently controls the authorized automatic and explicit activation
behavior.

## Functional Requirement

The manager shall provide the following per-VM functional variables with these
defaults:

```nix
activation = {
  startOnBoot = false;
  restartOnGuestShutdown = true;
  rolloutCandidateOnGuestShutdown = true;
  useCandidateOnExplicitStart = true;

  guestShutdownJitter = {
    minSeconds = 1;
    maxSeconds = 4;
  };
};
```

`startOnBoot` shall determine whether host boot authorizes a VM start.

`restartOnGuestShutdown` shall determine whether a guest-initiated shutdown
authorizes automatic recovery. When disabled, the VM shall remain stopped.

When guest-shutdown recovery is authorized,
`rolloutCandidateOnGuestShutdown` shall determine whether a pending candidate
is activated. If candidate rollout is disabled or no candidate is pending, the
known-good image shall be restarted.

`useCandidateOnExplicitStart` shall determine whether an explicit start selects
a pending candidate. When disabled or when no candidate is pending, the
explicit start shall select the known-good image.

Before an automatic guest-shutdown restart, the manager shall choose a delay
within the inclusive `guestShutdownJitter.minSeconds` through
`guestShutdownJitter.maxSeconds` interval.

The jitter bounds shall be non-negative and the minimum shall not exceed the
maximum. Enabling candidate rollout on guest shutdown while guest-shutdown
restart is disabled shall be rejected as a contradictory configuration.

## Failure Conditions

- One VM's activation variables alter another VM's behavior.
- A VM starts at boot while `startOnBoot` is disabled.
- Guest-shutdown recovery starts a VM while `restartOnGuestShutdown` is
  disabled.
- Candidate selection ignores the applicable per-VM variable.
- Automatic guest recovery uses a delay outside the configured bounds.
- Contradictory or invalid variable combinations are accepted.

## Downstream Handoff

HDS shall derive `FS-070-HDS-010` for per-VM activation policy and timing input.
