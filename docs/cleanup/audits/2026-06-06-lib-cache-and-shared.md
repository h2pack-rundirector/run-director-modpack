# Lib Cache And Shared Audit

Date: 2026-06-06

Scope:

- `adamant-ModpackLib/src/core/cache`
- `adamant-ModpackLib/src/core/shared`
- shared-data/shared-event adapters
- action-buffer contact point for draw-staged shared events
- related docs and tests

Focused baseline:

- `TestCache` + `TestShared`: 28 passed, 0 failed.

## Current Shape

### Cache

Cache is now narrow and coherent:

- `module.cache.define(...)` declares module-local runtime scratch buckets.
- only `domain = "currentRun"` exists.
- runtime code accesses cache through `runtime.data.cache.currentRun`.
- draw code does not receive cache.
- current-run buckets live under one Lib-owned root on active `CurrentRun`.

The separation from status and shared is clear:

- status handles runtime-authored values that UI reads.
- shared data handles cross-module read models.
- cache handles mutable per-run scratch tied to game lifecycle.

### Shared

Shared is two related surfaces:

- shared data: declared owner/reader roles, installed during activation, read through runtime/UI shared adapters.
- shared events: declared listeners and runtime/draw emission paths.

Shared data ownership is protected by owner id plus an owner token, which makes hot reload replacement safe. Reads return fallback when no active owner is published or when the owner module is disabled. Table values are copied on write and exposed through recursive read-only proxies.

Shared events are installed as activation receipts and delivered through a global queue. Disabled emitters return zero deliveries. Disabled listeners are skipped. Nested emits are queued behind the current delivery. Listener failures log and continue.

## Findings

### Cache Surface Is Lean And Cohesive

- Rating: leave alone
- Evidence:
  - `current_run_cache.lua` owns current-run table bucket behavior.
  - `adapters/data_cache.lua` is a thin runtime data adapter.
  - `definition.lua` accepts only `domain = "currentRun"`.
  - docs consistently point runtime/UI bridge use cases to status, and cross-module use cases to shared.
- Impact:
  - The subsystem has a clear lifecycle owner and does not overlap with data/status/shared in current code.
- Recommendation:
  - No cleanup selected.

### Shared Data Activation Commit Is Not Fully Atomic

- Rating: careful cleanup, completed
- Evidence:
  - `shared/data.lua` commits owner declarations by looping entries and writing `records[entry.id]` one at a time.
  - duplicate-publisher validation happens inside the same loop, immediately before each write.
  - `shared/adapters/module_install.lua` only marks `committedData = true` after `dataReceipt.commit()` returns successfully.
  - if a module declares multiple shared owners, an early unique owner can be written, then a later duplicate owner can throw before the receipt is marked committed.
- Failure scenario:
  - Module B declares two shared owners: `B.Unique` and `A.Existing`.
  - `B.Unique` is written into the shared registry.
  - `A.Existing` conflicts with Module A and activation fails.
  - activation rollback calls the shared receipt dispose path, but `committedData` is still false because commit did not return.
  - `B.Unique` can remain as an orphaned shared record from a failed activation.
- Impact:
  - The orphaned record is likely invisible because its `isEnabled` callback cannot find an active record, but it can still block a later legitimate publisher with `shared.duplicate_publisher`.
  - This is an activation transaction bug, not an author-facing API issue.
- Recommendation:
  - Completed: made shared-data install two-phase:
    - first validate all owner declarations and capture previous records;
    - then mutate `records`.
  - Added a regression test where a multi-owner shared-data activation fails on a later duplicate and verifies the earlier unique id does not block a later legitimate publisher.

### Shared Event Emission Lanes Were Ambiguous

- Rating: careful cleanup, completed
- Evidence:
  - draw callbacks receive the unphased `host`.
  - the old `host.shared.emit(...)` path called `shared.emitForModule(...)` immediately.
  - the old `ui.actions.emit(...)` path queued the event into the action buffer and delivered it during commit.
  - docs told authors not to emit directly from draw with `host.shared.emit(...)`.
