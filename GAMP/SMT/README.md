# Software Module Testing: nixos-shell VM Manager

Document: nixos-shell VM Manager SMT
Status: Current construction evidence
Source: `GAMP/SMS/README.md`
Evidence date: 2026-07-20

Verdicts apply to the release source containing this document. They do not
claim live-host or stakeholder acceptance.

| SMS | Status | Evidence |
| --- | --- | --- |
| FS-120-HDS-010-SDS-010-SMS-010 | OK | `nix build .#checks.x86_64-linux.module-evaluation`; valid module/closure evaluation plus seeded contradictory guest policy and inverted jitter bounds both rejected |
| FS-040-HDS-010-SDS-010-SMS-010 | OK | `nix build .#checks.x86_64-linux.module-tests`; atomic admission, source precedence, slot retention, and failed-candidate quarantine |
| FS-075-HDS-010-SDS-010-SMS-010 | OK | module tests; stop during gated local construction advances authority and returns 75 with the built candidate pending and no systemctl start |
| FS-070-HDS-010-SDS-010-SMS-010 | OK | module tests; baseline promotion, explicit rollout, bad functional health, healthy recovery, and foreground runner lifecycle |
| FS-030-HDS-010-SDS-010-SMS-010 | OK | module tests; source copied before mutation, both no-lock-update flags observed, running fixture unchanged during build, and failed final authority check |
| FS-130-HDS-010-SDS-010-SMS-010 | OK | dispatcher validation is ShellCheck-clean; module tests exercise update and state operations against generated-equivalent configuration |
| FS-140-HDS-010-SDS-010-SMS-010 | OK | `nix build .#checks.x86_64-linux.shellcheck .#checks.x86_64-linux.module-tests .#checks.x86_64-linux.module-evaluation`; outputs include `/nix/store/kg7rrs8fz6hcbipl5pimmdwffwfq60nk-nixos-shell-vm-manager-shellcheck` and `/nix/store/w0h62crvr1xjr7yw829qny1c7qcy80fd-nixos-shell-vm-manager-module-tests` |

## Seeded Negatives

- A process-alive candidate whose VM-specific health label is `bad` cannot
  promote and is moved to `failed`.
- Candidate rollout on guest shutdown while guest restart is disabled cannot
  produce a NixOS system generation.
- Jitter minimum greater than maximum cannot produce a generation.
- A stop after local archive capture prevents rollout even though admission
  completes.
- A stop during candidate health leaves the candidate pending, records the
  manager idle, and does not start rollback recovery.
- Build/archive commands lacking the configured immutable paths or lock inputs
  do not reach admission.
