# Run Director Monolith Conclusions

This document captures the current, source-grounded understanding of the existing `purpIe-Run_Director` monolith.
It is based on:

- [README.md](/d:/Work/win-projects/modding/modpacks/rundirector/purpIe-Run_Director/README.md)
- [main.lua](/d:/Work/win-projects/modding/modpacks/rundirector/purpIe-Run_Director/src/main.lua)
- [config.lua](/d:/Work/win-projects/modding/modpacks/rundirector/purpIe-Run_Director/src/config.lua)
- all files in `purpIe-Run_Director/src/mods/`

The goal is to document what the monolith actually is before making migration decisions.

---

## 1. What the monolith is

`purpIe-Run_Director` is a single standalone mod that bundles three major gameplay systems plus its own UI and profile/export machinery:

1. macro logic
2. micro logic
3. encounter logic
4. standalone UI
5. standalone profile serialization

It is not just a collection of independent files. It is a shared-state system centered on one global namespace:

- `adamant_RunDirector`

Most files treat that global namespace as a shared service container.

---

## 2. Entrypoint structure

Source:
- [main.lua](/d:/Work/win-projects/modding/modpacks/rundirector/purpIe-Run_Director/src/main.lua)

The entrypoint does the following:

- initializes `adamant_RunDirector`
- loads Chalk config into global `config`
- defines two loader phases:
  - `on_ready()`
  - `on_reload()`
- uses `reload.auto_single()`
- calls `loader.load(on_ready, on_reload)`

`on_ready()` loads:

1. `god_meta.lua`
2. `utilities.lua`
3. `logic_macro.lua`
4. `logic_micro_others.lua`
5. `logic_micro_core.lua`
6. `logic_encounter.lua`
7. `profile_manager.lua`
8. `shared_hooks.lua`

`on_reload()` reloads:

- `god_meta.lua`
- `ui.lua`

Important conclusion:

- The monolith is split into data/helpers/logic/UI files, but they are not independent modules.
- Initialization order matters.
- `god_meta.lua` is foundational enough that it is explicitly rebuilt on reload.

---

## 3. High-level feature split

From the README and source, the monolith has three real feature domains:

### 3.1 Macro logic

Source:
- [logic_macro.lua](/d:/Work/win-projects/modding/modpacks/rundirector/purpIe-Run_Director/src/mods/logic_macro.lua)

Owns:

- god pool filtering
- max gods per run
- keepsake override behavior
- biome priority god rewards
- trial priority god rewards
- early Selene/Hermes prevention
- forced first-room hammer

### 3.2 Micro logic

Source:
- [logic_micro_core.lua](/d:/Work/win-projects/modding/modpacks/rundirector/purpIe-Run_Director/src/mods/logic_micro_core.lua)
- [logic_micro_others.lua](/d:/Work/win-projects/modding/modpacks/rundirector/purpIe-Run_Director/src/mods/logic_micro_others.lua)

Owns:

- per-boon packed bans
- tier-aware boon filtering
- menu padding
- rarity forcing
- spell filtering
- NPC boon choice filtering
- Circe and Judgement filtering
- per-run boon pick tracking

### 3.3 Encounter logic

Source:
- [logic_encounter.lua](/d:/Work/win-projects/modding/modpacks/rundirector/purpIe-Run_Director/src/mods/logic_encounter.lua)

Owns:

- encounter forcing
- encounter enabled-state bitfield
- min/max biome depth overrides
- strict mode
- NPC spacing
- pre-run room-set mutations
- post-run pending/seen encounter state

Important conclusion:

- The actual gameplay split in the monolith already maps fairly cleanly into macro, micro, and encounter domains.
- The main migration challenge is not feature discovery. It is uncoupling shared config/state/UI/profile machinery.

---

## 4. The config shape

Source:
- [config.lua](/d:/Work/win-projects/modding/modpacks/rundirector/purpIe-Run_Director/src/config.lua)

The config is one large mixed namespace containing:

- global toggles
- macro settings
- micro settings
- encounter settings
- packed per-feature data
- profile storage

Top-level control flags:

- `ModEnabled`
- `DebugMode`
- `EnableGodPool`
- `EnableBanManager`
- `EnableEncounterManager`

Then several groups:

