# Lib UI Lean-Down Migration Guide

Status:
- working guide for the `experiment/ui-lean-down` branch
- update this as real migrations expose gaps or bad assumptions

## Goal

Move modules from:
- declarative node trees
- layout nodes
- prepared-node caches
- `definition.ui`

to:
- direct ImGui for structure
- `lib.widgets.*` for bound controls
- `lib.ui.verticalTabs(...)` for the one recurring non-native layout helper
- `lib.ui.isVisible(...)` for structured visibility checks

## New mental model

Old model:
- describe a UI tree
- let Lib prepare, validate, cache, and draw it

New model:
- write `DrawTab(imgui, uiState)` directly
- use plain ImGui for rows, groups, tabs, child regions, and spacing
- call `lib.widgets.*` at the leaf controls where binding and storage matter

The structure is immediate-mode.
The state contract is still owned by Lib.

## What survives from Lib

Keep using:
- `lib.store.create(...)`
- `lib.definition.validate(...)`
- `lib.mutation.*`
- `lib.coordinator.*`
- `lib.special.standaloneUI(...)`
- `lib.special.runDerivedText(...)`
- `lib.special.auditAndResyncState(...)`
- `lib.special.commitState(...)`
- `lib.storage.*`
- `lib.accessors.*`

New UI-facing surface:
- `lib.widgets.checkbox(...)`
- `lib.widgets.dropdown(...)`
- `lib.widgets.mappedDropdown(...)`
- `lib.widgets.packedDropdown(...)`
- `lib.widgets.radio(...)`
- `lib.widgets.mappedRadio(...)`
- `lib.widgets.packedRadio(...)`
- `lib.widgets.stepper(...)`
- `lib.widgets.steppedRange(...)`
- `lib.widgets.inputText(...)`
- `lib.widgets.packedCheckboxList(...)`
- `lib.widgets.button(...)`
- `lib.widgets.confirmButton(...)`
- `lib.widgets.separator(...)`
- `lib.widgets.text(...)`
- `lib.ui.verticalTabs(...)`
- `lib.ui.isVisible(...)`

## What is gone

Do not use:
- `definition.ui`
- `definition.customTypes`
- `lib.ui.validate(...)`
- `lib.ui.prepareNode(...)`
- `lib.ui.prepareNodes(...)`
- `lib.ui.drawNode(...)`
- `lib.ui.drawTree(...)`
- `lib.special.runPass(...)`
- `lib.special.getCachedPreparedNode(...)`
- layout nodes like:
  - `vstack`
  - `hstack`
  - `split`
  - `tabs`
  - `scrollRegion`
  - `collapsible`

Those concepts are replaced by direct ImGui structure.

## Basic migration pattern

### 1. Keep storage, remove `definition.ui`

Old:

```lua
public.definition = {
    id = "SomeModule",
    name = "Some Module",
    storage = { ... },
    ui = { ... },
}
```

New:

```lua
public.definition = {
    id = "SomeModule",
    name = "Some Module",
    storage = { ... },
}
```

The UI is now authored in `DrawTab`.

### 2. Write `DrawTab(imgui, uiState)` directly

Example shape:

```lua
function internal.DrawTab(imgui, uiState)
    imgui.Text("Settings")
    imgui.Separator()

    lib.widgets.checkbox(imgui, uiState, "EnabledFlag", {
        label = "Enable Feature",
        tooltip = "Turns the feature on.",
    })

    lib.widgets.dropdown(imgui, uiState, "Mode", {
        label = "Mode",
        values = { 1, 2, 3 },
        displayValues = { "Low", "Medium", "High" },
        controlWidth = 120,
    })
end
```

### 3. Let standalone/coordinator call `DrawTab`

Special modules:

```lua
local standaloneUi = lib.special.standaloneUI(
    public.definition,
    store,
    store.uiState,
    {
        drawTab = internal.DrawTab,
        afterDrawTab = internal.AfterDrawTab,
    }
)
```

Regular/coordinated modules:
- same `DrawTab`
- coordinator/host decides where to call it

## Structural patterns

### Plain sections

Use raw ImGui:

```lua
imgui.Text("Rooms")
imgui.Separator()
```

### Conditional blocks

Simple cases:

```lua
if uiState.view["SomeFlag"] == true then
    ...
end
```

Structured cases:

```lua
if lib.ui.isVisible(uiState, { alias = "Mode", anyOf = { 2, 3 } }) then
    ...
end
```

### Vertical tabs

Use `lib.ui.verticalTabs(...)` only for the sidebar selector.
You still own the detail pane.

```lua
activeTab = lib.ui.verticalTabs(imgui, {
    id = "BiomeTabs",
    navWidth = 180,
    tabs = {
        { key = "Erebus", label = "Erebus" },
        { key = "Oceanus", label = "Oceanus" },
    },
    activeKey = activeTab,
})

imgui.SameLine()
imgui.BeginChild("BiomeDetail", 0, 0, false)
if activeTab == "Erebus" then
    DrawErebus(imgui, uiState)
elseif activeTab == "Oceanus" then
    DrawOceanus(imgui, uiState)
end
imgui.EndChild()
```

Important:
- `verticalTabs(...)` only renders the left selector pane
- always draw the detail pane yourself after it

## Widget migration notes

### Checkbox

Old:

```lua
{ type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" }
```

New:

```lua
lib.widgets.checkbox(imgui, uiState, "Enabled", {
    label = "Enabled",
})
```

### Dropdown

Old:

```lua
{ type = "dropdown", binds = { value = "Mode" }, values = { 1, 2 }, displayValues = { "A", "B" } }
```

New:

```lua
lib.widgets.dropdown(imgui, uiState, "Mode", {
    values = { 1, 2 },
    displayValues = { "A", "B" },
})
```

### Stepped range

Old:

```lua
{ type = "steppedRange", binds = { min = "MinAlias", max = "MaxAlias" }, min = 1, max = 10 }
```

New:

```lua
lib.widgets.steppedRange(imgui, uiState, "MinAlias", "MaxAlias", {
    min = 1,
    max = 10,
})
```

### Packed controls

The packed widgets now depend on `store.getPackedAliases(...)`.
Pass `store` explicitly.

```lua
lib.widgets.packedCheckboxList(imgui, uiState, "PackedAlias", store, {
    valueColors = myColors,
})
```

## Migration guidance by module shape

### Small/simple module

Good fit:
- direct `DrawTab`
- mostly `lib.widgets.checkbox/dropdown/radio`
- minimal extra ImGui structure

Example candidates:
- God Pool

### Complex structured module

Use:
- direct ImGui for structure
- `lib.widgets.*` for the actual settings
- `lib.ui.verticalTabs(...)` only if you genuinely need sidebar navigation

Do not try to rebuild the old tree system locally.

Example candidates:
- Biome Control
- Boon Bans

## Current known migration risks

### 1. Old docs are stale

Until docs are rewritten, prefer the code on this branch over old docs.

### 2. Framework and other modules may still reference removed APIs

On this branch, expect breakage in:
- `adamant-ModpackFramework`
- any module still using:
  - `lib.drawUiTree`
  - `lib.runUiStatePass`
  - `lib.special.getCachedPreparedNode`

### 3. Tests still assume old APIs

The Lib tests need a dedicated rewrite after one real module migration proves the new shape.

## Migration checklist for one module

1. Remove `definition.ui` usage.
2. Keep `definition.storage`.
3. Write or rewrite `DrawTab(imgui, uiState)`.
4. Replace node declarations with `lib.widgets.*` calls.
5. Replace layout nodes with direct ImGui structure.
6. Replace `visibleIf` usage with:
   - direct `uiState.view[...]` checks, or
   - `lib.ui.isVisible(...)`
7. Replace tree/tab layout with `lib.ui.verticalTabs(...)` only if needed.
8. Remove prepared-node caches and `lib.special.getCachedPreparedNode(...)`.
9. Verify dirty state still commits through standalone/coordinator entrypoints.
10. Retest in game.

## Open questions to update as we learn

- Is `lib.ui.verticalTabs(...)` enough, or do we need one more structural helper?
- Are any widget signatures too verbose in real module code?
- Does `runDerivedText(...)` still earn its keep after the first migrated modules?
- Should `lib.registry.storage` remain public, or become internal after migration?

Update this file after each real migration with:
- what worked
- what was awkward
- what surface changes were needed
