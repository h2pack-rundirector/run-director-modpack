# Y Ownership Implementation Plan

## Purpose

This is the working implementation plan for bringing explicit `Y` ownership into the live Lib layout substrate.

It is meant to sit between:
- the conceptual north star in `Support/y_ownership_north_star.md`
- the actual live code in `adamant-ModpackLib/src/field_registry`

This file should be updated as work progresses:
- what was completed
- what changed from the original plan
- what challenges surfaced
- what follow-up steps were added or removed

---

## Current Assessment Of The Live Surface

This initial phase is now complete.

Completed in code:
- `DrawWidgetSlots(...)` owns row `Y` explicitly
- `panel.render` owns row settlement explicitly
- radio-family widgets now use the structured slot renderer
- `verticalTabs` no longer relies on ambient `SameLine()` split flow
- a shared internal structured child runner now codifies the start/end cursor contract

Completed in docs:
- `line` remains the public vertical placement surface
- raw `y` is internal only
- structured child start/end settlement contract is documented
- leaf-widget rule is documented

The remaining work is now follow-up refinement rather than unfinished foundation.

The original structural weak points were:

- `DrawWidgetSlots(...)` in `src/field_registry/shared.lua`
  - owns `X`
  - still relies on `SameLine()` / `NewLine()` for row flow
- `LayoutTypes.panel.render` in `src/field_registry/layouts.lua`
  - resolves rows and ordering
  - but still depends on implicit cursor `Y` and estimated row advance
- nested structured rendering remains brittle because parent layouts do not fully own row baseline and final cursor settlement

The current author-facing `line` model is acceptable and should be preserved initially.

The main goal is not to expose raw `y` coordinates immediately.
The goal is to make the engine resolve `line` into explicit row origins and explicit cursor settlement.

---

## Step 1. Add positioned structured-render helpers

### Target
- `adamant-ModpackLib/src/field_registry/shared.lua`

### Goal
Add small internal helpers for structured positioned rendering, built around:
- `SetCursorPos(x, y)`
- local row origin tracking
- post-draw footprint measurement

### Why
The current engine already pays for explicit `X` placement.
Moving to explicit `Y` should use the existing single-call cursor positioning primitive instead of separate `X` and `Y` calls.

### Status
- completed

### Notes
- prefer `SetCursorPos(x, y)` over separate `SetCursorPosX/Y`
- keep helpers internal first

---

## Step 2. Refactor `DrawWidgetSlots(...)` to own rows explicitly

### Target
- `adamant-ModpackLib/src/field_registry/shared.lua`

### Goal
Replace slot row flow based on:
- `SameLine()`
- `NewLine()`

with a model based on:
- explicit row origin `x,y`
- per-slot `SetCursorPos(x, y)`
- measured row max height
- explicit row settlement

### Why
This is the first real point where Lib can stop inheriting implicit `Y` movement from ImGui for structured slot rendering.

### Status
- completed (first pass)

### Expected challenges
- preserving current slot ordering and compatibility with `line`
- ensuring width/alignment behavior still works cleanly
- deciding how slot-local immediate mode affects measured row height

### Notes
- first pass now uses explicit `SetCursorPos(x, y)` for slot rows
- `Y` is owned explicitly per row
- `X` remains absolute only for slots with explicit `start`
- slots without explicit `start` still use existing inline flow for `X`
  - this was necessary to avoid breaking widgets that rely on same-row flow without absolute horizontal geometry

---

## Step 3. Refactor `panel.render` to own rows explicitly

### Target
- `adamant-ModpackLib/src/field_registry/layouts.lua`

### Goal
Stop using:
- `SameLine()`
- implicit cursor `Y`
- estimated row advance as the primary settlement mechanism

Move to:
- explicit panel origin
- explicit row baseline/origin
- explicit child `x,y` placement
- measured row height
- explicit final panel cursor settlement

### Why
`panel` is the central structured layout primitive.
If it does not own `Y`, the declarative tree is still only partially grounded.

### Status
- completed (first pass)

### Expected challenges
- mixed child types inside rows
- nested panel/group/tab interactions
- deciding whether invisible children affect row structure

### Notes
- `panel.render` now follows the same row-baseline model as `DrawWidgetSlots(...)`
- rows are settled through explicit cursor placement rather than `SameLine()` plus estimated vertical carry
- panel still preserves inline `X` flow for children without explicit `start`

---

## Step 4. Add a child footprint settlement contract

### Targets
- `adamant-ModpackLib/src/field_registry/ui.lua`
- `adamant-ModpackLib/src/field_registry/layouts.lua`
- `adamant-ModpackLib/src/field_registry/shared.lua`

### Goal
Allow parent structured layouts to know how much vertical space a child consumed without introducing a generic pre-measurement system.

Settled contract:
- parent/layout assigns the child start position
- child must begin drawing from that assigned start
- child must leave the cursor at the bottom of the space it consumed
- parent uses that settled end position as the child's footprint signal

This may remain internal at first.

### Why
Without a clear footprint settlement rule, parent layouts still cannot own row advancement deterministically.

### Status
- completed (first pass)

### Expected challenges
- deciding whether cursor-delta settlement is sufficient long term or whether some internal explicit height return is eventually needed
- keeping the public draw API stable while improving internal measurement
- documenting the difference between:
  - parent-owned placement
  - widget-owned overflow policy

### Notes
- the implementation relies on cursor delta as the footprint signal
- the contract is now explicit in both code and docs:
  - Lib owns child start position
  - structured child owns honest cursor settlement at end
- no explicit child height return shape has been introduced
- a shared internal helper exists for this pattern:
  - `DrawStructuredAt(imgui, startX, startY, fallbackHeight, drawFn)`
