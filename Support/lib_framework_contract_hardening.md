# Lib / Framework Contract Hardening

Stabilization document for `adamant-ModpackLib` and `adamant-ModpackFramework`.

Goal:

- identify the real contracts the system depends on today
- classify which ones are enforced vs assumed
- assess how brittle each contract is
- define how to harden the remaining weak points
- reduce the chance of another large module-fleet refactor unless a new feature or real bug requires it

This document is written against the current post-store-contract state:

- modules expose `public.store`
- special modules expose `public.store.specialState`
- Framework consumes `m.mod.store`
- standalone helpers are store-based
- the old special direct-config-write detector has been removed

---

## Executive Summary

The access architecture is now strong.

The most important contracts are no longer informal:

- module state goes through `public.store`
- special UI state goes through `public.store.specialState`
- Framework no longer depends on raw module config

The main remaining risks are no longer "how do modules talk to config?" They are:

1. hash / profile ABI stability
2. coordinator init/config shape
3. special UI entrypoint conventions
4. `apply` / `revert` mutation authoring contract
5. validation paths that warn but later runtime code still assumes validity

If those five surfaces are tightened, the system should be stable enough to leave alone except for new features and bug fixes.

---

## Severity Map

| Area | Current Strength | Brittleness | Why it matters |
|---|---|---|---|
| Module public surface (`public.definition`, `public.store`) | Good | Low-Medium | Core module ABI |
| Store access contract (`read/write`, `specialState`) | Good | Low | Main architecture is now solid |
| Special UI entrypoint naming (`DrawTab`, `DrawQuickContent`) | Weak | High | Easy to violate accidentally; silent no-op risk |
| Coordinator config / def shape | Weak | High | Framework assumes a lot; very little is validated |
| Hash / profile ABI | Weak | Very High | Most dangerous future-refactor surface |
| Schema / FieldType validation | Mixed | Medium | Warn-only validation disagrees with runtime assumptions |
| Framework staging coherency | Soft | Medium | External config mutation can stale UI state |
| `apply` / `revert` mutation contract | Soft | High | Major future refactor blast radius if tightened later |
| Store internals (`_config`, `_backend`) | Internally brittle | Medium | Mostly a Lib-internal concern today |
| Sidebar / coordinator option enums | Soft | Low | Easy to warn and normalize |

---

## 1. Module Public Surface Contract

### Current contract

Regular modules are expected to expose:

- `public.definition`
- `public.store`

Special modules are expected to expose:

- `public.definition`
- `public.store`
- `public.store.specialState`

### Current enforcement

Discovery checks:

- `definition.apply`
- `definition.revert`
- `public.store`
- `public.store.specialState` for specials

If missing, Framework warns and skips the module rather than crashing the whole pack.

### Brittleness

Low-Medium.

This is one of the better-enforced parts of the system now.

The main remaining weakness is that some important public behaviors are still inferred by naming convention rather than validated explicitly.

### Hardening actions

- Keep `public.store` as the one required state surface.
- Keep discovery skip-on-warn behavior for bad modules.
- Explicitly document `public.store` as frozen API.
- Do not reintroduce `public.config` or standalone `public.specialState`.

### Recommendation

Freeze this contract now.

This is stable enough to treat as ABI.

---

## 2. Special UI Entrypoint Contract

### Current contract

Framework expects special modules to expose one or both of:

- `public.DrawTab`
- `public.DrawQuickContent`

Those names are accessed directly at render time.

### Current enforcement

None at discovery.

Framework simply checks for those functions at draw time and renders nothing if they are absent.

### Brittleness

High.

This is the easiest contract to violate accidentally:

- wrong function name
- moving the function under a nested table
- forgetting to export it after refactor

Result today:

- the special still discovers
- the tab still exists
- UI may silently render nothing

### Hardening actions

- At discovery time, warn if a special exposes neither `DrawTab` nor `DrawQuickContent`.
- Optionally skip the special entirely if both are missing.
- Keep allowing only one of the two to exist.
- Document the names as required public entrypoints, not just examples.

### Recommendation

Do this soon.

It is a small change with high value and low blast radius.

---

## 3. Coordinator Init / Config Shape Contract

### Current contract

`Framework.init(params)` assumes:

- `params.packId`
- `params.windowTitle`
- `params.config`
- `params.def`
- `params.modutil`

It also assumes `params.config` contains:

- `ModEnabled`
- `DebugMode`
- `Profiles`

And that `params.def` contains:

- `NUM_PROFILES`
- `defaultProfiles`

Optional fields:

- `groupStyle`
- `groupStyleDefault`
- `categoryOrder`
- `sidebarOrder`
- `renderQuickSetup`

### Current enforcement

Very little.

There is no central validation or normalization step in `Framework.init(...)`.

### Brittleness

High.

This is one of the weakest remaining surfaces because:

- the full expected shape is spread across multiple files
- bad coordinator state can fail late
- profile UI is especially assumption-heavy

### Hardening actions

Add a coordinator validation/normalization step, for example:

- `Framework.validateInitParams(params)`
- or `Framework.normalizeInitParams(params)`

Recommended behavior:

- hard error on missing `packId`, `config`, `def`, `modutil`
- hard error or normalize on missing `Profiles`
- ensure `Profiles` is a table with `NUM_PROFILES` entries
- ensure each profile entry has `Name`, `Hash`, and `Tooltip`
- validate `sidebarOrder` against known constants
- validate `groupStyleDefault` against known constants

Suggested policy:

- coordinator contract violations should fail fast
- module contract violations should still warn-and-skip

### Recommendation

This is Tier 1 hardening work.

It reduces future coordinator-side breakage significantly.

---

## 4. Store Contract

### Current contract

The supported store surface is:

- `store.read(key)`
- `store.write(key, value)`
- `store.specialState` for special modules

Store instances are expected to be created via:

- `lib.createStore(config, schema?)`

### Current enforcement

Discovery checks `read` / `write`.

Framework uses only the public store surface.

### Brittleness

Low for module authors.

Medium internally, because Lib internals still reach into:

- `store._config`
- `store._backend`

### Important distinction

This is not currently a public-module fragility.

It becomes a fragility only if you decide that custom store implementations are supported.

Today, the clean rule should be:

- `lib.createStore(...)` is the only supported store constructor

If that rule is explicit, the `_config` / `_backend` coupling remains internal implementation debt, not public ABI debt.

### Hardening actions

- Explicitly document `lib.createStore(...)` as the only supported store constructor.
- Explicitly document that `_config` and `_backend` are private Lib internals.
- Do not support custom hand-rolled stores unless you are willing to refactor Lib internals first.

Optional future cleanup:

- move `_config` / `_backend` into a private weak table keyed by store
- keep the public store table clean

That is a nice cleanup, not an urgent stabilization task.

### Recommendation

Document the rule now. Refactor internals only if you later need custom store implementations.

---

## 5. SpecialState Contract

### Current contract

SpecialState exposes:

- `view`
- `get`
- `set`
- `update`
- `toggle`
- `reloadFromConfig`
- `flushToConfig`
- `isDirty`

Framework and standalone helpers both use that contract.

### Current enforcement

Good.

This contract is created only by Lib, and discovery requires `public.store.specialState` for special modules.

### Brittleness

Low-Medium.

The surface itself is clear.

The main soft assumption is lifecycle:

- `reloadFromConfig()` must happen after external config writes such as hash/profile application
- UI should not assume `specialState` auto-tracks out-of-band config mutation

### Hardening actions

- Freeze the `specialState` method surface.
- Keep flush orchestration in Lib/Framework, not in module code.
- Document that `specialState` is staged UI state, not a live mirror of persisted config.

Optional polish:

- make `set/update/toggle` no-op on unchanged values to avoid unnecessary dirty states

That is a performance/cleanliness improvement, not a correctness requirement.

### Recommendation

Treat this as stable and do not redesign it casually.

---

## 6. Schema / Field Descriptor Contract

### Current contract

Field descriptors are declaration tables that Lib and Framework enrich with cached metadata:

- `_schemaKey`
- `_imguiId`
- `_step`
- `_pushId`
- `_hashKey`

### Current enforcement

`validateSchema(...)` warns on:

- missing `type`
- missing `configKey`
- unknown type
- duplicate schema keys
- malformed `visibleIf`
- malformed field-specific data

### Brittleness

Medium-High.

Two reasons:

1. validation is largely warn-only
2. later runtime paths still assume validated fields are usable