- Impact:
  - Direct draw-time `host.shared.emit(...)` could deliver listeners while draw phase was active.
  - The event surface was split between host and actions even though shared events are not module actions.
- Recommendation:
  - Completed: removed `host.shared.emit(...)`, `module.shared.emit(...)`, and `ui.actions.emit(...)`.
  - Runtime/non-draw code emits with `runtime.shared.emit(...)`.
  - Draw code queues commit-staged shared events with `ui.shared.emit(...)`.
  - Added/updated regression coverage for runtime delivery, draw-staged delivery, disabled emitters/listeners, invalid emit input, and the closed action/author surfaces.

### Shared Event Intent In `action_buffer.lua` Is Acceptable For Now

- Rating: leave alone for now
- Evidence:
  - `ui.shared.emit(...)` stages shared-event intent in the same buffer as draw actions.
  - `actionBuffer.hasAny()` correctly treats emit-only draws as commit-worthy.
  - `finishSuccessfulCommit(...)` now makes the commit tail order explicit.
- Impact:
  - The file name `action_buffer.lua` is narrower than its behavior, but the behavior is conceptually "draw commit intent", and shared events emitted from draw are part of that lane.
- Recommendation:
  - Do not split shared-event staging yet.
  - If this keeps reading awkwardly during the managed-module/bootstrap audit, consider a narrow rename from action buffer to commit intent buffer.

### Draw-Staged Shared Emit Validation Belonged At The Staging Boundary

- Rating: safe cleanup, completed
- Evidence:
  - `ui.shared.emit(...)` staged shared-event intent into `action_buffer.lua`.
  - shared id/event-name validation happened only later when the commit tail flushed the staged event through the shared event service.
- Impact:
  - invalid draw-side shared emits could fail after draw, which made diagnostics point at commit rather than the author call site.
  - this also meant invalid events briefly entered the pending intent buffer.
- Recommendation:
  - Completed: shared event validation is exposed by the shared event service and called by the draw shared adapter before staging into the action buffer.
  - Added regression coverage that invalid `ui.shared.emit(...)` inputs fail inside the draw callback.

### UI Shared Emit Return Contract Needed To Be Narrower

- Rating: documentation cleanup, completed
- Evidence:
  - runtime shared emits deliver immediately and can return a listener delivery count.
  - UI shared emits only stage intent for the commit tail, so no delivery count exists at the draw call site.
- Impact:
  - the shared type/docs could imply `ui.shared.emit(...)` returns the same count as `runtime.shared.emit(...)`.
- Recommendation:
  - Completed: docs and type annotations now distinguish `runtime.shared.emit(...)` as `true, deliveredCount` from `ui.shared.emit(...)` as `true` after staging.

### Draw Shared-Data Writes Are Immediate

- Rating: documentation cleanup, completed
- Evidence:
  - `ui.shared.set(...)` and `ui.data.shared.set(...)` write directly to the shared-data registry during draw.
  - unlike `ui.data.write(...)`, these writes are not staged and do not wait for `commitIfDirty()`.
  - current module usage publishes shared data from runtime, but tests cover draw writes.
- Impact:
  - The behavior is useful for cross-module read models, but it is a different lifecycle lane from normal UI-owned settings.
  - Current docs imply shared event delivery timing clearly, but shared-data write timing could be more explicit.
- Recommendation:
  - Completed: shared/data-lane/draw-lifecycle/API docs now state that shared-data writes publish immediately, do not make the module dirty, do not wait for commit, and are not rolled back by later commit failures.
  - Behavior remains unchanged because shared data is a publication lane, not staged config storage.

## Suggested Cleanup Order

1. Completed: standardize shared events on `runtime.shared.emit(...)` and `ui.shared.emit(...)`.
2. Completed: document immediate shared-data write timing.
3. Completed: validate draw-staged shared emits before they enter the pending intent buffer.
4. Completed: document the different runtime/UI shared emit return contracts.
5. Leave action-buffer/shared-event staging in place unless later bootstrap audit still finds the name misleading.
