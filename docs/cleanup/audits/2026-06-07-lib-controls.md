# Lib Controls Audit

Date: 2026-06-07

Scope:

- `adamant-ModpackLib/src/core/controls`
- declaration wiring through `module.controls.*`
- activation-time control compilation
- runtime/UI control refs
- `ui.draw.control(...)` dispatch
- related tests, docs, and diagnostics

## Purpose

Controls are module-declared composite leaf objects that compile module-owned
templates into private Lib storage plus phase-specific UI/runtime refs.

## Surfaces

- Author:
  - `module.controls.defineTemplates(templates)`
  - `module.controls.define(instances)`
  - `runtime.controls.get/read`
  - `ui.controls.get/read/reset`
  - `ui.draw.control(control, viewName?, ...)`
- Module/bootstrap:
  - `controls.declarations`
  - `controls.compiler.compile(...)`
  - `controls.refs.createRuntime(...)`
  - `controls.refs.createUi(...)`
  - `controls.draw.render(...)`
- Internal:
  - generated private storage aliases shaped as `_Control:Field[:Child]`
  - compiled control catalog passed into managed modules
  - control ref marker stored on returned refs
- Tests-only:
  - `tests/TestControls.lua` local templates that exercise scalar, table,
    transient, packed, draw-view, reset, and invalid declaration behavior.

## Call Graph

- Declaration:
  - `module/declaration_surface.lua` writes templates and instances into a
    control declaration bucket while the declaration lifecycle is open.
- Activation:
  - `module/activation_finalizer.lua` calls `controlCompiler.compile(...)`.
  - compiled storage is merged into internal storage before definition
    preparation and module-state creation.
  - compiled catalog is passed to `managed_module.create(...)`.
- Runtime/UI:
  - `managed_module.lua` creates `runtime.controls` from persistent state and
    `ui.controls` from staged state.
  - `widgets/ui_draw.lua` forwards `ui.draw.control(...)` to
    `controls.draw.render(...)`.

Dependency direction is clean: controls depend on logging, values, storage refs,
and phase-gate write checks. Module bootstrap depends on controls only at
declaration/activation/ref-construction boundaries.

## State Ownership

- Owns:
  - generated private setting storage declared by control templates.
- Reads:
  - persistent committed setting refs for runtime controls.
  - staged setting refs for UI controls.
- Writes:
  - UI controls can write/reset generated staged fields and table rows.
  - runtime controls are read-only.

Controls intentionally do not own status, cache, shared state, or actions.
`mode = "runtime"` in control storage is rejected and authors should declare
status at module level.

## Lifecycle

- Declaration:
  - templates and instances are accepted before activation only.
  - names are stable identifiers.
- Activation:
  - templates are resolved, instances are prepared, storage is compiled, and
    private aliases enter the normal storage validator.
- UI draw:
  - `ui.controls.get(...)` returns cached UI refs.
  - field/table reads are phase-neutral.
  - generated writes, table mutations, and `ui.controls.reset(...)` require
    draw phase.
  - `ui.draw.control(...)` dispatches a named template view.
- Commit:
  - control storage flushes through the same staged-state path as normal UI
    settings.
- Runtime:
  - `runtime.controls.get/read` exposes cached runtime refs over persistent
    setting storage.
  - non-persisted UI-only control fields are unavailable on runtime refs and
    fail with `controls.unavailable_field`.
- Reload:
  - controls inherit staged/persistent reload behavior from module state.
- Teardown:
  - controls have no independent receipts; their state is part of module state.

## Findings

### Controls Earn Their Current Surface

- Rating: leave alone
- Evidence:
  - `compiler.lua` is the only lowering point from templates/instances to
    private storage and catalog entries.
  - `refs.lua` is the only phase-specific object-ref builder.
  - `draw_controls.lua` is a minimal dispatch layer.
  - tests cover private alias rejection, semantic aliases, table controls,
    UI-only fields, draw views, reset, caching, and status rejection.
