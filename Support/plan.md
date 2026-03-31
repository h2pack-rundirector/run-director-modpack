# Run Director — Migration Plan

Migrating `purpIe-Run_Director` from a monolithic standalone mod into three special modules
that plug into the `run-director-modpack` infrastructure (Framework + Lib).

---

## Overview

| Module | Thunderstore GUID | Type | Source |
|---|---|---|---|
| God Pool | `adamant-RunDirector-GodPool` | special | `logic_macro.lua` |
| Boon Bans | `adamant-RunDirector-BoonBans` | special | `logic_micro_*.lua` + `god_meta.lua` |
| Encounters | `adamant-RunDirector-Encounters` | special | `logic_encounter.lua` |

Each becomes its own git repo under `Submodules/`.

**Replaced entirely by Framework:**
- `shared_hooks.lua` — each module registers its own `StartNewRun` wrap
- `profile_manager.lua` — Framework hash handles export/import
- `ui.lua` (standalone window) — each module exposes `DrawTab` / `DrawQuickContent`

---

## Prerequisite: Add `int32` field type to Lib

**File:** `adamant-ModpackLib/src/main.lua`
**Where:** Add after `FieldTypes.radio = { ... }` block, before `public.FieldTypes = FieldTypes`

```lua
-- Hash-only field type for 32-bit packed integers and small integers with custom UI.
-- No draw widget — the module renders these via DrawTab.
FieldTypes.int32 = {
    validate  = function(field, prefix) end,
    toHash    = function(_, value)  return tostring(value or 0) end,
    fromHash  = function(_, str)    return tonumber(str) or 0 end,
    toStaging = function(val)       return tonumber(val) or 0 end,
    draw      = function(_, _, value) return value, false end,  -- no-op widget
}
```

This type is needed by BoonBans and Encounters to participate in the Framework hash pipeline for packed-integer config values.

---

## Module 1: God Pool (`adamant-RunDirector-GodPool`)

### What it owns
God pool filtering (which Olympians are in the run), max god limit, biome priority forcing,
keepsake adds god, prevent early Selene/Hermes, hammer first room.

### File structure
```
Submodules/adamant-RunDirector-GodPool/
  src/
    main.lua        — ENVY wiring, definition, staging setup, loader
    config.lua      — Chalk schema (flat booleans, no packed ints)
    mods/
      data.lua      — static god list + loot key lookup (replaces god_meta.lua for macro)
      logic.lua     — hooks (adapted from logic_macro.lua)
      ui.lua        — DrawTab + DrawQuickContent (adapted from ui.lua Run Setup tab)
```

### `src/config.lua`

All values flat. Per-god enabled state stored as individual booleans (not packed in bit 31).
Priority stored as loot-key strings (e.g. `"AphroditeUpgrade"`, `""` = None).

```lua
return {
    Enabled  = false,
    DebugMode = false,

    -- Pool settings
    MaxGodsPerRun                   = 4,
    KeepsakeAddsGod                 = false,
    PreventEarlySeleneHermes        = false,
    PrioritizeSpecificRewardEnabled = false,
    PrioritizeTrialRewardEnabled    = false,
    PrioritizeHammerFirstRoomEnabled = false,

    -- Per-god pool (true = included in the pool)
    AphroditeEnabled  = true,
    ApolloEnabled     = true,
    AresEnabled       = true,
    DemeterEnabled    = true,
    HephaestusEnabled = true,
    HeraEnabled       = true,
    HestiaEnabled     = true,
    PoseidonEnabled   = true,
    ZeusEnabled       = true,

    -- Biome priority god (loot key string, "" = none)
    PriorityBiome1 = "",
    PriorityBiome2 = "",
    PriorityBiome3 = "",
    PriorityBiome4 = "",
    PriorityTrial1 = "",
    PriorityTrial2 = "",
}
```

### `src/main.lua` structure