- macro settings like `MaxGodsPerRun`, `PackedPriorityB1`, etc.
- micro packed ban keys like `PackedAphrodite1`, `PackedStaff1`, `PackedChaosBuff`, etc.
- encounter packed state like `PackedEncounterStatus` and all `PackedXxxMin/Max`
- profile serialization state:
  - `PackedSettings`
  - `profileCode_1`..`profileCode_5`
  - `profileName_1`..`profileName_5`

Important conclusion:

- The config is not namespaced by feature.
- Serialization, UI, and feature logic all depend on this one shared keyspace.

---

## 5. `god_meta.lua` is the central data spine

Source:
- [god_meta.lua](/d:/Work/win-projects/modding/modpacks/rundirector/purpIe-Run_Director/src/mods/god_meta.lua)

This file is more than metadata. It constructs core runtime lookup tables for the entire mod.

It builds:

- `Utils.godMeta`
- `Utils.lootKeyLookup`
- `Utils.priorityLabels`
- `Utils.priorityValues`
- `Utils.encounterDefinitions`
- `Utils.encounterLookup`

It also:

- calculates dynamic bit widths for packed ban masks by inspecting game data
- defines grouping/sorting metadata used by the UI
- attaches rarity-variable mappings to relevant entries

Important conclusion:

- `god_meta.lua` is currently doing work for both micro and encounter systems.
- It is not a passive data file. It actively derives runtime structure from live game data.

---

## 6. `utilities.lua` is a mixed helper layer

Source:
- [utilities.lua](/d:/Work/win-projects/modding/modpacks/rundirector/purpIe-Run_Director/src/mods/utilities.lua)

This file mixes helpers for multiple domains:

### Macro-related helpers

- `IsGodEnabledInPool`
- `SetGodPoolStatus`

### Micro-related helpers

- `SetBanConfig`
- `GetBanConfig`
- rarity get/set/reset helpers

### Encounter-related helpers

- `IsDefinitionActive`
- `SetDefinitionActive`

### Shared run-state helper

- `GetRunState`

### Generic helpers

- `ListContainsEquivalent`

Important conclusion:

- `utilities.lua` is not a reusable neutral library.
- It is monolith glue that assumes shared config, shared metadata, and shared run-state.

---

## 7. The run-state model

Source:
- [utilities.lua](/d:/Work/win-projects/modding/modpacks/rundirector/purpIe-Run_Director/src/mods/utilities.lua)

Per-run state lives in:

- `CurrentRun.RunDirector_StateBackpack`

That one table holds all domains:

### Macro

- `EnabledGodsOverride`
- `MaxGodsPerRunOverride`
- `BiomePrioritySatisfied`

### Micro

- `BoonPickCounts`
- `ImproveFirstNBoonRarity`

### Encounter

- `ForcedNPCPending`
- `EncounterSeen`
- `EncounterStrictMode`

Important conclusion:

- The monolith uses one mixed per-run backpack for all features.
- The state fields are already logically grouped, so separation is possible, but it has not been done in code.

---

## 8. The most important cross-feature coupling: packed god ints

Source:
- [utilities.lua](/d:/Work/win-projects/modding/modpacks/rundirector/purpIe-Run_Director/src/mods/utilities.lua)
- [logic_macro.lua](/d:/Work/win-projects/modding/modpacks/rundirector/purpIe-Run_Director/src/mods/logic_macro.lua)
- [logic_micro_core.lua](/d:/Work/win-projects/modding/modpacks/rundirector/purpIe-Run_Director/src/mods/logic_micro_core.lua)

This is the strongest monolith coupling:

- bit 31 of packed god config values is used as the macro god-pool enabled flag
- lower bits of the same integer are used as the micro boon-ban mask

Specifically:

- macro reads/writes pool membership through `IsGodEnabledInPool` and `SetGodPoolStatus`
- micro reads/writes ban masks through `GetBanConfig` and `SetBanConfig`

These are operating on the same underlying `PackedAphrodite1`, `PackedApollo1`, etc. values.

Important conclusion:

- Macro and micro are not merely adjacent features. They are coupled in storage.
- Any migration that separates them must explicitly replace this storage model.

---

## 9. Macro logic details

Source:
- [logic_macro.lua](/d:/Work/win-projects/modding/modpacks/rundirector/purpIe-Run_Director/src/mods/logic_macro.lua)

Macro logic is gated by:

- `config.ModEnabled and config.EnableGodPool`

Main hooks:

