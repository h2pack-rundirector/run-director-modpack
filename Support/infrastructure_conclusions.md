# Run Director Modpack Infrastructure Conclusions

This document captures the current, source-grounded understanding of the modpack infrastructure in this repository.
It is based on the actual implementation in:

- `adamant-ModpackRunDirectorCore`
- `adamant-ModpackFramework`
- `adamant-ModpackLib`
- Example submodules:
  - `Submodules/adamant-RunModsWorld` (regular module)
  - `Submodules/adamant-FirstHammer` (special module)

It is intended to be the baseline reference before planning additional Run Director modules.

---

## 1. System shape

The infrastructure is a four-layer system:

1. `adamant-ModpackRunDirectorCore`
2. `adamant-ModpackFramework`
3. `adamant-ModpackLib`
4. Individual submodules under `Submodules/`

The coordinator is intentionally thin. The Framework owns discovery, UI orchestration, hash import/export, and HUD fingerprinting. Lib owns shared utilities and the module contract. Modules own their own game logic, hooks, and config schemas.

The key decoupling mechanism is `definition.modpack = "<packId>"`. Framework discovers modules by this value. Modules do not register themselves anywhere.

---

## 2. What the coordinator actually does

Source:
- [main.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackRunDirectorCore/src/main.lua)
- [config.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackRunDirectorCore/src/config.lua)

The coordinator owns only:

- `PACK_ID = "run-director"`
- window title
- Chalk config with:
  - `ModEnabled`
  - `DebugMode`
  - `Profiles`
- `def.NUM_PROFILES`
- `def.defaultProfiles`

The coordinator:

- loads its Chalk config
- calls `Framework.init(...)`
- registers the Framework renderer via `rom.gui.add_imgui(...)`
- registers the Framework menu bar entry via `rom.gui.add_to_menu_bar(...)`
- uses `reload.auto_single()` and calls `loader.load(init, init)`

Important conclusion:

- The coordinator does not own any module orchestration logic.
- The current source already uses a two-function `loader.load(init, init)` form.

---

## 3. What Framework actually owns

Source:
- [main.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackFramework/src/main.lua)
- [discovery.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackFramework/src/discovery.lua)
- [hash.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackFramework/src/hash.lua)
- [hud.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackFramework/src/hud.lua)
- [ui.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackFramework/src/ui.lua)
- [ui_theme.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackFramework/src/ui_theme.lua)

Framework is the real coordinator runtime. `Framework.init(params)` does all of the following:

- obtains Lib from `rom.mods['adamant-ModpackLib']`
- registers the coordinator into Lib via `lib.registerCoordinator(packId, config)`
- imports game globals via `import_as_fallback(rom.game)`
- preserves a stable per-pack HUD stack index across reloads
- creates fresh subsystem instances:
  - discovery
  - hash
  - theme
  - hud
  - ui
- runs discovery before HUD/UI creation
- stores pack instances in a late-bound `_packs[packId]` table

Public API:

- `public.init`
- `public.getRenderer(packId)`
- `public.getMenuBar(packId)`

Important conclusion:

- GUI registration is done by the coordinator, but the underlying runtime behavior lives in Framework.
- Framework is designed to be reinitialized on hot reload without re-registering GUI callbacks.

---

## 4. Discovery contract

Source:
- [discovery.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackFramework/src/discovery.lua)

Framework discovery scans `rom.mods` and selects entries where:

- `type(mod) == "table"`
- `mod.definition` exists
- `mod.definition.modpack == packId`

Two module classes exist:

### Regular modules

Required:

- `definition.id`
- `definition.apply`
- `definition.revert`

Optional but expected:

- `definition.name`
- `definition.category`
- `definition.group`
- `definition.tooltip`
- `definition.default`
- `definition.options`
- `definition.dataMutation`

### Special modules

Required:

- `definition.name`
- `definition.apply`
- `definition.revert`
- `definition.special = true`

Optional but expected:

- `definition.tabLabel`
- `definition.tooltip`
- `definition.stateSchema`

Discovery behavior that matters:

- modules are sorted alphabetically by display name
- categories are sorted alphabetically
- group layout inside categories is built automatically
- `def.options` for regular modules must use flat string `configKey`s
- table-path `configKey`s in regular options are warned and skipped
- `stateSchema` for special modules is validated if present
- duplicate special tab labels are automatically suffixed as `"Name (1)"`, `"Name (2)"`, etc.

Important conclusion:

- Regular modules and special modules have different config-key rules.
- Nested path keys are valid only in `stateSchema`, not in `definition.options`.

---

## 5. Hash and profile contract

Source:
- [hash.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackFramework/src/hash.lua)
- [TestHash.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackFramework/tests/TestHash.lua)

Framework uses a canonical key-value hash format:

```text
_v=1|ModId=1|ModId.Option=value|adamant-SpecialMod.Field=value
```

Real implementation guarantees:

- keys are sorted alphabetically for stable output
- only non-default values are encoded
- boolean modules encode enabled state only if it differs from `definition.default`
- special modules encode enabled state only if enabled
- special-module state fields encode only when current value differs from `field.default`
- import resets any missing field back to its declared default
- unknown keys are ignored
- `_v` must exist or the hash is rejected

Important compatibility rule:

- Defaults are part of the public contract.

If you change:

- `definition.id`
- an option `configKey`
- a special-module `stateSchema` key
- a field default

you are changing hash behavior, profile restore behavior, or both.

Important implementation detail:

- `GetConfigHash(source)` can read regular-module state from a passed staging source.
- For special-module schema fields, it reads from `special.mod.config`.
- Framework now owns the hosted flush boundary for specials, so special-module UI no longer has to call a Framework callback to keep hashes correct.

---

## 6. HUD behavior

Source:
- [hud.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackFramework/src/hud.lua)

Framework HUD behavior:

- computes a 12-character fingerprint from the canonical config hash
- displays that fingerprint in a HUD component named `ModpackMark_<packId>`
- stacks multiple packs vertically using the pack index
- updates the displayed text only when the fingerprint changes
- clears the HUD marker when the coordinator `ModEnabled` is false

Important conclusion:

- The visible HUD text is not the shareable hash.
- It is only a fingerprint of the hash.

---

## 7. UI staging model

Source:
- [ui.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackFramework/src/ui.lua)

Framework UI uses a staging cache:

- `staging.ModEnabled`
- `staging.modules[module.id]`
- `staging.options[module.id][configKey]`
- `staging.specials[special.modName]`
- `staging.debug[...]`

Profile data has a separate `profileStaging`.

Framework snapshots from Chalk/module config into staging at init and after profile load.

The render loop reads staging, not Chalk.

Event handlers write to Chalk/config only when the user makes a change.

Important conclusion:

- The staging pattern is not optional. It is the central UI model.
- Any module UI that reads or writes Chalk/config directly in its render path is violating the current system design.

---

## 8. Master toggle behavior

Source:
- [ui.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackFramework/src/ui.lua)
- [main.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackLib/src/main.lua)

There are two levels of enablement:

1. coordinator-level `config.ModEnabled`
2. per-module `config.Enabled`

`lib.isEnabled(modConfig, packId)` returns true only if:

- the module's own `Enabled` is true
- and the coordinator's `ModEnabled` is true, if a coordinator is registered for that `packId`

The Framework master toggle:

- updates only coordinator `config.ModEnabled`
- does not rewrite each module's `config.Enabled`
- re-applies or reverts game-side state according to staged module selections

Important conclusion:

- Turning the pack off preserves individual module selections.
- Modules should gate runtime behavior with `lib.isEnabled(config, packId)`, not with `config.Enabled` alone.

---

## 9. What Lib actually provides

Source:
- [main.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackLib/src/main.lua)
- [config.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackLib/src/config.lua)

Lib currently provides:

- `registerCoordinator(packId, config)`
- `isCoordinated(packId)`
- `isEnabled(modConfig, packId)`
- `warn(packId, enabled, msg)`
- `log(name, enabled, msg)`
- `createBackupSystem()`
- `standaloneUI(def, config, apply, revert)`
- `readPath(tbl, key)`
- `writePath(tbl, key, value)`
- `drawField(imgui, field, value, width)`
- `validateSchema(schema, label)`
- `createSpecialState(config, schema)`
- `FieldTypes`

Lib debug state is stored in its own Chalk config:

- [config.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackLib/src/config.lua)

Important conclusion:

- Lib has no pack-specific knowledge beyond coordinator registrations keyed by `packId`.
- That is the mechanism that keeps modules decoupled from coordinator repo names or Thunderstore IDs.

---

## 10. Special module state model

Source:
- [main.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackLib/src/main.lua)
- [TestSpecialState.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackLib/tests/TestSpecialState.lua)

`lib.createSpecialState(config, schema)`:

- validates the schema
- builds a private staging table
- copies config into that staging table using each field type's `toStaging`
- returns a managed `specialState` object with:
  - `view`
  - `get(path)`
  - `set(path, value)`
  - `update(path, fn)`
  - `toggle(path)`
  - `reloadFromConfig()`
  - `flushToConfig()`
  - `isDirty()`

Nested config keys are supported through:

- `readPath`
- `writePath`

Examples:

- `"Mode"`
- `{ "FirstHammers", "BaseStaffAspect" }`

Important conclusion:

- Special-module nested configuration is already a real supported pattern in source and tests.
- It is not speculative.
- The managed `specialState` object is now the required special-module UI contract.

---

## 11. Current field types

Source:
- [main.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackLib/src/main.lua)
- [TestFieldTypes.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackLib/tests/TestFieldTypes.lua)

Current field types in Lib are:

- `checkbox`
- `dropdown`
- `radio`

Each field type defines:

- `validate`
- `toHash`
- `fromHash`
- `toStaging`
- `draw`

