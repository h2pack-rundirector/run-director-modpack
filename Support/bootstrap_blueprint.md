# Bootstrap Blueprint

This document defines the preferred bootstrap pattern for the four layers in this modpack stack:

- Lib
- Framework
- Core coordinator
- Submodules

Use this as the canonical reference for new files and future refactors.

## Goals

- keep reload behavior predictable
- keep game-readiness gating in the right place
- keep persisted config separate from rerunnable bootstrap
- avoid re-deriving lifecycle rules from plugin source every time

## 1. Lib

Lib is a service library. It should not own game-readiness timing.

### Pattern

- no `reload.auto_single()` in normal Lib files
- no `modutil.once_loaded.game(...)` in normal Lib files
- file load should define and export API only

### Template

```lua
local mods = rom.mods
mods["SGG_Modding-ENVY"].auto()

---@diagnostic disable: lowercase-global
public = public or {}
private = private or {}

local function helper(...)
    ...
end

function public.someApi(...)
    ...
end
```

### Notes

- internal persistent state is fine if it is intentionally library-owned
- Lib should be re-importable and boring

## 2. Framework

Framework is also a library. It should expose a rerunnable entrypoint and let the coordinator own readiness and registration timing.

### Pattern

- no `reload.auto_single()` inside Framework
- no `modutil.once_loaded.game(...)` inside Framework
- `Framework.init(...)` is the rerunnable builder

### Template

```lua
local mods = rom.mods
mods["SGG_Modding-ENVY"].auto()

---@diagnostic disable: lowercase-global
Framework = {}

import "subsystem_a.lua"
import "subsystem_b.lua"
import "subsystem_c.lua"

local _packs = {}
local _packList = {}

function Framework.init(params)
    local lib = rom.mods["adamant-ModpackLib"]

    -- validate params
    -- register coordinator
    -- rebuild discovery/hash/ui/hud
    -- overwrite pack state

    _packs[params.packId] = {
        ...
    }

    return _packs[params.packId]
end

public.init = Framework.init

public.getRenderer = function(packId)
    return function()
        local pack = _packs[packId]
        if pack and pack.ui then
            pack.ui.renderWindow()
        end
    end
end
```

### Notes

- prefer late-bound stable callbacks over one-time hidden registration
- keep `Framework.init(...)` safe to rerun

## 3. Core Coordinator

Core owns:

- the coordinator config
- the game-readiness gate
- the stable GUI registration
- the call into Framework

### Preferred Pattern

```lua
local mods = rom.mods
mods["SGG_Modding-ENVY"].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN
game = rom.game
modutil = mods["SGG_Modding-ModUtil"]
chalk = mods["SGG_Modding-Chalk"]
reload = mods["SGG_Modding-ReLoad"]

config = chalk.auto("config.lua")
public.config = config

local Framework = mods["adamant-ModpackFramework"]

local PACK_ID = "my-pack"
local def = {
    NUM_PROFILES = #config.Profiles,
    defaultProfiles = {},
}

local function init()
    Framework.init({
        packId = PACK_ID,
        windowTitle = "My Pack",
        config = config,
        def = def,
        modutil = modutil,
    })
end

local loader = reload.auto_single()

modutil.once_loaded.game(function()
    rom.gui.add_imgui(Framework.getRenderer(PACK_ID))
    rom.gui.add_to_menu_bar(Framework.getMenuBar(PACK_ID))
    loader.load(init, init)
end)
```

### Notes

- GUI registration belongs in the coordinator, not Framework internals
- `loader.load(init, init)` is the default
- only split `on_ready` and `on_reload` if you have a specific one-time registration reason

## 4. Submodules

Submodules own:

- module definition
- module config
- module store/uiState
- module-local hook/bootstrap logic

### Preferred Pattern

```lua
local mods = rom.mods
mods["SGG_Modding-ENVY"].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN
game = rom.game
modutil = mods["SGG_Modding-ModUtil"]
chalk = mods["SGG_Modding-Chalk"]
reload = mods["SGG_Modding-ReLoad"]
local lib = mods["adamant-ModpackLib"]

local config = chalk.auto("config.lua")

MyModule_Internal = MyModule_Internal or {}
local internal = MyModule_Internal

public.definition = {
    modpack = "my-pack",
    id = "MyModule",
    name = "My Module",
    default = false,
    affectsRunData = true,
}

public.store = lib.createStore(config, public.definition)
internal.store = public.store

local function syncExports()
    public.DrawTab = internal.DrawTab
    public.DrawQuickContent = internal.DrawQuickContent
end

local function init()
    import_as_fallback(rom.game)

    import("mods/logic.lua")
    import("mods/ui.lua")

    if internal.RegisterHooks then
        internal.RegisterHooks()
    end

    syncExports()

    if lib.isEnabled(public.store, public.definition.modpack) then
        lib.applyDefinition(public.definition, public.store)
    end

    if public.definition.affectsRunData and not lib.isCoordinated(public.definition.modpack) then
        SetupRunData()
    end
end

local loader = reload.auto_single()

modutil.once_loaded.game(function()
    loader.load(init, init)
end)
```

### Notes

- `loader.load(init, init)` is the default submodule shape
- this keeps dev and shipped behavior aligned
- only use split `on_ready` / `on_reload` when the split is intentional and justified

## When To Split `on_ready` and `on_reload`

Use a split only when there is a real difference between:

- first-load-only setup
- rerunnable bootstrap

### Good `on_ready`-only candidates

- one-time GUI registration
- one-time global callback registration
- setup that is unsafe or pointless to repeat

### Good `on_reload` candidates

- reimporting logic/UI files
- re-syncing exported functions
- rebuilding module runtime state from persisted config
- reapplying enabled behavior from config

## Default Rule

If you do not have a concrete reason to split:

```lua
loader.load(init, init)
```

That is the default for this modpack stack.

## Current Run Director Guidance

Current intended pattern:

- Core coordinator: `loader.load(init, init)`
- Submodules: `loader.load(init, init)` by default
- Lib: no reload wrapper
- Framework: rerunnable `Framework.init(...)`, no reload wrapper

If a submodule uses only:

```lua
loader.load(init)
```

that means it is first-load-only for that file and will not rerun its bootstrap on plugin reload.

That should be treated as an explicit exception, not the default pattern.