```lua
local mods = rom.mods
mods['SGG_Modding-ENVY'].auto()
rom = rom; _PLUGIN = _PLUGIN; game = rom.game
modutil = mods['SGG_Modding-ModUtil']
chalk   = mods['SGG_Modding-Chalk']
reload  = mods['SGG_Modding-ReLoad']

config = chalk.auto('config.lua')
public.config = config

local lib = mods['adamant-ModpackLib']

-- PRIORITY_VALUES: ordered list of loot key strings for the dropdown
-- populated from the static god list; "" first for "None"
local PRIORITY_VALUES = { "", "AphroditeUpgrade", "ApolloUpgrade", "AresUpgrade",
    "DemeterUpgrade", "HephaestusUpgrade", "HeraUpgrade", "HestiaUpgrade",
    "PoseidonUpgrade", "ZeusUpgrade" }

local PRIORITY_LABELS = { "None", "Aphrodite", "Apollo", "Ares",
    "Demeter", "Hephaestus", "Hera", "Hestia", "Poseidon", "Zeus" }

public.definition = {
    modpack    = "run-director",
    special    = true,
    name       = "God Pool",
    tabLabel   = "God Pool",
    tooltip    = "Control which gods appear in the pool, how many, and when.",
    apply      = function() end,   -- hooks gate on isEnabled; no-op
    revert     = function() end,
    stateSchema = {
        { type="checkbox", configKey="KeepsakeAddsGod",                 label="Keepsake Adds a God",          default=false },
        { type="checkbox", configKey="PreventEarlySeleneHermes",        label="Prevent Early Selene/Hermes",  default=false },
        { type="checkbox", configKey="PrioritizeSpecificRewardEnabled", label="Enable Biome Priority",        default=false },
        { type="checkbox", configKey="PrioritizeTrialRewardEnabled",    label="Enable Trial Priority",        default=false },
        { type="checkbox", configKey="PrioritizeHammerFirstRoomEnabled",label="Force Hammer in First Room",   default=false },
        -- Per-god (default=true means "in pool by default" — only encode deviations)
        { type="checkbox", configKey="AphroditeEnabled",  label="Aphrodite",  default=true },
        { type="checkbox", configKey="ApolloEnabled",     label="Apollo",     default=true },
        { type="checkbox", configKey="AresEnabled",       label="Ares",       default=true },
        { type="checkbox", configKey="DemeterEnabled",    label="Demeter",    default=true },
        { type="checkbox", configKey="HephaestusEnabled", label="Hephaestus", default=true },
        { type="checkbox", configKey="HeraEnabled",       label="Hera",       default=true },
        { type="checkbox", configKey="HestiaEnabled",     label="Hestia",     default=true },
        { type="checkbox", configKey="PoseidonEnabled",   label="Poseidon",   default=true },
        { type="checkbox", configKey="ZeusEnabled",       label="Zeus",       default=true },
        -- MaxGodsPerRun — int32 (custom +/- UI in DrawTab, no widget from Framework)
        { type="int32", configKey="MaxGodsPerRun",  default=4 },
        -- Priority dropdowns (values are loot key strings)
        { type="dropdown", configKey="PriorityBiome1", label="Biome 1 Priority God", values=PRIORITY_VALUES, default="" },
        { type="dropdown", configKey="PriorityBiome2", label="Biome 2 Priority God", values=PRIORITY_VALUES, default="" },
        { type="dropdown", configKey="PriorityBiome3", label="Biome 3 Priority God", values=PRIORITY_VALUES, default="" },
        { type="dropdown", configKey="PriorityBiome4", label="Biome 4 Priority God", values=PRIORITY_VALUES, default="" },
        { type="dropdown", configKey="PriorityTrial1", label="Trial Priority God 1", values=PRIORITY_VALUES, default="" },
        { type="dropdown", configKey="PriorityTrial2", label="Trial Priority God 2", values=PRIORITY_VALUES, default="" },
    },
}

local staging, snapshot, sync = lib.createSpecialState(config, public.definition.stateSchema)
public.SnapshotStaging = snapshot
public.SyncToConfig    = sync
public.staging         = staging

-- GodPool data and logic don't depend on game data at module load time,
-- so a single loader function is sufficient (no separate on_reload needed).
-- ui.lua is imported in both paths because hot reload re-runs it to pick up UI changes.
local loader = reload.auto_single()
modutil.once_loaded.game(function()
    loader.load(function()
        import_as_fallback(rom.game)
        import("mods/data.lua")
        import("mods/logic.lua")
        import("mods/ui.lua")
    end)
end)
```