- `GetEligibleLootNames`
- `ReachedMaxGods`
- `GiveLoot`
- `SetupRoomReward`
- `SpawnRoomReward`

Also exposes:

- `Utils.PreRunStart_Macro()`

Key behavior:

- filters eligible god loot by pool membership
- supports per-run override state from keepsakes
- forces priority gods for biome and trial rewards
- tracks when biome priority has been satisfied
- can force first-room hammer via `SpawnRoomReward`
- injects requirement changes to prevent early Selene/Hermes

Important conclusion:

- Macro logic is mostly self-contained apart from shared metadata and the packed-int storage coupling.

---

## 10. Micro logic details

Source:
- [logic_micro_core.lua](/d:/Work/win-projects/modding/modpacks/rundirector/purpIe-Run_Director/src/mods/logic_micro_core.lua)
- [logic_micro_others.lua](/d:/Work/win-projects/modding/modpacks/rundirector/purpIe-Run_Director/src/mods/logic_micro_others.lua)

Micro logic is gated by:

- `config.ModEnabled and config.EnableBanManager`

There are two large pieces:

### 10.1 Core boon-menu filtering

Main hooks:

- `GetEligibleUpgrades`
- `GetReplacementTraits`
- `SetTraitsOnLoot`
- `IsTraitEligible`
- `GiveRandomHadesBoonAndBoostBoons`

Behavior:

- computes allowed vs banned options from packed masks
- applies tier-aware filtering using boon pick counts
- generates padded queues when necessary
- can force rarity on allowed boons
- handles duo/legendary queue correction

### 10.2 Other loot systems and runtime data

Main responsibilities:

- build `godInfo` runtime tables from game data
- maintain trait lookup structures
- track per-run boon counts
- Circe and Judgement filtering
- spell filtering
- NPC boon choice filtering
- active loot-source tracking
- `GetRarityChances` override for early boon rarity improvement

Important conclusion:

- Micro logic is the most complex part of the monolith.
- It depends heavily on:
  - `god_meta.lua`
  - shared run state
  - packed mask storage
  - UI-visible runtime data in `godInfo`

---

## 11. Encounter logic details

Source:
- [logic_encounter.lua](/d:/Work/win-projects/modding/modpacks/rundirector/purpIe-Run_Director/src/mods/logic_encounter.lua)

Encounter logic is gated by:

- `config.ModEnabled and config.EnableEncounterManager`

It has a real two-phase model:

### Pre-run phase

- `Utils.PreRunStart_Encounters()`

Runs before `CurrentRun` exists and mutates shared game data:

- room depth settings
- trial injections
- spacing requirements
- Echo-related room adjustments

### Post-run phase

- `Utils.PostRunStart_Encounters()`

Runs after `CurrentRun` exists and initializes per-run state:

- pending NPC tables
- seen encounter tracking
- strict-mode flag

Main runtime hooks:

- `ChooseEncounter`
- `Begin<Encounter>Encounter` wrappers for encounter tracking

Important conclusion:

- Encounter logic is structurally the cleanest of the three domains.
- It already has a clear pre-run/post-run separation.

---

## 12. `shared_hooks.lua` is monolith orchestration glue

Source:
- [shared_hooks.lua](/d:/Work/win-projects/modding/modpacks/rundirector/purpIe-Run_Director/src/mods/shared_hooks.lua)

This file wraps `StartNewRun` and coordinates:

1. debug logging
2. RNG reseeding
3. macro pre-run setup
4. encounter pre-run setup
5. base game `StartNewRun`
6. run-state initialization
7. encounter post-run setup

Important conclusion:

- This file is not feature logic on its own.
- It is the monolith-level sequencing layer for shared startup concerns.

The RNG reseeding currently lives here, which means it is shared by the whole mod even though it may only exist to support part of the micro padding behavior.

---

## 13. `profile_manager.lua` is monolith-only serialization infrastructure

Source:
- [profile_manager.lua](/d:/Work/win-projects/modding/modpacks/rundirector/purpIe-Run_Director/src/mods/profile_manager.lua)

This file implements a custom export/import pipeline:

- pack all `Packed*` keys as int32 binary
- RLE compress
- Base64 encode

It also packs loose booleans/ints into `PackedSettings` using a hand-maintained registry.

Important consequences:

- serialization depends on the exact set and order of packed keys
- `GlobalSettingsRegistry` order is part of backward compatibility
- profiles are tightly coupled to the monolith config layout

