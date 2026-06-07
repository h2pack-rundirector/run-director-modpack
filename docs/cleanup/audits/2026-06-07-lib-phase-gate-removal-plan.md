# Lib Phase Gate Removal Plan

Date: 2026-06-07

Scope:

- `adamant-ModpackLib/src/core/module_bootstrap/ui/phase_gate.lua`
- all `phaseGate` injections from `core/init.lua`
- UI/runtime data/status/cache/shared/control/action adapters
- tests and docs that assert `phase.*` diagnostics

## Direction

Retire phasing as a Lib concept.

The current API already provides the correct object for each callback:

- UI callbacks receive `ui`.
- Runtime callbacks receive `runtime`.
- Commit observers receive `commit`.
- UI controls and runtime controls are distinct refs.
- Shared events have explicit UI/runtime lanes.
- Status, cache, data, and shared state are named by ownership.

Remaining phase checks now mostly guard callback-object capture. Capturing UI or
runtime callback objects and using them later is unsupported by contract, not a
runtime behavior Lib should police on every method call.

## Current Consumer Inventory

Implementation consumers:

- `core/init.lua`
  - imports `phase_gate.lua`
  - passes it into module state, cache, controls, shared, widgets, and managed
    module bootstrap.
- `core/module_bootstrap/ui/phase.lua`
  - uses `phaseGate.runDraw(...)`.
  - uses `phaseGate.requireAnyDraw()` for `ui.resetAll(...)`.
- `core/module_bootstrap/managed_module.lua`
  - imports `ui/phase.lua` with `phaseGate`.
- `core/module_state/storage_ref_adapter.lua`
  - gates UI writes/resets and runtime status writes/resets.
- `core/module_state/staged/ui_state.lua`
  - gates `ui.data.write(...)`.
- `core/module_state/actions/action_buffer.lua`
  - gates draw action `stage/clear`.
- `core/module_state/actions/ui_actions.lua`
  - injects the gate into action refs.
- `core/status/adapters/runtime_status.lua`
  - gates `runtime.status.write/reset(...)`.
- `core/cache/adapters/data_cache.lua`
  - gates current-run cache `get/clear`.
- `core/shared/adapters/data_shared.lua`
  - gates shared read/set/clear/emit on UI/runtime surfaces.
- `core/controls/refs.lua`
  - gates UI field/table writes and `ui.controls.reset(...)`.
- `core/cache/00_init.lua`, `core/controls/00_init.lua`,
  `core/shared/00_init.lua`, `core/widgets/00_init.lua`,
  `core/module_state/00_init.lua`
  - mostly DI pass-through after adapter checks are removed.

Test consumers:

- `tests/TestPhaseGate.lua`
  - dedicated unit coverage for the phase abstraction.
- `tests/all.lua`
  - includes `TestPhaseGate`.
- `tests/TestCreateModule.lua`
  - asserts captured UI data refs fail after draw.
- `tests/TestManagedModule.lua`
  - asserts captured `ui.resetAll`, action refs, and shared refs fail after
    draw; asserts nested draw failure.
- `tests/TestControls.lua`
  - asserts captured UI control field writes fail after draw.
- `tests/TestCache.lua`
  - asserts runtime cache access fails during draw.
- widget/staged-state harness helpers
  - use `phaseGate.runDraw(...)` as a convenient draw simulator.

Policy/docs consumers:

- `core/logging/policies.lua`
  - `phase.invalid_ui_access`
  - `phase.invalid_runtime_access`
  - `phase.nested_draw`
  - `phase.invalid_leave`
- docs and cleanup audits mention draw/runtime phase gates. These should be
  updated after implementation, not before, so the historical audit record
  remains intelligible.

## Blast Radius

### Low-Risk Code Removal

These checks can be removed without changing normal module behavior:

- `runtime.status.write/reset` `requireRuntime()`
- cache `currentRun.get/clear` `requireRuntime()`
- shared read/set/clear/emit `requirePhase(...)`
- `ui.data.write(...)` direct `requireAnyDraw()`
- action ref `stage/clear` `requireAnyDraw()`
- control UI field/table/reset `requireAnyDraw()`
- storage ref adapter gate functions

Normal code receives these objects only in the right callback. Removing the
checks changes only retained/captured-object behavior.

### Medium-Risk Orchestration Removal

`phase_gate.runDraw(...)` currently also provides:

- callback result packing/unpacking.
- traceback wrapping through `xpcall`.
- active-draw enter/leave cleanup.
- nested draw rejection.

If phasing goes away, the callback runner behavior should move into
`ui/phase.lua` or a small callback-runner helper. Do not keep `phase_gate.lua`
just for `runDraw(...)`; that leaves the old concept alive under a smaller name.

### Test Churn

Expected test changes:

- delete `TestPhaseGate.lua` and remove it from `tests/all.lua`.
- remove capture-misuse assertions from:
  - `TestCreateModule`
  - `TestManagedModule`
  - `TestControls`
  - `TestCache`