### `src/mods/data.lua`

Static table — no game data queries. Replaces the macro-relevant parts of `god_meta.lua`.

```lua
local M = {}  -- local namespace accessible from logic.lua and ui.lua

-- Ordered list of pool-eligible Olympians (core gods only)
M.godList = {
    { key = "Aphrodite",  lootKey = "AphroditeUpgrade",  configKey = "AphroditeEnabled"  },
    { key = "Apollo",     lootKey = "ApolloUpgrade",     configKey = "ApolloEnabled"     },
    { key = "Ares",       lootKey = "AresUpgrade",       configKey = "AresEnabled"       },
    { key = "Demeter",    lootKey = "DemeterUpgrade",    configKey = "DemeterEnabled"    },
    { key = "Hephaestus", lootKey = "HephaestusUpgrade", configKey = "HephaestusEnabled" },
    { key = "Hera",       lootKey = "HeraUpgrade",       configKey = "HeraEnabled"       },
    { key = "Hestia",     lootKey = "HestiaUpgrade",     configKey = "HestiaEnabled"     },
    { key = "Poseidon",   lootKey = "PoseidonUpgrade",   configKey = "PoseidonEnabled"   },
    { key = "Zeus",       lootKey = "ZeusUpgrade",       configKey = "ZeusEnabled"       },
}

-- O(1) lookup: lootKey -> god entry (used in GetEligibleLootNames hook)
M.lootKeyLookup = {}
for _, g in ipairs(M.godList) do
    M.lootKeyLookup[g.lootKey] = g
end

-- Export onto public so logic.lua and ui.lua can import it
public.godList      = M.godList
public.lootKeyLookup = M.lootKeyLookup
```

### `src/mods/logic.lua`

Adapted from `logic_macro.lua`. Key changes:
- Replace `config.ModEnabled and config.EnableGodPool` gate with `lib.isEnabled(config, "run-director")` where `lib = rom.mods['adamant-ModpackLib']`
- Replace `config.PackedPriorityB1` etc. with `config.PriorityBiome1` (loot key string directly, no index lookup)
- Replace `Utils.IsGodEnabledInPool(godKey)` with direct config read: `config[lootKeyLookup[lootKey].configKey] ~= false`
- Keep all five `modutil.mod.Path.Wrap` calls verbatim (GetEligibleLootNames, ReachedMaxGods, GiveLoot, SetupRoomReward, SpawnRoomReward)
- Keep `Utils.PreRunStart_Macro()` (called from StartNewRun wrap, see below)
- Register `StartNewRun` wrap here (not in shared_hooks.lua):

```lua
modutil.mod.Path.Wrap("StartNewRun", function(base, prevRun, args)
    if lib.isEnabled(config, "run-director") then
        PreRunStart_GodPool()  -- local function (was PreRunStart_Macro)
    end
    local result = base(prevRun, args)
    return result
end)
```

### `src/mods/ui.lua`

Adapted from the "Run Setup" and god pool sections of the original `ui.lua`.
Must set:
- `public.DrawTab(ui, onChanged, theme)` — full tab content; reads/writes `public.staging`
- `public.DrawQuickContent(ui, onChanged, theme)` — compact summary for Quick Setup tab (god count, priority god)

**Pattern for any config change inside DrawTab:**
```lua
-- 1. Write to staging
public.staging.AphroditeEnabled = newVal
-- 2. Call onChanged (Framework will call SyncToConfig, then update hash)
onChanged()
```

The Framework's Enable checkbox is rendered by Framework before calling `DrawTab`; do not render it again inside DrawTab.

---

## Module 2: Boon Bans (`adamant-RunDirector-BoonBans`)

