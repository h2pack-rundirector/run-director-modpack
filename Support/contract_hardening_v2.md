# Lib / Framework Contract Hardening

Definitive reference for `adamant-ModpackLib` and `adamant-ModpackFramework`.

Written against the post-store-contract, post-debug-detection-removal state:

- modules expose `public.store` (created via `lib.createStore`)
- special modules expose `public.store.specialState`
- Framework consumes `m.mod.store` exclusively
- standalone helpers are store-based
- direct-config-write detector removed

---

## What Is Now Solid

These areas are well-enforced and should not be redesigned without a specific reason:

- **Store access contract** — `read/write` checked at discovery, skip on missing
- **`specialState` method surface** — created only by Lib, shape is complete and consistent
- **Discovery skip-on-warn** — bad modules do not crash the pack
- **Hash two-phase apply** — values written before `apply/revert` called; `reloadFromConfig` called after schema write
- **Field type implementations** — all required methods present and symmetric
- **Schema duplicate-key detection** — caught at validateSchema time

---

## The Freeze List

These are serialized identity or public ABI. Changing any of them without an explicit migration plan will silently break deployed modules or saved profiles.

| Item | Why frozen |
|---|---|
| `public.store` shape (`read`, `write`, `specialState`) | Core module ABI consumed by Framework |
| `specialState` method surface (`get/set/update/toggle/view/isDirty/flushToConfig/reloadFromConfig`) | Used by Framework and standalone helpers |
| `definition.id` for regular modules | Hash key for enabled state |
| Regular option `configKey` values | Hash key for option state |
| Special module ENVY `modName` | Hash key for special enabled state |
| Special schema `configKey` values | Hash key for schema-backed state |
| `field.default` values | Determines what gets omitted from hash |
| `toHash` / `fromHash` implementations | Must be symmetric across deployments |
| `DrawTab` / `DrawQuickContent` names | Hard-coded access in Framework render loop |
| `Framework.init` `params` keys | Coordinator wiring contract |

---

## Intentional Soft Areas

These should stay loose unless a real bug forces tightening. Do not harden for theoretical purity.

- Framework staging coherence under out-of-band config mutation (documented assumption, not a bug)
- Standalone helper behavior beyond store/specialState alignment
- Internal store backing details (`_config`, `_backend`)
- `FieldTypes` table mutability (low risk in practice)
- Low-risk enum typos with safe silent fallback behavior

---

## Tier 1 — Act Now

These are the highest-leverage, lowest-regret fixes. They prevent the most likely future breakage.

---

### 1.1 Special UI Entrypoints Not Validated at Discovery

**Files:** `discovery.lua` ~line 79, `ui.lua` ~line 427–437

**Problem:**

Framework accesses `special.mod.DrawTab` and `special.mod.DrawQuickContent` by those exact names at draw time with no prior check. A special module with a typo in the export name, a renamed function, or a restructured public table discovers cleanly, creates a tab, and silently renders nothing. There is no warning anywhere.

Code path:
```lua
-- ui.lua — special tab pass opts are built once at init
specialTabPassOpts[special.modName] = {
    draw = special.mod.DrawTab,   -- nil if missing, no warning
    ...
}

-- later at draw time
if special.mod.DrawTab then       -- same nil check, still no warning
    lib.runSpecialUiPass(passOpts)
end
```

**Fix:**

Add a check in `discovery.lua` immediately after the `GetSpecialState` validation block (around line 79). Warn if neither draw function is present. Do not skip — a special with only enable/disable and no content draw is valid.

```lua
-- After specialState validation passes:
if not mod.DrawTab and not mod.DrawQuickContent then
    lib.warn(packId, config.DebugMode,
        "%s: special module exposes neither DrawTab nor DrawQuickContent; tab will be empty",
        modName)
end
```

Add these names explicitly to documentation as required public entrypoints, not convention.

**Blast radius:** Discovery change only. No module changes needed.

---

### 1.2 Coordinator Init / Config Shape Not Validated

