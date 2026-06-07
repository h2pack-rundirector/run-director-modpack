# Lib Module State, Status, And Actions Audit

## Purpose

Module state owns the local data lanes that bridge Lib storage schemas into runtime reads, UI staged writes, runtime-authored status, and commit-time UI intent.

## Surfaces

- Author:
  - `runtime.data`
  - `ui.data`
  - `runtime.status`
  - `ui.status`
  - `ui.actions`
  - `commit.actions`
  - `ui.resetAll`
- Framework/module:
  - managed module `read`, `stage`, `writeAndFlush`, `flush`, `reloadFromConfig`, `commitIfDirty`, `resetAll`
  - Framework profile apply uses managed module staging/flushing, not raw state internals
- Internal:
  - `persistentState`
  - `stagedState`
  - `storage_ref_adapter`
  - `actionBuffer`
  - status declaration compiler
- Tests-only:
  - direct persistent/staged state construction through harness helpers
  - direct `_flushToConfig`, `_reloadFromConfig`, and drift tests

## Call Graph

- `core/module_state/00_init.lua` composes persistence backend, persistent state, staged state, status adapters, UI state, runtime store, and action buffers.
- `core/module_bootstrap/managed_module.lua` creates the runtime and UI public projections from those internals.
- `core/module_bootstrap/managed_module_lifecycle.lua` owns the commit order:
  - capture actions
  - flush staged config
  - apply/revert mutations when config changed
  - execute public actions
  - execute internal reset/status actions
  - flush shared events
  - notify commit observers
- `core/module_bootstrap/ui/phase.lua` builds draw callback objects and opens/closes the draw phase.
- Controls, widgets, cache, and shared all consume the same public projections or phase-gate assumptions, so cleanup here affects later audits.

## State Ownership

- Persistent state owns committed persisted roots and committed status roots.
- Staged state owns draw-time UI storage, transient values, dirty tracking, and config flush/reload.
- Status roots are storage roots with `mode = "runtime"`, no hash participation, and explicit `persist`.
- Action buffers own one-commit UI intent and pending shared event payloads.
- Internal reset uses a private action slot so `ui.resetAll` can reset status after staged config/mutation work succeeds.

## Lifecycle

- Declaration:
  - `module.status.define(...)` compiles status declarations into runtime-mode storage roots.
  - `module.actions.define(...)` declares action handlers and action order.
- Activation:
  - `moduleState.create(...)` prepares persistent and staged state around a prepared definition.
  - managed module creates runtime store/status and UI data/status/actions projections.
- UI draw:
  - `ui.data` stages UI-owned storage edits.
  - `ui.status` reads runtime-authored status.
  - `ui.actions` stages commit intent and shared events.
  - `ui.resetAll` resets staged roots and queues a status reset.
- Commit:
  - dirty staged config flushes first.
  - mutation sync happens after config flush when config changed.
  - public actions, internal reset actions, shared events, and `onCommit` run after successful config/mutation work.
- Runtime:
  - runtime callbacks read committed `runtime.data`.
  - runtime callbacks write/read `runtime.status`.
- Reload:
  - persistent state rehydrates persisted roots.
  - staged state copies committed/config values back into staging and clears dirty flags.
- Teardown:
  - module state itself has no teardown; lifecycle receipts live in managed module activation.

## Findings

### This Scope Is Too Broad For One Cleanup Patch

- Rating: leave alone
- Evidence:
  - `persistent_state.lua` and `staged_state.lua` are state backends.
  - `runtime_status.lua`, `ui_status.lua`, and `status/declarations.lua` are public lane adapters.
  - `action_buffer.lua`, `ui_actions.lua`, and `managed_module_lifecycle.lua` are commit orchestration.
  - Later systems, especially controls/widgets/shared/cache, depend on the exact object and phase semantics here.
- Impact:
  - A single cleanup patch would mix backend shape, author API, and lifecycle ordering. That raises risk and makes review harder.
- Recommendation:
  - Treat this document as the top-level audit only.
  - Split cleanup into focused passes:
    1. state backends and storage refs;
    2. status lane and status declarations;
    3. actions, reset, shared-event commit delivery, and lifecycle ordering.

### Persistent And Staged Backends Are Large But Cohesive

- Rating: leave alone
- Evidence:
  - `persistent_state.lua` owns committed root snapshots, persisted config hydration, status write/read/reset, and read-only runtime data handles.
  - `staged_state.lua` owns staged values, dirty tracking, transient state, config flush/reload, read-only status projection, and table/field handles.
  - Staged state only reaches into persistent state through `_readRoot`, `_replaceRoot`, and `_reloadFromConfig`.
- Impact:
  - The files are large, but the dependency is directional and practical: staged state needs committed status/persisted values, and persistent state owns committed normalized roots.
  - Extracting too early could create a fake abstraction with more indirection than clarity.
- Recommendation:
  - Do a focused backend/ref pass before code changes. Look for small helper extraction only where it removes repeated status/data surface checks.

### Status Is Publicly Clean But Internally Shares Storage Machinery

- Rating: leave alone
- Evidence:
  - Status declarations compile to storage roots with `mode = "runtime"` and `hash = false`.
  - `runtime.data` / `ui.data` reject status aliases.
  - `runtime.status` and `ui.status` route through dedicated adapters and diagnostics.
  - Persistent/staged internals still implement status handling because status needs the same normalization, packed child, and table behavior as storage roots.
