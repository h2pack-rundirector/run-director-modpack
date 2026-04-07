# Lib/Framework Documentation Audit

## Purpose

This note tracks the current `adamant-ModpackLib` / `adamant-ModpackFramework`
feature surface against the primary docs.

The goal is to keep the infrastructure docs honest, because:

- the template repo points to them
- module authors build against them
- Framework/Lib are now a real authoring surface, not just internal implementation

This file is intentionally higher-level than the API docs. It is an accountability
matrix, not a replacement for the docs themselves.

## Coverage Labels

- `Well documented`
  - primary docs exist
  - examples are current
  - terminology matches live code
- `Under-documented`
  - feature exists and is important, but docs are thin, easy to miss, or only implied
- `Over-documented / Historical`
  - doc exists but is mostly migration/history or risks drifting faster than it helps

## Feature Matrix

| Owner | Feature | Live Code Surface | Primary Docs | Status | Notes |
|---|---|---|---|---|---|
| Lib | `definition.storage` / `definition.ui` core model | `adamant-ModpackLib/src/core.lua`, `adamant-ModpackLib/src/field_registry.lua` | [API.md](../adamant-ModpackLib/API.md), [MODULE_AUTHORING.md](../adamant-ModpackLib/MODULE_AUTHORING.md), [FIELD_REGISTRY.md](../adamant-ModpackLib/FIELD_REGISTRY.md) | Well documented | This is the core mental model and the docs now reflect it cleanly. |
| Lib | `createStore(config, definition, dataDefaults)` defaults flow | `adamant-ModpackLib/src/core.lua` | [API.md](../adamant-ModpackLib/API.md), [MODULE_AUTHORING.md](../adamant-ModpackLib/MODULE_AUTHORING.md) | Well documented | Recently corrected. Important because templates now mirror this pattern. |
| Lib | Alias-backed `store.read/write` and raw `readBits/writeBits` | `adamant-ModpackLib/src/core.lua` | [API.md](../adamant-ModpackLib/API.md) | Well documented | Good reference surface. |
| Lib | Storage registry (`bool`, `int`, `string`, `packedInt`) | `adamant-ModpackLib/src/field_registry.lua` | [FIELD_REGISTRY.md](../adamant-ModpackLib/FIELD_REGISTRY.md), [API.md](../adamant-ModpackLib/API.md) | Well documented | Enough detail for authors. |
| Lib | Widget registry (`checkbox`, `dropdown`, `radio`, `stepper`, `steppedRange`, `packedCheckboxList`) | `adamant-ModpackLib/src/field_registry.lua` | [FIELD_REGISTRY.md](../adamant-ModpackLib/FIELD_REGISTRY.md), [API.md](../adamant-ModpackLib/API.md), [MODULE_AUTHORING.md](../adamant-ModpackLib/MODULE_AUTHORING.md) | Well documented | `packedCheckboxList` was the main recent gap and is now covered. |
| Lib | Layout registry (`separator`, `group`) | `adamant-ModpackLib/src/field_registry.lua` | [FIELD_REGISTRY.md](../adamant-ModpackLib/FIELD_REGISTRY.md), [MODULE_AUTHORING.md](../adamant-ModpackLib/MODULE_AUTHORING.md) | Well documented | Enough for current layout surface. |
| Lib | UI helpers (`validateUi`, `prepareUiNode`, `prepareUiNodes`, `drawUiNode`, `drawUiTree`) | `adamant-ModpackLib/src/field_registry.lua` | [API.md](../adamant-ModpackLib/API.md), [FIELD_REGISTRY.md](../adamant-ModpackLib/FIELD_REGISTRY.md) | Well documented | Reference coverage is good. |
| Lib | Module-local `customTypes` | `adamant-ModpackLib/src/field_registry.lua`, `adamant-ModpackLib/src/core.lua` | [API.md](../adamant-ModpackLib/API.md), [MODULE_AUTHORING.md](../adamant-ModpackLib/MODULE_AUTHORING.md), [FIELD_REGISTRY.md](../adamant-ModpackLib/FIELD_REGISTRY.md) | Well documented | Recently added to docs. Still worth watching as the feature grows. |
| Lib | Managed `uiState` and transactional UI commit | `adamant-ModpackLib/src/special.lua`, `adamant-ModpackLib/src/core.lua` | [API.md](../adamant-ModpackLib/API.md), [MODULE_AUTHORING.md](../adamant-ModpackLib/MODULE_AUTHORING.md) | Well documented | Strong coverage. |
| Lib | `runUiStatePass`, `commitUiState`, `auditAndResyncUiState` | `adamant-ModpackLib/src/special.lua` | [API.md](../adamant-ModpackLib/API.md) | Well documented | Good API-level coverage. |
| Lib | Lifecycle helpers (`inferMutationShape`, `applyDefinition`, `revertDefinition`, `reapplyDefinition`, `setDefinitionEnabled`) | `adamant-ModpackLib/src/core.lua` | [API.md](../adamant-ModpackLib/API.md), [MODULE_AUTHORING.md](../adamant-ModpackLib/MODULE_AUTHORING.md) | Well documented | Good enough for authors and maintainers. |
| Lib | Backup and mutation plan helpers | `adamant-ModpackLib/src/core.lua` | [API.md](../adamant-ModpackLib/API.md), [MODULE_AUTHORING.md](../adamant-ModpackLib/MODULE_AUTHORING.md) | Well documented | Good examples present. |
| Lib | Standalone helpers (`standaloneUI`, `standaloneSpecialUI`) | `adamant-ModpackLib/src/core.lua`, `adamant-ModpackLib/src/special.lua` | [API.md](../adamant-ModpackLib/API.md), [MODULE_AUTHORING.md](../adamant-ModpackLib/MODULE_AUTHORING.md), template repo | Well documented | Good authoring coverage. |
| Lib | Quick candidate collection (`quick = true`, `quickId`, `collectQuickUiNodes`) | `adamant-ModpackLib/src/field_registry.lua` | [API.md](../adamant-ModpackLib/API.md), [MODULE_AUTHORING.md](../adamant-ModpackLib/MODULE_AUTHORING.md) | Well documented | This was recently improved. |
| Lib/Framework | Runtime quick filtering (`definition.selectQuickUi`) | `adamant-ModpackFramework/src/ui.lua`, `adamant-ModpackFramework/src/discovery.lua` | [API.md](../adamant-ModpackLib/API.md), [MODULE_AUTHORING.md](../adamant-ModpackLib/MODULE_AUTHORING.md), [COORDINATOR_GUIDE.md](../adamant-ModpackFramework/COORDINATOR_GUIDE.md) | Well documented | Good enough now. If the feature grows, it may deserve its own focused guide. |
| Lib | Coordinator registration / coordinator-aware enable semantics | `adamant-ModpackLib/src/core.lua` | [API.md](../adamant-ModpackLib/API.md) | Well documented | Mostly reference-level; enough today. |
| Framework | Coordinator bootstrap and `Framework.init(...)` contract | `adamant-ModpackFramework/src/main.lua` | [COORDINATOR_GUIDE.md](../adamant-ModpackFramework/COORDINATOR_GUIDE.md) | Well documented | Good guide. |
| Framework | Discovery of regular/special modules and managed UI | `adamant-ModpackFramework/src/discovery.lua` | [COORDINATOR_GUIDE.md](../adamant-ModpackFramework/COORDINATOR_GUIDE.md) | Well documented | Coverage is concise but sufficient. |
| Framework | Quick Setup rendering model | `adamant-ModpackFramework/src/ui.lua` | [COORDINATOR_GUIDE.md](../adamant-ModpackFramework/COORDINATOR_GUIDE.md) | Under-documented | The guide now mentions runtime quick filtering, but Quick Setup still lacks a dedicated deeper explanation. |
| Framework | Hash canonical format and profile load behavior | `adamant-ModpackFramework/src/hash.lua` | [HASH_PROFILE_ABI.md](../adamant-ModpackFramework/HASH_PROFILE_ABI.md), [COORDINATOR_GUIDE.md](../adamant-ModpackFramework/COORDINATOR_GUIDE.md) | Well documented | Strong ABI-focused coverage. |
| Framework | `definition.hashGroups` | `adamant-ModpackFramework/src/hash.lua` | [HASH_PROFILE_ABI.md](../adamant-ModpackFramework/HASH_PROFILE_ABI.md), [COORDINATOR_GUIDE.md](../adamant-ModpackFramework/COORDINATOR_GUIDE.md), [FIELD_REGISTRY.md](../adamant-ModpackLib/FIELD_REGISTRY.md) | Well documented | Recently improved. |
| Lib/Framework | ABI stability rules (ids, aliases, defaults, hash groups) | `adamant-ModpackFramework/src/hash.lua` | [HASH_PROFILE_ABI.md](../adamant-ModpackFramework/HASH_PROFILE_ABI.md), [MODULE_AUTHORING.md](../adamant-ModpackLib/MODULE_AUTHORING.md) | Well documented | One of the stronger doc areas. |

