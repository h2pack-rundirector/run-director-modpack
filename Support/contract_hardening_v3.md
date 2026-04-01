# Lib / Framework Contract Hardening v3

Merged stabilization document for `adamant-ModpackLib` and `adamant-ModpackFramework`.

Purpose:

- define the real contracts the system depends on today
- separate public ABI from internal implementation details
- identify which assumptions are enforced, which are only conventions, and which are still brittle
- turn the highest-value weak points into concrete hardening tasks
- reduce the chance of another large module-fleet refactor unless a new feature or real bug truly requires it

Written against the current post-store-contract, post-debug-detection-removal state:

- modules expose `public.store`
- special modules expose `public.store.specialState`
- Framework consumes `m.mod.store`
- standalone helpers are store-based
- the direct-config-write detector is removed

---

## Executive Summary

The architecture is now in a much better place.

The strongest improvement is that module state access is no longer an informal pattern:

- regular state goes through `public.store`
- special UI state goes through `public.store.specialState`
- Framework no longer depends on raw module config

That means the biggest remaining risks are no longer about config access. They are:

1. hash / profile ABI stability
2. coordinator init / config shape
3. special UI public entrypoint conventions
4. `apply` / `revert` mutation authoring contract
5. validation/runtime mismatches around schema and field types

If those five surfaces are tightened, Lib/Framework should be stable enough to mostly stop changing except for real features and bug fixes.

---

## What Is Already Solid

These areas are in good shape and should not be casually redesigned:

- **Store access contract**
  - `public.store`
  - `store.read(...)`
  - `store.write(...)`
  - `store.specialState`
- **SpecialState surface**
  - `view`
  - `get/set/update/toggle`
  - `reloadFromConfig`
  - `flushToConfig`
  - `isDirty`
- **Discovery skip-on-warn behavior**
  - malformed modules do not crash the whole pack
- **Hash two-phase application**
  - decoded values are written before enable/apply runs
  - `specialState.reloadFromConfig()` happens after special schema writes
- **Standalone alignment**
  - standalone helpers now teach the same store/specialState contract as hosted mode

These should be treated as stable architecture, not active refactor targets.

---

## Severity Map

| Area | Current Strength | Brittleness | Why it matters |
|---|---|---|---|
| Module public surface (`public.definition`, `public.store`) | Good | Low-Medium | Core module ABI |
| Store access contract (`read/write`, `specialState`) | Good | Low | Main architecture is now solid |
| Special UI entrypoint naming (`DrawTab`, `DrawQuickContent`) | Weak | High | Easy to violate accidentally; silent empty-tab risk |
| Coordinator config / def shape | Weak | High | Framework assumes a lot; little centralized validation |
| Hash / profile ABI | Weak | Very High | Most dangerous future-refactor surface |
| Schema / FieldType validation | Mixed | Medium | Warn-only validation disagrees with runtime assumptions |
| Framework staging coherency | Soft | Medium | External config mutation can stale UI state |
| `apply` / `revert` mutation contract | Soft | High | Large future blast radius if tightened later |
| Store internals (`_config`, `_backend`) | Internally brittle | Medium | Mostly a Lib-internal concern today |
| Enum-like coordinator options (`sidebarOrder`, group styles) | Soft | Low | Easy to normalize/warn |

---

## Freeze Lists

There are two different kinds of “do not casually change this”.

### Public Interface Freeze

These are public contracts consumed by Framework, standalone helpers, or modules:

- `public.store` shape
- `specialState` shape
- `DrawTab`
- `DrawQuickContent`
- `Framework.init(params)` top-level contract
- standalone helper signatures

Changing these is a contract break, but not necessarily a serialization break.

### Serialization / Profile ABI Freeze

These are identity-bearing and must be treated as serialized ABI:

- regular `definition.id`
- regular option `configKey`
- special module `modName`
- special schema `configKey`
- field defaults
- `toHash(...)`
- `fromHash(...)`

Changing these without deliberate migration work can silently break:

- saved profiles
- shared hashes
- old pack compatibility

These are the most dangerous “cleanup” surfaces in the whole system.

---

## 1. Module Public Surface Contract

### Current contract

Regular modules must expose:

- `public.definition`
- `public.store`

Special modules must expose:

- `public.definition`
- `public.store`
- `public.store.specialState`

### Current enforcement

Discovery validates:

- `definition.apply`
- `definition.revert`
- `public.store`
- `public.store.specialState` for specials

If missing, Framework warns and skips the module.

### Brittleness

