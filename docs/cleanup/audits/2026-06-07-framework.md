# Framework Audit

## Purpose

`adamant-ModpackFramework` coordinates a pack-level UI, module discovery, profile/hash loading, HUD hash display, and pack enable/disable behavior over Lib-published live modules.

## Surfaces

- Author:
  - `Framework.registerCoordinator(packId, config, rebuildCallback?)`
  - `Framework.createPack(packId, windowTitle, config, numProfiles, defaultProfiles, opts?)`
  - `Framework.createGuiCallbacks(packId)`
- Framework/module:
  - Lib live-module methods such as `getPackId`, `getModuleId`, `getStorage`, `drawTab`, `drawQuickContent`, `setEnabled`, `commitIfDirty`, and pack-suspension lifecycle calls.
- Internal:
  - module registry snapshots
  - UI runtime state transitions
  - hash/profile codec and application pipeline
  - HUD overlay runtime
- Tests-only:
  - constructor injection through `CreateFrameworkHarness`
  - mock module registry and Lib live-module helpers.

## Call Graph

- `src/main.lua` creates the Lib framework runtime and imports `core/init.lua`.
- `core/init.lua` composes logging, hash codec, profile audit, module registry, config hash, HUD, theme, UI, and pack bootstrap.
- `core/pack_bootstrap.lua` validates coordinator inputs, builds the module registry/hash/HUD/UI runtimes, publishes pack state, and replaces existing pack instances safely.
- `core/ui/window.lua` owns render lifecycle and delegates state transitions to `core/ui/runtime.lua`.
- `core/modules/registry.lua` is the single discovery boundary over Lib live modules.

Dependency direction is clean: Framework depends on Lib live-module/runtime surfaces, and module code does not call Framework internals.

## State Ownership

- Owns:
  - coordinator UI staging (`ModEnabled`, per-module enable/debug mirrors)
  - cached config hash/fingerprint
  - pending run-data dirty flag
  - active pack registry entries
- Reads:
  - Chalk coordinator config
  - Lib live-module persisted state and metadata
  - Lib framework runtime modules/overlays/hashing/diagnostics
- Writes:
  - coordinator config `ModEnabled`
  - module enabled/debug/storage through live-module lifecycle methods
  - profile slots through coordinator config

## Lifecycle

- Declaration: coordinator registers itself with `registerCoordinator`.
- Activation/startup: `createPack` validates inputs, refreshes live-module discovery, audits saved profiles, installs HUD, and replaces prior pack UI if present.
- UI draw: `window.lua` snapshots live modules per UI operation, renders pack tabs, and commits dirty module state after module draw surfaces.
- Commit: `ui/runtime.lua` centralizes module toggles, profile load, reset, hash invalidation, and run-data flushing.
- Runtime: Framework does not run module runtime logic directly; it coordinates Lib live-module lifecycle methods.
- Reload: repeated `createPack` replaces the pack runtime while preserving its stable pack index/HUD slot.
- Teardown: old pack UI is disposed before replacement and GUI close releases overlay suppression.

## Findings

### Runtime And Profile Coordination Is Still Load-Bearing

- Rating: leave alone
- Evidence:
  - `core/ui/runtime.lua` owns pack toggle rollback, quick setup batch rollback, profile load, module reset, commit, and run-data flushing.
  - `tests/TestMain.lua` covers these transitions, including rollback and reset paths.
- Impact:
  - Splitting this file by operation would add more cross-file state threading without removing a stale abstraction.
- Recommendation:
  - Keep the current runtime coordinator file. Future cleanup should be behavior-driven, not generic size reduction.

### UI/HUD Boundaries Are Small And Coherent

- Rating: leave alone
- Evidence:
  - `core/ui/window.lua` owns render lifecycle, overlay suppression, and ImGui stack cleanup.
  - `core/hud/runtime.lua` owns only Framework hash marker display.
- Impact:
  - The xpcall render guard is useful here because Framework renders multiple pack/module surfaces through one window.
- Recommendation:
  - Keep UI/HUD files as-is. Do not split the render guard into fallback UI-style behavior.

### Module Examples Used Old `bind(data)` Composition

- Rating: safe cleanup
- Evidence:
  - `README.md` and `QUICK_SETUP.md` showed `import("mods/logic.lua").bind(data)` and `import("mods/ui.lua").bind(data)`.
- Impact:
  - New modules now use explicit dependency injection with `local deps = ...`; the old example made Framework docs lag behind current module style.
- Recommendation:
  - Update examples to import with explicit dependency tables and use a generic `logic.register(module)` entrypoint.

### Private Helper Naming Was Inconsistent

- Rating: safe cleanup
- Evidence:
  - `core/hash/config_hash.lua`, `core/modules/registry.lua`, and `core/pack_bootstrap.lua` mixed PascalCase private helpers with lower-camel locals.
- Impact:
  - This was style debt only, but it made private helpers look more public or method-like than they are.
- Recommendation:
  - Normalize private helpers in those files to lower camel case. Keep public object methods such as `ConfigHash.GetConfigHash` and `ConfigHash.ApplyConfigHash` unchanged.

## Deferred Questions

- `TextColored` is duplicated in a few UI files. The helper is tiny and local to ImGui call sites, so centralizing it would add another shared UI dependency for little value.
