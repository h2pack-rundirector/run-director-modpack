# Layout Substrate Redesign

## Context

Phase 1 Y-ownership work (`y_ownership_plan.md`) is complete.

That work made the existing row-dominant substrate explicit and deterministic:
- `DrawWidgetSlots` owns row Y explicitly
- `panel.render` owns row origin and settlement
- `verticalTabs` positions panes from a captured origin
- `DrawStructuredAt` is the internal footprint settlement primitive

Phase 1 was the right incremental step. It is now finished.

This document is the plan for Phase 2: the last major architectural work in the lib
layout story.

---

## The Remaining Problem

Phase 1 made the current model work correctly. It did not change what the model is.

The current model is row-dominant. Rows stack vertically. Within a row, X has rich
declarative support (`start`, `width`, `align`). Y has only `line` — a row selector —
and nothing else. The axes are not equal in the authoring model or the internal engine.

The deeper issue is that the model was inherited from ImGui's implicit vertical flow
rather than deliberately chosen. ImGui flows vertically by default and treats horizontal
placement as the exceptional case. The lib built on top of that assumption instead of
questioning it.

The result is two separate layout systems that should be one:

- Outer layout: `panel` / `group` / tabs with `line` / `column.start`
- Inner layout: `DrawWidgetSlots` with slot geometry

These are the same problem at different scales. They use different primitives, different
geometry specs, and different cursor-management strategies. Unifying them is the last
structural work.

---

## What The Declarative Model Deserves

The declarative model is complete and sound:
- storage system and aliases
- binds, visibleIf, customTypes
- validation and node preparation
- discovery and framework integration

The declarative model is ahead of the substrate. It deserves a layout engine that is
proportional to it: symmetric on both axes, rect-based internally, with a clear contract
between layout nodes and widget nodes.

---

## Design Goals For Phase 2

1. **Symmetric axes** — X and Y are equal concepts in both the authoring model and the
   internal engine. No axis is inherited from ImGui flow.

2. **Rect-based internal engine** — every structured child receives an explicit
   `(x, y, availWidth)` from its parent. No ambient cursor inheritance in structured
   paths.

3. **Unified inner and outer layout** — slot geometry and panel layout use the same
   primitives. The two-level system collapses into one.

4. **Clean widget contract** — widgets receive their assigned position and available
   width. They draw within it. They report consumed height. They do not control
   surrounding flow.

5. **Layout/region separation** — `BeginChild`/`EndChild` is an explicit opt-in region
   primitive, not implied by any layout node type. Matches the boundary stated in
   `y_ownership_north_star.md` requirement 9.

6. **Variable-height handled honestly** — widgets declare a `measure(node, availWidth)`
   method returning height or `nil`. `nil` means unknown until drawn. The engine falls
   back to post-measurement for those nodes only, not universally.

7. **Custom widget contract is clear** — a custom widget receives a rect, draws inside
   it using whatever ImGui calls it needs, and returns consumed height. Footprint
   settlement is not author-managed per-call; it is enforced by the contract shape.

---

## New Layout Primitives

### `vstack`

Stacks children vertically with configurable gap.

```lua
{
    type = "vstack",
    gap = 4,
    children = { ... }
}
```

Children are drawn sequentially from top to bottom. Each child receives
`(x, currentY, availWidth)`. `currentY` advances by the child's consumed height plus gap
after each draw. Replaces the row-sequencing role of `panel`.

### `hstack`

Stacks children horizontally with configurable gap.

```lua
{
    type = "hstack",
    gap = 8,
    children = { ... }
}
```

Children are drawn left to right. Each child receives `(currentX, y, remainingWidth)`.
`currentX` advances by the child's consumed width plus gap. Replaces `SameLine`-based
placement and the column-within-row role of the geometry slot model.

`vstack` and `hstack` are symmetric. A row is an `hstack`. A column of rows is a
`vstack` of `hstack`s. No concept of "row" as a special primitive.

### `split`

Two-pane layout at a declared ratio or fixed width. Replaces `verticalTabs` internal
structure and any future split-pane need.

```lua
{
    type = "split",
    direction = "horizontal",  -- sidebar left, detail right
    sidebarWidth = 180,
    sidebar = { ... },
    detail = { ... }
}
```