Important conclusion:

- This entire subsystem exists because the monolith stores feature state in packed ints and loose globals.
- It is packaging/serialization infrastructure, not gameplay logic.

---

## 14. `ui.lua` is tightly coupled to monolith internals

Source:
- [ui.lua](/d:/Work/win-projects/modding/modpacks/rundirector/purpIe-Run_Director/src/mods/ui.lua)

This file is not a thin view layer. It depends directly on:

- packed config variables
- `godMeta`
- `godInfo`
- `lootKeyLookup`
- profile serialization APIs
- encounter definitions
- pooled cached state for UI performance

It owns:

- standalone ImGui window rendering
- standalone menu-bar rendering
- all tabs:
  - Run Setup
  - Encounters
  - Boon Bans
  - Profiles
  - Settings

It directly edits config and packed values, including:

- god pool toggles
- priority indices
- encounter activation
- boon bans and rarity flags
- profile storage

Important conclusion:

- `ui.lua` is deeply monolith-specific.
- It should be treated as a source of feature-specific interaction patterns, not as a transferable UI architecture.

---

## 15. What belongs to gameplay logic vs monolith shell

This distinction matters for migration planning.

### Real gameplay logic

- macro hooks and helper flow
- micro filtering, padding, rarity, spell/NPC/Circe/Judgement logic
- encounter forcing and strict-mode logic
- metadata derivation needed by those systems

### Monolith shell / packaging logic

- shared global namespace wiring
- single mixed config surface
- combined run-state backpack
- standalone monolith window
- standalone profile serialization format
- `shared_hooks.lua` sequencing as a central monolith concern

Important conclusion:

- A migration should preserve gameplay behavior, not monolith shell structure.

---

## 16. Existing natural seams in the monolith

The monolith already suggests several separations:

### Natural seam 1: Macro

- `logic_macro.lua`
- macro-related pieces of `utilities.lua`
- priority data from `god_meta.lua`

### Natural seam 2: Micro

- `logic_micro_core.lua`
- `logic_micro_others.lua`
- runtime boon metadata from `god_meta.lua`
- packed ban and rarity helpers from `utilities.lua`

### Natural seam 3: Encounters

- encounter section of `god_meta.lua`
- encounter helpers from `utilities.lua`
- `logic_encounter.lua`

### Natural seam 4: Monolith-only support

- `shared_hooks.lua`
- `profile_manager.lua`
- `ui.lua`

Important conclusion:

- The feature split is already visible in source.
- The hard part is untangling shared storage and shared support code, not inventing new boundaries.

---

## 17. Main migration risks implied by the monolith

These are the key risk areas any migration plan has to address:

1. Packed god ints currently combine macro pool flags and micro ban masks.
2. `god_meta.lua` serves both micro and encounter domains.
3. `utilities.lua` mixes domain helpers and shared run state.
4. `shared_hooks.lua` centralizes startup sequencing across features.
5. `profile_manager.lua` assumes the monolith packed-config format.
6. `ui.lua` assumes one shared monolith config and one window.

Important conclusion:

- Most migration work is about replacing shared shell mechanisms with infrastructure-native ones.
- The raw gameplay hook logic is not the main blocker.

---

## 18. Hard facts that should guide future discussion

These should be treated as established facts from source:

1. The monolith has three real gameplay domains: macro, micro, and encounters.
2. Macro and micro are coupled through shared packed god integers.
3. Encounter logic already has a clean two-phase pre-run/post-run shape.
4. `god_meta.lua` is both boon metadata and encounter metadata.
5. `utilities.lua` is monolith glue, not a clean shared library.
6. `shared_hooks.lua`, `profile_manager.lua`, and `ui.lua` are monolith shell code.
7. The profile format is designed around `Packed*` keys and `PackedSettings`, not around the new Framework hash model.

---

## 19. Working baseline for future migration planning

Before evaluating any migration design, the working assumption should be:

- preserve feature behavior
- do not preserve monolith packaging just because it exists
- treat packed-int coupling, shared run-state, and custom profile serialization as monolith implementation artifacts unless a feature still truly needs them under the new infrastructure

This document should be used alongside:

- [infrastructure_conclusions.md](/d:/Work/win-projects/modding/modpacks/rundirector/run-director-modpack/Support/infrastructure_conclusions.md)

Together they provide the baseline needed to discuss migration from source rather than from memory.