- replace harness `phaseGate.runDraw(...)` helpers in:
  - `TestModuleState_StagedState`
  - `TestWidgets`
  - `TestWidgets_Nav`
  - `TestStorageValidation`
  with direct callback helpers or a non-phase callback runner.

Tests should continue to cover:

- callback object shape.
- committed vs staged data semantics.
- action/commit ordering.
- UI/runtime control ref distinction.
- declaration/activation/contact-point validation.

They should stop asserting retained callback-object failures.

## Proposed Removal Order

### Step 1: Remove Runtime-Side Gates

Remove `requireRuntime()` checks from:

- `cache/adapters/data_cache.lua`
- `status/adapters/runtime_status.lua`
- runtime branch of `shared/adapters/data_shared.lua`
- runtime storage refs through `storage_ref_adapter.lua`

This is the safest first implementation step. Runtime reads/writes are already
behind runtime object surfaces, and normal draw callbacks do not receive them.

Expected test updates:

- remove or rewrite `TestCache:testDeclaredCacheSurfacesArePhaseGated`.
- remove `phase.invalid_runtime_access` expectations.

### Step 2: Remove UI Write Gates

Remove `requireAnyDraw()` checks from:

- `storage_ref_adapter.lua`
- `staged/ui_state.lua`
- `actions/action_buffer.lua`
- `actions/ui_actions.lua`
- `controls/refs.lua`
- `ui/phase.lua` `ui.resetAll(...)`
- UI branch of `shared/adapters/data_shared.lua`

At this point callback-object capture becomes explicitly unsupported rather
than runtime-policed.

Expected test updates:

- remove captured UI ref/action/control/reset assertions.
- keep tests that exercise the same operations inside real draw callbacks.

### Step 3: Move Callback Runner Out Of `phase_gate.lua`

Replace `phaseGate.runDraw(...)` with a local callback runner owned by
`core/module_bootstrap/ui/phase.lua`.

The runner should keep:

- result preservation.
- traceback-enriched callback errors.

The runner should drop:

- active draw global state.
- nested draw production checks.
- `enterDraw/leaveDraw`.

Expected test updates:

- delete `TestPhaseGate.lua`.
- if needed, add a narrow `ui/phase.lua` test that callback errors still include
  traceback and return values are preserved.

### Step 4: Remove `phase_gate.lua` And DI Wiring

Delete:

- `core/module_bootstrap/ui/phase_gate.lua`

Remove `phaseGate` from:

- `core/init.lua`
- `module_state/00_init.lua`
- `cache/00_init.lua`
- `controls/00_init.lua`
- `shared/00_init.lua`
- `widgets/00_init.lua`
- `managed_module.lua`
- harness objects.

Remove phase policies:

- `phase.invalid_ui_access`
- `phase.invalid_runtime_access`
- `phase.nested_draw`
- `phase.invalid_leave`

### Step 5: Documentation Cleanup

Update author-facing docs from phase language to callback-scope language:

- callback objects are valid for the callback invocation that receives them.
- retaining callback objects and using them later is unsupported.
- use the object passed to the callback you are currently in.

Docs to check:

- `adamant-ModpackLib/docs/module-authors/DRAW_LIFECYCLE.md`
- `adamant-ModpackLib/docs/module-authors/DATA_LANES.md`
- `adamant-ModpackLib/docs/module-authors/MODULE_AUTHORING.md`
- `adamant-ModpackLib/docs/module-authors/GETTING_STARTED.md`
- `adamant-ModpackLib/docs/module-authors/capabilities/*`
- `adamant-ModpackLib/docs/lib-contributors/CONTROL_ERGONOMICS.md`
- cleanup strategy/audits for current-state notes.

## Recommended Implementation Shape

Do this as one focused branch/checkpoint, but not necessarily one patch:

1. Runtime-side gate removal and tests.
2. UI write gate removal and tests.
3. callback runner migration and `phase_gate.lua` deletion.
4. docs/policy cleanup.

Run after each patch:

```powershell
lua52 -e "require('tests/TestCache'); require('tests/TestControls'); require('tests/TestManagedModule'); require('tests/TestCreateModule'); local lu=require('luaunit'); os.exit(lu.LuaUnit.run())"
```

Run at the end:

```powershell
lua52 tests\all.lua
luacheck src tests
```

## Risk Assessment

Functional risk is moderate because many tests assert the old diagnostics, but
normal module runtime risk is low:

- normal modules receive the right object in the right callback.
- object-shape validation still prevents wrong control/render/data surfaces.
- declaration, activation, schema, alias, action, shared id, and lifecycle
  validations remain.

The main behavior change is deliberate: retained callback objects may now mutate
state instead of failing with `phase.invalid_*`. That is accepted as unsupported
author behavior.

## Decision Point

Before implementation, decide whether to keep a renamed callback runner helper
or inline it into `ui/phase.lua`.

Recommendation: inline it into `ui/phase.lua` unless another subsystem needs the
same xpcall/result-preservation behavior. Keeping a separate helper risks
preserving the old phase abstraction under a new name.
