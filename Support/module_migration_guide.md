# Module Migration Guide: Legacy Schema → Storage/UI API

## Overview

This guide covers migrating a module from the legacy `definition.stateSchema` API to the current `definition.storage` + `definition.ui` API.

---

## 1. Storage Layer

### Replace `definition.stateSchema` with `definition.storage`

**Before:**
```lua
definition.stateSchema = {
    { type = "checkbox", configKey = "MyFlag",   default = config.MyFlag },
    { type = "stepper",  configKey = "MyCount",  default = config.MyCount, min = 1, max = 10 },
    { type = "dropdown", configKey = "MyChoice", default = config.MyChoice },
}
```

**After:**
```lua
definition.storage = {
    { type = "bool",   configKey = "MyFlag",   default = false },
    { type = "int",    configKey = "MyCount",  default = 5, min = 1, max = 10 },
    { type = "string", configKey = "MyChoice", default = "" },
}
```

### Type mapping

| Legacy type  | Storage type |
|--------------|--------------|
| `checkbox`   | `bool`       |
| `stepper`    | `int`        |
| `int32`      | `int`        |
| `dropdown`   | `string`     |

### Default values must not drift with saved profiles

**Wrong:**
```lua
local config = chalk.auto('config.lua')
{ type = "bool", configKey = "MyFlag", default = config.MyFlag }  -- drifts as profiles are saved
```

**Correct:** pass `dataDefaults` to `lib.createStore` — the lib fills in missing defaults automatically:

```lua
local dataDefaults = import("config.lua")
local config = chalk.auto("config.lua")

public.store = lib.createStore(config, public.definition, dataDefaults)
```

Storage nodes need no `default` field at all — the lib looks up `dataDefaults[configKey]` for any node where `default` is absent:

```lua
definition.storage = {
    { type = "bool",   configKey = "MyFlag" },
    { type = "int",    configKey = "MyCount", min = 1, max = 10 },
    { type = "string", configKey = "MyChoice" },
}
```

`dataDefaults` is the raw config.lua table before chalk merges saved profile values on top. It always reflects the authored file values. For nodes where the default genuinely can't come from config.lua (e.g. dynamic range pairs derived from definition data), set `default` explicitly on the node and the lib will use that value instead.

---

## 2. UI Layer — Regular Modules

Regular modules declare a `definition.ui` tree. The lib renders it automatically; no custom draw code needed.

### Replace `definition.stateSchema` widget entries with `definition.ui` nodes

**Before:** widgets were mixed into `stateSchema` with implicit rendering.

**After:** declare a `ui` tree with explicit layout nodes:

```lua
definition.ui = {
    { type = "group", label = "My Settings", children = {
        { type = "checkbox", label = "Enable Flag", binds = { value = "MyFlag" } },
        { type = "stepper",  label = "Count",       binds = { value = "MyCount" }, min = 1, max = 10 },
        { type = "dropdown", label = "Choice",      binds = { value = "MyChoice" },
          values = myOptions, displayValues = myDisplayValues },
    }},
}
```

The `binds.value` string is the alias — matches the `configKey` in `definition.storage` unless an explicit `alias` was set on the storage node.

---

## 3. UI Layer — Special Modules (Custom DrawTab)

Special modules set `special = true` in their definition and implement `DrawTab`/`DrawQuickContent` themselves. They omit `definition.ui`. Instead they use `lib.prepareUiNodes` to get prepared widget nodes for use with `lib.drawUiNode`.

### Build the node list and call `lib.prepareUiNodes`

Do this **after** `lib.createStore` so storage aliases are resolved.

```lua
public.store = lib.createStore(config, definition)
store = public.store

local uiNodes = {
    { type = "dropdown", label = "My Choice", binds = { value = "MyChoice" },
      values = myOptions, displayValues = myDisplayValues },
    { type = "stepper",  label = "My Count",  binds = { value = "MyCount" }, min = 1, max = 10 },
}

-- Add dynamic nodes (e.g. one per definition entry)
for _, def in ipairs(internal.myDefinitions) do
    table.insert(uiNodes, {
        type = "steppedRange", label = "",
        binds = { min = def.configKeyMin, max = def.configKeyMax },
        min = def.minDefault, max = def.maxDefault,
        default = def.minDefault, defaultMax = def.maxDefault,
    })
end

internal.uiNodes = lib.prepareUiNodes(uiNodes, "MyModule ui", definition.storage)
```

`lib.prepareUiNodes` returns a single flat registry. Every alias declared in a node's `binds` table is a key — so a `steppedRange` with `binds = { min = "FooMin", max = "FooMax" }` is reachable by both `"FooMin"` and `"FooMax"`.

### Draw using the registry

```lua
local function DrawManagedField(ui, uiState, alias, width)
    local node = internal.uiNodes[alias]
    if not node then return end
    lib.drawUiNode(ui, node, uiState, width)
end
```

Use the same helper for all widget types — scalar, range, or any future multi-bind widget. Pass whichever alias is convenient (typically the primary/min alias).

### Replace `lib.drawField` call sites

**Before:**
```lua
lib.drawField(ui, schema, configKey, uiState, width)
```

**After:**
```lua
DrawManagedField(ui, uiState, alias, width)
```

---

## 4. Store creation and wiring

```lua
local dataDefaults = import("config.lua")
local config = chalk.auto("config.lua")

public.store = lib.createStore(config, definition, dataDefaults)
store = public.store
```

`createStore` replaces the old schema-based store initialisation. The third argument `dataDefaults` is the raw config.lua table — the lib uses it to fill in `default` for any storage node that doesn't declare one explicitly. The store exposes `store.read(alias)` / `store.write(alias, value)` and `store.uiState` for UI bindings.

---

## 5. Checklist

- [ ] `definition.stateSchema` removed, replaced with `definition.storage`
- [ ] `dataDefaults = import("config.lua")` declared before `chalk.auto`, passed as third arg to `lib.createStore`
- [ ] `default =` removed from storage nodes (lib derives from `dataDefaults` automatically); only keep explicit `default` on dynamic nodes whose value comes from definition data, not config
- [ ] Type names updated per mapping table above
- [ ] Regular module: `definition.ui` tree declared with `binds` declarations
- [ ] Special module: `lib.prepareUiNodes` called after `createStore`, result assigned to `internal.uiNodes`
- [ ] All `lib.drawField` call sites replaced with `lib.drawUiNode` (directly or via helpers)
- [ ] `definition.storage` has `min`/`max` set on int nodes where clamping is needed
