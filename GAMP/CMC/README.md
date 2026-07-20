# Configuration Management and Change Control

Document: nixos-shell VM Manager CMC
Status: Active

The controlled product is this Git repository. URS and FS changes require an
explicit stakeholder proposal and approval. HDS, SDS, SMS, implementation,
tests, and evidence must continue to trace to the approved FS. The manager
commit pushed to `origin/main` is the releasable configuration item.

For consumer acceptance, `~/github/nixos/flake.lock` shall pin the exact pushed
manager revision. That consumer tree is an authorized local/offline staging
configuration and is not a release of this repository. HAT evidence records the
manager revision, consumer lock node, host generation, commands, and outcomes.

Secrets, credentials, mutable VM data, generated QCOW files, and `/run` state
are not configuration items. SMT/SIT evidence cannot be relabeled as HAT or SAT.
SAT requires a separate stakeholder authorization and remains outside this
change.
