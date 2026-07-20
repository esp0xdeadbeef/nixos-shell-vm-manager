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
| FS-150-HDS-010-SDS-010-SMS-010 | OK | module evaluation proves the default stable socket and rejects a relative endpoint; systemd integration supplies offline interactive input, exact pane-process observation, stable endpoint reuse, and stop cleanup |
| FS-140-HDS-010-SDS-010-SMS-010 | OK | `nix flake check --all-systems`; x86_64 outputs include `/nix/store/1vjq6dbphbd54mqgnm32jnr6pj690i4b-nixos-shell-vm-manager-shellcheck`, `/nix/store/5b6jbx7igbdm7n2xh6b0igx0npnxfafl-nixos-shell-vm-manager-module-tests`, and `/nix/store/41zzyvdrxhikf98pbsc7w4qmbixv8r3x-nixos-shell-vm-manager-module-evaluation` |

## Seeded Negatives

- A process-alive candidate whose VM-specific health label is `bad` cannot
  promote and is moved to `failed`.
- Candidate rollout on guest shutdown while guest restart is disabled cannot
  produce a NixOS system generation.
- Jitter minimum greater than maximum cannot produce a generation.
- An enabled console with a relative or duplicate socket path cannot produce a
  generation.
- Carrier policy cannot reference an unknown VM or a boot-enabled VM.
- A stop after local archive capture prevents rollout even though admission
  completes.
- A stop during candidate health leaves the candidate pending, records the
  manager idle, and does not start rollback recovery.
- Build/archive commands lacking the configured immutable paths or lock inputs
  do not reach admission.
