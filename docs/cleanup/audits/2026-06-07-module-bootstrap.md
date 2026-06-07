# Module Bootstrap Audit - 2026-06-07

Scope:

- `src/core/module_bootstrap/module.lua`
- `src/core/module_bootstrap/definition.lua`
- `src/core/module_bootstrap/managed_module.lua`
- `src/core/module_bootstrap/managed_module_activation.lua`
- `src/core/module_bootstrap/managed_module_lifecycle.lua`
- `src/core/module_bootstrap/module/*.lua`
- `src/core/module_bootstrap/ui/context.lua`
- module bootstrap tests and public docs/API notes

## Summary

Module bootstrap is now a coherent composition layer. The current split is:

- `module.lua`: public `lib.createModule(...)` entrypoint.
- `declaration_facade.lua`: author-facing declaration object and activation lifecycle.
- `declaration_surface.lua`: capability declaration namespaces and callback adaptation.
- `activation_finalizer.lua`: control/status compilation, definition preparation, state construction, live-module creation.
- `managed_module.lua`: live managed-module runtime object, UI/runtime context assembly, live reset/flush surfaces.
- `managed_module_activation.lua`: activation transaction and hot-reload replacement publish/rollback.
- `managed_module_lifecycle.lua`: draw commit, mutation sync, reset, pack enable/disable transitions.

No runtime correctness issue was found in the current activation transaction. The
earlier structural rebuild concerns are resolved: candidate effects are built,
mutation sync participates in the candidate commit, the replacement module is
published before Framework rebuild is requested, and rollback restores the
previous live module when activation/rebuild fails.

## Findings

- `keep`: Activation is a real transaction for managed effects. It rolls back
  Lib-managed hooks, shared events, overlays, mutation state, fallback runtime,
  and live-module publication on activation failure.
- `keep`: `module.resetAll(...)` on the live managed module is staged by design.
  Framework follows it with `commitIfDirty()` during global reset, matching the
  draw-lifecycle reset semantics.
- `keep`: `record.host` remains the correct name for the narrow callback host
  projection. It is distinct from the live managed module object.
- `document`: Public API wording had small stale residue: the overview omitted
  `module.status.define(...)`, said "That host owns" for the module declaration
  object, and one LuaCAT callback type used unqualified `Host` / `RuntimeContext`.
  These were updated in this pass.
- `keep`: `managed_module.lua` is large, but it is the live-module assembly
  point. Splitting it further would be a readability refactor, not current debt.

## Checks

Focused tests to keep using after module bootstrap edits:

```powershell
lua52.exe tests\all.lua TestCreateModule TestManagedModule TestManagedModule_PrepareDefinition TestModuleDefinitionContract
```

Useful follow-up scans:

```powershell
rg -n "createModule|module\.activate|managed_module\.|module\.status\.define|That host owns|host's module owner" src tests docs API.md
rg -n "Host|host" src/core/module_bootstrap src/def.lua API.md docs/module-authors
```