### What it owns
Per-boon ban management (all gods, weapons, NPCs, specials), tier logic, rarity forcing, smart padding.

### File structure
```
Submodules/adamant-RunDirector-BoonBans/
  src/
    main.lua        — ENVY wiring, definition, staging, loader
    config.lua      — Chalk schema (all Packed* ban and rarity keys)
    mods/
      god_meta.lua  — copied verbatim from original; populates public.godMeta etc.
      utilities.lua — bit-packing helpers; adapted to use lib.isEnabled gate
      logic.lua     — combined logic_micro_core.lua + logic_micro_others.lua; adapted gate
      ui.lua        — DrawTab (adapted from BoonBans section of original ui.lua)
```

### `src/config.lua`

Identical to the `Packed*` section of `purpIe-Run_Director/src/config.lua` plus flat settings.
Remove all non-BoonBans keys (god pool, encounters, profiles, settings booleans).

```lua
return {
    Enabled   = false,
    DebugMode = false,

    -- Padding settings (flat booleans)
    EnablePadding           = false,
    Padding_UsePriority     = true,
    Padding_AvoidFutureAllowed = true,
    Padding_AllowDuos       = false,

    ImproveFirstNBoonRarity = 0,
    ViewRegion = 4,  -- 1=Neither 2=UW 3=SF 4=Both

    -- All PackedXxx ban integers (copy from original config.lua, MICRO section only)
    -- Olympians (5 tiers each):
    PackedAphrodite1=0, PackedAphrodite2=0, ..., PackedAphrodite5=0,
    -- ... all 9 olympians ...
    -- Rarity:
    PackedRarityAphrodite=0, ...,
    -- Hammers (3 tiers each):
    PackedStaff1=0, ...,
    -- Singles:
    PackedArachne=0, ...,
    -- Specials:
    PackedChaosBuff=0, PackedChaosCurse=0, PackedCirceBNB=0, ...,
    -- Extras:
    PackedHadesKeepsake=0, PackedCirceBNB=0, ...,
}
```

### stateSchema design decision — hash coverage

The ban data (Packed* integers) participates in the Framework hash so that shared hashes include full ban state. Each `PackedXxx` key is declared as `int32` type. This makes the hash string long when many bans are set, but it remains valid and decodable.

**Simple settings are checkboxes; all PackedXxx keys are int32.**

```lua
local stateSchema = {
    { type="checkbox", configKey="EnablePadding",           label="Enable Padding",              default=false },
    { type="checkbox", configKey="Padding_UsePriority",     label="Use Core Priority",           default=true  },
    { type="checkbox", configKey="Padding_AvoidFutureAllowed", label="Avoid Future Allowed",    default=true  },
    { type="checkbox", configKey="Padding_AllowDuos",       label="Allow Duos as Padding",       default=false },
    { type="int32",    configKey="ImproveFirstNBoonRarity", default=0 },
    { type="int32",    configKey="ViewRegion",              default=4 },
    -- All Packed* ban integers: one entry each
    { type="int32", configKey="PackedAphrodite1", default=0 },
    { type="int32", configKey="PackedAphrodite2", default=0 },
    -- ... (all ~60 packed keys) ...
    { type="int32", configKey="PackedRarityAphrodite", default=0 },
    -- ... (all ~13 rarity keys) ...
}
```

### `src/main.lua` structure

Same pattern as GodPool. Key differences:
- `public.godMeta` and `public.godInfo` are populated by on_ready imports, not at module load time
- Staging setup happens at top-level (before game data loads); `god_meta.lua` runs inside `on_ready`

