# BoonBans / ModpackLib Panelization — Handoff
 
## Context
 
Mid-way through a two-pass refactor that panelizes BoonBans UI using ModpackLib's node/widget system
and adds missing lib primitives needed to complete it.
 
---
 
## ModpackLib — What Was Added
 
### New Widgets (`field_registry/widgets.lua`)
 
| Widget | Key fields | Notes |
|---|---|---|
| `dynamicText` | `getText` (req), `getColor`, `getTooltip` | Frame-cached via `_dynamicTextCtx` |
| `confirmButton` | `onConfirm`, `confirmLabel`, `cancelLabel`, `timeoutSeconds` | Per-node `_confirmButtonState`; **has bug (see below)** |
 
### New Layouts (`field_registry/layouts.lua`)
 
| Layout | Notes |
|---|---|
| `horizontalTabs` | Thin ImGui tab bar wrapper. Children need `tabLabel`, optional `tabId`. No `runtimeLayout` support. |
| `verticalTabs` | Sidebardetail split. `_activeTabKey` per node. `runtimeLayout.children[key].hidden` implemented via `PrepareRuntimeTabbedLayout`. Active tab falls back to first visible child when hidden. |
 
### New Public Functions (`field_registry.lua`)
 
- `lib.buildIndexedHiddenSlotGeometry(items, slotPrefix, opts)` — builds slot geometry with hidden flags for indexed widgets (`packedCheckboxList`, `radio`). `opts.isHidden(item, index, nextVisibleIndex)`, `opts.line(item, index, visibleIndex, hidden)`.
- `lib.WidgetHelpers` — empty table, reserved namespace for cross-widget authoring utilities.
 
### Summary Functions on Widgets
 
- `radio.summary(node, bound)` — returns `{ totalCount, visibleCount, hiddenCount, selectedValue, selectedLabel, selectedIndex }`
- `packedCheckboxList.summary(node, bound)` — returns `{ totalCount, visibleCount, hiddenCount, checkedCount, uncheckedCount, visibleCheckedCount, visibleUncheckedCount }`
 
**Design decision:** Do NOT call through `lib.getWidgetSummary` (generic dispatch, opaque return type).
Callers always know the widget type. Call directly:
```lua
node._widgetType.summary(node, bound)
```
`node._widgetType` is already the merged resolved type (lib or custom), set during validation.
 
`lib.getWidgetSummary` exists in `field_registry/ui.lua` but **should be removed** — it has no valid use case now that the direct call pattern is established.
 
---
 
## ModpackLib — Known Bugs
 
### `confirmButton` returns `true` on initial arm press
 
In `widgets.lua` around line 449–454: when the user clicks the trigger button (arming the confirm state), the slot draw function returns `true`. No data changed — only internal widget state. Should return `false`.
 
The fix: remove the `return true` from the arm branch, move `ShowPreparedTooltip` outside the `if` block.
 
---
 
## BoonBans — What Was Panelized
 
All node builders live in `ui/nodes.lua`. All use `lib.drawUiNode` with `internal.definition.customTypes`.
 
| Function | Description |
|---|---|
| `GetRarityBadgeNode(alias)` | Single `rarityBadge` widget node |
| `GetRarityPanelNode(root)` | Rarity panel for a root (iterates scopes) |
| `GetBanListNode(scopeKey)` | `packedCheckboxList` for a scope's boons |
| `GetBanControlsPanelNode(scopeKey)` | Ban controls (filter, search, select/deselect) |
| `GetBanPanelNode(scopeKey)` | Ban controls  ban list combined |
| `GetBridalGlowPanelNode(root)` | Bridal glow summary  picker |
| `GetForcePanelNode(root)` | `mappedDropdown` for force boon selection |
| `GetRootViewsTabsNode(root)` | `horizontalTabs` over force/bans/rarity/bridalGlow panels |
| `GetSettingsPanelNode()` | Settings: `disabledText` hints, `stepper`, `dangerButton` ×2 |
| `GetNpcRegionFilterPanelNode()` | NPC region filter panel |
| `GetDomainTabsNode(tabName, visibleRoots, uiState)` | Signature-based `verticalTabs` node. Rebuilds when root list or labels change. `sidebarWidth = 260`. |
 