Low-Medium.

This is one of the better-enforced parts of the system now.

### Hardening action

- Keep `public.store` as the only outward state surface.
- Do not reintroduce `public.config` or standalone `public.specialState`.
- Explicitly document `public.store` as frozen public API.

### Recommendation

Freeze this now.

---

## 2. Special UI Entrypoint Contract

### Current contract

Framework expects special modules to expose one or both of:

- `public.DrawTab`
- `public.DrawQuickContent`

These are accessed directly by name during UI rendering.

### Current enforcement

None at discovery.

If they are missing, the special can still discover and its tab can still exist. It may simply render nothing.

### Brittleness

High.

This is one of the easiest accidental contract violations:

- typo in export name
- function moved under a nested table
- forgotten export after refactor

### Concrete hardening task

**Files:** `adamant-ModpackFramework/src/discovery.lua`, `adamant-ModpackFramework/src/ui.lua`

Add a discovery-time warning if a special exposes neither entrypoint:

```lua
if not mod.DrawTab and not mod.DrawQuickContent then
    lib.warn(packId, config.DebugMode,
        "%s: special module exposes neither DrawTab nor DrawQuickContent; tab will be empty",
        modName)
end
```

Do not skip the special automatically. A special with no custom content but meaningful enable/disable behavior may still be legitimate.

### Recommendation

Tier 1. Small change, high value.

---

## 3. Coordinator Init / Config Shape Contract

### Current contract

`Framework.init(params)` assumes:

- `params.packId`
- `params.windowTitle`
- `params.config`
- `params.def`

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

There is no central validation or normalization step at init time.

### Brittleness

High.

This is one of the weakest remaining surfaces because:

- the required shape is spread across `main.lua`, `ui.lua`, `hud.lua`, and `hash.lua`
- malformed coordinator config can fail late
- `Profiles` is especially assumption-heavy

Important correction to prior analysis:

- missing or malformed `Profiles` is not always a harmless silent degrade
- some malformed states can fail weirdly or late, not just render an empty UI

### Concrete hardening task

**File:** `adamant-ModpackFramework/src/main.lua`

Add a validation/normalization helper called at the top of `Framework.init(...)`.

Recommended policy:

- coordinator contract violations should fail fast
- module contract violations should still warn-and-skip

Recommended checks:

- `packId` must be non-empty string
- `config` must be table
- `def` must be table
- `NUM_PROFILES` must be positive integer/number
- `config.Profiles` must exist and be a table
- each `Profiles[i]` must exist for `1..NUM_PROFILES`
- each profile entry should be normalized to have:
  - `Name`
  - `Hash`
  - `Tooltip`

Also normalize/warn for:

- unknown `sidebarOrder`
- unknown `groupStyleDefault`

### Recommendation

Tier 1. This is one of the highest-value hardening steps left.

---

## 4. Store Contract

### Current contract

The supported store surface is:

- `store.read(key)`
- `store.write(key, value)`
- `store.specialState` for special modules

Stores are expected to come from:

- `lib.createStore(config, schema?)`

### Current enforcement

Discovery checks `read` / `write`.
Framework uses only the public store surface.

### Brittleness

Low for module authors.

Medium internally, because Lib internals still use:

- `store._config`
- `store._backend`

### Important distinction

This is not a public contract problem today unless you intend to support custom store implementations.

As long as the rule is:

- `lib.createStore(...)` is the only supported store constructor

then `_config` / `_backend` remain internal implementation details, not public ABI.

### Concrete hardening tasks

**Documentation**

- explicitly document `lib.createStore(...)` as the only supported store constructor
- explicitly document `_config` and `_backend` as private internals

**Code**

`public.getConfigBackend(...)` should probably stop being public.

**File:** `adamant-ModpackLib/src/core.lua`

Reason:

- it is now mostly an implementation detail of store creation
- leaving it public creates a bypass surface around the store contract

### Recommendation

Tier 2 for documentation.
Tier 3 for making `getConfigBackend` local/internal.

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

### Current enforcement

Good.

This contract is created only by Lib and required by discovery for special modules.

### Brittleness

Low-Medium.

The surface is clear. The main remaining soft assumption is lifecycle:

- `reloadFromConfig()` must be called after external persisted writes such as hash/profile apply
- `specialState` is staged UI state, not a live mirror of config

### Concrete hardening tasks

- Freeze the method surface.
- Keep flush orchestration in Lib/Framework rather than modules.
- Document the lifecycle more explicitly.

Small cleanup item:

