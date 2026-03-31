# Migration Planning — Open Discussion

This file captures the state of the planning conversation so it can be resumed later.
Read `plan.md` first for the full migration plan.

---

## Where we are

The overall split into 3 modules (GodPool, BoonBans, Encounters) is agreed.
`plan.md` has the detailed file-by-file plan for all three but needs corrections
noted in the "Plan corrections" section below.

We were working through open questions before starting implementation.

---

## Resolved

**Module split** — agreed: GodPool, BoonBans, Encounters as separate special modules.

**`int32` field type — back in the plan (correctly understood).**
The reasoning:
- For *regular* modules, Framework calls `drawField` on options — the draw function matters.
- For *special* modules, Framework never calls `drawField` on stateSchema fields.
  It only calls `toHash` and `fromHash` during hash encode/decode.
- Therefore a no-op `draw` on `int32` is correct and does not break any contract.
- The bit-packing logic (SetBanConfig, GetBanConfig, etc.) is internal to BoonBans.
  The Framework only sees the resulting integer as a string in the canonical hash.
  How BoonBans arrives at that integer is none of the Framework's business.
- This is confirmed by the special module template (`h2-modpack-template/src/main_special.lua`):
  stateSchema fields are never rendered by Framework for special modules.

`int32` implementation in Lib:
```lua
FieldTypes.int32 = {
    validate  = function(field, prefix) end,
    toHash    = function(_, value)  return tostring(value or 0) end,
    fromHash  = function(_, str)    return tonumber(str) or 0 end,
    toStaging = function(val)       return tonumber(val) or 0 end,
    draw      = function(_, _, value) return value, false end,  -- never called for specials
}
```

---

## Plan corrections (plan.md needs updating)

These are errors or omissions in the current plan.md:

**1. `loader.load` signature**
The template uses `loader.load(fn)` — a single function.
The plan's `main.lua` skeletons use `loader.load(on_ready, on_reload)` (two functions).
The two-function form may still be needed for BoonBans (god_meta must re-run on reload
because it queries live game data). This is a legitimate deviation from the template
but should be called out explicitly in the plan rather than silently differing.

**2. `stateSchema` placement**
The plan declares stateSchema as a local variable, then assigns it.
The template sets it directly on `public.definition.stateSchema`.
The correct pattern:
```lua
public.definition = {
    ...
    stateSchema = {
        { type="checkbox", ... },
        ...
    },
}
```
Not:
```lua
local stateSchema = { ... }
public.definition = { ... }
public.definition.stateSchema = stateSchema
```

**3. Standalone UI**
The plan's `main.lua` skeletons don't mention standalone UI.
The template includes it as a standard part of every special module — each module
renders itself (via DrawTab + DrawQuickContent in a plain ImGui window) when no
coordinator is installed. This is important for Run Director modules which are complex
enough to be used standalone. The plan should note this is inherited from the template,
not something to implement separately.

---

## Additional resolved decisions (second review)

**Debug prints in `wrapNPCChoice`** — unconditional `print()` calls in `wrapNPCChoice`
and the `PrintTable` helper are development noise. In BoonBans `logic.lua`, replace
with `lib.log("BoonBans", config.DebugMode, ...)` calls or remove entirely.

**Encounter stateSchema depth keys** — the ~50 `PackedXxxMin/Max` keys in config.lua
are intentionally hardcoded by the author (Chalk requires static keys at declaration time;
runtime generation is not possible). The stateSchema listing them manually is correct.

**Run state backpack separation** — vars are already naturally separated in the monolith.
Each module gets its own `CurrentRun` key:
- GodPool: `CurrentRun.RunDirector_GodPool_State`
- BoonBans: `CurrentRun.RunDirector_BoonBans_State`
- Encounters: `CurrentRun.RunDirector_Encounters_State`

**No backbone/shared module** — considered splitting `god_meta.lua` and `utilities.lua`
into a shared backbone module. Rejected: only BoonBans needs this data. GodPool only
needs a trivial inline god list (9 entries). Encounters is fully self-contained.
A shared module would be overhead with one consumer and adds dependency wiring complexity.
BoonBans owns `god_meta.lua` and `utilities.lua` internally.

**Dead code** — commented-out blocks (rarity forcing, timer hook) will not be carried over.

---

## Open questions (need answers before implementation)

### 1. Packed state — sharing strategy — **RESOLVED: Option A**

Keep packed ints. Put them in stateSchema as `int32`.
- All state in the Framework hash. One canonical string shares everything.
- No separate export/import system needed.
- Preserves all existing bit-packing logic almost verbatim.
- Config stays compact — going flat would mean hundreds of individual booleans (~60 packed
  keys would explode into potentially 500+ individual booleans for boon bans alone).
- Hash verbosity is a non-issue — it's shared as text, not displayed to the user.

### 2. GodPool config format — **RESOLVED: flat booleans**

BoonBans keeping packed ints (Option A) does NOT mean GodPool should too.
In the monolith, bit 31 of each `PackedXxx` served dual purpose: pool flag + ban mask container.
That coupling only existed because they were the same module sharing the same config variable.
As separate modules, GodPool has no reason to use packed ints — it has 9 gods, flat booleans
are fine and make the stateSchema straightforward checkboxes.

GodPool per-god pool flags: `AphroditeEnabled = true` etc. (flat booleans, default true).
These participate in the Framework hash as `checkbox` fields — clean, human-readable.

### 3. `RandomSetNextInitSeed` — **RESOLVED: belongs in BoonBans**

Was added to fix padding determinism: when many boons are banned and padding kicks in,
the fallback choices were appearing consistently across runs. The seed manipulation
makes padding picks genuinely varied.

Lives in BoonBans' `StartNewRun` wrap in `logic.lua`, gated on padding being enabled:

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

Does not belong in GodPool or Encounters.

### 4. Execution order — **RESOLVED: order doesn't matter**

The three modules are fully independent — no shared data, no build dependencies.
Build whichever is most convenient first.