- Impact:
  - The subsystem is small and each file has a clear responsibility.
  - The recent status/data/shared cleanup did not leave broad compatibility
    bridges inside controls.
- Recommendation:
  - Keep the subsystem shape.
  - Cleanup should stay focused on validation, diagnostics, and docs.

### Template `prepare(...)` Return Validation Is Too Loose

- Rating: safe cleanup, completed
- Evidence:
  - `compiler.lua` calls `template.prepare(instance)` and only checks for nil.
  - a non-table return is assigned to `instance`, then `instance.name` is read.
- Failure scenario:
  - A template accidentally returns a string or boolean.
  - activation fails with a raw Lua indexing error instead of a
    `controls.invalid_declaration` or `controls.invalid_template` diagnostic.
- Impact:
  - This is an author-contact-point validation gap.
- Recommendation:
  - Completed: `prepare(...)` non-table returns now fail with a
    `controls.invalid_declaration` diagnostic.
  - Added a focused regression test.

### Draw Dispatch Accepts Runtime Control Refs

- Rating: careful cleanup, completed
- Evidence:
  - `refs.lua` stores only the catalog entry in `CONTROL_REF_MARKER`.
  - `draw_controls.lua` checks that the argument is a Lib-created control ref,
    but not that it came from `ui.controls`.
  - runtime refs and UI refs share the same marker shape.
- Failure scenario:
  - author code captures a runtime control ref and passes it to
    `ui.draw.control(...)`.
  - the render dispatch accepts it, then the template may fail later because
    UI-only methods/fields are missing.
- Impact:
  - Normal author flow does not expose runtime controls during draw, so this is
    mostly capture misuse.
  - Still, it weakens the current variant-object model: draw rendering should
    require a UI control ref, not merely any control ref.
- Recommendation:
  - Completed: ref marker metadata now records the control phase.
  - Completed: `ui.draw.control(...)` rejects non-UI control refs with
    `controls.invalid_render_target`.
  - Added a regression test that runtime refs cannot be rendered.

### Controls Docs Have Small Signature And Diagnostic Residue

- Rating: safe cleanup, completed
- Evidence:
  - `API.md` still shows `ui.draw.control(ui.controls.get("Priority"),
    { view = "compact" })`, but the current API is
    `ui.draw.control(control, viewName, ...)`.
  - `src/def.lua` types `ControlDrawCallback` with a single `opts: table`
    argument, but templates may receive arbitrary positional view arguments.
  - `controls.duplicate_name` policy text mentions "command names", which is
    residue from the abandoned control-action direction.
- Impact:
  - Docs and annotations can teach the wrong draw dispatch shape.
  - The policy wording is harmless at runtime but stale.
- Recommendation:
  - Completed: updated the `API.md` example.
  - Completed: relaxed the `ControlDrawCallback` annotation to positional view
    args.
  - Completed: removed "command names" from the controls duplicate-name policy
    text.

### Control Phase Checks Are Currently At The Right Layer

- Rating: leave alone for now
- Evidence:
  - control reads are phase-neutral.
  - generated field/table writes and `ui.controls.reset(...)` are gated.
  - runtime controls are read-only by construction.
  - non-persisted UI-only fields are absent from runtime refs and fail loudly
    when touched.
- Impact:
  - Controls align with the current variant-object policy: object shape carries
    most access rules, with cheap write-side capture protection still present.
- Recommendation:
  - Do not remove controls phase-gate use in this pass.
  - Keep `phaseGate` as a cross-cutting inventory item until widgets and
    managed-module draw orchestration are audited.

## Suggested Cleanup Order

1. Completed: fix `prepare(...)` return validation and add the regression test.
2. Completed: tighten `ui.draw.control(...)` to accept only UI control refs
   and add the regression test.
3. Completed: clean docs/types/policy wording for draw view dispatch and
   duplicate-name diagnostics.

## Deferred Questions

- If more control templates start consuming actions through view args, revisit
  whether controls need a first-class action-binding helper. This is not needed
  now.