**File:** `Framework.init` in `main.lua`, consumed by `hud.lua`, `ui.lua`, `hash.lua`

**Problem:**

`Framework.init` passes `params` to four subsystems. Each subsystem assumes specific keys exist without any central validation. Failures happen late, silently, or with unhelpful errors.

Unvalidated assumptions across subsystems:

| Assumed | Where assumed | Failure if missing |
|---|---|---|
| `params.packId` is string | everywhere | silent wrong behavior or crash |
| `params.config.ModEnabled` | `hud.lua:20`, `ui.lua:37` | nil treated as false (silent) |
| `params.config.DebugMode` | all subsystems | nil treated as false (silent) |
| `params.config.Profiles` is populated array | `ui.lua:SnapshotToStaging` | profile UI silently empty |
| `params.def.NUM_PROFILES` is positive integer | `ui.lua:DrawProfiles` | for-loop does nothing (silent) |
| `params.def.defaultProfiles` exists | `ui.lua:DrawProfiles` | nil index crash on restore |

`params.config.Profiles` is the most dangerous: it is a Chalk-backed array that must be pre-populated by the coordinator's config.lua. A version mismatch where the profile array is not initialized leaves the profile UI silently broken with no diagnostic.

**Fix:**

Add `Framework.validateInitParams(params)` called at the top of `Framework.init`. Policy:

- coordinator contract violations should **fail fast** (error, not warn)
- module contract violations should **warn and skip**

```lua
local function validateInitParams(params)
    assert(type(params.packId) == "string" and params.packId ~= "",
        "Framework.init: packId must be a non-empty string")
    assert(type(params.config) == "table",
        "Framework.init: config must be a table")
    assert(type(params.def) == "table",
        "Framework.init: def must be a table")

    -- Normalize Profiles: ensure it is a table with NUM_PROFILES entries
    local numProfiles = params.def.NUM_PROFILES
    assert(type(numProfiles) == "number" and numProfiles > 0,
        "Framework.init: def.NUM_PROFILES must be a positive number")

    if type(params.config.Profiles) ~= "table" then
        error("Framework.init: config.Profiles must be a pre-populated table")
    end
    for i = 1, numProfiles do
        if type(params.config.Profiles[i]) ~= "table" then
            error(string.format(
                "Framework.init: config.Profiles[%d] is missing; ensure config.lua declares all %d profile entries",
                i, numProfiles))
        end
        -- Normalize missing string fields to empty string
        params.config.Profiles[i].Name    = params.config.Profiles[i].Name or ""
        params.config.Profiles[i].Hash    = params.config.Profiles[i].Hash or ""
        params.config.Profiles[i].Tooltip = params.config.Profiles[i].Tooltip or ""
    end

    -- Warn on unknown enum values; normalize to safe default
    local validSidebarOrders = { ["special-first"] = true, ["category-first"] = true }
    if params.def.sidebarOrder ~= nil and not validSidebarOrders[params.def.sidebarOrder] then
        lib.warn(params.packId, true,
            "Framework.init: unknown sidebarOrder '%s'; defaulting to 'special-first'",
            tostring(params.def.sidebarOrder))
        params.def.sidebarOrder = "special-first"
    end

    local validGroupStyles = { collapsing = true, separator = true, flat = true }
    if params.def.groupStyleDefault ~= nil and not validGroupStyles[params.def.groupStyleDefault] then
        lib.warn(params.packId, true,
            "Framework.init: unknown groupStyleDefault '%s'; defaulting to 'collapsing'",
            tostring(params.def.groupStyleDefault))
        params.def.groupStyleDefault = "collapsing"
    end
end
```

**Blast radius:** Framework.init change only. No module changes needed. Any coordinator with a malformed Profiles array that was silently failing will now error with a clear message.

---

### 1.3 Hash / Profile ABI Must Be Treated as Frozen

**Files:** `hash.lua`, all module `definition.id` and schema `configKey` values

**Problem:**

