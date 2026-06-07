# Subsystem Audit Strategy

This cleanup phase audits first and edits second. Each subsystem should produce
a short finding document before code changes are selected. The goal is not to
find things to delete; it is to decide whether each subsystem still earns its
surface area after the recent API and module migrations.

Progress tracking lives in [README.md](README.md). This file is the reusable
rubric and template.

## Audit Order

Work from low dependency to high dependency:

1. Init/composition files that only gather services.
2. Leaf utilities and adapters with no downstream ownership.
3. State/data backends.
4. Capability subsystems.
5. Module/bootstrap orchestration.
6. Framework coordination surfaces.
7. Module implementations.

Within each repo, start with `00_init.lua`, `init.lua`, `main.lua`, and other
composition files. These reveal dependency direction and usually show which
subsystems are independent enough to audit next.

## Audit Workflow

1. Read the subsystem end to end.
2. Map its direct callers and dependencies with `rg`.
3. Write findings using the rubric below.
4. Classify each finding as safe cleanup, careful cleanup, or leave alone.
5. Review the findings before making edits.
6. Patch selected findings.
7. Run focused tests first, then the relevant repo test suite.

Do not combine the audit and cleanup patch unless the finding is trivial and
already agreed.

## Rubric

### Purpose

State the current purpose of the subsystem in one sentence. If this is hard,
that is itself a finding.

### Public Surface

List the surfaces separately:

- author-facing API
- Framework-facing or module-facing API
- internal API
- tests-only API

Mark anything that exists only for migration or historical compatibility.

### Call Graph

Record:

- who calls this subsystem
- who it calls
- whether dependency direction is still clean
- whether any dependency is only present for a thin wrapper

Prefer source references over prose where useful.

### State Ownership

Identify every state lane the subsystem owns or touches:

- config data
- staged UI data
- status/runtime-published state
- cache
- shared data/events
- transient locals
- global or reload-stable state

Flag state that crosses domains without a clear reason.

### Phase And Lifecycle Rules

State how the subsystem behaves during:

- declaration
- activation
- UI draw
- commit
- runtime hooks
- reload
- teardown/rollback

Flag checks that protect the wrong phase or now duplicate object-shape rules.

### Validation And Checks

Separate checks by purpose:

- author contract validation
- data integrity validation
- lifecycle safety
- Lib/Framework invariant checks
- migration/deprecation checks

Checks that only defend internal invariants should usually be covered by tests
instead of paid for on hot paths.

### Dead Or Thin Wrappers

Look for:

- functions that only forward without adding policy
- one-line helpers that hide the real dependency
- files that exist only as historical grouping
- names that describe an old design rather than current behavior

Do not remove wrappers that intentionally name a domain concept.

### Compatibility Residue

Search for:

- deprecated names
- old docs/examples
- legacy test suite names
- compatibility shims
- comments explaining history instead of current behavior

Classify residue as removable now, intentionally retained, or needing a
deprecation path.

### Test Value

For each major test group, decide whether it protects:

- current behavior
- an important migration boundary
- old architecture only

Tests should be renamed or reshaped when they obscure the current model.

### Documentation Debt

Check whether docs are:

- stale
- duplicated
- too implementation-specific
- missing phase/lifecycle language
- still using old names

Prefer one canonical doc per concept, with smaller docs linking to it.

### Risk Rating

Every finding gets one rating:

- `safe cleanup`: rename, doc fix, dead wrapper, unreachable branch.
- `careful cleanup`: behavior-preserving but shared or lifecycle-sensitive.
- `leave alone`: current shape is intentional, useful, or too risky without a
  broader design pass.

## Finding Template

```md
# <Subsystem> Audit

## Purpose

<One sentence.>

## Surfaces

- Author:
- Framework/module:
- Internal:
- Tests-only:

## Call Graph

- Callers:
- Dependencies:
- Direction notes:

## State Ownership

- Owns:
- Reads:
- Writes:

## Lifecycle

- Declaration:
- Activation:
- UI draw:
- Commit:
- Runtime:
- Reload:
- Teardown:

## Findings

### <Finding Title>

- Rating: safe cleanup | careful cleanup | leave alone
- Evidence:
- Impact:
- Recommendation:

## Deferred Questions

- <Question>
```
