# Roadmap: Stable Static Foundation

## Status

This is a transition roadmap and execution record, not the current API contract.

Use this document for:
- what was actually changed to get back to a stable static base
- which architectural decisions were made during the rollback/consolidation
- what still remains before Lib can be called structurally settled again

Do not use this as the source of truth for current live API behavior.
Current behavior lives in:
- `adamant-ModpackLib/API.md`
- `adamant-ModpackLib/MODULE_AUTHORING.md`
- the current code on `main`

This document is expected to be deleted once:
- BoonBans is fully stabilized
- the remaining Lib follow-up work is either completed or explicitly deferred

---

## Goal

Re-establish a stable static UI foundation on `main` with:
- no half-built dynamic runtime/planner infrastructure in the live Lib surface
- honest boundaries between layouts, widgets, and custom widget leaf behavior
- BoonBans running cleanly as a special module with static structure for its static pieces
- a clear path for future Lib evolution without reviving the old middle ground

The intended end state is:
- static tree structure on main
- controlled transient UI state where needed
- small explicit Lib helpers for recurring patterns
- dynamic/systemic work deferred to a separate future effort

---

## What Was Completed

## 1. Dynamic and planner-era middle ground was removed from main

### Lib

Completed:
- removed planner/runtime geometry direction from the active Lib model
- `dynamicText` was removed from the live mainline surface
- the static contract is now:
  - prepared nodes
  - declarative layouts/widgets
  - widget-local behavior from declared binds
  - explicit custom widget leaf behavior where a real static primitive does not fit

Direction confirmed:
- main no longer carries the half-built runtime geometry/planner middle ground
- future dynamic work belongs on a separate path, not as residual surface on `main`

### BoonBans

Completed:
- old planner-style communication patterns were removed from active UI code
- ban panel geometry planning/runtime overrides are gone
- the ban list now sits on the packed-list model instead of custom runtime geometry

---

## 2. Lib widget surface was expanded where the static model needed it

The rollback did not stop at deletion. Several static primitives were added or clarified so BoonBans could stay mostly declarative.

Completed in Lib:
- `confirmButton` fixed and adopted as the standard danger action primitive
- `stepper.displayValues`
- `stepper.valueColors`
- `packedCheckboxList` optional filtering support
  - `filterText`
  - `filterMode`
- text coloring support
- tab label coloring support
- optional active tab binding on:
  - `horizontalTabs`
  - `verticalTabs`
- optional `panel.id`
  - explicit `PushID` / `PopID` scope only when requested

Architectural result:
- several BoonBans custom widgets were removed because the static Lib surface became capable enough
- the Lib surface is smaller in concept than the planner/dynamic branch, but materially stronger for the static model

---

## 3. Derived display text was standardized without reopening dynamic widgets

One real gap remained after removing `dynamicText`: modules still needed a safe way to maintain transient display text derived from state.

Completed:
- BoonBans first implemented a lightweight local derived-text refresh pass
- that pattern was then moved into Lib as:
  - `lib.runDerivedText(uiState, entries, cache?)`

Current contract:
- string-only by design
- entry fields:
  - `alias`
  - `compute(uiState)`
  - optional `signature(uiState)`
- writes only when the text changed

Important boundary decision:
- this helper is intentionally for derived display text only
- it is not generic derived state
- it is not a reactive subsystem
- non-text structural state remains module-local unless repeated demand justifies another helper

This was used to replace the former BoonBans `dynamicText` call sites:
- ban summary text
- ban empty-state text
- Bridal Glow current-target text

---

## 4. BoonBans UI structure was converted into a mostly declarative tree

This was the largest practical cleanup phase.

Completed:
- top-level main tabs now use real node children instead of the old `mainTabContent` adapter widget
- domain shells were panelized/declarativized
- `Settings` is now a direct declarative panel
- `NPCs` filter is declarative and intentionally transient
- `Other Gods` and `Hammers` sit on the shared domain-tabs path cleanly
- `Olympians` is now structurally stable and mostly declarative

Removed or replaced in BoonBans:
- `dynamicText`
- `forceStatus`
- `rarityBadge`
- `dangerButton`
- old NPC filter wrapper widget path
- old layout wrapper shells around domain panels/settings

Current intentional custom widgets:
- `bridalGlowPicker`
- `forceRarityStatus`

Current judgment:
- both remaining custom widgets are legitimate
- they are domain leaf widgets, not hidden planner/runtime infrastructure

---

## 5. Tab and root selection state is now explicit transient UI state

This was an important architectural cleanup.

Old shape:
- BoonBans maintained parallel controller-side root-selection state
- layout/controller code had to coordinate tree state manually

Completed:
- added optional `activeTab` binds to Lib tab layouts
- BoonBans now binds domain root selection through transient aliases
- `selectedRootByMainTab` was removed

Current state model:
- selected root for each main tab is explicit transient UI state
- tab layouts read/write that state directly
- post-draw module logic reacts to that explicit state rather than compensating for missing ownership

This materially improved:
- tree ownership
- debuggability
- separation between UI state and side effects

---

## 6. Forced-rarity rendering clarified an important Lib boundary

This was one of the most useful findings of the whole migration.

What happened:
- force rows were initially cleaned up by replacing many sibling `visibleIf` rarity nodes with one `forceRarityStatus` custom widget
- that custom widget originally tried to recursively draw a prepared Lib `stepper` node inside itself
- rendering bugs exposed that this nested widget-in-widget approach was brittle

What was learned:
- under the current slot model, widgets should be treated as leaf renderers
- layouts can compose layouts
- custom widgets can render atomic local ImGui controls
- recursively drawing another full slot-based widget from inside a widget is unsafe in the current system