Both panes receive explicit `(x, y, width)`. Replaces the `BeginChild`-based split in
`verticalTabs`.

### `scrollRegion`

Explicit opt-in scroll container. Uses `BeginChild`/`EndChild` internally.

```lua
{
    type = "scrollRegion",
    height = 220,   -- fixed height, scrolls if content exceeds it
    children = { ... }
}
```

This is the only node type that creates a new ImGui coordinate space. It is an explicit
authoring choice, not a side effect of any layout node. `bridalGlowPicker`'s current
`BeginChild` usage becomes this.

### `collapsible`

Header widget with toggled content. Variable height.

```lua
{
    type = "collapsible",
    label = "Advanced",
    defaultOpen = false,
    children = { ... }
}
```

Uses `imgui.CollapsingHeader` for the header widget. When closed, consumed height is
frame height. When open, consumed height is frame height plus measured content height.
The parent does not pre-assign height; it receives consumed height after drawing.

`measure` returns `nil` (unknown until drawn). The engine handles this with
post-measurement for this node only.

### `tabs` (replaces `horizontalTabs` / `verticalTabs`)

```lua
{
    type = "tabs",
    direction = "horizontal",  -- or "vertical"
    id = "myTabs",
    binds = { activeTab = "SomeAlias" },
    children = {
        { tabLabel = "Olympians", tabId = "olympians", ... },
        ...
    }
}
```

`horizontalTabs` uses `BeginTabBar`/`BeginTabItem`. `verticalTabs` uses the `split`
primitive with a selectable list. The `direction` field selects which.

### `separator` and `group`

These remain as simple structural nodes. They participate in the vstack/hstack flow
naturally — consumed height is their rendered height, no special handling needed.
`group` with `collapsible = true` becomes the `collapsible` node above.

---

## New Widget Contract

### Current signature

```lua
draw = function(imgui, node, bound, width, uiState)
```

Width is available. Position is ambient cursor.

### New signature

```lua
draw = function(imgui, node, bound, x, y, availWidth, uiState)
    -- draw at (x, y) within availWidth
    -- return consumedHeight
    return height
end
```

Position is an explicit parameter. Width is an explicit parameter. Consumed height is an
explicit return value. The cursor is an implementation detail — call `SetCursorPos(x, y)`
at entry because that is how ImGui renders, but that is contained inside the widget, not
ambient state.

The engine calls `SetCursorPos(x, y)` before each widget draw and reads `GetCursorPosY()`
after to confirm settlement. The explicit return value is the primary footprint signal.
The post-draw cursor check is a secondary consistency verification, not the primary
mechanism.

### `measure` protocol

```lua
measure = function(node, availWidth)
    return height  -- or nil if unknown until drawn
end
```

Fixed-height widgets return `GetFrameHeight()` or a known constant. Variable-height
widgets return `nil`. The engine calls `measure` for pre-positioning when it can, and
falls back to draw-then-measure for `nil` returns.

Most widgets in the current system are fixed-height. `measure` is trivial for them.

### Custom widget authoring

A custom widget receives `(x, y, availWidth)`, draws using ImGui primitives, returns
`consumedHeight`. No `SetAtomicCursor` pattern. No manual footprint settlement. The
contract shape handles it.

`lib.WidgetHelpers.drawAt(imgui, x, y, fallbackHeight, drawFn)` remains available for
custom widgets that need to compose sub-elements, but it is a convenience helper, not a
requirement.

---

## Performance Contract

The performance regression in BoonBans did not come from the declarative model. It came
from churn: per-frame node preparation, signature rebuilding, and repeated allocation in
hot paths. That was addressed with prepared-node caching and root-level signature caching.

Phase 2 must respect those same hot-path costs from the start:

- node preparation happens once, not per frame
- `measure` results are cached with a signature; only recomputed when relevant state changes
- the rect-based traversal does not allocate new tables per frame for child rects — it
  passes x/y/width as scalar parameters, not as table objects
- `_boundCache` and `_renderSlotCache` patterns from v1 carry forward

The declarative model being correct does not mean it is free. The substrate must be
designed with allocation discipline from the beginning, not added later.

---

## What Does Not Change

