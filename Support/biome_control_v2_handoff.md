# Biome Control V2 Handoff

## Current State

Biome Control is now partially migrated off the old custom `ui.lua` path and onto declarative `definition.ui`.

Active declarative shell:
- top-level tabs:
  - `Underworld`
  - `Surface`
  - `Settings`
- `Underworld` and `Surface` each wrap an inner vertical `tabs` node
- `Settings` is fully declarative and working

Ported sections in `ui_v2.lua`:
- region-specific `NPCs`
- `Erebus`
- `Oceanus`
- `Fields`
- `Tartarus`
- `Thessaly`
- `Olympus`
- `Ephyra`

Ported section types:
- direct room controls from `registerRoomControl(...)`
- biome room entry controls from `registerBiomeRoom(... kind = "modeField")`
- checkbox specials
- Ephyra rewards, including packed reward-ban lists

## Storage / Data Changes

NPC mode state is no longer packed and no longer group-level.

Current model:
- per-biome NPC mode ints, e.g.
  - `ModeNPCArtemisErebus`
  - `ModeNPCArtemisOceanus`
  - `ModeNPCHeraclesOlympus`
- per-biome NPC min/max depth ints remain as before

Other room/special mode state is also now flat integer storage rather than packed mode roots.

Ephyra reward bans were moved onto real `packedInt` storage roots so the new declarative UI can bind to them through `packedCheckboxList`.

## Runtime Logic Changes

Updated logic files:
- `src/mods/logic.lua`
- `src/mods/logic_npc.lua`

Current NPC behavior matches the new data shape:
- forced pending state is tracked per NPC group and per biome
- forced/disabled/default checks read each biome definition's `modeKey`

## Known Good

- `Settings` renders correctly
- declarative shell is active
- standalone declarative UI width clamp in Lib was fixed
- files parse with `loadfile(...)`

## Main Unresolved Issue

Nested vertical tabs under `Underworld` and `Surface` still render with an unwanted extra right-side area in game.

Observed behavior:
- `Settings` looks correct
- any tab under `Underworld` / `Surface`, even empty `Summit`, still shows:
  - left vertical tab nav
  - content area
  - extra empty right-side area

This means the problem is not specific to:
- NPC rows
- room rows
- rewards
- specials

It is structural to how `Underworld` / `Surface` are composed.

## What Was Already Tried

Tried and kept:
- Lib standalone width fixes:
  - `adamant-ModpackLib/src/special/standalone.lua`
  - `adamant-ModpackLib/src/core/standalone.lua`
- these removed the old 40–45% width clamp for declarative UI trees

Tried and kept:
- removing nested `scrollRegion` wrappers from Biome Control tab bodies

Tried and currently present:
- matching Boon Bans more closely by wrapping region content in a `vstack`
  - top-level `Underworld` / `Surface` tab child is now a `vstack`
  - inner vertical `tabs` sits inside that `vstack`

This still did **not** resolve the extra right-side area.

## Most Likely Next Investigation

Compare Biome Control's nested tabs path against Boon Bans at runtime, not just tree shape.

Most likely places to inspect:
- `adamant-ModpackLib/src/field_registry/layouts.lua`
  - vertical `tabs.render`
- whether nested `tabs` inside another tab body is advancing/consuming width incorrectly
- whether the vertical tab detail pane is being treated as if it has another sibling region in this module's tree

Useful comparison:
- `Submodules/adamant-RunDirector_BoonBans/src/mods/ui/nodes.lua`
  - Boon Bans vertical tabs behave correctly

## Files Touched In This Migration

Biome Control:
- `src/config.lua`
- `src/main.lua`
- `src/mods/data.lua`
- `src/mods/logic.lua`
- `src/mods/logic_npc.lua`
- `src/mods/ui_v2.lua`

Lib:
- `adamant-ModpackLib/src/core/standalone.lua`
- `adamant-ModpackLib/src/special/standalone.lua`

## Recommended Next Step

Do not keep porting more Biome Control UI until the nested vertical-tabs layout issue is understood.

Next step should be:
1. instrument or inspect `layouts.lua` vertical `tabs.render`
2. compare the working Boon Bans nested tab case against the Biome Control nested tab case
3. fix the structural layout issue first
4. only then continue polishing the remaining biome sections
