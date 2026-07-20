# Hardware Acceptance Testing: nixos-shell VM Manager

Document: nixos-shell VM Manager HAT
Status: Authorized, execution pending
Source: `GAMP/HDS/README.md`
Target: `s-tau`

The stakeholder authorized bounded live-host testing on `s-tau`, which is not
currently a production target. `s-sigma` is outside this HAT scope.

Before execution, this manager repository shall be committed and pushed. The
local `~/github/nixos` staging tree shall pin that exact pushed manager revision
in `flake.lock`, build all assigned `s-tau` images, and deploy through
`nixos-rebuild switch --flake path:...#s-tau`. The consumer staging tree is not
required to be committed or pushed.

## Planned Rows

| HDS | Status | Acceptance action |
| --- | --- | --- |
| FS-010-HDS-010 | N/A | Pending pinned full `s-tau` host-generation build |
| FS-020-HDS-010 | N/A | Pending local-closure and offline-start observation |
| FS-040-HDS-010 | N/A | Pending baseline/local candidate registry observation |
| FS-050-HDS-010 | N/A | Pending running `s-test` observation during candidate construction |
| FS-070-HDS-010 | N/A | Pending `s-test` activation-policy observation |
| FS-075-HDS-010 | N/A | Pending live explicit-stop preservation observation |
| FS-080-HDS-010 | N/A | Pending process plus `s-test` functional ping evidence |
| FS-090-HDS-010 | N/A | Pending bounded failed-candidate rollback exercise |
| FS-100-HDS-010 | N/A | Pending runtime QCOW placement and persistent-state preservation observation |
| FS-110-HDS-010 | N/A | Pending lock/state observation during bounded actions |
| FS-120-HDS-010 | N/A | Pending pinned external-flake deployment evidence |
| FS-130-HDS-010 | N/A | Pending live operator command exercise |
| FS-140-HDS-010 | N/A | Pending evidence review; SAT remains unauthorized |