This is the main inconsistency:

- `drawField(...)` gracefully handles unknown field types
- hash encode/decode assumes `lib.FieldTypes[field.type]` exists

That means:

- validation says "this is bad"
- runtime later says "this cannot be bad"

### Hardening actions

Make a decision and apply it consistently:

Option A:

- invalid field descriptors are skipped during validation/discovery

Option B:

- invalid field descriptors cause a hard failure at module discovery

Recommended practical version:

- for regular modules, invalid fields should be skipped with warning
- for hash encode/decode, unknown field types should warn-and-skip rather than crash

Also harden FieldType registration:

- document required FieldType methods explicitly
- optionally validate FieldType completeness at registration/load time

### Recommendation

This is Tier 2 hardening.

It is not as dangerous as hash ABI, but it is a real correctness mismatch.

---

## 7. Hash / Profile ABI Contract

### Current contract

The hash/profile system treats all of the following as serialized identity:

- regular `definition.id`
- regular option `configKey`
- special module `modName`
- special `stateSchema` keys
- field defaults
- field `toHash(...)` / `fromHash(...)`

### Current enforcement

Almost none.

There is version checking on the outer hash format, but not on semantic field identity.

### Brittleness

Very High.

This is the most dangerous future-refactor surface in the system.

Changing any of the above can silently alter:

- what gets encoded
- what gets omitted as "default"
- what old hashes mean
- whether old profiles still round-trip

### Why this matters

This is where "harmless cleanup" turns into deployed-module breakage.

It is the main place where a refactor can force pack-wide migration work later.

### Hardening actions

Treat hash identity as explicit ABI.

Write that down in one place:

- `definition.id` is frozen after release
- option `configKey` is frozen after release
- special module `modName` is frozen after release
- `stateSchema` keys are frozen after release
- changing field default is a compatibility change, not a cosmetic one
- changing `toHash/fromHash` is a compatibility change, not an internal implementation detail

If you need future renames:

- add explicit migration shims in hash apply
- or bump format version and implement migration logic deliberately

Do not rely on implicit field renames.

### Recommendation

This is Tier 1 hardening and should be written as policy, not left as tribal knowledge.

---

## 8. Framework Staging Coherency Contract

### Current contract

Framework keeps plain Lua staging for:

- regular module enabled states
- regular module option values
- special enabled states
- per-entry debug state
- profiles

Special schema-backed state is handled separately by `specialState`.

### Current enforcement

None beyond the known update paths:

- init
- profile/hash load
- Framework-owned UI interactions

### Brittleness

Medium.

If something outside Framework changes persisted config while the UI is open:

- regular-module staging may go stale
- cached hash may go stale
- special enabled booleans in staging may go stale

### Hardening actions

Decide ownership explicitly:

Recommended policy:

- Framework owns UI-side regular module state while the window is open
- out-of-band config mutation is unsupported unless followed by explicit resync

If you want to harden this further later:

- add a manual `resync` / `reload` control
- or expose a Framework-level `resnapshot` helper

Do not add expensive constant runtime sync checks.

### Recommendation

Document this assumption and leave it soft unless a real bug forces stronger synchronization.

---

## 9. `apply` / `revert` and `dataMutation` Contract

### Current contract

Framework and Lib assume:

- module authors back up every targeted game-data change correctly
- `revert` fully restores baseline
- `apply` is safe enough to call repeatedly
- `definition.dataMutation` is set correctly

### Current enforcement

Very little.

Framework only orchestrates calls. It does not verify correctness.

### Brittleness

High.

This is one of the most important future-refactor surfaces, even though it is not a hidden plumbing contract.

Why:

- every mutation module currently owns its own backup/revert discipline
- there is no shared authoring primitive
- if you later want tighter guarantees, many module implementations must change

### Hardening actions

The right tightening is not runtime policing.

The right tightening is a narrower authoring surface.

Recommended direction:

1. split mutation modules into explicit modes

- `mutationMode = "patch"`
- `mutationMode = "manual"`

2. introduce a Lib-owned mutation plan / patch helper for the common case

Example shape:

```lua
local plan = lib.createMutationPlan()
plan:set(tbl, "Key", value)
plan:path(tbl, { "Parent", "Child" }, value)
plan:merge(tbl, "SubTable", patch)
```

