# Software Module Testing: nixos-shell VM Manager

Document: nixos-shell VM Manager SMT
Status: Current construction evidence
Source: `GAMP/SMS/README.md`
Evidence date: 2026-07-21

Verdicts apply to the release source containing this document. They do not
claim live-host or stakeholder acceptance.

| SMS | Status | Evidence |
| --- | --- | --- |
| FS-120-HDS-010-SDS-010-SMS-010 | OK | `nix build .#checks.x86_64-linux.module-evaluation`; valid module/closure evaluation, carrier device ordering and immutable instance paths, plus seeded invalid target, contradictory guest policy, and inverted jitter bounds rejected |
| FS-040-HDS-010-SDS-010-SMS-010 | OK | `nix build .#checks.x86_64-linux.module-tests`; atomic admission, source precedence, slot retention, and failed-candidate quarantine |
| FS-075-HDS-010-SDS-010-SMS-010 | OK | module and carrier-watcher tests; stop during gated local construction advances authority, automatic carrier stop is typed separately, carrier-up clears only its own marker, and explicit-stop produces policy refusal 75 without a systemctl start |
| FS-070-HDS-010-SDS-010-SMS-010 | OK | module and systemd integration tests; `restartOnGuestShutdown` defaults on, unexpected supervisor termination is recovered with a new service process, guest shutdown follows its configured policy, and explicit stop plus carrier-down remain inactive beyond the service restart delay |
| FS-030-HDS-010-SDS-010-SMS-010 | OK | module tests; source copied before mutation, both no-lock-update flags observed, running fixture unchanged during build, and failed final authority check |
| FS-130-HDS-010-SDS-010-SMS-010 | OK | dispatcher validation is ShellCheck-clean; module tests exercise update and state operations against generated-equivalent configuration |
| FS-150-HDS-010-SDS-010-SMS-010 | OK | module evaluation proves the default stable socket and rejects a relative endpoint; systemd integration discovers the instance through `vm-list`, attaches through `vm-attach` from a separate tmux client, supplies offline interactive input, observes the exact pane process, retains the endpoint, and verifies stop cleanup |
| FS-160-HDS-010-SDS-010-SMS-010 | OK | module evaluation proves disabled-by-default policy, the default `host` lock scope, and rejection of enabled refresh without an approved source; module tests prove isolated source mutation, cross-instance reuse and atomic publication of the shared runtime lock, refreshed-lock provenance, eligible guest restart, excluded forced rollout, and unchanged shared lock plus host-pinned fallback after update, capture, or construction failure |
| FS-140-HDS-010-SDS-010-SMS-010 | OK | `nix flake check --all-systems`; x86_64 construction checks passed and aarch64 outputs evaluated successfully |

## Seeded Negatives

- A process-alive candidate whose VM-specific health label is `bad` cannot
  promote and is moved to `failed`.
- Candidate rollout on guest shutdown while guest restart is disabled cannot
  produce a NixOS system generation.
- Jitter minimum greater than maximum cannot produce a generation.
- An enabled console with a relative or duplicate socket path cannot produce a
  generation.
- Pin refresh defaults off, and enabling it without an approved flake source
  cannot produce a generation.
- Carrier policy cannot reference an unknown VM or a boot-enabled VM.
- Carrier policy cannot use unsafe policy or interface names, and carrier-up
  cannot clear an explicit-stop marker.
- A stop after local archive capture prevents rollout even though admission
  completes.
- A stop during candidate health leaves the candidate pending, records the
  manager idle, and does not start rollback recovery.
- Build/archive commands lacking the configured immutable paths or lock inputs
  do not reach admission.
- Failed refreshed-lock update, immutable capture, and construction stages do
  not admit, publish shared lock state, or prevent startup from the unchanged
  current image; later stages are not entered after an earlier failure.
