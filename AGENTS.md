# Agent Instructions

## Validation And Trust Boundaries

Prefer validating data at trust boundaries, then trusting validated internals.

Keep strong runtime validation where data crosses from outside our control into Lib/Framework:
- Public module-author APIs such as `prepareDefinition`, `createStore`, `createModuleHost`, and `standaloneHost`.
- Storage schema preparation and storage type validation.
- Registration APIs for hooks, overlays, integrations, game-object state, coordinators, and widgets.
- Framework/Core initialization boundaries.
- Cross-language or external data reads from game state, config files, hash/profile input, or ROM/ModUtil APIs.

Avoid repeating primitive type checks at internal hops after a value has already been validated or constructed by our own code. Internal Lib/Framework functions should usually trust:
- Prepared definitions and prepared storage metadata.
- Lib-created stores, sessions, module hosts, and table handles.
- Lib-owned registration tables and callbacks after registration.
- Framework discovery snapshots produced by Framework discovery.

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