```lua
-- (ENVY wiring same as GodPool)

config = chalk.auto('config.lua')
public.config = config

local lib = mods['adamant-ModpackLib']

public.definition = {
    modpack     = "run-director",
    special     = true,
    name        = "Boon Bans",
    tabLabel    = "Boon Bans",
    tooltip     = "Ban individual boons per god, per tier. Smart padding included.",
    apply       = function() end,
    revert      = function() end,
    stateSchema = {
        -- (full stateSchema as listed in the stateSchema section above)
    },
}

local staging, snapshot, sync = lib.createSpecialState(config, public.definition.stateSchema)
public.SnapshotStaging = snapshot
public.SyncToConfig    = sync
public.staging         = staging

-- Runtime tables (populated by god_meta.lua inside loader)
public.godMeta = {}
public.godInfo = {}

-- BoonBans uses the two-function loader form (deviation from template):
-- god_meta.lua queries live game data (LootSetData, UnitSetData, SpellData) at load time
-- and must re-run on hot reload so godMeta/godInfo reflect any changed game data.
-- on_reload skips logic.lua (hooks are already registered; re-registering duplicates them).
local loader = reload.auto_single()
modutil.once_loaded.game(function()
    loader.load(
        function()  -- on_ready
            import_as_fallback(rom.game)
            public.godMeta = {}
            public.godInfo = {}
            bit32 = require("bit32")
            import("mods/god_meta.lua")   -- populates public.godMeta
            import("mods/utilities.lua")  -- bit-packing helpers onto public
            import("mods/logic.lua")      -- registers hooks (runs once)
            import("mods/ui.lua")         -- sets public.DrawTab
        end,
        function()  -- on_reload
            import_as_fallback(rom.game)
            public.godMeta = {}
            public.godInfo = {}
            import("mods/god_meta.lua")   -- re-query game data
            import("mods/ui.lua")         -- pick up UI changes
        end
    )
end)
```

### `src/mods/god_meta.lua`

BoonBans owns this entirely — not shared with GodPool or Encounters.

Adapted from `purpIe-Run_Director/src/mods/god_meta.lua`. Changes:
- `local Utils = adamant_RunDirector` → `local Utils = public` (top of file)
- All `Utils.xxx = ...` export assignments stay as-is (they now write onto `public`)

### `src/mods/utilities.lua`

BoonBans owns this entirely — not shared with other modules.

Adapted from `purpIe-Run_Director/src/mods/utilities.lua`. Changes:
- `local Utils = adamant_RunDirector` → `local Utils = public`
- `local godMeta = Utils.godMeta` → `local godMeta = public.godMeta`
- Run state key: `CurrentRun.RunDirector_StateBackpack` → `CurrentRun.RunDirector_BoonBans_State`

### `src/mods/logic.lua`

Merged from `logic_micro_core.lua` + `logic_micro_others.lua`. Changes:
- `local Utils = adamant_RunDirector` → `local Utils = public`
- Replace `IsBanManagerActive()`: `return config.ModEnabled and config.EnableBanManager` → `return lib.isEnabled(config, "run-director")` where `lib = rom.mods['adamant-ModpackLib']`
- Add `StartNewRun` wrap for the padding RNG fix. The original monolith ran this for all
  features combined; here it belongs only in BoonBans since it fixes padding determinism:
  when many boons are banned, padding fallback picks were consistently the same across runs.

```lua
modutil.mod.Path.Wrap("StartNewRun", function(base, prevRun, args)
    if lib.isEnabled(config, "run-director") and config.EnablePadding then
        local seed = GetClockSeed()
        RandomSetNextInitSeed({ Seed = seed, Id = 1 })
        math.randomseed(os.time())
        math.random(); math.random(); math.random()
    end
    return base(prevRun, args)
end)
```

- Remove all references to `config.ModEnabled` / `config.EnableBanManager` (replaced by `IsBanManagerActive`)
- Keep `PopulateGodInfo()` call at the bottom of the file (runs at load time inside on_ready)

### `src/mods/ui.lua`

Adapted from the BoonBans UI section of the original `ui.lua`. Sets `public.DrawTab`.

The `ViewRegion` filter and god group collapsing logic are adapted as-is; they read from `public.staging.ViewRegion` etc.

**No `DrawQuickContent`** — BoonBans is too dense for the Quick Setup tab.

---

## Module 3: Encounters (`adamant-RunDirector-Encounters`)