Result:
- `forceRarityStatus` now renders its local rarity control directly and atomically
- the force tab is stable again

This is now an important authoring rule for Lib:
- widgets are leaf renderers unless the nested render is truly atomic

---

## 7. Performance regression was partially corrected

The structural cleanup improved ownership, but it also introduced per-frame rebuild churn in the special-module render path.

Completed:
- top-level BoonBans main tabs node is cached again
- a reusable Lib helper was added:
  - `lib.getCachedPreparedNode(cacheEntry, signature, buildFn, opts?)`
- BoonBans main tabs / domain panels / domain tabs now use that helper
- root-level cached signature fragments were added so selector/header strings are not rebuilt into every higher-level signature on every frame

Current result:
- there may still be a small first-open hitch
- steady-state redraw cost is now much better
- the largest obvious per-frame churn was removed

Important architectural choice:
- reusable cache mechanism belongs in Lib
- invalidation policy/signature contents stay module-side

---

## What Is Now Considered Structurally Stable

The following are no longer active concerns for the static-foundation effort:

- `dynamicText` as a mainline widget surface
- planner/runtime geometry in the live Lib model
- BoonBans ban-list geometry planning
- `rarityBadge`
- `forceStatus`
- top-level adapter-style `mainTabContent`
- controller-owned parallel selected-root tables

The following are now considered acceptable intentional boundaries:

- `bridalGlowPicker`
- `forceRarityStatus`
- module-side derived text entries using `lib.runDerivedText(...)`
- transient UI state for:
  - filters
  - active tabs
  - selected roots

---

## Remaining Work Before Closing This Down

The remaining work is now mostly Lib follow-up, not more BoonBans cleanup.

## A. Explicit Y ownership in Lib layout/slot infrastructure

Completed:
- structured slot rendering now owns row `Y` explicitly
- `panel` now owns row settlement explicitly
- radio-family widgets now use the structured slot renderer
- `verticalTabs` no longer relies on ambient `SameLine()` split flow
- the start/end cursor settlement contract is implemented and documented

Outcome:
- `line` remains the public vertical descriptor
- raw `y` remains internal
- the first-pass Y-ownership work is complete and stable enough for regression testing

## B. Relative positioning support

Still desired, but intentionally deferred until after the future `X`/`Y` unification discussion.

Why it still matters:
- current layout is still mostly absolute-pixel-based
- relative measures would make the static system more flexible without reopening dynamic layout

Recommended scope:
- keep it narrow
- start with practical relative width/start support
- do not jump to a large responsive layout subsystem

## C. Standardized post-draw registration for special modules

Completed:
- `lib.runUiStatePass(...)` now supports:
  - `beforeDraw(imgui, uiState, theme)`
  - `afterDraw(imgui, uiState, theme, changed)`
- `lib.standaloneSpecialUI(...)` forwards special-module before/after draw hooks for quick content and tab passes
- Framework coordinator special tabs now forward the same hooks
- BoonBans now uses:
  - `BeforeDrawTab` for derived-text/frame refresh
  - `AfterDrawTab` for root/filter/cache/stats reactions

Important boundary kept:
- Lib provides the orchestration mechanism
- modules still own the actual side-effect policy

## D. Document cache and invalidation conventions

Now that caching is part of the active design, Lib needs a clearer authoring rule for:
- what may be cached on nodes/descriptors
- what invalidates those caches
- where invalidation should live

Completed:
- `lib.getCachedPreparedNode(...)` is now documented as the reusable prepared-node cache helper
- `lib.runDerivedText(...)` documents caller-owned cache lifecycle more explicitly
- module authoring docs now state the intended ownership split:
  - Lib owns mechanical caches
  - modules own semantic signatures and invalidation policy

## E. Document the leaf-widget rule

Completed:
- authoring docs now state:
  - layouts may compose layouts and widgets
  - widgets should generally be treated as leaf renderers
  - custom widgets should not recursively draw full slot-based widgets unless the nested thing is truly atomic

---

## What Is Intentionally Deferred

These are not part of closing the static-foundation effort:

- front-loading first-open special-module warmup optimizations
- full dynamic layout/runtime geometry revival
- generic non-text derived-state/reactive system
- broad automatic caching/invalidation inference in Lib

These may matter later, but they are not required to call the static foundation re-established.

---

## Current Assessment

At this point:
- the static rollback/consolidation succeeded
- BoonBans is no longer structurally blocked on the old middle ground
- the remaining work is mostly about maturing Lib around the lessons learned

The main remaining Lib topics are:
1. relative positioning
2. future `X`/`Y` symmetry discussion after real-world regression shakeout

That is a much narrower and healthier scope than where this effort started.

---

## Summary Timeline

| Area | Result |
|---|---|
| Dynamic rollback | Planner/runtime middle ground removed from `main` |
| Static widget surface | `confirmButton`, enum stepper display, packed filtering, colors, active-tab binding, optional panel ID |
| Derived text | `lib.runDerivedText(...)` added and adopted |
| Special hooks | before/after draw hooks standardized across standalone and coordinator paths |
| Y ownership | first-pass explicit internal row `Y` ownership completed for slots, panels, and `verticalTabs` |
| BoonBans structure | Main tabs, domain shells, most views now declarative |
| Selection ownership | Root/tab state moved to transient UI aliases |
| Force tab lesson | Leaf-widget rule clarified through direct `forceRarityStatus` rendering |
| Performance | Reusable prepared-node cache helper added; major steady-state churn reduced |
| Remaining work | `Y` ownership, post-draw registration, relative positioning, docs/contracts |
