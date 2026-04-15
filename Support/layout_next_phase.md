# Layout Next Phase

## Status

Forward-looking design notes for the next Lib layout phase.

This is not an API contract and not an implementation plan.
It captures the friction points identified after the v2 substrate stabilized,
so they do not need to be re-derived from scratch when the work begins.

Current docs for the live v2 surface:
- `adamant-ModpackLib/FIELD_REGISTRY.md`
- `adamant-ModpackLib/MIGRATING_TO_LAYOUT_V2.md`

---

## Context

The v2 rect-based substrate is now stable. Containers (`vstack`, `hstack`, `split`,
`tabs`, `scrollRegion`, `collapsible`) correctly propagate `(x, y, availWidth,
availHeight)` top-down and collect `(consumedWidth, consumedHeight, changed)` bottom-up.
Container-level layout is responsive — it adapts to whatever space it is given.

The remaining friction is at the **leaf level** and at specific **composition patterns**
that the current primitive set cannot express cleanly.

---

## 1. Relative / Fractional Sizing

### Problem

All width-accepting props (`controlWidth`, `valueWidth`, `navWidth`, `text.width`) are
pixel values. At different window sizes or resolutions the UI does not adapt. Container
layout is already responsive — leaf sizing is not.

### Why it is safe to add

The layout engine already passes `availWidth` to every draw call. `GetContentRegionAvail()`
inside a child window returns the child's available space, not the parent's — so the
recursive case is already correct. Resolving a fraction is a single multiply at draw time.

### Design direction

Width-accepting props should accept:
- positive integer: pixel value, current behavior
- float between 0 and 1: fraction of `availWidth`
- `-1` (or negative): fill remaining space, matching ImGui's own `PushItemWidth` convention

### Edge case to resolve

When `availWidth` is unconstrained (e.g. a widget inside an unconstrained hstack), a
fractional value has nothing to multiply against. Needs a clear rule — likely fall back to
a declared pixel minimum, or warn and render at zero width. The `split` doc already
surfaces this same constraint for `ratio`.

---

## 2. Multi-Column Aligned Form Layout

### Problem

Label-control pairs where all labels align to the same width and all controls start at
the same X — the standard settings form pattern — cannot be expressed cleanly in v2.
The workaround is consistent `controlWidth` values across rows, which hardcodes pixel
values and collapses under relative sizing or different window widths.

The old `panel` with columns handled this. v2 has no equivalent.

### Why it matters

This is the most common layout pattern in settings UIs. Almost every module with more
than two controls wants aligned label-control rows. Without native support it either
requires hardcoded pixel discipline or looks misaligned.

### Design direction

A `table` layout node backed by ImGui's `BeginTable`/`EndTable` API. ImGui tables
handle column alignment across rows natively, support fixed and proportional column
widths, and already exist in the Lua binding.

The authoring surface would declare columns once and children would flow into them,
similar to how `tabs` children declare `tabLabel` and flow into the tab bar.

Column widths on the `table` node would naturally participate in the relative sizing
system from item 1.

---

## 3. Flex Child in `hstack`

### Problem

In an `hstack`, there is no way to say "this child should take all remaining width
after the others consume their share." Each child gets whatever it consumes. The
common pattern — fixed label, flexible control — cannot be expressed without hardcoding
the control width or knowing the total available width at authoring time.

### Relationship to relative sizing

Relative sizing (item 1) partially solves this. A child with `width = { frac = 1.0 }`
or an equivalent fill convention would express the intent. But the hstack needs to know
which children are fixed and which are flexible before it can lay them out, which requires
a two-pass or declaration-time hint.

### Design direction

A `flex = true` or `fill = true` flag on an hstack child node. One flex child per hstack
takes all remaining width after fixed-width siblings are measured. Multiple flex children
divide remaining width equally, or by declared weight.

This is the standard flex-grow concept and maps cleanly onto the existing hstack
traversal — measure fixed children first, then distribute remainder to flex children.

---

## 4. Equal N-Column Division

### Problem

`split` is two-pane only. Dividing available width equally among three or more children
requires nested splits, which is awkward to author and hard to read. A common pattern
like a three-column option row has no clean expression.

### Design direction

Two options:

**Option A:** Allow `hstack` to declare equal-width distribution as a mode, so all
children receive `availWidth / n` automatically.

**Option B:** A dedicated `columns` layout node that declares N equal (or weighted)
columns and flows children into them.

Option A is simpler and reuses the existing hstack. Option B is more explicit and
composable with the table layout from item 2. These may converge into the same thing
depending on how the table node is designed.

---

## 5. `enabledIf`

### Problem

`visibleIf` hides nodes conditionally. There is no equivalent for disabling — showing
a node as grayed out and non-interactive based on an alias condition. Conditionally
disabled controls are a common UI pattern, especially for options that depend on another
option being active.

### Design direction

An `enabledIf` prop on widget nodes, using the same condition forms as `visibleIf`:

```lua
enabledIf = "Enabled"
enabledIf = { alias = "Mode", value = "Advanced" }
enabledIf = { alias = "Mode", anyOf = { "Advanced", "Custom" } }
```

When the condition is false, Lib wraps the widget draw in `ImGui.BeginDisabled()` /
`ImGui.EndDisabled()`. The widget renders normally but ImGui handles the graying and
interaction suppression.

This is a small targeted addition — the condition evaluation already exists from
`visibleIf`, and ImGui's disable API is a simple bracket pair.

---

## Implementation Order

No fixed order yet. Some natural dependencies:

- Relative sizing (item 1) should land before or alongside flex child (item 3), since
  they solve the same problem at different levels.
- Table layout (item 2) benefits from relative sizing for column widths but can ship
  independently with pixel-only column widths first.
- `enabledIf` (item 5) is fully independent and could land at any time.
- Equal N-column division (item 4) may be subsumed by how table layout and flex child
  are designed — evaluate after those land.