Important conclusion:

- There is currently no `int32` field type in source.
- Any plan that depends on `int32` is proposing a real infrastructure change, not using an existing feature.

---

## 12. Standalone mode is part of the contract

Source:
- [main.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/Submodules/adamant-RunModsWorld/src/main.lua)
- [main.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/Submodules/adamant-FirstHammer/src/main.lua)
- [main_special.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/Submodules/adamant-RunModsWorld/src/main_special.lua)

Regular modules:

- use `lib.standaloneUI(...)`
- hide that UI when `lib.isCoordinated(packId)` is true

Special modules:

- render their own standalone window
- hide that window when `lib.isCoordinated(packId)` is true

Important conclusion:

- Standalone mode is not an optional extra.
- Existing module patterns assume every module remains usable without the coordinator.

---

## 13. Real regular-module example: `adamant-RunModsWorld`

Source:
- [main.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/Submodules/adamant-RunModsWorld/src/main.lua)
- [config.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/Submodules/adamant-RunModsWorld/src/config.lua)

This module shows the real regular-module pattern:

- uses flat config keys
- exposes `definition.options = option_fns`
- uses `definition.default = true`
- uses `definition.dataMutation = true`
- registers hooks once on load
- conditionally calls `apply()` if enabled
- calls `SetupRunData()` itself only in standalone mode
- uses `lib.standaloneUI(...)`

Important conclusion:

- The regular-module path is suited to flat option sets and Framework-rendered controls.

---

## 14. Real special-module example: `adamant-FirstHammer`

Source:
- [main.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/Submodules/adamant-FirstHammer/src/main.lua)
- [config.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/Submodules/adamant-FirstHammer/src/config.lua)

This module shows the real special-module pattern:

- declares `definition.special = true`
- sets `tabLabel`
- builds `definition.stateSchema` after data tables are available
- uses nested path keys in `stateSchema`
- gets `public.specialState` from `lib.createSpecialState(...)`
- exposes `DrawTab(ui, specialState, theme)`
- exposes `DrawQuickContent(ui, specialState, theme)`
- renders its own standalone window

Most important UI rule shown by the example:

- special-module UI reads from `specialState.view`
- special-module UI mutates via `specialState.set/update/toggle`
- Framework flushes once after hosted draw if `specialState.isDirty()` is true
- standalone special windows flush after draw if `specialState.isDirty()` is true

Important conclusion:

- `adamant-FirstHammer` is effectively the best in-repo reference for future Run Director special modules.

---

## 15. Hot reload behavior

Source:
- [main.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/adamant-ModpackFramework/src/main.lua)
- [main.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/Submodules/adamant-RunModsWorld/src/main.lua)
- [main.lua](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/Submodules/adamant-FirstHammer/src/main.lua)

Observed pattern:

- Framework is intended to be recreated on reload.
- GUI callbacks remain stable via late binding to the latest pack instance.
- Modules use `reload.auto_single()`.
- Hook registration is expected to happen inside the loader callback.

Important caution:

- If a module uses reload patterns that re-import data files but also re-register hooks, it must do so carefully to avoid duplicate wraps.

This is a module-level concern, not something Framework automatically solves.

---

## 16. Rules that should be treated as hard constraints

These are the most important conclusions to preserve in future planning:

1. Modules are discovered only through `definition.modpack = packId`.
2. Runtime gating should use `lib.isEnabled(config, packId)`.
3. Regular-module options must use flat string `configKey`s.
4. Nested/path keys belong in special-module `stateSchema`.
5. Special-module UI must use `public.specialState.view` for schema-backed render reads.
6. Special-module UI must mutate schema-backed state through `public.specialState.set/update/toggle`, not by writing `config` directly during draw.
7. Hash defaults are part of the compatibility contract.
8. Renaming `definition.id`, option keys, or special state keys is a breaking change for profiles/hashes.
9. Standalone mode is part of the expected module contract.
10. `int32` does not currently exist and would be a real Lib extension.

---

## 17. Open documentation mismatches

These do not change the implementation, but they are worth remembering:

- Some docs and comments vary between `adamant-ModpackLib` and `adamant-Modpack_Lib` naming.
- The docs discuss single-function vs two-function `loader.load(...)` patterns, but the live coordinator already uses the two-argument form.
- Some markdown files in the repo display mojibake characters, so textual examples should not be trusted more than source.

---

## 18. Working baseline for future Run Director planning

Before designing any Run Director migration, the working assumption should be:

- If the configuration is flat and Framework can render it, use a regular module.
- If the configuration is structured, large, nested, or needs a custom tab, use a special module.
- If a proposed design requires a field type not in Lib today, that proposal includes infrastructure work.
- Any migration plan should be checked against the `adamant-FirstHammer` pattern for special modules and the `adamant-RunModsWorld` pattern for regular modules.
- For special modules, treat `public.specialState` as the UI state boundary and `config` as persistence, not the object you should write during draw.

This document should be treated as the implementation baseline until the infrastructure source changes.