### `GetDomainTabsNode` — signature rebuild pattern
 
Builds a string signature from `tabName  root.id  selectorLabel` per root. Only rebuilds the `verticalTabs` node when the signature changes. `_activeTabKey` is synced two-way in `DrawDomainTab` (layout.lua): set before draw from module state, read back after draw to detect user navigation.
 
### `DrawDomainTab` (layout.lua)
 
Replaced `DrawRootSelector`  `DrawRootDetail` with the `verticalTabs` node. Handles `_activeTabKey` sync and calls `internal.UpdateGodStats` on change.
 
---
 
## BoonBans — Custom Widgets Current State
 
File: `ui/customUi.lua`, registered in `public.definition.customTypes.widgets`.
 
| Widget | Status | Plan |
|---|---|---|
| `banSummary` | Exists | Replace with `dynamicText`  `getText` callback reading `GetScopeSummary` |
| `disabledText` | Exists | Keep until v2 color-on-geometry pass |
| `banList` | Exists | Keep — complex imperative widget |
| `bridalGlowSummary` | Exists | Replace with `dynamicText`  `getText` callback |
| `bridalGlowPicker` | Exists | Keep — complex imperative widget |
| `rarityBadge` | Exists | Replace with enum display on `stepper` (second pass) |
| `forceStatus` | Exists | Replace with `dynamicText`  `getText` callback |
| `paddingOptions` | Exists | Keep for now — imperative sub-settings |
| `dangerButton` | Exists | Replace with lib `confirmButton` |
| `npcRegionFilter` | Exists | Keep — SameLine radio buttons, no lib equivalent |
 
---
 
## Pending Work
 
### First Pass (do next)
 
1. **Fix `confirmButton` arm-press returning `true`** (see bug above) — do before BoonBans migration
2. **Replace `banSummary`** → `dynamicText` node with `getText = function(node, uiState) ... end` reading `GetScopeSummary`
3. **Replace `bridalGlowSummary`** → `dynamicText` node with `getText` reading `BridalGlowTargetBoon` view state
4. **Replace `forceStatus`** → `dynamicText` node with `getText` reading `GetForcedBoonStatusText`
5. **Replace `dangerButton`** → lib `confirmButton`. The module-global `pendingDanger` pattern (in `views.lua`) stays only for `DrawQuickContent` which is outside the node system.
6. **Remove `getWidgetSummary`** from lib public API (or at minimum stop documenting it)
 
### Second Pass (deferred)
 
- Enum display on `stepper`: add `displayValues` (table mapping int→label) and `valueColors` (table mapping int→color) optional fields. Eliminates `rarityBadge`.
- Int storage support on `radio` — needed for `rarityBadge` migration path
- `visibleIf` predicate on `group`/`panel` nodes
- Final BoonBans pass: after above, only `banList` and `bridalGlowPicker` should remain as custom widgets
 
### v2 Pass (separate, no date)
 
- Color on slot geometry → eliminates `disabledText`
- Relative/percentage slot positioning
 
---
 
## Key Files
 
| File | Purpose |
|---|---|
| `adamant-ModpackLib/src/field_registry/widgets.lua` | All widget type definitions |
| `adamant-ModpackLib/src/field_registry/layouts.lua` | All layout type definitions |
| `adamant-ModpackLib/src/field_registry/ui.lua` | `drawUiNode`, `getWidgetSummary`, `isUiNodeVisible` |
| `adamant-ModpackLib/src/field_registry.lua` | Public API surface, `buildIndexedHiddenSlotGeometry` |
| `BoonBans/src/mods/ui/nodes.lua` | All node builder functions |
| `BoonBans/src/mods/ui/customUi.lua` | Custom widget definitions  `definition.customTypes` |
| `BoonBans/src/mods/ui/layout.lua` | `DrawDomainTab`, `DrawMainContent`, `DrawQuickContent` |
| `BoonBans/src/mods/ui/views.lua` | `DrawSettingsTab`, `DrawBanPanel`, `DrawDangerAction` etc |
| `BoonBans/src/mods/ui/planner.lua` | `GetBanListGeometry` — signature-based ban list slot geometry |
