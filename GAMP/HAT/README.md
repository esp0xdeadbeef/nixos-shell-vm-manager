# Hardware Acceptance Testing: nixos-shell VM Manager

Document: nixos-shell VM Manager HAT
Status: Executed — pass with recorded observations
Source: `GAMP/HDS/README.md`
Evidence date: 2026-07-20
Target: `s-tau`

The stakeholder authorized bounded live-host testing on non-production `s-tau`.
`s-sigma`, `l-esp`, and SAT were outside this execution scope. No deployment or
remote validation was performed on `l-esp`.

FS-150 was added after the release exercised by this HAT. Its offline console
contract has construction and integration coverage, but no live-host verdict is
claimed here. A new HAT requires separate authorization.

## Configuration Items

| Item | Accepted value |
| --- | --- |
| Manager release | `de54a691cd950b2f1563911b4110afa26abfd245` on `origin/main` |
| Consumer lock | revision above; `sha256-Fa+eVtlJOSOpAvX8pxu7rUrN90SZ4t8uIwP525aerBY=` |
| Consumer state | authorized uncommitted/offline `~/github/nixos` staging tree |
| Host generation | `/nix/store/fw4hql1vs6vpk9yqzdzdp0lmz4j8wvba-nixos-system-s-tau-26.05.20260719.fd14620` |
| Final `s-test` current | `/nix/store/94v35v9y89rj7f9h93v9wcgrwids3pg7-nixos-vm` |

The final host build completed with all 13 configured direct image outputs in
the host closure. Every configured runner was executable, including the
intentional `s-router-legacy-prod` compatibility path
`bin/run-s-router-prod-vm`. Only `s-test-vm.service` was wanted by
`multi-user.target`.

The closure was transferred through the trusted remote Nix daemon and activated
with:

```console
nix copy --no-check-sigs --to \
  'ssh-ng://s-tau?remote-program=sudo%20nix-daemon' \
  /nix/store/fw4hql1vs6vpk9yqzdzdp0lmz4j8wvba-nixos-system-s-tau-26.05.20260719.fd14620
nixos-rebuild switch --flake 'path:.#s-tau' --target-host s-tau --sudo
```

The one-shot `--no-check-sigs` affected transport validation only; no persistent
host trust setting was changed. Activation admitted all 13 baseline candidates
and explicitly reported that the already-running `s-test` unit was not
restarted.

## Executed Scenarios

### Baseline migration and non-disruption

The old `s-test` process remained healthy and retained the same main PID while
the final host generation was built, copied, switched, and its new image was
admitted. A controlled `systemctl stop s-test-vm.service` followed by
`vm-rollout s-test` then promoted the final host-generation candidate only after
functional ping health succeeded.

### Explicit-stop authority

While stopped, host-generation readmission left the unit inactive and retained
the stop marker. On the final release, an explicit stop changed the registry to
`phase=idle`, set `explicitlyStopped=true`, cleared `runnerPid`, and advanced the
authority epoch exactly once. A later explicit start cleared that authority and
restored the same current image.

### Offline start

Both `nix-daemon.service` and `nix-daemon.socket` were inactive while
`systemctl start s-test-vm.service` started the final current image. The guest
passed its functional ping and `vm-status` returned `phase=running` without
construction or dependency resolution. The daemon and socket were restored and
verified active after the test.

### Health-gated failure and rollback

An immutable negative candidate had an executable runner that stayed alive as
`sleep infinity` but booted no guest. Admission did not change either the
supervisor or runner PID. During explicit rollout the process remained alive,
guest health remained unavailable, and promotion was denied after all 30
configured health attempts. The candidate was retained in `failed`, and the
exact prior current image was automatically restarted and health-checked:

```text
s-test: functional health failed after 30 attempts
s-test: candidate failed; healthy current image restored
```

### Guest shutdown rollout

A distinct immutable known-good candidate was admitted without interrupting the
running guest. Direct SSH was unavailable because the test account lacked guest
authorization, so QMP `system_powerdown` supplied a real ACPI power event to the
guest instead of typing `shutdown now`. The guest shut down cleanly, the manager
observed the natural runner exit, applied 3 seconds of configured jitter, booted
the candidate, health-checked it, and promoted it. The final host-generation
image was then readmitted and restored as current.

### Storage preservation

The persistent disk remained
`/persist/vm-persists/s-test/state.qcow2` with inode `6235` across migration,
failed rollout, rollback, guest shutdown, promotion, explicit stops, and offline
starts. The replaceable root was recreated below
`/var/cache/nixos-shell-vm-manager/s-test/s-test.qcow2`; it was not placed in the
persistence directory.

## Verdicts

| HDS | Status | Live evidence |
| --- | --- | --- |
| FS-010-HDS-010 | OK | Complete final host generation contained all 13 configured image outputs and runners before activation |
| FS-020-HDS-010 | OK | Final current image started and passed health with the Nix daemon and socket inactive |
| FS-040-HDS-010 | OK | Host and HAT-local candidates traversed candidate, current, previous, and failed slots atomically |
| FS-050-HDS-010 | OK | Running `s-test` PID and health remained unchanged through host build, transfer, switch, and candidate admission |
| FS-070-HDS-010 | OK | Explicit rollout, explicit start, configured jitter, and ACPI guest-shutdown policy were observed live |
| FS-075-HDS-010 | OK | Explicit stop blocked admission-driven start, was idempotent, reported idle, and required later explicit authority |
| FS-080-HDS-010 | OK | A live runner without functional guest health was not promoted; healthy VM images passed ping |
| FS-090-HDS-010 | OK | Failed candidate was quarantined and the exact prior current image was automatically restored healthy |
| FS-100-HDS-010 | OK | Persistent inode `6235` survived every action; ephemeral root remained below `/var/cache` |
| FS-110-HDS-010 | OK | Live actions produced consistent locked registry states; construction concurrency negatives remain covered by SMT/SIT |
| FS-120-HDS-010 | OK | External consumer pinned the exact pushed manager release and deployed direct consumer-built image derivations |
| FS-130-HDS-010 | OK | `vm-status`, `vm-rollout`, direct service start/stop, admission, and recovery were exercised live |
| FS-140-HDS-010 | OK | Construction evidence and this authorized HAT are current; no SAT claim is made |

## Final State and Observations

At handoff, `s-tau` runs the accepted host generation above. Only
`s-test-vm.service` is active among managed VM units. Its candidate is empty,
its current is the final host-generation image, functional ping is healthy,
the Nix daemon socket is restored, and its phase is `running`. The known-good
HAT image remains in `previous` and the negative fixture remains quarantined in
`failed`, as required by slot retention.

The `s-test` console reported failures for `nebula@mesh.service` during boots.
The approved health policy for this VM is network reachability, which passed;
therefore this did not invalidate manager HAT. If Nebula is a required guest
function, the consumer should strengthen `healthCheck.command` before treating
it as an acceptance criterion.

The repository-wide consumer `nix flake check --all-systems` was not used as
final HAT evidence because `l-esp` was explicitly excluded and a pre-existing,
unrelated `s-router-hetz` inventory check is known to fail. The complete targeted
`s-tau` build, exact closure check, manager SMT/SIT suite, and live scenarios
above form the accepted evidence boundary.
