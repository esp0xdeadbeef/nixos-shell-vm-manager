# FS: Reusable Flake Integration

Document: FS-120
Status: Stakeholder-approved functional baseline
Owner: Supplier
Source URS: `GAMP/URS/README.md`

## Scope

The manager consumes declarative image products rather than owning VM sources.

## Functional Requirement

A consumer Nix flake shall be able to provide its assigned baseline VM image
derivations, lifecycle policy, health criteria, and storage policy to the
manager. The consumer's approved dependency graph shall govern baseline image
construction. The manager shall not require a consumer-specific repository
layout, a remote repository URL, or runtime source selection for those images.

If pin refresh is enabled, the consumer shall declaratively provide the
approved VM flake and image build target through the public integration
boundary. The manager shall treat that input as data and shall not infer a
repository layout, substitute a different source, or require a GitHub-specific
reference. The refreshed source and effective lock shall be captured immutably
before construction. Refresh shall not mutate the consumer's host-generation
source or approved lock.

## Failure Conditions

- Integration requires copying manager implementation into the consumer.
- The manager requires knowledge of a consumer's internal source paths.
- A baseline VM requires a runtime GitHub or other remote-source override.
- The manager replaces the consumer's approved dependency graph.
- Pin refresh requires manager knowledge of consumer repository layout.
- Pin refresh accepts an undeclared source or build target.
- Pin refresh mutates the consumer's host-generation lock.

## Downstream Handoff

HDS shall derive `FS-120-HDS-010` for the public Nix integration boundary.
