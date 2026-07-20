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
  refreshPins = false;

  guestShutdownJitter = {
    minSeconds = 1;
    maxSeconds = 4;
  };
};
```

The manager shall additionally support named host carrier policies:

```nix
carrierControls.<policy> = {
  interface = "<carrier-interface>";
  instances = [ "<vm-name>" ];
  requiredInterfaces = [ ];
  pollIntervalSeconds = 5;
  dryRun = false;
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
explicit start shall select the known-good image. Carrier-up activation shall
use the same candidate-selection policy so that a first carrier-authorized
start can admit the host-generation baseline.

`refreshPins` shall determine whether an authorized normal start first attempts
the pre-start pin refresh defined by FS-160. The default shall preserve fully
offline, host-pinned startup. The variable applies to configured boot starts,
ordinary explicit service starts, carrier-up starts, and guest-shutdown
restarts. It shall not apply to `vm-update`, rollout of an already admitted
candidate, rollback, or recovery.

Before an automatic guest-shutdown restart, the manager shall choose a delay
within the inclusive `guestShutdownJitter.minSeconds` through
`guestShutdownJitter.maxSeconds` interval.

The jitter bounds shall be non-negative and the minimum shall not exceed the
maximum. Enabling candidate rollout on guest shutdown while guest-shutdown
restart is disabled shall be rejected as a contradictory configuration.
Enabling pin refresh without a declaratively approved VM flake and build target
shall also be rejected.

For a carrier policy, `interface` shall identify the host-local carrier source,
`instances` shall identify the managed VMs controlled by it, and
`requiredInterfaces` shall identify additional host-local interfaces or bridges
that must exist before policy evaluation begins. Carrier-up shall authorize an
automatic start and carrier-down shall authorize an automatic stop. These
automatic transitions shall follow the explicit-stop precedence defined by
FS-075. A carrier-controlled VM shall not simultaneously enable `startOnBoot`.
`pollIntervalSeconds` shall be positive. `dryRun` shall observe and report
transitions without changing VM service state.

## Failure Conditions

- One VM's activation variables alter another VM's behavior.
- A VM starts at boot while `startOnBoot` is disabled.
- Guest-shutdown recovery starts a VM while `restartOnGuestShutdown` is
  disabled.
- Candidate selection ignores the applicable per-VM variable.
- Pin refresh runs while `refreshPins` is disabled.
- Pin refresh is attempted for an excluded action.
- Automatic guest recovery uses a delay outside the configured bounds.
- Contradictory or invalid variable combinations are accepted.
- A carrier policy starts before a declared required interface exists.
- Carrier-up overrides explicit-stop authority, or carrier-down is recorded as
  an explicit operator stop.
- A carrier-controlled VM also enables `startOnBoot`.
- Carrier dry-run changes VM service state.

## Downstream Handoff

HDS shall derive `FS-070-HDS-010` for per-VM activation policy and timing input.
