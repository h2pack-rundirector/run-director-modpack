# Mutation Plan Migration Guide

Guide for migrating mutation modules from manual `createBackupSystem()` patterns to the current
Lib-owned mutation plan contract.

This is a mutation authoring guide, not a store-contract guide.

See also:

- `store_contract_migration.md` for `public.store` / `specialState` migration
- `adamant-ModpackLib/CONTRIBUTING.md` for the current Lib contract

---

## Final v1 contract

Modules that need run-data rebuild/reapply behavior still set:

```lua
public.definition.affectsRunData = true
```

But the mutation lifecycle can now be authored in three shapes.

### Patch-only

```lua
public.definition.patchPlan = function(plan, store)
    plan:set(SomeTable, "SomeKey", 123)
end
```

### Manual-only

```lua
local backup, revert = lib.createBackupSystem()

public.definition.apply = function()
    backup(SomeTable, "SomeKey")
    SomeTable.SomeKey = 123
end

public.definition.revert = revert
```

### Hybrid

```lua
local backup, revert = lib.createBackupSystem()

public.definition.patchPlan = function(plan, store)
    plan:set(SomeTable, "SimpleKey", 123)
end

public.definition.apply = function()
    -- procedural leftovers
end

public.definition.revert = revert
```

---

## Inference rules

Framework/Lib infer mutation shape from exports:

- `patchPlan` only -> patch-only
- `apply` + `revert` only -> manual-only
- both -> hybrid

If `affectsRunData = true` but the module exposes neither patch nor manual lifecycle, discovery warns.

---

## Patch plan API

Create patch steps inside:

```lua
public.definition.patchPlan = function(plan, store)
    ...
end
```

Available v1 primitives:

- `plan:set(tbl, key, value)`
- `plan:setMany(tbl, kv)`
- `plan:transform(tbl, key, fn)`
- `plan:append(tbl, key, value)`
- `plan:appendUnique(tbl, key, value, equivalentFn?)`

Behavior:

- plans are built fresh on every apply
- Lib owns first-write backup and revert for plan-owned keys
- `appendUnique(...)` uses Lib deep-equivalence by default
- `transform(...)` should return the full replacement value for the targeted key

---

## When to use patch vs manual

### Use patch mode for

- scalar key replacement
- several writes on one table
- list append
- append-if-missing
- clone/modify/replace of one keyed value

### Use manual mode for

- engine-side side effects
- procedural loops that do not fit a bounded patch cleanly
- behavior that is fundamentally hook-like rather than table-mutation-like
- cases where backup/revert cannot be expressed as normal table restore

### Use hybrid mode for

- modules that are mostly patch-shaped
- but still have a small procedural remainder

Current runtime ordering for hybrid modules:

- apply: patch first, then manual
- revert: manual first, then patch

Practical rule:

- keep patch-owned keys and manual-owned keys separated where possible

---

## Migration patterns

### 1. Plain set

Before:

```lua
backup(RoomSetData.F.F_Story01, "ForceIfUnseenForRuns")
RoomSetData.F.F_Story01.ForceIfUnseenForRuns = nil
```

After:

```lua
plan:set(RoomSetData.F.F_Story01, "ForceIfUnseenForRuns", nil)
```

### 2. Several related keys on one table

Before:

```lua
backup(room, "ForceAtBiomeDepthMin", "ForceAtBiomeDepthMax")
room.ForceAtBiomeDepthMin = minValue
room.ForceAtBiomeDepthMax = maxValue
```

After:

```lua
plan:setMany(room, {
    ForceAtBiomeDepthMin = minValue,
    ForceAtBiomeDepthMax = maxValue,
})
```

### 3. Append to a list

Before:

```lua
backup(args, "MultihitProjectileWhitelist")
table.insert(args.MultihitProjectileWhitelist, "ProjectileTorchOrbit")
```

After:

```lua
plan:append(args, "MultihitProjectileWhitelist", "ProjectileTorchOrbit")
```

### 4. Append if missing

Before:

```lua
backup(NamedRequirementsData, "SpellDropRequirements")
local list = DeepCopyTable(NamedRequirementsData.SpellDropRequirements or {})
if not ListContainsEquivalent(list, req) then
    table.insert(list, DeepCopyTable(req))
end
NamedRequirementsData.SpellDropRequirements = list
```

After:

```lua
plan:appendUnique(NamedRequirementsData, "SpellDropRequirements", req)
```

### 5. Clone, modify, replace

Before:

```lua
backup(RoomData.H_Bridge01, "ForcedRewards")
local forcedRewards = DeepCopyTable(RoomData.H_Bridge01.ForcedRewards)
for _, forcedReward in ipairs(forcedRewards) do
    if forcedReward.Name == "Story" then
        forcedReward.GameStateRequirements = forcedReward.GameStateRequirements or {}
        forcedReward.GameStateRequirements.ChanceToPlay = 13 / 14
        break
    end
end
RoomData.H_Bridge01.ForcedRewards = forcedRewards
```

After:

```lua
plan:transform(RoomData.H_Bridge01, "ForcedRewards", function(current)
    local forcedRewards = DeepCopyTable(current or {})
    for _, forcedReward in ipairs(forcedRewards) do
        if forcedReward.Name == "Story" then
            forcedReward.GameStateRequirements = forcedReward.GameStateRequirements or {}
            forcedReward.GameStateRequirements.ChanceToPlay = 13 / 14
            break
        end
    end
    return forcedRewards
end)
```

---

## What to leave manual on purpose

Do not force everything into patch mode.

Keep manual mode for:

- procedural mutation that is clearer as code than as a patch callback
- legacy modules where only a small fraction is worth migrating now
- engine-side side effects with no clean plan primitive

That is why hybrid mode exists.

---

## Recommended migration order

Use this order:

1. Identify patch-shaped writes
2. Move those into `definition.patchPlan`
3. Keep procedural leftovers in manual `apply/revert`
4. Let discovery validate the inferred lifecycle against the actual exports
5. Keep `affectsRunData` only for modules whose lifecycle changes require run-data rebuilds

Do not try to eliminate manual mode first. Shrink it first.

---

## Current proof examples

The current repo already demonstrates both v1 proof shapes:

- patch-only:
  - `Submodules/adamant-RunDirectorEncounters`
- hybrid:
  - `Submodules/adamant-RunDirectorGodPool`

Use those as reference implementations when migrating more modules.
