# Lib Actions, Reset, And Commit Lifecycle Audit

## Purpose

Actions/reset/commit lifecycle owns draw-time UI intent, module-wide reset staging, commit-time side effects, shared-event delivery, and post-commit observers.

## Surfaces

- Author:
  - `module.actions.define(...)`
  - `ui.actions.get/trigger`
  - draw action refs: `stage/read/clear/has`
  - `ui.resetAll(opts?)`
  - `module.onCommit(function(host, runtime, commit) ...)`
  - `commit.actions.get/hasAny`
- Framework/module:
  - live module `commitIfDirty`, `flush`, `writeAndFlush`, `resetAll`, `setEnabled`, `setDebugMode`
  - pack suspend/restore helpers route through the same commit lifecycle
- Internal:
  - `src/core/module_state/actions/action_buffer.lua`
  - `src/core/module_state/actions/ui_actions.lua`
  - `src/core/module_bootstrap/managed_module_lifecycle.lua`
  - reset wiring in `src/core/module_bootstrap/managed_module.lua`
  - UI phase wiring in `src/core/module_bootstrap/ui/phase.lua`
- Tests-only:
  - direct action buffer and commit action refs through module-state harnesses.
  - managed module tests that exercise draw, commit, mutation, shared events, reset, and commit observers.

## Call Graph

- `module.actions.define(...)` stores action declarations.
- definition preparation validates action keys/handlers and creates deterministic `_actionOrder`.
- `managed_module.lua` creates one action buffer per managed module.
- `ui_actions.lua` turns the buffer into draw-phase refs and helpers.
- widgets consume draw action refs through the action-ref marker helper.
- `managed_module_lifecycle.lua` captures action snapshots, flushes staged state, syncs mutation, executes actions/internal actions/shared events, clears the buffer, and notifies commit observers.

## State Ownership

- Owns:
  - one-commit public action slots.
  - one-commit internal action slots.
  - one-commit pending shared events staged by `ui.shared.emit(...)`.
- Reads:
  - staged action snapshots for commit observers.
  - persistent/staged state dirtiness and mutation effective state.
- Writes:
  - action handlers may write `runtime.status`.
  - `ui.resetAll` stages UI-owned reset immediately and queues internal status reset.
  - shared event flush calls the internal shared emitter after action handlers.

## Lifecycle

- Declaration:
  - public action keys must be stable identifiers and cannot start with `_`.
  - Lib internal actions are injected as private `_` keys.
  - action execution order is deterministic by sorted key order after internal action injection.
- UI draw:
  - `ui.actions.get(...):stage/clear` and `ui.actions.trigger` require draw phase.
  - refs can be read outside draw, but mutation methods remain gated.
  - `ui.resetAll(...)` requires draw phase.
- Commit:
  - action and internal snapshots are captured before staged storage flush.
  - staged storage flushes to config first.
  - mutation apply/revert runs if committed UI-owned settings changed and the module affects run data.
  - public action handlers run after successful mutation sync.
  - internal reset/status actions run after public actions.
  - shared events flush after actions/internal actions.
  - action/shared buffers clear before `onCommit`.
  - `onCommit` receives the captured public action snapshot.
- Runtime:
  - action handlers receive `(host, runtime, value)` and read committed data.
  - action handlers may write status.
- Reload:
  - module reload clears action/shared intent buffers.
- Teardown:
  - action buffers own no external receipts.

## Findings

### Commit Ordering Is Coherent And Well Covered

- Rating: leave alone
- Evidence:
  - `managed_module_lifecycle.lua` implements the documented order: flush staged state, sync mutation, run public actions, run internal actions, flush shared events, clear buffer, then `onCommit`.
  - `TestManagedModule` covers actions seeing committed data, actions after mutation, failed mutation preventing action execution, emit delivery after actions, emit-only commits, and `ui.resetAll` clearing public actions/events while preserving status reset.
  - `DRAW_LIFECYCLE.md` documents this order in the draw commit cycle.
- Impact:
  - The core lifecycle now matches the lane model: UI intent is captured during draw, then side effects run only after the committed data state is stable.
- Recommendation:
  - Keep the ordering.
  - Avoid changing action/shared/reset sequencing opportunistically during unrelated cleanups.

### Post-Commit Side Effects Are Best-Effort But Not Explicitly Documented

- Rating: safe cleanup, completed
- Evidence:
  - action handler, internal action handler, shared-event flush, and `onCommit` errors are caught and logged with `lifecycle.on_commit_failed`.
  - these failures do not roll back already-flushed config or mutation state.
  - public docs describe ordering, but do not clearly state that post-commit side-effect failures are best-effort logging after config/mutation success.
