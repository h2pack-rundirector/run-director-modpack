---
name: Tabled Patches — ModpackLib Field Types
description: Architectural improvements to field types tabled for an upcoming patch
type: project
---

Two related refactors to be done together in one patch targeting `adamant-ModpackLib/src/fields.lua`.

## 1. Primitive/Widget split

**Fact:** FieldTypes currently conflates data concerns (toHash/fromHash/toStaging) with widget concerns (draw) in one registry with a unified contract. Every type must implement all methods even when only one side applies — separator has dead data methods, int32/string have dead draw functions.

**Why:** Config values reduce to three primitives (bool, int, string). Widgets are just presentation of a primitive. The set of primitives is closed and stable; the widget set is expected to grow.

**How to apply:** Split into:
- `Primitives` — own `toHash`/`fromHash`/`toStaging`/`validate`. Closed set: bool, int, string.
- `Widgets` — own `draw`/`validate`, declare `storeAs = "bool"|"int"|"string"`. Open set, grows freely.
- Layout hints (separator) — own only `draw`, store nothing.

Data pipeline routes through the primitive's methods; render pipeline routes through the widget's draw. No dummy implementations.

## 2. lib.prepareField + specials reusing field type draw

**Fact:** Special modules must implement all widget rendering from scratch in raw ImGui even though `lib.drawField` is already public. The gap is that `validate` pre-computes cached state (_step, _fastStep, _imguiId etc.) and is only called via `validateSchema` on a full options list.

**Why:** Specials own layout/flow (what renders where, conditional visibility) but shouldn't have to reimplement steppers/dropdowns in raw ImGui. This creates code redundancy and discourages adding richer field types.

**How to apply:** Add `lib.prepareField(field)` — runs validate + metadata prep on a single field. Specials define field tables at module load, call prepareField on each, then call `lib.drawField` in their render loop freely. Split: special owns structure, field types own widgets.

Do both together — they touch the same layer and the prepareField feature depends on the cleaner primitive/widget boundary to be reliable.

## 3. int32 bit partition support in store.read/store.set

**Fact:** Modules that use bit-packed int32 configs (like BoonBans) must manually implement bit extraction and write-back in every module. The store has no awareness of internal packing layout.

**Why:** int32 can pack multiple booleans and small integer ranges (e.g. 0–15) into a single config key, reducing config footprint. But the pack/unpack logic is reimplemented per module, making the schema opaque and the code redundant.

**How to apply:** Allow `bits` declaration on int32 fields:
```lua
{ type = "int32", configKey = "PackedAphrodite", bits = {
    { name = "AttackBanned",   offset = 0, width = 1 },  -- width=1 → bool
    { name = "RarityOverride", offset = 4, width = 2 },  -- width>1 → int, clamped to range
}}
```
Extend store.read/store.set with optional second arg for partition name:
```lua
store.read("PackedAphrodite", "AttackBanned")         -- extracts bit 0 → bool
store.read("PackedAphrodite", "RarityOverride")        -- extracts bits 4-5 → int
store.set("PackedAphrodite", "AttackBanned", true)     -- read-modify-write
store.read("PackedAphrodite")                          -- raw int, existing behavior unchanged
```
- width=1 → bool in/out; width>1 → int in/out, clamped to fit width bits
- Partition names scoped under their backing key — uniqueness enforced per int32, not globally
- Hashing stays at the int32 level, partitions are derived only
- validate time builds a lookup: partition name → {backingKey, offset, mask}

## 4. Field type registry restructure + steppedRange widget + layout expansion

**Fact:** FieldTypes conflates three distinct roles into one registry with a unified contract. Named categories settled on:
- **Primitives** — `bool`, `int`, `string`. Data only (toHash/fromHash/toStaging). Closed set.
- **Widgets** — `checkbox`, `dropdown`, `radio`, `stepper`. UI + data, each declaring `storeAs` primitive. Open set.
- **Layout** — owns organization and grouping. Two kinds:
  - Dividers/labels: `separator`, section headers
  - Containers: future `columns`, `group`, `checkboxGrid` etc. that arrange widgets spatially
  - Layout never stores values. Widgets never care about neighbors.

New widget to add: **`steppedRange`** — two bound steppers rendered as `[min] to [max]` with live constraint (min ≤ max enforced per frame). Replaces the custom `DrawFieldRangeControls` in BiomeControl. Supports same `controlOffset`/`valueWidth`/`fastStep` params as stepper.

**Architectural direction:** A rich layout layer is the primary mechanism for reducing the need for special modules. Most modules become special today because flat sequential rendering isn't expressive enough — not because they need genuinely custom logic. With layout containers (columns, conditional sections, checkboxGrid, collapsible groups), most non-trivial UIs become declarative. Special modules should be reserved for irreducibly custom rendering (e.g. BiomeControl's per-room inline editor, BoonBans' per-god domain tree).

`prepareField` remains important even as layout expands — specials with genuine custom rendering should not have to reimplement widget drawing in raw ImGui. It enables code recycling at the widget level regardless of how much layout capability grows.

Do all four together — same layer, same patch.