The hash system encodes module identity and config state into a string that users share and save as profiles. Any change to the items below silently changes what gets encoded or decoded, breaking saved profiles and shared hashes without any error.

Specific silent failure modes:

- **Rename `definition.id`**: old hashes have the old key; decode finds no matching module and silently ignores it. Module reverts to default state.
- **Rename option `configKey`**: same silent ignore.
- **Rename special module ENVY `modName`**: same. Special silently disabled.
- **Rename schema field `configKey`**: same.
- **Change `field.default`**: a field that was previously encoded (non-default) may now be omitted (matches new default), or vice versa. Old hashes silently write the old value to config.
- **Change `toHash`/`fromHash`**: old encoded strings decode to wrong values.

There is no runtime detection for any of this. The hash version check (`_v=1`) guards only format changes, not semantic identity changes.

**Policy to write down and enforce by convention:**

```
Hash ABI is frozen after first release.

These are NOT cosmetic changes — they are compatibility breaks:
  - changing definition.id
  - changing option configKey
  - changing special module modName
  - changing stateSchema field configKey
  - changing field.default
  - changing toHash or fromHash

If a rename is necessary:
  - add a _hashKey override to preserve the old wire name
  - or bump HASH_VERSION and add explicit migration in ApplyConfigHash
  - never rely on silent decode-to-default behavior as migration

field._hashKey exists precisely for this: it separates the config key
(what code uses) from the hash key (what gets serialized). Use it.
```

Write this in a CONTRIBUTING or ABI doc, not only here.

---

## Tier 2 — Important Consistency

These are real correctness issues that do not need immediate emergency fixes but should be closed before the system is considered stable.

---

### 2.1 Schema Validation Is Warn-Only But Hash Assumes Validity

**Files:** `fields.lua:validateSchema`, `hash.lua:125`, `hash.lua:128`

**Problem:**

`validateSchema` warns on unknown field types but does not exclude them from `_configFields`. Hash encode/decode then calls `lib.FieldTypes[field.type].toHash(field, value)` without a nil guard. A field with an unknown type that survived validation (with a warning) causes a hard crash during hash encode.

```lua
-- hash.lua:125 — no guard
local function EncodeValue(field, value)
    return lib.FieldTypes[field.type].toHash(field, value)  -- crashes if field.type unknown
end
```

The draw path is correctly guarded (`drawField` checks and falls back gracefully). Hash is not.

**Fix A — Hash resilience (minimum fix):**

```lua
local function EncodeValue(field, value)
    local ft = lib.FieldTypes[field.type]
    if not ft then
        lib.warn(packId, config.DebugMode,
            "hash encode: unknown field type '%s' for key '%s', skipping",
            tostring(field.type), tostring(field.configKey))
        return ""
    end
    return ft.toHash(field, value)
end

local function DecodeValue(field, str)
    local ft = lib.FieldTypes[field.type]
    if not ft then
        lib.warn(packId, config.DebugMode,
            "hash decode: unknown field type '%s' for key '%s', using default",
            tostring(field.type), tostring(field.configKey))
        return field.default
    end
    return ft.fromHash(field, str)
end
```

**Fix B — Schema consistency (full fix):**

In `validateSchema`, exclude fields with unknown types from `_configFields`:

```lua
if ft then
    if ft.validate then
        -- ...
    end
    table.insert(configFields, field)   -- only add if type is known
else
    libWarn(...)                         -- warn but do not add to configFields
end
```

This makes validation and runtime agree: unknown type = not in schema pipeline at all.

**Recommendation:** Do both. Fix A is a safety net; Fix B is the correct behavior.

---

### 2.2 `apply`/`revert` Mutation Contract Is Undocumented

**Files:** `core.lua:createBackupSystem`, every module's `apply`/`revert`

**Problem:**

`lib.createBackupSystem()` already exists as a backup/restore primitive, but it is not documented as the standard pattern. Modules that roll their own ad-hoc saved-value tables will require manual changes if the mutation contract is ever tightened.

