# Store Contract Migration Guide

Guide for migrating existing modules from raw Chalk config access to the current Lib/Framework store contract.

Target contract:

- modules expose `public.store`
- modules do not expose `public.config`
- special modules do not expose standalone `public.specialState`
- regular modules read/write persisted values through `store.read(...)` / `store.write(...)`
- special-module UI reads/writes managed state through `store.specialState`
- runtime code reads persisted values through `store.read(...)`

This guide is written for maintainers migrating already-deployed modules, not for greenfield templates.

---

## Why this migration exists

Old modules commonly did one or more of these:

- exported `public.config = chalk.auto("config.lua")`
- exported `public.specialState = lib.createSpecialState(config, schema)`
- let imported files close over raw `config`
- used raw Chalk config in standalone UI helpers

That worked, but it made accidental contract violations easy:

- UI code could write raw config directly
- runtime code and UI code could blur persisted state vs managed state
- modules could bypass the intended access path without meaning to

The new contract makes the correct path the default:

- `public.store` is the one outward-facing state surface
- raw Chalk config stays local to `main.lua`
- regular modules use persisted store access
- special-module UI uses `store.specialState`

---

## Final state to aim for

### Regular module

```lua
local config = chalk.auto("config.lua")
public.store = lib.createStore(config)

local function IsEnabled()
    return lib.isEnabled(public.store, public.definition.modpack)
end
```

Imported files:

- may use `internal.store`
- should not use raw `config`

Standalone UI:

```lua
local uiCallback = lib.standaloneUI(public.definition, public.store)
```

### Special module

```lua
local config = chalk.auto("config.lua")
public.store = lib.createStore(config, public.definition.stateSchema)

function public.DrawTab(ui, specialState, theme)
    ...
end
```

Imported UI files:

- read `specialState.view`
- mutate via `specialState.set/update/toggle`
- should not use raw `config`

Standalone special UI:

```lua
local standaloneUi = lib.standaloneSpecialUI(
    public.definition,
    public.store,
    public.store.specialState,
    opts
)
```

---

## Migration order

Use this order. It avoids the worst half-migrated states.

1. Add `public.store = lib.createStore(...)` in `main.lua`
2. Add `internal.store = public.store`
3. Migrate imported files from raw `config` to `store`
4. Update standalone UI helpers to pass `store`
5. Remove `public.config`
6. For special modules, remove standalone `public.specialState`
7. Sweep docs/comments/tests for old contract wording

Do not remove `public.config` first if imported files still depend on it.

---

## Step 1: Create the store in `main.lua`

### Regular module

Before:

```lua
local config = chalk.auto("config.lua")
public.config = config
```

After:

```lua
local config = chalk.auto("config.lua")
public.store = lib.createStore(config)
```

### Special module

Before:

```lua
local config = chalk.auto("config.lua")
public.specialState = lib.createSpecialState(config, public.definition.stateSchema)
public.config = config
```

After:

```lua
local config = chalk.auto("config.lua")
public.store = lib.createStore(config, public.definition.stateSchema)
```

Important:

- keep local `config` in `main.lua`
- you still need it for schema defaults and store creation
- the goal is not “never have a local config variable”
- the goal is “do not expose raw config as the module contract”

---

## Step 2: Wire `internal.store`

In multi-file modules, set this immediately after store creation:

```lua
MyModule_Internal = MyModule_Internal or {}
local internal = MyModule_Internal
internal.store = public.store
```

Imported files should then use:

```lua
local store = MyModule_Internal.store
```

This is the normal bridge for:

- runtime logic files
- helper/utility files
- UI files

Do not make imported files reopen Chalk.

---

## Step 3: Migrate regular-module reads and writes

### Old pattern

```lua
if config.Enabled then
    ...
end

local mode = config.Mode
config.Mode = "Always"
```

### New pattern

```lua
if store.read("Enabled") == true then
    ...
end

local mode = store.read("Mode")
store.write("Mode", "Always")
```

For nested paths:

```lua
local mode = store.read({ "Nested", "Mode" })
store.write({ "Nested", "Mode" }, "Slow")
```

Use `lib.isEnabled(store, packId)` for gating module activity:

```lua
local function IsEnabled()
    return lib.isEnabled(store, public.definition.modpack)
end
```

Do not manually combine:

- `store.read("Enabled")`
- coordinator `ModEnabled`

Lib already owns that rule.

---

## Step 4: Migrate special-module UI code

Special-module UI should not use persisted store writes for schema-backed state.

### Read path

Prefer:

```lua
local view = specialState.view
local strict = view.StrictMode
```

Use `specialState.get(...)` when the code is naturally key-driven:

```lua
local packed = specialState.get("PackedFoo")
```

### Write path

Use:

```lua
specialState.set("StrictMode", true)
specialState.update("Count", function(v) return v + 1 end)
specialState.toggle("Enabled")
```

Do not do this in special UI:

```lua
store.write("StrictMode", true)
config.StrictMode = true
```

Schema-backed UI state lives in `store.specialState`, not in persisted direct writes.

---

## Step 5: Migrate shared helpers correctly

This is where most migrations go wrong.

There are three valid helper categories:

### 1. Runtime-only helper

Uses persisted reads only:

```lua
local function GetPaddingEnabled()
    return store.read("EnablePadding") == true
end
```

### 2. UI-only helper

Uses `specialState` directly:

```lua
local function ToggleFlag(specialState, key)
    specialState.toggle(key)
end
```

### 3. Shared read helper

Supports UI and runtime reads:

```lua
local function ReadValue(key, specialState)
    if specialState then
        return specialState.get(key)
    end
    return store.read(key)
end
```

What not to do:

- shared write helpers that silently fall back to persisted config when `specialState` is missing

If a helper writes UI-managed state, require `specialState`.

That keeps the important rule intact:

- runtime may read UI-managed fields
- runtime should not mutate UI-managed fields

---

## Step 6: Update standalone helpers

This matters now because the standalone helpers are part of the contract too.

### Regular modules

Before:

```lua
lib.standaloneUI(public.definition, config)
```

After:

```lua
lib.standaloneUI(public.definition, public.store)
```

### Special modules

Before:

```lua
lib.standaloneSpecialUI(public.definition, config, public.specialState, opts)
```

After:

```lua
lib.standaloneSpecialUI(
    public.definition,
    public.store,
    public.store.specialState,
    apply,
    revert,
    opts
)
```

Once you do this, standalone mode no longer teaches the old raw-config pattern.

---

## Step 7: Remove old exports

After imported files are migrated:

- remove `public.config`
- for special modules, remove standalone `public.specialState`

Framework now expects:

- regular modules: `public.store`
- special modules: `public.store.specialState`

If you leave both surfaces around during migration, it becomes much harder to know which path the module is actually using.

---

## Common migrations by module type

## Regular boolean module

Typical changes:

- `public.store = lib.createStore(config)`
- `internal.store = public.store`
- `config.Enabled` checks become `lib.isEnabled(store, packId)`
- option reads/writes become `store.read/write`
- standalone UI changes to `lib.standaloneUI(..., public.store, ...)`
- remove `public.config`

## Special module with dedicated UI

Typical changes:

- `public.store = lib.createStore(config, stateSchema)`
- `internal.store = public.store`
- UI functions continue to accept `(ui, specialState, theme)`
- imported UI files stop reading raw `config`
- runtime files stop reading raw `config` and use `store.read(...)`
- standalone UI changes to `lib.standaloneSpecialUI(..., public.store, public.store.specialState, ...)`
- remove `public.config`
- remove standalone `public.specialState`

---

## Things that are still allowed in `main.lua`

These are normal and do not violate the contract:

- `local config = chalk.auto("config.lua")`
- using `config` to seed `stateSchema` defaults
- scanning `config` at load time to build schema fields
- passing local `config` into `lib.createStore(config, ...)`

What should not happen anymore:

- exporting `public.config = config`
- imported files closing over `config`
- imported files reopening Chalk themselves

---

## Migration checklist

Use this checklist after each module migration.

### Source contract

- module exports `public.store`
- module does not export `public.config`
- special module does not export standalone `public.specialState`
- imported files do not call `chalk.auto(...)`

### Regular module behavior

- runtime gating uses `lib.isEnabled(store, packId)`
- option reads use `store.read(...)`
- option writes use `store.write(...)`
- standalone menu uses `lib.standaloneUI(..., public.store, ...)`

### Special module behavior

- UI reads `specialState.view` or `specialState.get(...)`
- UI writes `specialState.set/update/toggle(...)`
- runtime reads persisted values through `store.read(...)`
- standalone window uses `lib.standaloneSpecialUI(..., public.store, public.store.specialState, ...)`

### Validation

- `rg -n "public\\.config|public\\.specialState|chalk\\.auto\\(" src`
- syntax-check touched files with `luac5.1 -p`
- run Lib/Framework tests if the migration touched shared infrastructure
- smoke test:
  - standalone module menu
  - coordinator-hosted UI
  - enable/disable
  - option persistence
  - profile/hash round-trip for special modules

---

## Recommended grep patterns

Useful sweeps during migration:

```powershell
rg -n "public\.config|public\.specialState" src
rg -n "\bconfig\b" src\mods
rg -n "chalk\.auto\(" src
rg -n "isStoreEnabled|createSpecialState" src
rg -n "standaloneUI\(|standaloneSpecialUI\(" src
```

What you usually want at the end:

- no `public.config`
- no standalone `public.specialState`
- no imported-file `chalk.auto(...)`
- no `isStoreEnabled`
- no `createSpecialState`
- standalone helpers receiving `public.store`

---

## Notes on the removed direct-config-write detector

Older versions of Lib/Framework carried a debug-only direct-config-write detector for special UI.
That feature has been removed.

Reason:

- it was expensive enough to make debug UI unpleasant
- the store contract now prevents accidental misuse structurally
- remaining bypasses require deliberate boundary-breaking, not ordinary mistakes

So do not try to preserve or recreate:

- `DebugSpecialConfigWrites`
- `captureSpecialConfigSnapshot(...)`
- `warnIfSpecialConfigBypassedState(...)`

The current design relies on the stronger contract instead.

---

## Recommended migration strategy for large modpacks

If a modpack has many deployed modules, migrate in this order:

1. regular modules with simple logic
2. regular modules with inline options
3. smaller special modules
4. large special modules with shared helpers

Do not start with the most complex special module unless you already know the contract well.

If you have to support a large fleet:

- migrate one module completely
- use it as the reference example
- then sweep the rest with the grep checklist above

The store contract is simple once it is consistent. The painful part is half-migrated modules that still expose both old and new surfaces.