### What it owns
NPC encounter forcing (Artemis, Nemesis, Heracles, Athena, Icarus), story rooms, trials, fountains, shops, depth controls, strict mode.

### File structure
```
Submodules/adamant-RunDirector-Encounters/
  src/
    main.lua        — ENVY wiring, definition, staging, loader
    config.lua      — Chalk schema
    mods/
      data.lua      — encounter definitions (from god_meta.lua section 6)
      logic.lua     — adapted from logic_encounter.lua
      ui.lua        — DrawTab (adapted from Encounters tab of original ui.lua)
```

### `src/config.lua`

All encounter-relevant keys from `purpIe-Run_Director/src/config.lua`:

```lua
return {
    Enabled   = false,
    DebugMode = false,

    -- Encounter settings
    StrictMode    = false,
    IgnoreMaxDepth = false,
    NPCSpacing    = 6,

    -- Encounter enable bitfield
    PackedEncounterStatus = 0,

    -- All depth pairs (copy from original config.lua, ENCOUNTER section only)
    PackedCombatArtemisMin=4,  PackedCombatArtemisMax=10,
    PackedCombatNemesisMin=4,  PackedCombatNemesisMax=10,
    -- ... all encounter depth pairs ...
    PackedShopOlympusMin=5,    PackedShopOlympusMax=7,
}
```

### `src/main.lua` structure

`public.definition.stateSchema` is declared inline (same pattern as GodPool/BoonBans).
Encounters has no dynamic data dependency (encounter definitions are static),
so the single-function loader form is sufficient — no separate on_reload needed.

```lua
public.definition = {
    modpack     = "run-director",
    special     = true,
    name        = "Encounters",
    tabLabel    = "Encounters",
    tooltip     = "Force specific NPCs and events to spawn at chosen depths.",
    apply       = function() end,
    revert      = function() end,
    stateSchema = {
        { type="checkbox", configKey="StrictMode",             label="Strict Mode",      default=false },
        { type="checkbox", configKey="IgnoreMaxDepth",         label="Ignore Max Depth", default=false },
        { type="int32",    configKey="NPCSpacing",             default=6 },
        { type="int32",    configKey="PackedEncounterStatus",  default=0 },
        -- All depth pairs as int32:
        { type="int32", configKey="PackedCombatArtemisMin", default=4 },
        { type="int32", configKey="PackedCombatArtemisMax", default=10 },
        -- ... all ~50 depth keys ...
    },
}

local staging, snapshot, sync = lib.createSpecialState(config, public.definition.stateSchema)
public.SnapshotStaging = snapshot
public.SyncToConfig    = sync
public.staging         = staging

local loader = reload.auto_single()
modutil.once_loaded.game(function()
    loader.load(function()
        import_as_fallback(rom.game)
        import("mods/data.lua")    -- static encounter definitions
        import("mods/logic.lua")   -- registers hooks + StartNewRun wrap
        import("mods/ui.lua")      -- sets public.DrawTab
    end)
end)
```

`StartNewRun` wrap in `logic.lua` must handle both phases:

```lua
modutil.mod.Path.Wrap("StartNewRun", function(base, prevRun, args)
    if lib.isEnabled(config, "run-director") then
        Utils.PreRunStart_Encounters()   -- modifies RoomSetData BEFORE base()
    end
    local result = base(prevRun, args)
    if lib.isEnabled(config, "run-director") then
        Utils.PostRunStart_Encounters()  -- initializes state AFTER base()
    end
    return result
end)
```

### `src/mods/data.lua`

The encounter definitions section from `god_meta.lua` (section 6 — "ENCOUNTER META"), extracted verbatim.
- Replace `Utils = adamant_RunDirector` with `Utils = public`
- Export: `public.encounterDefinitions`, `public.encounterLookup`

### `src/mods/logic.lua`

**Copied from `logic_encounter.lua`.**
Changes:
- Replace `Utils = adamant_RunDirector` with `Utils = public`
- Replace `IsEncounterManagerActive()`: `return config.ModEnabled and config.EnableEncounterManager` → `return lib.isEnabled(config, "run-director")`
- Replace `encounterLookup = Utils.encounterLookup` with `local encounterLookup = public.encounterLookup`
- Keep `Utils.GetRunState()` — adapted to use `public.GetRunState()`
- Keep all hooks verbatim

