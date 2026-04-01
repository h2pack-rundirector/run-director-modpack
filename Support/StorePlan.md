# Plan: Replace Raw Module Config Access with `lib.createStore(...)`

## Summary

Redesign the module contract so modules no longer expose raw Chalk config by default. `adamant-ModpackLib` provides a single entry point, `lib.createStore(config, schema?)`, which owns persisted config access and, for special modules, staged UI state. `createSpecialState(...)` becomes an internal implementation detail of that store.

This pass includes both:
- the reusable Lib/Framework contract
- migration of the current Run Director modules (`God Pool`, `Encounters`, `Boon Bans`) to that contract now

Chosen defaults:
- use a Lib-owned **store facade**
- migrate all three current modules in this pass
- keep direct-config-write detection as a **legacy special-module safety net**
- remove both `public.config` and standalone `public.specialState` from the target module contract

## Key Changes

### 1. New Lib entry point: `lib.createStore(config, schema?)`
Add `lib.createStore(config, schema?)` as the only module-facing state entry point.

Behavior:
- regular modules call `lib.createStore(config)`
- special modules call `lib.createStore(config, definition.stateSchema)`
- `createSpecialState(...)` becomes internal to `createStore(...)`

Store surface:
- `store.read(key)`
- `store.write(key, value)`
- `store.specialState` only when a schema is provided

Special-state surface remains:
- `view`
- `get/set/update/toggle`
- `reloadFromConfig`
- `flushToConfig`
- `isDirty`

Not part of the new surface:
- no `public.config`
- no standalone `public.specialState`
- no extra `store.view`, `store.reload`, or `store.flush` aliases

### 2. Lib implementation changes
Refactor `adamant-ModpackLib` so the optimized Chalk backend is fully owned by the store layer.

Implementation changes:
- `getConfigBackend(...)` becomes an internal detail used by `createStore(...)`
- `createSpecialState(...)` is no longer a public entry point modules call directly
- store-backed persisted reads/writes become the default path for all module code
- special-state creation, cached Chalk entries, and dirty/flush behavior stay behind the store contract

Direct-config-write detection:
- remains special-only
- continues to run through the special UI pass and special-state schema
- is documented and treated as a legacy/bypass debug tool, not primary enforcement

### 3. Framework consumes `m.mod.store`
Update Framework so it reads/writes module state through `m.mod.store`.

Concrete substitutions:
- `m.mod.config.Enabled` becomes `m.mod.store.read("Enabled")` / `m.mod.store.write("Enabled", value)`
- `m.mod.config[configKey]` becomes `m.mod.store.read(configKey)` / `m.mod.store.write(configKey, value)`
- Framework special access uses `m.mod.store.specialState`

Apply this in:
- Discovery enable/debug reads and writes
- UI staging snapshot
- option change handlers
- hash encode/decode
- special reload-from-config paths after hash/profile load

The Framework contract becomes:
- regular modules expose `public.store`
- special modules expose `public.store`
- Framework uses `m.mod.store.specialState` when `definition.special = true`

### 4. Migrate the current Run Director modules
Migrate all three current modules to the new store contract.

God Pool:
- create `public.store = lib.createStore(config)`
- stop exporting `public.config`
- runtime logic and helpers read/write persisted values through the store

Encounters:
- create `public.store = lib.createStore(config, public.definition.stateSchema)`
- stop exporting both `public.config` and standalone `public.specialState`
- UI reads `public.store.specialState`
- runtime logic uses persisted store reads
- Framework consumes `m.mod.store.specialState`

Boon Bans:
- create `public.store = lib.createStore(config, public.definition.stateSchema)`
- stop exporting both `public.config` and standalone `public.specialState`
- UI remains `specialState`-driven through `public.store.specialState`
- runtime/helpers use persisted store access instead of raw config visibility

Module coding rule after migration:
- imported files should not have raw Chalk config in scope
- UI files mutate only through `store.specialState`
- runtime files read persisted values through `store.read(...)`
- deliberate bypass still exists, but accidental direct config writes are no longer the default failure mode

### 5. Docs and contract tightening
Update Lib/Framework docs to reflect the new rule:

- modules should expose `public.store`, not raw config
- `lib.createStore(...)` is the single state entry point
- special modules do not expose a second standalone `public.specialState`
- direct-config-write detection is a legacy safety net for special UI misuse
- regular and special modules share one top-level store contract, while retaining different persisted vs staged semantics underneath

## Test Plan

### Lib
- add tests for `lib.createStore(config)` persisted reads/writes
- add tests for `lib.createStore(config, schema)` returning `store.specialState`
- verify special store creation still stages, flushes, reloads, and uses the Chalk fast path
- verify direct-config-write detection still warns for special modules when enabled

### Framework
- verify discovery, staging snapshot, and option changes use `m.mod.store`
- verify hash export/import still round-trips for regular and special modules
- verify profile load reloads `m.mod.store.specialState` correctly
- verify special enable/disable and `dataMutation` behavior is unchanged

### Module acceptance
God Pool:
- all regular options still render and persist correctly through `store.read/write`

Encounters:
- special UI edits still apply through `store.specialState`
- runtime behavior still sees persisted values after flush

Boon Bans:
- UI remains responsive and correctly staged through `store.specialState`
- runtime helpers still read persisted values through `store.read(...)`
- batch UI actions still work under the new contract

### Regression focus
- no `public.config` remains in the migrated modules
- no standalone `public.specialState` remains in the migrated modules
- no imported module file should need `chalk.auto(...)`
- direct-config-write detection still works when deliberately bypassed in a special UI path
- rendering performance should remain at least as good as the current post-optimization baseline

## Assumptions

- raw Chalk config should no longer be part of the normal public module contract
- `public.store` is the single outward-facing module state surface
- `createSpecialState(...)` remains as internal Lib machinery, not a public module API
- direct-config-write detection remains opt-in debug tooling and is not expanded further
- migration includes the three current Run Director modules in this pass