`dataMutation = true` in `definition` is a semantic contract (tells Framework to re-apply after option changes and after hash apply). There is no validation that it is set correctly.

**What `createBackupSystem` provides:**

```lua
local backup, restore = lib.createBackupSystem()

-- In apply:
backup(GameData.SomeTable, "Key1", "Key2")  -- saves original values once; idempotent
GameData.SomeTable.Key1 = newValue

-- In revert:
restore()  -- deep-copies originals back
```

It handles nil values (via sentinel), deep-copies tables, and will not overwrite an already-taken backup.

**Fix — Document the standard:**

```
Mutation authoring contract:

1. lib.createBackupSystem() is the standard backup/restore primitive.
   Do not roll ad-hoc saved-value tables.

2. backup() must be called before every write in apply().
   Never write without backing up first.

3. restore() must fully return game tables to their pre-apply state.
   Framework cannot verify this — author responsibility.

4. definition.dataMutation = true must be set if apply/revert touches
   game data tables (not just config). Framework uses this to re-apply
   after hash loads and option changes.

Future direction: a lib.createMutationPlan() will eventually wrap this
into a patch-based model. When introduced, manual backup/restore will
become the explicit escape hatch. Write apply/revert against
createBackupSystem() today so the future migration is mechanical.
```

---

## Tier 3 — Cleanup and Polish

Lower urgency. Address when touching affected files for another reason or when Tier 1/2 is closed.

---

### 3.1 `public.getConfigBackend` Should Not Be Public API

**File:** `core.lua:384`

**Problem:**

`public.getConfigBackend` is on the public Lib surface. Its only current internal use is `createStore`. Its previous use (direct-config-write detector) was removed.

As a public function, module code can call `lib.getConfigBackend(config)` and get direct Chalk entry access, bypassing the store contract. This is exactly the bypass path the store architecture prevents.

**Fix:** Make it a local function. `createStore` already calls it directly — no other code needs it on `public`.

---

### 3.2 Field and Schema Tables Are Mutated In-Place at Runtime

**Files:** `core.lua:PrepareSchemaFieldRuntimeMetadata`, `fields.lua:validateSchema`, `fields.lua:stepper draw`

**Problem (documentation gap, not a bug):**

Lib injects runtime-cached metadata directly onto field and schema objects:

| Injected key | Set by | On |
|---|---|---|
| `field._schemaKey` | `PrepareSchemaFieldRuntimeMetadata` | field table |
| `field._readValue` | `PrepareSchemaFieldRuntimeMetadata` | field table |
| `field._writeValue` | `PrepareSchemaFieldRuntimeMetadata` | field table |
| `field._imguiId` | `validateSchema` / `drawField` | field table |
| `field._step` | stepper validate | field table |
| `field._pushId` | discovery | field table |
| `field._hashKey` | discovery | option field table |
| `field._lastStepperVal` | stepper draw | field table |
| `field._lastStepperStr` | stepper draw | field table |
| `schema._configFields` | validateSchema / GetSchemaConfigFields | schema table |

The stepper's `_lastStepperVal`/`_lastStepperStr` are per-frame mutable render state on the field object.

**Implications:**

- Field objects are not pure declaration tables after first use.
- `schema._configFields` uses `rawget` to detect a cached value. Re-declared schemas (typical on hot reload) get fresh caches. Reused schema table references across reloads keep the stale cache. **Modules must re-declare their schemas in the loader function, not at the top level as module constants.**
- Do not share field descriptor tables across multiple schemas or modules.

**Fix:** Document in the module authoring guide:

```
Schema and field descriptor tables are enriched in-place by Lib at
validation/discovery time. Always declare schemas inline in the module
loader function (not as top-level constants) so hot reload gets a
fresh table. Never share a field descriptor object across multiple
schemas or modules.
```

---

### 3.3 `FieldTypes` Table Is Writable From Outside Lib

**File:** `fields.lua:330`

```lua
public.FieldTypes = FieldTypes
```

