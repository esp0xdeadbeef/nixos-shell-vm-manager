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
| FS-150-HDS-010-SDS-010-SMS-010 | OK | module evaluation proves the default stable socket and rejects a relative endpoint; systemd integration discovers the instance through `vm-list`, attaches through `vm-attach` from a separate tmux client, supplies offline interactive input, observes the exact pane process, retains the endpoint, and verifies stop cleanup |
| FS-160-HDS-010-SDS-010-SMS-010 | OK | module evaluation proves disabled-by-default policy and rejects an enabled refresh without an approved source; module tests prove isolated lock mutation, refreshed-lock provenance, eligible guest restart, excluded forced rollout, and unchanged-slot host-pinned fallback after update, capture, or construction failure |
| FS-140-HDS-010-SDS-010-SMS-010 | OK | `nix flake check --all-systems`; x86_64 outputs include `/nix/store/l49qhbnbz48bjbaxgjz5flrhsn7dwra7-nixos-shell-vm-manager-shellcheck`, `/nix/store/1lwnpm9qdkq72wccfy2v5rx4bvpyy7qr-nixos-shell-vm-manager-module-tests`, and `/nix/store/41zzyvdrxhikf98pbsc7w4qmbixv8r3x-nixos-shell-vm-manager-module-evaluation` |

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
- A stop after local archive capture prevents rollout even though admission
  completes.
- A stop during candidate health leaves the candidate pending, records the
  manager idle, and does not start rollback recovery.
- Build/archive commands lacking the configured immutable paths or lock inputs
  do not reach admission.
- Failed refreshed-lock update, immutable capture, and construction stages do
  not admit or prevent startup from the unchanged current image; later stages
  are not entered after an earlier failure.
