# Lib Data Front-End Audit

## Purpose

The data front end is the author-facing UI-owned storage lane: modules declare storage with `module.data.define(...)`, UI draw code edits staged values through `ui.data`, and runtime callbacks read committed values through `runtime.data`.

## Surfaces

- Author:
  - `module.data.define(storage)`
  - `ui.data.get/read/write`
  - writable refs and table handles returned by `ui.data.get(...)`
  - `runtime.data.get/read`
  - read-only refs and table handles returned by `runtime.data.get(...)`
- Framework/module:
  - declaration facade stores raw data storage for activation.
  - module state narrows persistent state to `runtime.data`.
  - UI phase creates `ui.data` from staged state for each draw callback.
- Internal:
  - `src/core/module_bootstrap/module/declaration_surface.lua`
  - `src/core/module_state/persistent/store.lua`
  - `src/core/module_state/staged/ui_state.lua`
  - `src/core/module_state/storage_ref_adapter.lua`
- Tests-only:
  - direct state/front-end creation through module-state harnesses.
  - module activation tests that exercise `ui.data` and `runtime.data` through real callbacks.

## Call Graph

- `module.data.define(...)` validates public-data-only policy for `mode`, then stores declarations for activation.
- activation merges data, status, built-ins, and control storage before storage schema validation.
- `moduleState.createStore(...)` wraps persistent state as `runtime.data`.
- `ui/phase.lua` wraps staged state as `ui.data` during draw callback construction.
- `storage_ref_adapter` supplies common refs, table handles, private-alias rejection, method-call checks, and write/reset phase gates.

## State Ownership

- Owns:
  - no raw state by itself; this lane is a front-end projection over persistent/staged state.
- Reads:
  - schema metadata from persistent/staged state to reject status aliases.
  - committed values through `runtime.data`.
  - staged values through `ui.data`.
- Writes:
  - `ui.data` stages UI/config writes during draw only.
  - `runtime.data` is read-only.
  - resets are ref/handle methods or whole-module `ui.resetAll`, not a top-level `ui.data.reset(...)` operation.

## Lifecycle

- Declaration:
  - `module.data.define(...)` can be called once before activation.
  - public data rejects `mode` recursively so `mode = "runtime"` does not appear as a data API concept.
- Activation:
  - normal storage validation owns descriptor shape, aliases, persistence, hashing, table rows, packed bits, and defaults.
- UI draw:
  - `ui.data` reads staged values and stages writes.
  - write/reset methods on refs and table handles require draw phase.
- Commit:
  - staged values flush to config before actions/shared events/commit callbacks.
- Runtime:
  - `runtime.data` reads committed setting values.
  - `runtime.data` cannot write and cannot read transient UI-only aliases.
- Reload:
  - persistent/staged state own rehydration and staged-copy refresh.
- Teardown:
  - data front-end adapters own no receipts or teardown state.

## Findings

### Data Front-End Is Correctly Thin

- Rating: leave alone
- Evidence:
  - `persistent/store.lua` only rejects status aliases, builds read-only refs, and exposes `cache`/`shared` aliases.
  - `staged/ui_state.lua` only rejects status aliases, builds writable draw refs, and exposes `shared`.
  - both adapters delegate private-alias rejection and ref/table behavior to `storage_ref_adapter`.
- Impact:
  - The front end stays readable because actual storage semantics live below it.
  - Keeping the wrappers gives author-facing diagnostics like `runtime.data.get` and `ui.data.get` instead of leaking backend names.
- Recommendation:
  - Keep these adapters.
  - Do not merge them into persistent/staged state.

### `module.data.define(...)` Rejects Only The Public-Mode Boundary

- Rating: leave alone
- Evidence:
  - declaration surface rejects `mode` recursively for roots, packed bits, and table rows.
  - storage schema validation still owns all normal descriptor validation.
  - `TestCreateModule:testModuleDataDefineTreatsModeAsUnknownPublicField` covers root and row `mode` rejection.
- Impact:
  - This keeps the public API forward-looking: data declarations do not know about the old runtime-owned/storage-mode idea.
  - The one early validation is a semantic boundary, not a second storage validator.
- Recommendation:
  - Keep the narrow early check.
  - If future fields move out of public data, add similarly targeted boundary checks instead of duplicating storage validation.

### Status And Private Aliases Are Properly Excluded

- Rating: leave alone
- Evidence:
  - `runtime.data` and `ui.data` reject status aliases before delegating to state backends.
  - `storage_ref_adapter` rejects private Lib aliases on `get/read/write` and ref alias methods.
  - tests cover status wrong-surface behavior and private alias access through data/status/front-end refs.
- Impact:
  - Public data remains the storage lane for author-declared config/staged state, not status or control internals.
  - Controls can generate private storage while ordinary data APIs remain clean.
- Recommendation:
  - Keep the exclusion policy in the front-end adapters and ref adapter.

### Shared And Cache Are Attached Here But Should Be Audited Separately

- Rating: leave alone
- Evidence:
  - `runtime.data.cache` is attached on the runtime data object.
  - `runtime.data.shared` / `ui.data.shared` are attached as shared-data aliases.
  - these are referenced heavily in author docs, but the behavior is owned by cache/shared subsystems, not by the data front-end adapters.
- Impact:
  - The namespace is practical for authors, but it can make audits look wider than the actual front-end code.
- Recommendation:
  - Do not evaluate cache/shared semantics in this pass.
  - Cover those as the next independent data-lane/capability audit after actions/reset/commit or before controls, depending on priority.

### Tests Cover Behavior Through Higher-Level Paths

- Rating: leave alone
- Evidence:
  - `TestCreateModule` covers module declaration, draw-time `ui.data.write`, committed `runtime.data.read`, and status wrong-surface rejection.
  - `TestModuleState_StagedState` covers UI status/data separation.
  - `TestStorageValidation` and `TestControls` cover private alias rejection through public data surfaces.
  - backend tests cover table, packed, transient, default, and persistence behavior below the front end.
- Impact:
  - There is no obvious missing data-front-end-only test comparable to the status declaration gap.
  - More direct adapter tests would duplicate backend/ref tests without adding much confidence.
- Recommendation:
  - Leave tests as-is for this pass.
  - Add targeted tests only if future cleanup changes the front-end adapter surfaces.

## Deferred Questions

- Should docs continue to show `runtime.data.shared` and `ui.data.shared` as first-class aliases, or should shared docs prefer `runtime.shared` / `ui.shared` to keep data conceptually narrower?
- Should `ui.data` ever grow a top-level `reset(alias, ...)` convenience, or should resets remain ref/handle-level plus `ui.resetAll`?