This exposes the live `FieldTypes` table. Module code can replace or mutate field type implementations and affect all consumers globally.

**Risk:** Low in practice.

**Fix:** Document `lib.FieldTypes` as read-only by convention. Do not expose a proxy — not worth the overhead given the actual risk.

---

### 3.4 `visibleIf` Behaves Differently Between Standalone and Framework Paths

**Files:** `core.lua:114-117` (standaloneUI), `ui.lua:325` (Framework), `fields.lua:32-35`

**Problem:**

Two different code paths evaluate `visibleIf` with different semantics:

- `standaloneUI` (`core.lua:117`): calls `store.read(opt.visibleIf)` directly — reads live from the Chalk backend, works for any key in the store
- Framework rendering (`ui.lua:325`): calls `lib.isFieldVisible(opt, staging.options[m.id])` — reads from per-module staging, which only contains that module's own option values

A `visibleIf` key that references another module's option works correctly in standalone mode and silently evaluates to false in Framework hosted mode. No warning is issued either way.

In practice this matters only if a module uses `visibleIf` to reference a key outside its own `def.options` — which is unusual. The GodPool module uses `visibleIf` correctly (same-module keys only), so this is not a current bug.

**Fix:** Warn in `validateSchema` if `visibleIf` does not match any `configKey` in the same schema, making the limitation explicit at declaration time:

```lua
if field.visibleIf ~= nil then
    local found = false
    for _, other in ipairs(schema) do
        if other.configKey == field.visibleIf then found = true; break end
    end
    if not found then
        libWarn("%s: visibleIf '%s' does not match any configKey in this schema; " ..
            "will always be false in Framework-hosted rendering",
            prefix, field.visibleIf)
    end
end
```

Warn-only — do not error, since the key may be valid in the standalone path.

---

### 3.5 `runSpecialUiPass` Has No Nil Guard on `specialState`

**File:** `special.lua:250`

```lua
if specialState.isDirty() then   -- crashes if specialState is nil
```

**Risk:** Low through normal Framework + validated discovery path (specials without specialState are skipped at discovery). Risk exists for direct callers.

**Fix:** Add a nil guard:

```lua
if not specialState or type(specialState.isDirty) ~= "function" then
    libWarn("runSpecialUiPass: specialState is missing or malformed; pass skipped")
    return false
end
```

---

## Consolidated Priority Table

| # | Area | File | Priority | Type |
|---|---|---|---|---|
| 1.1 | Special UI entrypoint validation | `discovery.lua` | Tier 1 | Add warn at discovery |
| 1.2 | Coordinator init validation | `main.lua` (Framework) | Tier 1 | Add `validateInitParams` |
| 1.3 | Hash ABI policy | All hash-touching files | Tier 1 | Policy documentation |
| 2.1 | Hash crash on unknown field type | `hash.lua` | Tier 2 | Add nil guard in Encode/Decode |
| 2.2 | `apply`/`revert` mutation contract | `core.lua` + modules | Tier 2 | Documentation |
| 3.1 | `getConfigBackend` public exposure | `core.lua` | Tier 3 | Make local |
| 3.2 | Field table mutation side effects | `core.lua`, `fields.lua` | Tier 3 | Document |
| 3.3 | `FieldTypes` mutability | `fields.lua:330` | Tier 3 | Document as read-only |
| 3.4 | `visibleIf` cross-schema limitation | `fields.lua` | Tier 3 | Warn in validateSchema |
| 3.5 | `runSpecialUiPass` nil specialState | `special.lua:250` | Tier 3 | Nil guard |

---

## When This Is Done

After Tier 1 and Tier 2 are closed:

- Coordinator wiring failures are caught immediately with clear errors
- Hash ABI is explicit policy, not tribal knowledge
- Schema validation and runtime assumptions agree
- Dead code is gone
- The mutation authoring contract is written down for the fleet

After that: stop touching Lib/Framework unless a new feature or real bug requires it. The contracts are stable enough to treat as ABI.
