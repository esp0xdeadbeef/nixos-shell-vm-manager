# FS: Stable Offline Interactive Console

Document: FS-150
Status: Stakeholder-approved functional baseline
Owner: Supplier
Source URS: `GAMP/URS/README.md`

## Scope

Each managed VM provides operator terminal access independently of guest
network availability.

## Functional Requirement

The manager shall expose an attachable interactive host-local terminal for each
running VM by default. The terminal shall carry both runner output and operator
input without requiring IP connectivity, SSH, a guest agent, or an Internet
connection.

The terminal endpoint and session identifier shall be configurable per VM. The
defaults shall be:

```nix
console = {
  enable = true;
  socketPath = "/run/nixos-shell/<vm>.tmux";
  sessionName = "vm";
};
```

For a given VM configuration, explicit start, candidate rollout,
guest-shutdown restart, and rollback shall recreate the same endpoint and
session identifier regardless of the selected immutable image. Stopping the VM
service shall terminate the associated terminal session and remove its live
socket.

Disabling the console shall require an explicit per-VM configuration change.
Console availability shall not be accepted as functional guest health.

## Failure Conditions

- A running VM cannot accept terminal input when its guest network is absent.
- Image promotion or rollback changes the configured attachment command.
- Console attachment requires guest SSH, IP connectivity, or Internet access.
- A normal service stop leaves a live orphan console session.
- The default console is silently disabled.
- Console presence alone allows a candidate to pass functional health.

## Downstream Handoff

HDS shall derive `FS-150-HDS-010` for the host-local terminal boundary.
