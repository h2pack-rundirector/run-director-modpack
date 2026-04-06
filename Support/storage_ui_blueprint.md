# Storage/UI Migration Blueprint

## Purpose
This document is the source of truth for the hard-cut migration from:
- `definition.stateSchema`
- `definition.options`

to:
- `definition.storage`
- `definition.ui`

No compatibility layer is kept. Every migrated module must follow the rules here.

## Core Rules
- Every packed child storage node has a required module-unique `alias`.
- Root storage aliases default to `configKey` when omitted, though explicit aliases are still recommended.
- Root storage nodes own `configKey` and persistence.
- Packed containers may own child aliases, but only the root persists and hashes.
- Widgets bind by alias, never by `configKey`.
- Layout nodes never persist data.
- `visibleIf` references:
  - a bool alias string
  - or a structured alias condition
- `store.read(keyOrAlias)` and `store.write(keyOrAlias, value)` are the normal access surface.
- `store.readBits(configKey, offset, width)` and `store.writeBits(configKey, offset, width, value)` are the raw packed escape hatch.

## Generic Translation Rules

### Scalar field to storage + widget
Old:

```lua
{ type = "checkbox", configKey = "FooEnabled", label = "Foo" }
```

New:

```lua
storage = {
    { type = "bool", alias = "FooEnabled", configKey = "FooEnabled", default = config.FooEnabled },
}

ui = {
    { type = "checkbox", binds = { value = "FooEnabled" }, label = "Foo" },
}
```

### Old dropdown/radio/stepper
- Storage becomes `string` or `int`.
- UI node keeps widget type and binds through `bind`.

### Old steppedRange
Old:
- one composite field descriptor with `configKeyMin` + `configKeyMax`

New:
- two scalar storage aliases
- one `steppedRange` UI node with `binds.min` + `binds.max`

### Packed int config
Current hard-cut policy:
- If a module only treats a packed value as a raw mask, keep it as root `int` storage.
- Only introduce `packedInt` child aliases when Lib-owned UI or alias-addressable packed subfields are needed.

### Visibility
Old:
- `visibleIf = "ConfigKey"`

New:
- `visibleIf = "Alias"`
- or `visibleIf = { alias = "Alias", value = ... }`
- or `visibleIf = { alias = "Alias", anyOf = { ... } }`

## Module Inventory

### adamant-RunDirectorGodPool
Current declaration surface:
- plain regular module
- all persisted values are scalar config keys
- UI is hosted and fully declarative

Target storage model:
- scalar storage aliases matching current config keys exactly

Target UI model:
- declarative `definition.ui`
- section separators remain layout nodes
- all controls bind by alias

Alias decisions:
- use existing config key names verbatim to minimize churn in runtime logic

Packed layout decisions:
- none

Special rendering conversions:
- none

Status:
- migrated

### adamant-RunDirectorBoonBans
Current declaration surface:
- special module
- mixed scalar settings plus many `Packed*` config values
- most UI is custom-drawn in module code

Target storage model:
- scalar storage aliases matching current config keys
- raw packed masks remain root `int` storage for now
- `definition.ui` stays empty until the custom UI is intentionally lifted into reusable nodes

Target UI model:
- custom `DrawQuickContent` / `DrawTab` continue to own layout
- custom UI reads and writes alias-backed `uiState`
- future packed alias work can move individual masks from root `int` to `packedInt`

Alias decisions:
- use current config key names verbatim

Packed layout decisions:
- current patch keeps `Packed*` values as raw root ints
- future packed alias rollout should group by logical container, not by historical prefix alone

Special rendering conversions:
- custom UI helpers continue to use `uiState.view.Alias` and `uiState.set("Alias", value)`

Status:
- storage migrated
- UI intentionally remains custom

### adamant-BiomeControl
Current declaration surface:
- special module
- mixed scalar settings, packed mode ints, and many range pairs
- UI is mostly custom but already benefits from reusable widget nodes

Target storage model:
- scalar storage aliases matching current config keys
- raw packed mode values remain root `int` storage
- every range endpoint is its own scalar storage alias

Target UI model:
- reusable UI nodes registered once at load time
- custom screens look up nodes by alias and call generic node render helpers
- `steppedRange` is the canonical range widget and binds by alias pair

Alias decisions:
- use config key names as aliases for all scalar and range endpoints

Packed layout decisions:
- keep packed mode keys as raw root ints for this patch
- defer child packed aliases until there is a real Lib-owned binding use case

Special rendering conversions:
- `schemaFieldByConfigKey` becomes `uiNodeByAlias`
- `rangeFieldByConfigKeyMin` becomes `rangeNodeByMinAlias`
- generic node rendering replaces ad-hoc field helper calls

Status:
- storage migrated
- custom UI partially re-pointed to alias-bound nodes

## Runtime Access Rules
- Runtime logic may keep using `store.read("ConfigKey")` and `store.write("ConfigKey", value)` as long as the alias matches the old config key.
- New reusable UI code should prefer alias names conceptually even when they equal the raw key.
- Custom special UI should prefer `uiState.get(alias)`, `uiState.view[alias]`, and `uiState.set(alias, value)`.

## Follow-Up Work
- Convert raw packed root ints to `packedInt` only when:
  - child alias addressing is needed
  - or Lib-owned hosted widgets need to bind into the packed value
- Replace old docs and tests that still mention field-centric APIs
- Extend module READMEs after the Lib docs are rewritten