`Utils.GetRunState()` needs to be available. Since it was in `utilities.lua` of the monolith,
move it into Encounters' `logic.lua` or `data.lua`. The run state backpack for Encounters is:

```lua
function public.GetRunState()
    if not CurrentRun then return nil end
    if not CurrentRun.RunDirector_Encounters_State then
        CurrentRun.RunDirector_Encounters_State = {
            ForcedNPCPending    = {},
            EncounterSeen       = {},
            EncounterStrictMode = false,
        }
    end
    return CurrentRun.RunDirector_Encounters_State
end
```

Note the key name `RunDirector_Encounters_State` (not shared with the monolith key `RunDirector_StateBackpack`).

### `src/mods/ui.lua`

Sets `public.DrawTab`. Adapted from the Encounters tab of the original `ui.lua`.
Optionally sets `public.DrawQuickContent` for a compact region-filtered NPC list.

---

## Summary of breaking changes from the monolith

| Original | New location | Change |
|---|---|---|
| `config.ModEnabled` gate | `lib.isEnabled(config, "run-director")` | Coordinator's flag checked via Lib |
| `config.EnableGodPool` | `config.Enabled` (GodPool module) | Module's own enable |
| `config.EnableBanManager` | `config.Enabled` (BoonBans module) | Module's own enable |
| `config.EnableEncounterManager` | `config.Enabled` (Encounters module) | Module's own enable |
| `PackedPriorityB1`–`B4` (int index) | `PriorityBiome1`–`4` (loot key string) | Simpler, no index resolution |
| Bit 31 pool flag in `Packed*` | `config.AphroditeEnabled` etc. | Separate flat booleans |
| `config.PackedSettings` | Not needed (replaced by individual keys + Framework hash) | |
| `shared_hooks.lua` | Each module's `logic.lua` owns its `StartNewRun` wrap | |
| Profile manager (binary/RLE/Base64) | Framework hash pipeline | Profiles stored in coordinator config |
| Standalone ImGui window | Framework window; modules expose `DrawTab` | |
| `adamant_RunDirector` global namespace | `public` table (ENVY pattern per module) | Standard framework pattern |
| Run state key `RunDirector_StateBackpack` | `RunDirector_GodPool_State`, `RunDirector_BoonBans_State`, `RunDirector_Encounters_State` | One key per module on `CurrentRun` |

---

## Execution order

1. **Add `int32` to Lib** — smallest change, required by steps 2–4.
2. **Build `adamant-RunDirector-GodPool`** — simplest module; no dynamic data dependency; validates the Framework integration pattern end-to-end.
3. **Build `adamant-RunDirector-Encounters`** — self-contained data; no god_meta dependency; tests the two-phase StartNewRun pattern.
4. **Build `adamant-RunDirector-BoonBans`** — most complex; builds on the validated pattern from steps 2–3.
5. **Register submodules** — `git submodule add` for each repo; run `Setup/scaffold/register_submodules.py` if it handles the coordinator's thunderstore.toml deps.
6. **Validate** — test with coordinator installed; confirm Framework discovers all three; confirm hash includes all modules; confirm profiles round-trip.

---

## Things NOT carried over from the monolith

- **`config.ViewRegion`** default `= 4` ("Both") — kept in BoonBans config as-is since it gates UI rendering
- **`RandomSetNextInitSeed`** call in shared_hooks.lua — this was in the `StartNewRun` gate and is RNG seeding unrelated to any of the three feature modules; it belongs in a future separate module or the coordinator. **Do not migrate it.**
- **The Timer update hook** (`UpdateTimers`) — was commented out in the original; do not migrate.
- **`wrapNPCChoice` debug print block** — the verbose debug `print` statements inside `wrapNPCChoice` in `logic_micro_others.lua` were clearly development noise; replace with `lib.log` calls or remove.
