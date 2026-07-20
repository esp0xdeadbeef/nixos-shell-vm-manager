# FS: Immutable Local Candidate

Document: FS-030
Status: Stakeholder-approved functional baseline
Owner: Supplier
Source URS: `GAMP/URS/README.md`

## Scope

A deliberate local development source may provide a candidate without becoming
mutable runtime state.

## Functional Requirement

The local candidate action shall require an explicitly selected local flake and
its dependency lock. Before construction, the relevant source content and lock
shall be captured as one immutable input. Construction shall not refresh the
lock. Edits made after capture shall not affect the candidate produced by that
action.

## Failure Conditions

- A local candidate is constructed without captured dependency pins.
- Construction silently refreshes or replaces the local lock.
- The running image refers directly to a mutable working tree.
- Later source edits change an already built candidate.

## Downstream Handoff

HDS shall derive `FS-030-HDS-010` for local source availability and immutable
capture support.