3. make patch-plan style the preferred/default path

4. keep `manual` as an explicit advanced escape hatch

### Why this matters

This is the contract most likely to trigger another painful multi-module refactor if left loose and then tightened later.

### Recommendation

This is Tier 1 future-blast-radius hardening.

Even if you do not implement the patch-plan system immediately, you should at least document:

- `apply/revert` is currently author-owned
- `dataMutation` is a semantic contract
- a future tightening may replace manual backup/revert with a Lib-owned patch model

---

## 10. Standalone Contract

### Current contract

Every module should still work without Framework:

- regular modules via `lib.standaloneUI(...)`
- special modules via `lib.standaloneSpecialUI(...)`

Both now consume `store`.

### Current enforcement

Good enough.

Standalone helpers are now aligned with the store contract and no longer leak raw config as the normal pattern.

### Brittleness

Low-Medium.

The main risk here is not architectural anymore. It is divergence between hosted and standalone behavior over time.

### Hardening actions

- Treat standalone helpers as first-class contract surfaces.
- Keep them using store and `specialState`.
- Avoid adding coordinator-only assumptions into standalone paths.

### Recommendation

Stable enough. No urgent hardening needed.

---

## 11. Internal Lib Implementation Contracts

### Current contract

Lib still has some internal-only assumptions:

- store internals (`_config`, `_backend`)
- shared internal namespace tables
- Chalk backend caching structure

### Current enforcement

Implicit.

### Brittleness

Medium, but mostly inside Lib.

This matters for Lib refactors, not for module authors, as long as:

- `createStore(...)` remains the only supported store constructor
- internal namespace patterns stay private

### Hardening actions

- Explicitly distinguish public API vs internal coupling in docs.
- Avoid promoting underscore-prefixed fields in examples.
- If you later need cleaner internals, move store private data out of the public table.

### Recommendation

Low urgency. Important to document, not urgent to redesign.

---

## 12. Low-Severity Contract Gaps

These are real but not worth major churn.

### `sidebarOrder` / enum typos

Current behavior:

- unknown values silently fall back to default behavior

Recommended action:

- warn on unknown enum values at init normalization

### `runSpecialUiPass(...)` direct-call assumptions

Current behavior:

- normal Framework/standalone paths are safe
- direct ad hoc callers can still misuse it

Recommended action:

- document it as Lib-owned orchestration helper, not a general-purpose public utility for arbitrary callers

---

## Hardening Priorities

### Tier 1: highest leverage, lowest regret

1. Formalize hash/profile ABI policy
2. Add coordinator init/config validation and normalization
3. Add discovery validation for special UI entrypoints
4. Write down the `apply/revert` / `dataMutation` authoring contract as a future tightening target

### Tier 2: important consistency work

5. Make hash encode/decode resilient to invalid field types
6. Decide whether invalid field descriptors are skipped or fatal, and apply that policy consistently
7. Document `createStore(...)` as the only supported store constructor

### Tier 3: cleanup and polish

8. Add optional resnapshot path for Framework staging if a real bug requires it
9. Normalize / warn on enum-like coordinator options
10. Optionally hide store internals in a private weak table later

---

## Freeze List

Unless you are intentionally introducing a compatibility break, do not casually change:

- `public.store` public shape
- `specialState` public shape
- `definition.id`
- regular option `configKey`
- special module `modName`
- special schema keys
- field defaults
- hash serialization behavior
- special UI entrypoint names

These should be treated as ABI, not implementation detail.

---

## Intentional Soft Areas

Some parts should stay intentionally soft unless a real problem appears:

- Framework staging coherence under out-of-band config mutation
- standalone helper behavior beyond store/specialState alignment
- internal store backing implementation
- low-risk enum typos with safe fallback behavior

Do not tighten these just for theoretical purity.

---

## Recommended Next Moves

If the goal is to tighten Lib/Framework and then mostly leave them alone:

1. Add a coordinator validation/normalization step.
2. Add discovery-time special UI entrypoint validation.
3. Write one short hash ABI policy document or section in contributing docs.
4. Decide whether the future mutation contract will stay manual or move toward a Lib patch-plan model.
5. After that, stop refactoring contract surfaces unless a new feature or real bug requires it.

That should close the most important remaining gaps without reopening the whole architecture.