**File:** `adamant-ModpackLib/src/special.lua`

Add a nil/malformed-state guard in `runSpecialUiPass(...)`:

```lua
if not specialState or type(specialState.isDirty) ~= "function" then
    libWarn("runSpecialUiPass: specialState is missing or malformed; pass skipped")
    return false
end
```

This is low severity because normal Framework/standalone paths are already safe, but it is cheap hardening.

### Recommendation

Treat this as stable.
Only polish around the edges.

---

## 6. Schema / Field Descriptor Contract

### Current contract

Field descriptors are declaration tables that Lib/Framework enrich in place with cached metadata:

- `_schemaKey`
- `_imguiId`
- `_step`
- `_pushId`
- `_hashKey`
- stepper display caches

Schema tables also receive:

- `_configFields`

### Current enforcement

`validateSchema(...)` warns on:

- missing type
- missing `configKey`
- unknown type
- duplicate keys
- malformed `visibleIf`
- malformed field-specific data

### Brittleness

Medium-High.

Two real issues exist:

1. validation is warn-only
2. some runtime paths still assume validation success

Main inconsistency:

- `drawField(...)` is resilient to unknown types
- hash encode/decode assumes the type exists

### Concrete hardening tasks

#### 6.1 Make hash resilient to unknown field types

**File:** `adamant-ModpackFramework/src/hash.lua`

Guard `EncodeValue(...)` / `DecodeValue(...)`:

- warn and skip on encode
- warn and use default on decode

#### 6.2 Make validation and runtime agree

Recommended direction:

- if a field type is unknown, do not let that field participate in schema pipelines

That means:

- either skip invalid fields during validation/discovery
- or make invalid schema fatal at discovery time

Practical recommendation:

- skip with warning
- do not crash at hash time later

#### 6.3 Document field/schema mutation in place

This is a real documentation gap.

Because Lib mutates descriptor tables in place:

- schemas should be declared freshly in loader/module setup code
- field tables should not be shared across modules/schemas
- descriptor objects should not be treated as immutable pure data after validation

### Recommendation

Tier 2. This is important consistency work.

---

## 7. Hash / Profile ABI Contract

### Current contract

The following are effectively serialized ABI:

- regular `definition.id`
- option `configKey`
- special module `modName`
- special schema `configKey`
- field defaults
- field serialization semantics

### Current enforcement

Almost none.

The hash version only protects outer format, not semantic identity changes.

### Brittleness

Very High.

This is the most dangerous future-refactor surface in the entire system.

### Important correction to earlier analysis

Do not overstate `_hashKey` as a universal rename solution.

- for regular options, `_hashKey` can support deliberate compatibility work
- for special schema fields, there is no equivalent general rename facility today
- for module ids and special `modName`, there is no generic safety net

So the safe rule remains:

- renames are compatibility work
- not a casual refactor

### Concrete hardening tasks

Document hash ABI explicitly in one authoritative place.

Required policy:

- `definition.id` is frozen after release
- option `configKey` is frozen after release
- special `modName` is frozen after release
- special schema keys are frozen after release
- changing `field.default` is compatibility work
- changing `toHash/fromHash` is compatibility work

If you need to change these:

- add explicit migration logic in hash application
- or version the format and migrate deliberately

Do not rely on silent decode-to-default behavior.

### Recommendation

Tier 1. This is the highest-risk surface to leave undocumented.

---

## 8. Framework Staging Coherency Contract

### Current contract

Framework keeps staging for:

- regular module enabled states
- regular module option values
- special enabled states
- per-entry debug values
- profiles

Special schema-backed state is handled separately by `specialState`.

### Current enforcement

None beyond known resync points:

- init
- profile/hash apply
- Framework-owned UI interactions

### Brittleness

Medium.

If something outside Framework mutates persisted config while the window is open:

- staging can go stale
- cached hash can go stale
- special enabled booleans can go stale

### Concrete hardening tasks

This should mostly remain a documented ownership assumption, not a heavily engineered feature.

Recommended policy:

- Framework owns UI-side regular-module state while the window is open
- out-of-band config mutation is unsupported unless followed by explicit resync

Optional future addition if a real bug requires it:

- manual `resnapshot` / `reload` action

Do not reintroduce expensive continuous sync/debug checks.

### Recommendation

Keep this soft unless a real bug forces stronger synchronization.

---

## 9. `apply` / `revert` and `dataMutation` Contract

### Current contract

Framework/Lib assume:

- authors back up every targeted game-data mutation correctly
- `revert` fully restores baseline
- `apply` is safe enough to call repeatedly
- `definition.dataMutation` is set correctly

### Current enforcement

Very little.

Framework orchestrates calls. It does not verify correctness.

### Brittleness

High.

This is one of the highest future blast-radius surfaces in the system.

Why:

- every mutation module currently owns its own backup/revert discipline
- there is no shared authoring primitive
- if you tighten this later, many modules must be touched

### Existing mitigation

Lib already has:

- `lib.createBackupSystem()`

That is useful, but it is not yet the explicit standard contract for mutation authoring.

### Concrete hardening tasks

#### 9.1 Document the current standard

Write down that today:

- `createBackupSystem()` is the standard backup/restore primitive
- authors should not roll ad hoc saved-value tables by default
- `backup()` must be called before every write in `apply()`
- `restore()` must fully undo those writes
- `dataMutation = true` is a semantic contract required for Framework reapply behavior

#### 9.2 Document the future tightening direction

Recommended future direction:

- explicit mutation modes:
  - `patch`
  - `manual`
- eventual Lib-owned patch/mutation plan for common mutation modules

That gives you a path to tighten this later without pretending the system already enforces it today.

### Recommendation

Tier 1 as a documentation and future-design issue.
Potential later implementation project if you decide to actually tighten module authoring.

---

## 10. Standalone Contract

### Current contract

Modules should work without Framework:

- regular modules via `lib.standaloneUI(...)`
- special modules via `lib.standaloneSpecialUI(...)`

Both are now store-based.

### Current enforcement

Good enough.

### Brittleness

Low-Medium.

The main risk is drift between hosted and standalone behavior over time, not a major architecture flaw.

### Hardening actions

- keep standalone helpers aligned with store/specialState
- treat them as first-class contract surfaces
- avoid coordinator-only assumptions leaking into standalone behavior

### Recommendation

No urgent hardening needed.

---

## 11. Lower-Severity but Valid Gaps

These are worth capturing, but not worth major churn on their own.

### 11.1 `visibleIf` mismatch between standalone and hosted paths

Hosted Framework visibility checks operate on per-module staging.
Standalone checks read live from the store.

That means a `visibleIf` pointing outside the module’s own option space can behave differently between the two modes.

Recommended action:

- warn during validation if `visibleIf` does not correspond to a same-schema / same-option key

Warn only. Do not hard-fail.

### 11.2 Enum typos

Examples:

- `sidebarOrder`
- `groupStyleDefault`

Recommended action:

- warn and normalize at coordinator init

### 11.3 `FieldTypes` mutability

`lib.FieldTypes` is still a live table.

Risk:

- low in practice

Recommended action:

- document as read-only by convention

### 11.4 `runSpecialUiPass(...)` as a public helper

Risk:

- low in normal paths
- direct callers can misuse it

Recommended action:

- document it as a Lib-owned orchestration helper, not a generic public utility for arbitrary callers

---

## Hardening Priorities

### Tier 1: highest leverage, lowest regret

1. Formalize hash/profile ABI policy
2. Add coordinator init/config validation and normalization
3. Add discovery-time warning for specials with neither `DrawTab` nor `DrawQuickContent`
4. Document the `apply` / `revert` and `dataMutation` authoring contract

### Tier 2: important consistency work

5. Make hash encode/decode resilient to invalid field types
6. Make validation and runtime agree on what invalid schema fields mean
7. Explicitly document `createStore(...)` as the only supported store constructor
8. Document field/schema table mutation in place

### Tier 3: cleanup and polish

9. Make `getConfigBackend(...)` internal
10. Warn on problematic `visibleIf`
11. Add a nil/malformed-state guard to `runSpecialUiPass(...)`
12. Normalize / warn on enum-like coordinator options

---

## Intentional Soft Areas

These should stay soft unless a real bug proves they need stronger machinery:

- Framework staging coherence under out-of-band config mutation
- standalone behavior beyond store/specialState alignment
- internal store backing implementation
- low-risk enum typos with safe normalization

Do not tighten these just for theoretical purity.

---

## Recommended Next Moves

If the goal is to tighten Lib/Framework and then mostly leave them alone:

1. add coordinator validation/normalization
2. add discovery-time special entrypoint warning
3. write hash ABI policy into the contributing docs
4. write down the current mutation authoring contract and likely future patch-plan direction
5. fix the unknown-field-type hash mismatch

After that, stop changing contract surfaces unless a new feature or real bug requires it.

That will close the highest-risk gaps without reopening the whole architecture.
