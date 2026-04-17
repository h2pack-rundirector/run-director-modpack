# Lib UI Lean-Down Progress

Branch:
- `experiment/ui-lean-down`

Goal:
- keep the data side intact
- remove the layout/tree UI pipeline
- replace it with thin bound widget functions plus a very small helper surface

Current intended Lib surface on this branch:
- `lib.config`
- `lib.store`
- `lib.storage`
- `lib.widgets`
- `lib.ui`
- `lib.special`
- `lib.definition`
- `lib.mutation`
- `lib.coordinator`
- `lib.logging`
- `lib.accessors`
- `lib.registry.storage`

## Status

### Phase 1 - Remove the layout system
- [x] delete `adamant-ModpackLib/src/field_registry/layouts.lua`
- [x] stop importing layouts from `adamant-ModpackLib/src/field_registry/init.lua`
- [x] remove `public.registry.layouts` initialization from `adamant-ModpackLib/src/field_registry/init.lua`
- [x] remove `public.registry.widgetHelpers` initialization from `adamant-ModpackLib/src/field_registry/init.lua`
- [x] internalize widget helper exports in `adamant-ModpackLib/src/field_registry/internal/ui.lua`
- [x] simplify `adamant-ModpackLib/src/field_registry/internal/registry.lua` to storage-only registry validation

Notes:
- This phase intentionally cuts the old layout registry path first.
- The old tree UI path is expected to remain incomplete/broken until later phases remove or replace it.
- This branch is an implementation experiment, not a compatibility branch.

### Phase 2 - Remove the node tree public API
- [x] delete old `field_registry/ui.lua`
- [x] remove old tree API import from `field_registry/init.lua`
- [x] cut old prepare/validate/draw tree exports from `field_registry/internal/ui.lua`

### Phase 3 - Rewrite widgets as plain functions
- [x] replace widget registry entries with `lib.widgets.*`
- [x] rewire `field_registry/widgets/*.lua` to write plain widget functions
- [x] initialize `public.widgets` in `field_registry/init.lua`

### Phase 4 - New thin `lib.ui`
- [x] add `lib.ui.verticalTabs`
- [x] add `lib.ui.isVisible`
- [x] restore a new thin `field_registry/ui.lua`

### Phase 5+
- [x] simplify standalone/coordinator rendering
- [x] stop processing `definition.ui` and `definition.customTypes`
- [x] cut dead legacy aliases for removed tree/layout UI symbols
- [x] add `store.getPackedAliases`
- [x] remove `runPass` and `getCachedPreparedNode`
- [x] remove `compat/legacy_api.lua` from the active Lib surface
- [x] shrink `public.registry` back to storage-only
- [ ] migrate modules
- [ ] rewrite tests for the lean surface
- [ ] update Lib docs for the lean surface

Notes:
- `special.standaloneUI` now calls `drawTab(imgui, uiState)` directly and commits dirty state inline.
- The old `def.ui` / `drawTree` fallback is removed from both standalone entrypoints.
- `runDerivedText`, `auditAndResyncState`, and `commitState` now live in `special/standalone.lua`.
- `special/pass.lua` is deleted.
- `store.create(...)` no longer validates or warns on `definition.ui`; the field is ignored on this branch.
- `compat/legacy_api.lua` is removed on this branch. Only the lean namespaces remain active.
- `public.registry.validate` is no longer exported; registry validation runs internally during Lib init.

Remaining known fallout on this branch:
- `adamant-ModpackFramework` still references removed tree/pass APIs.
- `adamant-RunDirector_BoonBans` still references removed prepared-node helpers.
- Lib tests and docs still describe the old tree/layout pipeline.

Next recommended order:
1. migrate one real module against the new surface, preferably Biome Control
2. rewrite Lib tests around `lib.widgets.*`, `lib.ui.verticalTabs`, and `lib.ui.isVisible`
3. update Lib docs after one migration proves the authoring model
