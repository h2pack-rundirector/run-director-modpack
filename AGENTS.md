# Agent Instructions

## Validation And Trust Boundaries

Prefer validating data at contact points, then trusting validated internals.

Contact points are the only places where broad shape/type validation belongs:
- `prepareDefinition(...)` owns module definition validation: required metadata, definition field names, stable module id/name rules, hash group hint shape, structural fingerprint inputs, and storage-schema handoff.
- Storage preparation owns storage validation: root aliases, packed child aliases, table row aliases, storage type fields, axes, defaults, packed bit layout, and table schema shape.
- `createStore(...)` owns config hydration validation: external config table shape, persisted values, and managed store/session construction.
- `createModuleHost(...)`, `createModule(...)`, `tryCreateModule(...)`, `activateModuleHost(...)`, and `tryActivateModule(...)` own host lifecycle validation: host opts, callback surfaces, owner/hot-reload semantics, activation rollback, hook/integration refresh, and structural reload boundaries.
- Registration APIs own their registries: hooks, overlays, integrations, game-object state, coordinators, widgets, and lifecycle callbacks validate inputs when registered.
- Framework/Core initialization owns pack-level external input: coordinator config, profiles, discovered modules, runtime prerequisites, HUD/UI setup, and hash/profile boundary behavior.
- Cross-language/external reads own their translation boundary: game state, config files, hash/profile strings, ROM APIs, ModUtil APIs, Chalk config, and user-editable data.

After a contact point validates or constructs a value, downstream Lib/Framework code should usually trust it:
- Framework discovery should trust prepared definitions and prepared storage metadata; it should not re-validate definition ids, storage aliases, or hash group key-prefix syntax.
- Store/session/widget/hash/profile internals should trust prepared storage nodes and alias maps; they should not repeat primitive alias/type checks unless accepting external keys or values.
- Hook/integration/overlay dispatch should trust registered callback records; it should not re-check callback shape at every internal hop.
- Module host internals should trust Lib-created stores, sessions, module hosts, author hosts, table handles, and prepared definitions.
- Framework runtime/UI code should trust Framework discovery snapshots produced by Framework discovery.

Distinguish optional nil-handling from defensive type-checking:

```lua
-- Keep: optional callback is absent.
if callback == nil then return true end

-- Avoid after construction/registration already validated callback shape.
if type(callback) ~= "function" then return true end
```

For impossible internal states, prefer one semantic invariant error over broad repeated audits. For example, use "expected managed store binding" rather than checking every field on a Lib-owned state table at every call site.

Do not paper over hot-reload partial-state bugs with scattered defensive checks. If a hot-reload edge case needs protection, validate or assert it at the reload boundary and add a test for that boundary.

Use LuaCATS annotations to document internal parameter types. Do not add runtime type checks only to restate annotations.

When removing defensive checks, keep tests focused on the boundary that owns the invariant.

## Composition And Ownership

Prefer explicit dependency composition over global buses.

Use persistent globals only for hot-reload-stable anchors or host-owned registries that must survive reload. Do not use them as a general dependency bus for data objects, services, helpers, or cross-file function gathering.

Preferred dependency patterns:
- Use `create(...)` for constructed data/runtime objects.
- Use `bind(...)` when a module captures dependencies and returns a bound behavior object.
- Use ENVY import args for small behavior files where import-time dependency capture is clearer than ceremony.
- Pass targeted dependencies, not broad `context` or `data` blobs, unless the object is genuinely the domain object being consumed.

Avoid fake objects and pure forwarding:
- Do not return module tables whose methods only forward to another table.
- Do not add `local module = {}` wrappers unless the file is actually modeling an object or public surface.
- Header/public files should own public function shape and orchestration.
- Private/support files should provide helper pieces used by that orchestration.

Global/stable anchors:
- Keep hot-reload-stable anchors for owner identity, hook/overlay lifecycle, and Lib/Framework runtime registries.
- Do not attach ordinary module data or implementation helpers to those anchors.
- If a module needs its own private bus, name it for that module-specific role rather than using generic `internal`.

Visibility:
- Prefer grep-visible ownership at public/API definition sites and important call sites.
- Avoid local aliases that only redirect one or two calls.
- Local aliases are acceptable when repeated heavily, capturing a real domain object, or improving semantic clarity.
- Avoid fake public wrappers that only forward to another table:

```lua
-- Avoid
function public.foo(...)
    return private.foo(...)
end
```
