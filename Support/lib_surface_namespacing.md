# Lib Surface — Namespace Analysis

**Status:** Deferred. Revisit after BoonBans audit is stable.

---

## Why this was deferred

This analysis was done after the static foundation cleanup (dynamic infrastructure removed, `filteredCheckboxList` added). The surface is now clean enough that namespacing is a genuine option — but:

- BoonBans custom widget audit may remove or reshape some tier-2/tier-3 surface items
- Namespacing before that pass risks moving things twice
- Current priority is BoonBans, then docs/test sync, then this

---

## Three-Tier Surface View

### Tier 1 — Core public API (stable, main authoring story)

Module authors live here. These are the main verbs of the framework.

```
createStore
validateDefinition
applyDefinition / revertDefinition / reapplyDefinition
validateStorage
getStorageRoots
getStorageAliases
validateUi
prepareUiNode / prepareWidgetNode / prepareUiNodes
drawUiNode / drawUiTree
isUiNodeVisible
runUiStatePass
commitUiState
auditAndResyncUiState
standaloneUI
```

Also the registries:
```
StorageTypes
WidgetTypes
LayoutTypes
```

### Tier 2 — Advanced public API (legitimate, not the default story)

Custom widget authors and special-module authors need these. Ordinary module authors can ignore them.

```
drawWidgetSlots       — custom widget slot rendering primitive
alignSlotContent      — custom widget slot alignment helper
collectQuickUiNodes   — quick-access UI node collection
getQuickUiNodeId      — quick node identity
standaloneSpecialUI   — special module UI entry point
```

**Pending move:** `drawWidgetSlots` and `alignSlotContent` should move to `lib.WidgetHelpers` during BoonBans audit when those call sites are already being touched.

### Tier 3 — Soft-public / framework plumbing

Still exposed, but these are not the "main API" in the same way. Useful for advanced integrators, coordinators, and framework-internal tooling.

```
createBackupSystem
createMutationPlan
inferMutationShape
affectsRunData
registerCoordinator
isCoordinated
isEnabled
readPath / writePath
readBitsValue / writeBitsValue
warn / contractWarn / log
validateRegistries
WidgetHelpers          (reserved namespace, currently empty)
```

---

## Namespace Recommendation

Do not create namespaces to mirror tiers — that is documentation work, not architecture.

**What to keep flat (top-level lib):**

The main lifecycle verbs read well as top-level entry points and should stay there:
```
lib.createStore
lib.applyDefinition
lib.revertDefinition
lib.standaloneUI
```

**What to consider namespacing (if surface still feels noisy after BoonBans):**

Natural conceptual clusters that could move under light namespaces:

| Namespace | Contents |
|---|---|
| `lib.ui.*` | validateUi, prepareUiNode, prepareWidgetNode, prepareUiNodes, drawUiNode, drawUiTree, isUiNodeVisible, collectQuickUiNodes, getQuickUiNodeId |
| `lib.storage.*` | validateStorage, getStorageRoots, getStorageAliases |
| `lib.mutation.*` | createMutationPlan, createBackupSystem, readPath, writePath, readBitsValue, writeBitsValue |
| `lib.coordinator.*` | registerCoordinator, isCoordinated, affectsRunData |
| `lib.WidgetHelpers.*` | drawWidgetSlots, alignSlotContent — move here from top-level during BoonBans audit |

**What to avoid:**
- `lib.advanced.*` — editorial, not conceptual
- `lib.internal.*` — use docs to mark these, not structure

---

## Decision Gate

After BoonBans audit is stable, ask:

1. Does autocomplete feel noisy when authoring a regular module?
2. Are there name collisions or near-collisions?
3. Has any conceptual cluster grown significantly?

If yes to any: do the partial namespace pass described above.
If no: leave it flat, document the tiers in API.md instead.
