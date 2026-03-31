# Run Director Migration Plan

## Summary

Migrating `purpIe-Run_Director` into the modpack infrastructure is feasible and desirable if it is treated as a gameplay-preserving decomposition, not as an attempt to preserve the monolith's packaging or export format.

Target modules:

- `adamant-RunDirectorGodPool`: regular module, `dataMutation = true`
- `adamant-RunDirectorEncounters`: special module, `dataMutation = true`
- `adamant-RunDirectorBoonBans`: special module, `dataMutation = false`

Locked decisions:

- preserve gameplay coverage, not monolith UI parity
- drop old monolith export/profile strings and use Framework hashes only
- preserve packed-int storage for Encounters and Boon Bans
- move deterministic pre-run data mutation into `apply/revert`
- simplify the monolith's randomized encounter pre-run choices into deterministic rules for v1
- add `int32` and `stepper` to Lib
- do not add `slider` or a compound min/max field type in this phase

## Implementation Changes

### 1. Infrastructure

Add `FieldTypes.int32` in `adamant-ModpackLib` for special-module schema values that must round-trip through Framework hashes but are not Framework-rendered.

Add `FieldTypes.stepper` in `adamant-ModpackLib` as the bounded integer field used by the migration:

- numeric `default`
- numeric `min`
- numeric `max`
- optional `step` defaulting to `1`
- monolith-style `- value +` draw behavior
- hash/staging decode clamps to bounds

Add one small `adamant-ModpackFramework` enhancement so special modules with `definition.dataMutation = true` participate in data-mutation lifecycle the same way regular modules do:

- special enable/disable calls `apply/revert`
- after dirty special-state flush, reapply the module's deterministic data mutation and call `SetupRunData()`
- non-data-mutation specials keep current behavior

### 2. Module creation flow

Create the three repos/submodules with the existing scaffold:

- `python Setup/scaffold/new_module.py --name RunDirectorGodPool --pack-id run-director --namespace adamant --org h2pack-rundirector`
- `python Setup/scaffold/new_module.py --name RunDirectorEncounters --pack-id run-director --namespace adamant --org h2pack-rundirector`
- `python Setup/scaffold/new_module.py --name RunDirectorBoonBans --pack-id run-director --namespace adamant --org h2pack-rundirector`

This yields the intended submodule ids and local paths:

- `Submodules/adamant-RunDirectorGodPool`
- `Submodules/adamant-RunDirectorEncounters`
- `Submodules/adamant-RunDirectorBoonBans`

After scaffolding, replace the template implementation in each repo with the migrated module code.

### 3. God Pool

Implement God Pool as a regular module with flat config:

- per-god booleans
- macro booleans
- `MaxGodsPerRun` as `stepper`
- biome/trial priorities as loot-key dropdowns with `""` meaning none

Use `dataMutation = true` and move deterministic global-table edits into `apply/revert` backed by `createBackupSystem()`:

- early Selene/Hermes requirement injection
- tool element chance overrides

Do not keep bit-31 pooled storage. God Pool and Boon Bans should no longer share storage.

Do not keep a God Pool `StartNewRun` wrapper in v1 unless a later implementation pass finds a true per-run dependency that cannot be handled lazily.

### 4. Encounters

Implement Encounters as a special module with `public.specialState` and `dataMutation = true`.

Keep packed storage in v1:

- `PackedEncounterStatus` as `int32`
- all `PackedXxxMin/Max` as `stepper`
- `NPCSpacing` as `stepper`
- `StrictMode`, `IgnoreMaxDepth` as booleans

Move all pre-run room/data mutation into `apply/revert` with backups. Replace the monolith's random pre-run selection with deterministic rules:

- trial injection uses the first valid room in the existing valid-room list for that biome
- Echo anti-scam logic makes both candidate mini-boss rooms invalid at the target depth

Do not add a compound min/max field type. Encounters should use paired `stepper` fields plus a small module-local helper that preserves `min <= max`.

Do not keep `PreRunStart_Encounters`. Post-run state setup should be encounter-local lazy initialization on `CurrentRun`, using a dedicated key such as `CurrentRun.RunDirector_Encounters_State`.

### 5. Boon Bans

Implement Boon Bans as a special module and build it last.

Keep packed storage in v1:

- all `Packed*` ban keys as `int32`
- all packed rarity keys as `int32`
- `ImproveFirstNBoonRarity` as `stepper`
- `ViewRegion` as `int32`
- padding booleans remain flat

Boon Bans owns:

- the boon metadata/runtime lookup pieces from `god_meta.lua`
- the relevant helpers from `utilities.lua`
- its own `CurrentRun.RunDirector_BoonBans_State`

Keep its two-function reload pattern:

- initial load registers hooks and builds metadata/runtime tables
- reload rebuilds metadata/UI only, without duplicate hook registration

Keep its `StartNewRun` wrapper only for the padding RNG reseed path. That is not data mutation and should not be moved into `apply/revert`.

### 6. Monolith decomposition rules

Do not migrate these monolith shell systems as systems:

- `shared_hooks.lua`
- `profile_manager.lua`
- the standalone monolith window architecture
- the shared `adamant_RunDirector` namespace
- the shared `CurrentRun.RunDirector_StateBackpack`

Replace them with:

- per-module hook ownership
- Framework hash/profile handling
- infrastructure-native hosted and standalone UIs
- one `CurrentRun` state key per migrated module

Ownership split:

- God Pool gets its own tiny static god list / loot-key lookup
- Encounters gets its own extracted encounter definitions
- Boon Bans owns the boon metadata and helper logic it still needs

## Test Plan

### Infrastructure

- unit tests for `FieldTypes.int32`
- unit tests for `FieldTypes.stepper`, including clamping and hash round-trip
- tests that special modules with `dataMutation = true` trigger `apply/revert` and `SetupRunData()` on enable changes and state flushes
- regression coverage that non-data-mutation specials keep current behavior

### Module acceptance

God Pool:

- pool filtering, max-god logic, priority rewards, keepsake behavior, early Selene/Hermes prevention, and first-room hammer still work
- hosted option changes rerun deterministic data mutation correctly

Encounters:

- enable/disable and state edits rerun deterministic room/data mutation correctly
- strict mode, spacing, forced NPC/event behavior, and depth overrides still work
- deterministic trial injection and deterministic Echo anti-scam behavior are stable and documented
- paired min/max steppers preserve valid bounds

Boon Bans:

- bans, tier logic, padding, rarity forcing, spell filtering, NPC-choice filtering, Circe/Judgement handling, and boon-pick tracking still work
- metadata rebuild on hot reload does not duplicate hooks

Integration:

- Framework discovers all three modules under `definition.modpack = "run-director"`
- hosted UI and standalone UI both work
- Framework hashes round-trip for all three modules
- no support is added for old monolith export strings

## Assumptions

- Old monolith export/profile strings are intentionally dropped.
- Gameplay coverage matters more than monolith UI fidelity.
- The deterministic encounter behavior changes are acceptable for v1:
  - first-valid-room trial injection
  - both candidate Echo mini-boss rooms invalid at the target depth
- No automatic migration from the monolith's existing Chalk config is required.
- Hybrid simple/special composition remains out of scope for this migration.
