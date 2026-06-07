# Lib Bootstrap Primitives Audit

## Subsystem

Bootstrap primitives:

- `core/logging/logging.lua`
- `core/logging/policies.lua`
- `core/lib_bootstrap/registry.lua`
- `core/lib_bootstrap/module_registry.lua`
- `core/lib_bootstrap/system_scope.lua`
- `core/game_deps/game_deps.lua`
- `core/helpers/values.lua`

Current purpose:

These files form the low-dependency foundation for Lib. They provide diagnostics, hot-reload-stable runtime buckets, module record/live-module indexing, internal system ownership scopes, game-global boundary reads, and table copy/equality helpers.

Entry points:

- `logging.violate`, `logging.printWithPrefix`, `logging.printWithPrefixIf`
- `registry` buckets under `AdamantModpackLib_Runtime.registry`
- `moduleRegistry.get/setRecord`, `get/setLiveModule`, `get/setPluginInfo`, `get/setPendingCoordinatorRebuild`
- `systemScope.create`
- `gameDeps.cache`, `gameDeps.runData`, `gameDeps.overlays`
- `values.deepCopy`, `values.deepEqual`

Dependencies:

- `logging` depends only on config and policy definitions.
- `registry` depends only on the runtime root.
- `module_registry` depends only on the registry module bucket.
- `system_scope` depends on logging and injected capability factories.
- `game_deps` depends on `rom` and logging.
- `values` is pure.

State and lifecycle:

- `registry` and `module_registry` own hot-reload-stable buckets.
- `system_scope` creates internal non-module owners for hooks/overlays.
- `game_deps` intentionally late-reads game globals, avoiding stale snapshots across game reloads or harness mutation.
- `values` is stateless.

## Findings

- Severity: careful cleanup
  Evidence: `core/status/declarations.lua` uses `status.invalid_alias`, `status.invalid_declaration`, `status.invalid_declarations`, `status.invalid_field`, `status.invalid_persist`, and `status.missing_persist`; `core/module_state/storage_ref_adapter.lua` uses `storage.private_alias`. None are present in `core/logging/policies.lua`.
  Recommendation: Add policy entries for these IDs, then update policy coverage tests to scan all `src/core/**/*.lua` files instead of maintaining a manual file list.
  Risk: Low behavior risk, but high diagnostic value. Today these paths raise `violation.unknown_id`, so author-facing errors lose their intended classification and description.

- Severity: careful cleanup
  Evidence: `tests/TestLogging.lua` manually enumerates source files for policy coverage and omits `core/status/declarations.lua` and `core/module_state/storage_ref_adapter.lua`. Existing tests can still pass if another assertion only checks for the missing ID substring inside `violation.unknown_id`.
  Recommendation: Replace the hand-maintained file list with recursive discovery of Lua files under `src/core`, or centralize the list in a helper used by both orphan and missing-policy tests.
  Risk: Test-only change with strong payoff. It may reveal existing policy drift immediately.

- Severity: leave alone
  Evidence: `core/lib_bootstrap/registry.lua` only initializes stable buckets, and `core/lib_bootstrap/module_registry.lua` only wraps those buckets with named accessors.
  Recommendation: Keep these boring. They are doing the right amount of work for hot-reload state.
  Risk: Adding validation here would spread lifecycle policy into low-level storage.

- Severity: leave alone
  Evidence: `core/game_deps/game_deps.lua` validates expected boundary types and late-reads `rom.game` / game globals through narrow named functions.
  Recommendation: Keep this shape. Add new game dependencies here only when another subsystem needs a boundary, and keep validation at this edge.
  Risk: Low. This file is a good dependency boundary.

- Severity: leave alone
  Evidence: `core/helpers/values.lua` only exposes cycle-safe `deepCopy` and `deepEqual`, and usage is broad but appropriate for storage, shared data, controls, mutation plans, and overlays.
  Recommendation: Keep it pure and small. Do not add domain-specific helpers here.
  Risk: Low. It is a foundational utility with focused tests.

- Severity: safe cleanup
  Evidence: `core/logging/logging.lua` has a simple formatter/print surface used by managed module logs, and violation errors now include tracebacks.
  Recommendation: No structural change. Only improve policy coverage and diagnostics.
  Risk: Low.

## Decision Log

- Action: Mark bootstrap primitives audited.
  Reason: The core shapes are coherent. The only actionable issues are centralized logging policy coverage and missing policy entries.

- Action: Resolved logging policy drift.
  Reason: Added policy entries for status declaration and private storage alias diagnostics, then replaced the hand-maintained logging policy file list with recursive `src/core` discovery. Verified with the full Lib suite and a direct policy consistency scan.