- Storage system — unchanged
- Aliases, hash/profile ABI — unchanged
- Binds and bind validation — unchanged
- `visibleIf` — unchanged
- `customTypes` — unchanged
- `validateUi` / `prepareUiNode` — updated for new node types, contract preserved
- Discovery and framework integration — unchanged
- `createStore`, `applyDefinition`, `isEnabled` — unchanged
- `runDerivedText`, `getCachedPreparedNode` — unchanged
- `standaloneUI` / `standaloneSpecialUI` — unchanged

The declarative model above the layout substrate is preserved. Only the layout node types
and the widget draw signature change.

---

## Migration Scope

### `adamant-ModpackLib`

- `layouts.lua` — replace `panel` render with `vstack`/`hstack` traversal; replace
  `verticalTabs` internal structure with `split`; add `collapsible`, `scrollRegion`;
  update `horizontalTabs`/`verticalTabs` → `tabs`
- `shared.lua` — `DrawWidgetSlots` goes away or becomes internal to the slot-rendering
  path; `DrawStructuredAt` remains as the internal positioned-draw primitive
- `ui.lua` — `drawUiNode` passes `(x, y, availWidth)` to widget draw; reads consumed
  height from return value; confirms cursor settlement as secondary check
- `widgets.lua` — update all widget `draw` signatures; add `measure` to fixed-height
  widgets
- `field_registry.lua` — update `WidgetHelpers` surface

### `adamant-RunDirector_BoonBans`

- `nodes.lua` — update layout node types (`panel` → `vstack`/`hstack`); remove slot
  geometry DSL where it existed; update custom widget calls
- `customUi.lua` — update `forceRarityStatus` and `bridalGlowPicker` to new widget
  signature; remove `SetAtomicCursor` pattern; `bridalGlowPicker`'s `BeginChild` panes
  become `scrollRegion` nodes or remain in a `raw` custom widget

### Other modules

Handled at branch time for each module. The contract change is mechanical: update
`draw` signature, add `measure` for fixed-height widgets, replace layout node types.

---

## V1 Strengthening — Before Branching

These are the tasks to complete and commit on the current branch before the redesign
branch opens. They close open items without changing the layout model.

1. **Expose `lib.WidgetHelpers.drawAt` and `lib.WidgetHelpers.estimateRowAdvanceY`**
   Make `DrawStructuredAt` and `EstimateStructuredRowAdvanceY` available as public
   WidgetHelpers. Reduces custom widget author burden now and establishes the surface
   that Phase 2 will formalize.

2. **`lib.validateDefinition` — unknown key warning**
   At `createStore` time, warn on unknown definition fields. Closes the definition table
   authoring story. Low risk, high value for catching author errors early.

3. **`getWidgetSummary` removal**
   HANDOFF noted this should be removed, not just undocumented. Remove it cleanly.

4. **In-game regression pass**
   The Phase 1 Y-ownership work has structural integration issues documented in
   `y_ownership_plan.md`. Regression test in-game, fix any remaining issues, confirm
   stable before branching.

5. **Commit and tag v1**
   Clean commit of the strengthened v1 state. This is the stable checkpoint before the
   substrate redesign begins.

---

## Branch Strategy

```
main          ← v1 strengthened and committed here
  └── layout-substrate-v2   ← redesign branch opens here
```

The redesign branch targets `adamant-ModpackLib` first, then migrates
`adamant-RunDirector_BoonBans` against the new lib surface. Other modules follow.

Work order on the branch:

1. Define and implement `vstack`/`hstack` as the new core layout primitives
2. Update widget draw signature and `measure` protocol
3. Implement `collapsible`, `scrollRegion`, `split`
4. Update `tabs` to handle both directions
5. Remove `DrawWidgetSlots` / slot geometry DSL; unify inner and outer layout
6. Migrate BoonBans nodes and custom widgets to the new surface
7. Update authoring docs

---

## Success Criteria

The redesign is complete when:

- `vstack` and `hstack` replace the `line`/`column`/slot-geometry model
- Widget draw signatures take explicit `(x, y, availWidth)` and return consumed height
- No ambient cursor inheritance in any structured layout path
- `DrawWidgetSlots` and the separate slot geometry system no longer exist
- Custom widget authoring does not require manual cursor settlement
- BoonBans renders correctly under the new substrate
- Authoring docs reflect the final model

At that point the lib layout story is complete. The declarative model has a substrate
proportional to it.