## Holistic Assessment

After the recent doc pass, the main live docs are in a decent state.

The current split is mostly good:

- `API.md`
  - reference surface
- `MODULE_AUTHORING.md`
  - author workflow and examples
- `FIELD_REGISTRY.md`
  - storage/widget/layout registry model
- `COORDINATOR_GUIDE.md`
  - Framework/coordinator authoring
- `HASH_PROFILE_ABI.md`
  - compatibility rules

That is a sane split.

## Where The Split Is Still Weak

Two areas are starting to grow beyond “just mention it in passing.”

### 1. Quick Setup / runtime quick selection

Right now the information is spread across:

- `API.md`
- `MODULE_AUTHORING.md`
- `COORDINATOR_GUIDE.md`

That is acceptable for now, but if Quick Setup grows further, it may deserve its own focused note.

Candidate future doc:

- `QUICK_UI.md`

Use it only if any of these happen:

- `selectQuickUi(...)` gains more behavior
- Quick Setup gets more runtime selection patterns
- module authors start asking how quick candidates are discovered, filtered, and rendered

### 2. Custom types and richer layout composition

`customTypes` is now documented well enough, but if the panel/layout direction expands further,
the current split may become awkward:

- some of that belongs in `FIELD_REGISTRY.md`
- some belongs in authoring guidance
- some may become its own composition/layout guide

Candidate future doc:

- `UI_COMPOSITION.md`

Use it only if any of these happen:

- panel abstractions become real
- side-tab or sidebar-detail layout types land
- modules start programmatically generating panel/widget trees in a common pattern

## Recommended Documentation Policy

For now:

- keep the current file split
- treat doc updates as part of infrastructure changes, not follow-up cleanup

If the UI system expands again:

1. Add a focused Quick Setup doc before the feature becomes folklore.
2. Add a UI composition/layout doc only when panel/container patterns become real public authoring surface.

Do not add more files just to anticipate possible future growth.

## Practical Conclusion

Current docs after the recent updates are:

- mostly well documented
- no longer dangerously stale on the modern storage/UI contract
- not yet at the point where a bigger file split is clearly justified

Everything still in the live doc surface has a clear purpose.
