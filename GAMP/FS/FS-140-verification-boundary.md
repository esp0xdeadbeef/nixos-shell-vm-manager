# FS: Verification Boundary

Document: FS-140
Status: Stakeholder-approved functional baseline
Owner: Supplier
Source URS: `GAMP/URS/README.md`

## Scope

Functional claims require current construction and integration evidence.

## Functional Requirement

The project's normal verification entrypoint shall actively test required
baseline construction, complete offline readiness, immutable local capture,
unified admission, build isolation, provenance and precedence, stop races,
health-gated promotion, rollback, and persistent-data preservation. Required
negative cases shall be executed and shall fail when their protected predicate
is violated. Construction and integration evidence shall not be presented as
live host or final system acceptance.

## Failure Conditions

- A required functional predicate has no active test.
- A seeded negative is present but does not gate success.
- Evidence predates the current controlled source or test.
- SMT or SIT evidence is used to claim HAT or SAT acceptance.

## Downstream Handoff

HDS shall derive `FS-140-HDS-010` for supported construction and integration
test environments. HAT and SAT remain separately authorized.