- Impact:
  - The public mental model is now clean: `data` is UI-owned, `status` is runtime-owned.
  - The internal implementation is intentionally shared; status does not need a separate backend unless future cleanup finds repeated checks that obscure state behavior.
- Recommendation:
  - Keep status on the same storage backend for now.
  - In the status-focused pass, verify diagnostics and docs only mention `status` in live code and avoid reintroducing `runtimeOwned` language outside historical audit files.

### Read Phase Gating Has Moved To The Right Shape

- Rating: leave alone
- Evidence:
  - `storage_ref_adapter` gates writes and resets but not reads.
  - UI data writes require draw phase.
  - Runtime status writes/resets require runtime phase.
  - `ui.status` and `runtime.data` reads are object-shaped but not read-gated.
- Impact:
  - This matches the current design: API shape and variant refs prevent normal misuse, while write-side checks still catch captured-object writes.
- Recommendation:
  - Do not remove `phaseGate` in this pass.
  - Keep inventorying consumers until state refs, controls, widgets, cache, shared, and draw orchestration have all been audited.

### Actions Are Commit Orchestration, Not A State Backend

- Rating: careful cleanup
- Evidence:
  - `action_buffer.lua` owns public action slots, private/internal slots, and pending shared events.
  - `managed_module_lifecycle.lua` captures action snapshots before flush and executes them after config/mutation succeeds.
  - `ui.resetAll` clears public action/shared-event intent and queues a private status reset action.
- Impact:
  - Actions currently do more than just "button callbacks": they are the commit-time intent lane and the draw-emitted shared-event staging lane.
  - This should not be refactored while also touching persistent/staged state.
- Recommendation:
  - Audit actions/reset/shared-event commit delivery as its own focused pass.
  - Keep the future `status/task` design deferred until this pass confirms the current action lane's actual responsibilities.

### `ui.resetAll` Is Coherent But Crosses Multiple Lanes

- Rating: leave alone
- Evidence:
  - `stageResetAll` resets staged storage immediately and queues status reset through an internal action.
  - `ui.resetAll` clears public action/shared-event intent for the frame.
  - Internal status reset executes after mutation sync succeeds.
- Impact:
  - This matches the current lane model: UI reset can request a whole-module reset without exposing status reset as a public action.
  - The behavior is lifecycle-sensitive, so it should be covered by action/lifecycle tests rather than touched opportunistically.
- Recommendation:
  - Keep as-is for now.
  - Revisit in the actions/lifecycle pass only if the commit order changes.

### `stagedState.view` Looks Like Legacy Internal Surface

- Rating: safe cleanup, deferred
- Evidence:
  - Production code does not use `stagedState.view`.
  - Framework and module repos do not use it.
  - Lib tests use it heavily as a convenient assertion surface.
  - `API.md` still documents `stagedState.view` and underscore methods alongside Framework/internal plumbing.
- Impact:
  - It is not a current author-facing concept. Keeping it in prominent API docs makes the state model look broader than the actual public `ui.data` / `runtime.data` / `ui.status` / `runtime.status` model.
- Recommendation:
  - Do not remove it before a focused state-backend test cleanup.
  - In the backend/ref pass, decide whether `stagedState.view` should stay as an internal test convenience, be replaced by explicit reads in tests, or move to internal-only docs.

## Recommended Focused Passes

1. **State Backends And Refs**
   - Files:
     - `src/core/module_state/persistent/persistent_state.lua`
     - `src/core/module_state/staged/staged_state.lua`
     - `src/core/module_state/storage_ref_adapter.lua`
     - `tests/TestModuleState_PersistentState.lua`
     - `tests/TestModuleState_StagedState.lua`
   - Questions:
     - Are repeated status/data alias checks worth extracting?
     - Should `stagedState.view` remain?
     - Are underscore methods documented in the right place?

2. **Status Lane**
   - Files:
     - `src/core/status/declarations.lua`
     - `src/core/status/adapters/runtime_status.lua`
     - `src/core/status/adapters/ui_status.lua`
     - status sections in `API.md`, `DATA_LANES.md`, and `DRAW_LIFECYCLE.md`
   - Questions:
     - Are status diagnostics all current and non-historical?
     - Is `persist` explicitness documented well enough?
     - Is the runtime-write/UI-read contract clear without mentioning old runtime-owned wording?

3. **Actions, Reset, And Commit Lifecycle**
   - Files:
     - `src/core/module_state/actions/action_buffer.lua`
     - `src/core/module_state/actions/ui_actions.lua`
     - `src/core/module_bootstrap/managed_module_lifecycle.lua`
     - `src/core/module_bootstrap/managed_module.lua`
     - `src/core/module_bootstrap/ui/phase.lua`
   - Questions:
     - Are public actions, internal actions, and shared-event staging named clearly?
     - Is reset status sequencing explicit enough?
     - Does `commit.actions` still expose exactly the intended snapshot?

## Deferred Questions

- Should `stagedState.view` be retired from API docs and tests, or kept as an internal-only debugging/assertion surface?
- Should status helper logic eventually move out of persistent/staged state into a small status backend adapter, or is that indirection not worth it?
- Should action/shared-event staging remain in one buffer, or should shared events become a sibling commit queue after the action pass?
