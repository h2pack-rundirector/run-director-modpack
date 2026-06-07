# Lib State Backends And Refs Audit

## Purpose

Persistent state owns committed storage snapshots; staged state owns draw-time edits; storage refs expose phase-shaped field/table handles over those backends.

## Surfaces

- Author:
  - no direct persistent/staged backend surface
  - public projections are `runtime.data`, `ui.data`, `runtime.status`, and `ui.status`
- Framework/module:
  - managed module `read`, `stage`, `writeAndFlush`, `flush`, `reloadFromConfig`, `commitIfDirty`
  - Framework config hash/profile apply uses those managed module methods
- Internal:
  - `persistentState.read/get/table/getAliasSchema/status`
  - `stagedState.read/write/get/table/field/reset/resetAll/isDirty/auditMismatches`
  - `stagedState._flushToConfig/_reloadFromConfig/_captureDirtyConfigSnapshot/_restoreConfigSnapshot`
  - `persistentState._readRoot/_replaceRoot/_reloadFromConfig`
  - `storage_ref_adapter.create(...)`
- Tests-only:
  - direct `persistentState` and `stagedState` assertions

## Call Graph

- `module_state/00_init.lua` creates:
  - persistence backend
  - storage config adapter
  - persistent state
  - staged state, with persistent state passed in as its committed-root source
  - UI/runtime projection adapters
- `managed_module.lua` consumes persistent/staged state directly for module lifecycle and creates public projections.
- `managed_module_lifecycle.lua` consumes internal staged-state methods for flush, rollback, reload, and drift resync.
- Framework consumes only managed module methods, not raw staged/persistent internals.

## State Ownership

- `persistent_state.lua`
  - owns committed root cache for persisted roots and status roots
  - owns config hydration/normalization for persisted roots
  - owns status writes/resets
  - exposes read-only runtime data handles
- `staged_state.lua`
  - owns staging values and dirty roots
  - owns transient data values
  - owns table/field handles for UI writes
  - reads committed status values from persistent state
  - flushes dirty persisted staged roots back into config and persistent committed cache
- `storage_ref_adapter.lua`
  - owns public ref wrapping, method-call validation, private-alias rejection, and write/reset phase gates

## Findings

### Backend Direction Is Coherent

- Rating: leave alone
- Evidence:
  - `staged_state.lua` only reaches into persistent state through `_readRoot`, `_replaceRoot`, and `_reloadFromConfig`.
  - `persistent_state.lua` does not depend on staged state.
  - Framework profile code reaches the backend only through managed module methods.
- Impact:
  - The direction is correct: persistent owns committed state; staged owns pending UI edits.
  - This is the right foundation for the status/data split.
- Recommendation:
  - Keep the current ownership model.
  - Avoid introducing a separate status backend unless the status-focused pass finds more concrete duplication.

### Staged State Depended On Persistent State Through Private Methods

- Rating: careful cleanup, completed
- Evidence:
  - `staged_state.lua` checked `persistentState._readRoot` in several places for status/runtime roots.
  - `staged_state.lua` called `persistentState._replaceRoot` when flushed staged config updated committed snapshots.
  - `staged_state.lua` called `persistentState._reloadFromConfig` during staged reload.
- Impact:
  - The dependency was valid, but the full persistent-state object was being passed where staged state really needed a small committed-root interface.
  - The repeated `type(persistentState._readRoot) == "function"` checks made the relationship look optional even though normal module state always supplies it.
- Recommendation:
  - Completed by passing a small committed-root adapter into staged state:
    - `readRoot(root)`
    - `replaceRoot(root, value)`
    - `reloadFromConfig()`
  - Private persistent-state method knowledge now lives in `module_state/00_init.lua`, the composition layer.

### `stagedState.view` Was Legacy Test/Internal Surface

- Rating: safe cleanup, completed
- Evidence:
  - Production code did not use `stagedState.view`.
  - Framework and module repos did not use it.
  - Lib tests used it for assertions.
  - API docs listed `stagedState.view` beside internal staged-state plumbing.
- Impact:
  - The live author model is object/ref based (`ui.data.get/read/write`), not table-proxy based.
  - Keeping `view` documented as part of the internal API widened the perceived state surface.
- Recommendation:
  - Removed the proxy and replaced test assertions with explicit `stagedState.read(...)` / `stagedState.status.read(...)`.

### `storage_ref_adapter` Lacked Internal Option Validation

- Rating: safe cleanup, completed
- Evidence:
  - `storage_ref_adapter.create(opts)` treated any phase other than `"draw"` as runtime because `createGate(opts.phase == "draw")` received a boolean.
  - All current production callers pass `"draw"` or `"runtime"`.
- Impact:
  - This is not an author-facing bug, but a future internal caller typo would silently create runtime-gated refs.
  - The check would run at ref-container creation time, not on hot read/write paths.
- Recommendation:
  - Added construction-time validation that `opts.phase` is exactly `"draw"` or `"runtime"`.
  - Kept the existing write/reset gates.

### Convenience Writes Double-Check Phase In Some Paths

- Rating: leave alone
- Evidence:
  - `ui_state.write(...)` calls `phaseGate.requireAnyDraw()` and then calls a writable ref whose `write(...)` also gates draw phase.
  - `runtime_status.write/reset(...)` calls `phaseGate.requireRuntime()` and then may call a writable ref whose `write/reset(...)` also gates runtime phase.
  - Ref methods need their own gates because callers can hold refs and call methods directly.
- Impact:
  - The duplicate checks are cheap and only apply to writes/resets, not reads.
  - Removing top-level checks would require care because `runtime.status.reset(alias)` can reset a root directly without going through a ref reset method.
- Recommendation:
  - Leave this alone unless profiling or a larger ref-adapter cleanup gives a clear reason.
  - The duplicated checks are acceptable safety/clarity at low cost.

### Table Handles Already Protect Mutable Reads

- Rating: leave alone
- Evidence:
  - `storage/table.lua` returns deep copies from `snapshot(...)` and `snapshots(...)`.
  - Persistent read-only table handles do not expose write methods.
  - Staged table handles copy rows before structural writes.
  - Tests cover snapshot mutation not affecting stored table values.
- Impact:
  - The current live-table vs hash-snapshot policy is preserved: runtime table operations stay flexible, while exposed snapshots are copied.
- Recommendation:
  - No backend cleanup needed here in this pass.

### Framework Boundary Is Already Narrow Enough

- Rating: leave alone
- Evidence:
  - Framework config hash uses `liveModule.stage(...)`, `liveModule.flush()`, and `liveModule.reloadFromConfig()`.
  - Framework module registry uses `liveModule.read(...)` and `liveModule.writeAndFlush(...)`.
  - Framework does not call `stagedState` or `persistentState` directly.
- Impact:
  - The Framework boundary does not need backend-specific cleanup.
  - Backend changes should preserve managed module methods rather than exposing new state internals.
- Recommendation:
  - Keep Framework out of raw state backends.

## Suggested Cleanup Order

1. Completed: add `storage_ref_adapter.create(...)` option validation.
2. Completed: remove `stagedState.view` and update tests to use explicit reads.
3. Completed: introduce a committed-root adapter between persistent and staged state.

## Deferred Questions

- None for the focused backend/ref pass. Move to the status-lane audit next unless new backend behavior issues appear.