- normal render path remains assertion-free
  - misbehaving children are expected to show visible layout breakage
  - any future diagnostics should be opt-in, not hot-path default

---

## Step 5. Preserve the author-facing `line` model initially

### Targets
- `adamant-ModpackLib/src/field_registry/shared.lua`
- `adamant-ModpackLib/src/field_registry/layouts.lua`

### Goal
Do not require authors to rewrite geometry around raw `y`.

Keep:
- `line`

Change internally:
- resolve `line` to explicit row origin `y`

### Why
This reduces migration risk and keeps the public surface stable while the renderer is improved underneath.

### Status
- completed

### Notes
- `line` remains the public vertical descriptor
- raw `y` is still internal plumbing
- public `start` remains horizontal-only

---

## Step 6. Leave tab layouts mostly alone in the first pass

### Target
- `adamant-ModpackLib/src/field_registry/layouts.lua`

### Goal
Avoid unnecessary churn in layouts that are already using stronger ImGui container primitives.

### Why
Slots and panels were the main weak substrate under the original structured system.

### Status
- completed with one deliberate deviation

### Notes
- `horizontalTabs` was intentionally left alone
- `verticalTabs` was also refactored because it remained the one structural outlier after slots/panels were fixed

---

## Step 7. Update docs and authoring rules after behavior is settled

### Targets
- `adamant-ModpackLib/API.md`
- `adamant-ModpackLib/FIELD_REGISTRY.md`
- `adamant-ModpackLib/MODULE_AUTHORING.md`

### Goal
Document the final structured-render boundary and the leaf-widget rule after the renderer changes are in place.

### Why
The correct authoring guidance depends on the final implementation shape, especially around:
- nested rendering
- row ownership
- what remains safe inside custom widgets

### Status
- completed

### Notes
- the docs now describe:
  - prepared-node expectation for draw
  - `line` as the public vertical surface
  - raw `y` as internal only
  - structured child start/end settlement
  - leaf-widget rule

---

## Result Of The Initial Phase

The first-pass Y-ownership foundation is complete.

Delivered:
- explicit internal row `Y` ownership for slots
- explicit internal row `Y` ownership for `panel`
- radio-family alignment with the structured renderer
- explicit pane positioning for `verticalTabs`
- a documented structured child footprint contract
- a documented leaf-widget rule

Deferred deliberately:
- full absolute `X` ownership
- public raw `y` geometry
- hot-path assertions or debug instrumentation
- explicit child height return values

## Regression Follow-Up

The post-implementation shakeout already surfaced a few real integration issues:

- `forceRarityStatus` custom widget needed:
  - the correct custom-widget `draw(...)` signature
  - local `PushID(...)` / `PopID()` around repeated `-` / `+` controls
- Framework special tabs needed to forward:
  - `BeforeDrawQuickContent`
  - `AfterDrawQuickContent`
  - `BeforeDrawTab`
  - `AfterDrawTab`
  so derived-text and post-draw reactions run in coordinator paths as well as standalone paths
- BoonBans needed to export those hook functions on `public`, not only keep them on `internal`

Current conclusion:
- the first-pass Y-ownership work is structurally complete
- the next immediate work is in-game regression testing and bug fixing
- future `X`/`Y` symmetry should wait until this stabilization pass is finished

## Original Working Order

Recommended implementation order:

1. add positioned helpers in `shared.lua`
2. refactor `DrawWidgetSlots(...)`
3. refactor `panel.render`
4. add/settle footprint reporting
5. update docs

---

## Change Log

Use this section to record actual progress during implementation.

### Completed
- Step 1 completed for slot rendering primitives in `shared.lua`
- Step 2 partially completed:
  - `DrawWidgetSlots(...)` now owns row `Y` explicitly
  - slot rows are settled with explicit cursor placement instead of `NewLine()`-driven advancement
  - Lib test suite passes after this change
- Step 3 completed (first pass):
  - `panel.render` now owns row `Y` explicitly
  - panel rows are settled with explicit cursor placement
  - Lib test suite passes after this change
- Step 4 partially completed:
  - slots and panels now use a shared structured child runner
  - parent-assigned start and cursor-settled end are now explicit in code
  - no hot-path assertions were added
- radio-family follow-up completed:
  - `radio` no longer adds an extra trailing `NewLine()`
  - `mappedRadio` now renders through the slot renderer instead of hand-managed `SameLine()` / `NewLine()`
  - `packedRadio` now renders through the slot renderer instead of hand-managed `SameLine()` / `NewLine()`
  - Lib test suite passes after this change
- `verticalTabs` follow-up completed:
  - split panes are now positioned explicitly from a captured origin
  - `verticalTabs` no longer depends on ambient `SameLine()` for the sidebar/detail split
  - final cursor settlement is explicit
  - Lib test suite passes after this change

### Challenges discovered
- slot rendering cannot become fully absolute on both axes in one pass because some existing slot definitions rely on inline `X` flow when `start` is omitted
- this means the safe incremental path is:
  - explicit `Y` ownership first
  - preserve inline `X` flow for non-positioned slots
  - revisit fuller `X` ownership only if later cleanup justifies it
- panel rendering has the same constraint:
  - explicit `Y` ownership is safe now
  - full `X` ownership still depends on whether child placement without explicit `start` should remain flow-based long term
- the real contract question is not generic pre-measurement
  - it is whether structured children can be required to begin at the assigned start and settle their cursor honestly at the consumed end

### Follow-up questions
- whether the final documentation should keep this as an internal renderer contract only, or expose it more directly in authoring guidance for custom layouts/widgets