- Impact:
  - The behavior is reasonable: once config/mutation succeeds, action/shared/onCommit are side effects, not rollback boundaries.
  - Authors reading lifecycle docs may assume a failed action aborts commit, which is not current behavior.
- Recommendation:
  - Completed: `DRAW_LIFECYCLE.md` and `API.md` now state that action handlers, shared-event delivery, and commit observers are post-commit side effects whose failures are logged rather than config rollback boundaries.
  - Do not change runtime behavior unless there is a separate design pass on side-effect failure policy.

### Action Buffer Has Dead Or Over-Broad Internal Surface

- Rating: safe cleanup, completed
- Evidence:
  - `actionBuffer.getRef(...)` is not used by production callers; public refs are created through `ui_actions.create(...)`.
  - `createInternalDrawActionRef(...)` is exported but unused.
  - `createActionCatalog`, `validateDeclaredAction`, and `isPrivateActionKey` are exported but not used outside `action_buffer.lua`.
  - `module_state/00_init.lua` still documents `ActionBuffer.getRef`.
- Impact:
  - The current live path is cleaner than the exported surface suggests.
  - The unused ungated `buffer.getRef(...)` is especially misleading because public draw refs are supposed to be phase-gated through `ui_actions`.
- Recommendation:
  - Completed: unused action-buffer exports and `buffer.getRef(...)` were removed.
  - Keep the exports that are actively used:
    - `createBuffer`
    - `createCommitActions`
    - `createGatedDrawActionRef`
    - `isDrawActionRef`

### Controls Receive An Unused Action-Refs Dependency

- Rating: safe cleanup, completed
- Evidence:
  - `core/init.lua` passes `actionRefs = moduleState.actionBuffer` into `core/controls/00_init.lua`.
  - current controls files do not read `deps.actionRefs`.
- Impact:
  - This is minor DI residue from earlier controls/action design exploration.
- Recommendation:
  - Completed: removed the unused dependency from `core/init.lua`.

### Successful Commit Tail Is Duplicated

- Rating: careful cleanup, completed
- Evidence:
  - `commitStagedState(...)` has one branch for "no mutation sync needed" and one branch for "mutation sync succeeded".
  - both branches run the same sequence:
    - execute public actions
    - execute internal actions
    - flush shared events
    - clear action buffer
    - notify commit observer
- Impact:
  - The duplication is behavior-preserving today, but future ordering changes must be made in two places.
  - This is lifecycle-sensitive, so cleanup should be small and covered by the existing managed module tests.
- Recommendation:
  - Completed: extracted local `finishSuccessfulCommit(...)` helper in `managed_module_lifecycle.lua`.
  - Verified with `TestManagedModule` and the full Lib suite.

### Action Buffer Also Owns Shared Event Intent

- Rating: leave alone for now
- Evidence:
  - `ui.shared.emit(...)` stores pending shared events in `action_buffer.lua`.
  - `actionBuffer.hasAny()` includes public actions, internal actions, and pending events so emit-only commits still run.
  - tests cover emit-only commits.
- Impact:
  - The file name is narrower than the behavior, but the buffer now represents broader draw commit intent.
  - Splitting shared events out before the shared subsystem audit would add churn without a clearer owner yet.
- Recommendation:
  - Leave the behavior in place.
  - Revisit naming or extraction during the shared-events audit if the combined buffer keeps obscuring responsibilities.

### Framework Draw Lifecycle Was Sequenced At The Call Site

- Rating: careful cleanup, completed
- Evidence:
  - fallback UI previously called `drawTab()` and then `commitIfDirty()` directly.
  - the actual draw lifecycle order was correct, but spread across the caller.
- Impact:
  - Future lifecycle reordering would require callers to know the correct draw/commit sequence.
  - This is infrastructure-sensitive because Framework owns normal draw timing.
- Recommendation:
  - Completed: added live-module draw-and-commit lifecycle entry points and switched fallback UI to `drawTabAndCommit()`.
  - Kept `drawTab()` and `commitIfDirty()` as lower-level primitives for tests and explicit infrastructure work.
  - Verified with focused fallback/managed-module tests and the full Lib suite.

## Deferred Questions

- Should action handlers remain best-effort forever, or should a future design allow action failure to block later side effects while still not rolling back config?
- Should `action_buffer.lua` be renamed later to something broader like commit intent buffer, or is the public `ui.actions` name enough?
- Should shared-event staging eventually live beside shared-event declarations instead of inside action buffering?
