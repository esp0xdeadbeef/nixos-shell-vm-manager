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

## Failure Conditions

- Integration requires copying manager implementation into the consumer.
- The manager requires knowledge of a consumer's internal source paths.
- A baseline VM requires a runtime GitHub or other remote-source override.
- The manager replaces the consumer's approved dependency graph.

## Downstream Handoff

HDS shall derive `FS-120-HDS-010` for the public Nix integration boundary.
