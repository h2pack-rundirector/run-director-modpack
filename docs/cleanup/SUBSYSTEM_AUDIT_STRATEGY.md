# Subsystem Audit Strategy

This cleanup phase audits first and edits second. Each subsystem should produce a
short finding document before code changes are selected. The goal is not to find
things to delete; it is to decide whether each subsystem still earns its surface
area after the recent API and module migrations.

## Progress Snapshot

| Area | Audit Status | Cleanup Status | Notes |
| --- | --- | --- | --- |
| Lib bootstrap primitives: logging, registry, module registry, system scope, game deps, values | Done | Done for identified findings | See `docs/cleanup/audits/2026-06-06-lib-bootstrap-primitives.md`. Logging policy drift was fixed and policy coverage now scans `src/core` recursively. |
| Lib storage core: types, packed, fields, table, schema, alias access | Done | Done | See `docs/cleanup/audits/2026-06-06-lib-storage-core.md` and `docs/cleanup/audits/2026-06-06-lib-storage-and-hashing.md`. Removed unused hash-packing metadata while keeping explicit `packedInt` behavior. |
| Lib hashing | Done | Done | Audited with storage because hashing is a Framework-facing projection over storage primitives. Best-effort hash import policy is documented and tested. See `docs/cleanup/audits/2026-06-06-lib-storage-and-hashing.md`. |
| Framework hash/profile boundary | Done | Done for identified findings | Covered with the storage/hash audit because Framework profile hashing consumes Lib storage hash primitives. Added table round-trip coverage and documented best-effort profile import: malformed loose segments, unknown modules, and unknown known-module keys are ignored, unsupported versions reject, and invalid known values rollback. |
| Lib module state, status, and actions overview | Done | Split into focused passes | See `docs/cleanup/audits/2026-06-06-lib-module-state-status-actions.md`. Broad shape is coherent; focused passes are tracking state backends/refs, status lane, then actions/reset/commit lifecycle. |
| Lib state backends and refs: persistent state, staged state, storage refs | Done | Done | See `docs/cleanup/audits/2026-06-06-lib-state-backends-and-refs.md`. Backend direction is coherent. Ref adapter option validation, `stagedState.view` removal, and committed-root adapter cleanup are complete. |
| Lib data front end: `module.data.define`, `runtime.data`, `ui.data` | Done | No cleanup selected | See `docs/cleanup/audits/2026-06-06-lib-data-front-end.md`. Data front-end adapters are intentionally thin over storage refs/backends. |
| Lib status lane: declarations and runtime/UI adapters | Done | Done | See `docs/cleanup/audits/2026-06-06-lib-status-lane.md`. Status shape is coherent; focused declaration validation tests are now covered. |
| Lib actions, reset, and commit lifecycle | Done | Done | See `docs/cleanup/audits/2026-06-06-lib-actions-reset-commit-lifecycle.md`. Ordering is coherent and tested. Dead action-buffer surface, unused controls DI, best-effort side-effect docs, duplicated commit-success tail, and fallback draw lifecycle sequencing are cleaned up. |
| Lib cache and shared | Pending | Pending | Audit current-run cache, shared data, shared events, and adapters. |
| Lib controls | Pending | Pending | Audit compiler, refs, draw dispatch, private storage/action lowering, and control template support. |
| Lib coordinator and definitions | Pending | Pending | Audit coordinator registry, definition preparation, and internal declaration merging. |
| Lib runtime capability installers: hooks, overlays, mutations | Pending | Pending | Audit after state/controls so callback/data surfaces are clear. |
| Lib widgets and UI draw | Pending | Pending | Audit widget helpers, widget surfaces, nav, UI draw, and control draw integration. |
| Lib fallback UI | Pending | Pending | Audit fallback menu/HUD behavior and framework fallback registration. |
| Lib managed module bootstrap | Pending | Pending | Audit managed module record, activation, lifecycle, reset, commit, reload, and UI phase orchestration. |
| Lib public surfaces | Pending | Pending | Audit `createModule`, framework runtime bridge, and exported author/framework APIs last. |
| Cross-cutting `phaseGate` inventory | In progress | Pending | Track consumers during each subsystem audit; do focused cleanup only after state/status/controls/widgets are understood. |
| Framework | Pending | Pending | Start after Lib pass, using the same low-dependency to high-dependency order. |
| Module repos | Pending | Pending | Start after infrastructure pass; audit data, logic, UI, then main composition. |

## Recommended Next

Next step: **audit cache/shared**.

Reason:

- The focused backend/ref audit is complete and did not find an architectural fault.
- The clearly safe backend cleanups are done: `storage_ref_adapter.create(...)` option validation and `stagedState.view` removal.
- The committed-root adapter cleanup is complete.
- The focused standard data front-end audit is complete and found no cleanup candidate.
- The focused status-lane audit is complete and found no architecture issue.
- Focused status declaration validation tests are complete.
- The focused actions/reset/commit lifecycle audit is complete.
- Safe action lifecycle cleanup is complete.
- The careful action lifecycle cleanup is complete.
- Framework fallback UI now uses the live module draw-and-commit lifecycle entry point.

Suggested choices:

1. Next subsystem audit:
   - cache and shared data/events

Keep `phaseGate` as an inventory item during this audit. Do not delete it globally until state refs, controls, widgets, cache/shared, and managed module draw orchestration have all been checked.

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

## Initial Traversal

Start with Lib composition and low-dependency subsystems:

1. `adamant-ModpackLib/src/core/init.lua`
2. `adamant-ModpackLib/src/core/*/00_init.lua`
3. low-level utilities: logging, values, game deps
4. storage/schema/hash helpers
5. module state lanes: data, status, actions
6. capabilities: cache, shared, hooks, mutations, overlays, widgets, controls
7. module bootstrap and activation
8. Framework runtime bridge

Then repeat the same pattern in Framework, then module repos.
