# Software Integration Testing: nixos-shell VM Manager

Document: nixos-shell VM Manager SIT
Status: Current integration evidence
Source: `GAMP/SDS/README.md`
Evidence date: 2026-07-20

Command:

```console
nix build --print-build-logs .#checks.x86_64-linux.systemd-integration
```

Result: `OK`, output
`/nix/store/6m9v5s1hcj3afyaa02jc7a05bb2xmv4d-vm-test-run-nixos-shell-vm-manager-systemd`.
The test used a real NixOS VM and real systemd. Its managed fixture service had
`IPAddressDeny=any`; image selection and startup therefore completed without IP
network access.

| SDS | Status | Evidence |
| --- | --- | --- |
| FS-010-HDS-010-SDS-010 | OK | Test-host activation admitted its closure-retained baseline while `startOnBoot=false` left the VM service inactive |
| FS-030-HDS-010-SDS-010 | OK | SMT provides immutable construction evidence; systemd test admits the resulting local-source class only through the common registrar |
| FS-040-HDS-010-SDS-010 | OK | Real service moved baseline/local records through candidate, current, previous, and failed slots |
| FS-070-HDS-010-SDS-010 | OK | Real foreground service handled explicit start, explicit rollout, explicit stop, and natural runner exit as distinct events |
| FS-075-HDS-010-SDS-010 | OK | `systemctl stop` created the session stop marker and idle phase; later candidate admission did not start the service; a stop during candidate health left that candidate pending without starting recovery; `vm-rollout` supplied later authority |
| FS-080-HDS-010-SDS-010 | OK | Exact runner stayed alive while the `bad` functional command failed; promotion was denied, proving process presence alone insufficient |
| FS-090-HDS-010-SDS-010 | OK | Bad candidate was stopped and quarantined, unchanged current was restarted and health-checked, then the service remained healthy |
| FS-100-HDS-010-SDS-010 | OK | Marker below the independent persistent directory survived promotion, failed rollout, rollback, guest restart, and final stop |
| FS-110-HDS-010-SDS-010 | OK | State transitions completed under real concurrent systemd/service boundaries without overlapping slot changes; construction lock/token negatives are covered by SMT |
| FS-120-HDS-010-SDS-010 | OK | External test configuration imported `nixosModules.default`, supplied direct derivations and policy without repository layout knowledge, and started an aliased instance through its configured compatible runner path |
| FS-140-HDS-010-SDS-010 | OK | Current NixOS test exercised positive and negative integration paths; this verdict is not HAT or SAT |
| FS-150-HDS-010-SDS-010 | OK | With `IPAddressDeny=any` on the managed service, the test sent input through `/run/nixos-shell/test-vm.tmux`, matched its pane PID to the exact runner, retained the endpoint through rollout, rollback, and guest restart, and verified stop cleanup |
| FS-160-HDS-010-SDS-010 | OK | An opted-in real systemd service ran Nix lock update, immutable archive and build against a retained local no-input fixture, admitted `pin-refresh` source and lock provenance, passed functional health, and promoted while the service had `IPAddressDeny=any` |
