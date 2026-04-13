# Roadmap: Dynamic UI System (WIP Branch)

## Status

This is a future-design document for a possible dynamic branch, not a description of current mainline Lib behavior.

Use this document for:
- preserving the forward path from the old dynamic experiments
- understanding what the discarded middle ground was trying to achieve
- evaluating whether a future dynamic system should come back on cleaner terms

Do not treat the surfaces named here as current APIs on `main`.
Many of them were intentionally removed during the static-foundation pass.

## Prerequisite

This roadmap assumes the static foundation (see `roadmap_static_foundation.md`) is complete
and stable on main. The dynamic system is built on top of that foundation, not alongside it.

Do not start this roadmap until:
- Static branch is declared stable
- At least two real special modules exist with enough patterns to validate design decisions
- The reactive model design has been reviewed against those real cases

---

## What the WIP Branch Currently Has

The WIP branch preserves the half-built dynamic work from the pre-split state:

- `runtimeGeometry` / `runtimeLayout` parameters on `drawUiNode`
- `buildIndexedHiddenSlotGeometry`
- `PrepareRuntimeWidgetGeometry`, `PrepareRuntimeTabbedLayout`, `PrepareRuntimePanelLayout`
- `getWidgetSummary` with `radio.summary` and `packedCheckboxList.summary`
- `dynamicText` with `getText`/`getColor`/`getTooltip` callbacks
- `_runtimeSlotGeometrySource` / `_runtimeSlotGeometryCache` node caching
- Signature-based node rebuild in BoonBans `GetDomainTabsNode`
- BoonBans `planner.lua` geometry cache

---

## Current Flaws in the WIP Branch

Understanding what is broken before designing the replacement.

### 1. No change signaling

There is no mechanism to say "this storage value changed, dependent nodes are stale."
Draw code pulls state every frame by convention. This works but means every widget
recomputes everything every frame regardless of whether anything changed.

### 2. No dependency tracking

`GetDomainTabsNode` manually computes a signature string to detect when to rebuild.
This is hand-rolled dependency tracking. Every dynamic node that needs to react to
state changes needs its own bespoke signature/cache strategy. Does not scale.

### 3. Unstable node identity across rebuilds

When `GetDomantTabsNode` detects a signature change and rebuilds the `verticalTabs` node,
the new node has new `_imguiId` values. ImGui loses scroll position, active tab state,
any per-item interaction state. The rebuild is visually jarring and loses user context.

### 4. Cache ownership is ambiguous

`_runtimeSlotGeometrySource` / `_runtimeSlotGeometryCache` live on nodes but are written
by both `drawUiNode` and `getWidgetSummary`. Neither owns the cache exclusively.
Invalidation is implicit (table identity comparison). Easy to get wrong.

### 5. Runtime geometry is a partial solution

Runtime geometry only handles slot-level visibility overrides. It does not handle:
- Structural changes to the node tree (adding/removing children)
- Layout-level changes (column counts, sidebar width)
- Cross-node reactive dependencies

### 6. `getWidgetSummary` return shape is opaque

Returns `{ type, data }` where `data` is widget-specific. Callers need widget-type
knowledge to interpret it. The dispatch is generic but the payload is not.
The API implies more generality than it delivers.

### 7. `dynamicText` callbacks are unconstrained

`getText`/`getColor`/`getTooltip` can call anything — game entities, module globals,
arbitrary Lua. No contract on what they may read. Makes reasoning about the draw
path impossible when debugging.

### 8. No lifecycle hooks

Nodes have no awareness of being added, removed, or having their data change.
No `onMount`, `onUnmount`, `onChange`. This means side effects tied to node presence
(clearing state, triggering animations, logging) have no clean home.

---

## What a Proper Dynamic System Needs

Four foundational pieces. Each one is load-bearing for the next.

### A. Change signaling

A way to mark storage aliases as dirty when their value changes, and a way for the
draw system to know which nodes care about which aliases.

This does not require a full reactive graph. A simple dirty-flag system per alias,
checked at the start of each frame, is enough to drive selective redraw.

`uiState.set(alias, value)` already exists — it is the right place to emit a change signal.

### B. Stable node identity

Node identity must survive rebuilds. The current `_imguiId` derived from bindings
is good for static nodes. Dynamic nodes that get rebuilt need an explicit stable key
declared by the module — something that does not change when the node is reconstructed.

This is the `quickId` field that already exists on nodes. The gap is that the system
does not use it to preserve ImGui state across rebuilds. A proper implementation would
push the `quickId` as the ImGui ID so ImGui's own retained state survives the rebuild.

### C. Unified runtime state object

Instead of `runtimeGeometry` and `runtimeLayout` as separate parameters threading
through every call, a single `runtimeState` object:

```lua
{
    widgetGeometry = { ... },   -- slot overrides for widget nodes
    layoutOverrides = { ... },  -- child overrides for layout nodes
    -- extensible
}
```

Owned and cached by the planner/layout layer. Passed as one argument.
Draw and summary are pure consumers — they do not parse or cache it themselves.

### D. Dependency declaration on nodes

A way for a node to declare which storage aliases it depends on for its dynamic behavior:

```lua
{
    type = "dynamicText",
    dependsOn = { "BanFilterMode", "BanFilterText" },
    getText = function(node, uiState) ... end,
}
```

The system uses this to know when to re-evaluate the node's dynamic state.
Without this, the only option is full recompute every frame.

---

## Phase D1 — Design Review Against Real Patterns

**Goal:** Before writing any code, validate the design against real special module needs.

### D1.1 Audit special modules

Identify all special modules that exist after the static foundation is complete.
For each, document:
- What dynamic behavior they need
- What state drives that behavior
- How often that state changes
- What the rebuild cost is if they fully recompute each frame

### D1.2 Evaluate whether full-recompute-every-frame is acceptable

ImGui is immediate mode. Full recompute every frame is its native model.
The question is whether the performance cost of not having a reactive system
is actually observable in practice given the frame budget of a mod UI.

If full recompute is acceptable for all real cases, the reactive system is
unnecessary and the dynamic branch should focus only on:
- Stable node identity across rebuilds
- Unified runtime state object
- Unconstrained `dynamicText` → constrained `dynamicText`

If full recompute is not acceptable, proceed with the full reactive design.

### D1.3 Write the design document

Before any implementation, write a concrete design document covering:
- Change signaling mechanism
- Dependency declaration syntax
- Runtime state object shape
- Node identity/rebuild strategy
- What `getWidgetSummary` looks like under the new model
- What `dynamicText` constraints look like

Get a second opinion on the design document before implementation.

---

## Phase D2 — Stable Node Identity

**Goal:** Rebuilding a node tree no longer loses ImGui state.

This is the lowest-risk first step regardless of whether the full reactive system is built.
It improves special module ergonomics immediately.

### D2.1 Enforce `quickId` as ImGui push ID for dynamic nodes

When a node has `quickId`, push it as the ImGui ID instead of the derived `_imguiId`.
The derived ID remains as fallback for nodes without `quickId`.

### D2.2 Add `quickId` stability contract to docs

Document that `quickId` must be stable across rebuilds for ImGui state to survive.
Module authors are responsible for choosing stable keys (e.g. root ids, scope keys).

### D2.3 Remove signature-based rebuild from `GetDomainTabsNode`

With stable identity, node rebuild on every frame is safe — ImGui state survives.
The signature check becomes unnecessary. `GetDomainTabsNode` simplifies to
always rebuilding and relying on `quickId` for ImGui stability.

---

## Phase D3 — Unified Runtime State Object

**Goal:** Replace the fragmented `runtimeGeometry` / `runtimeLayout` parameter pair
with a single owned runtime state object.

### D3.1 Define `RuntimeNodeState` shape

```lua
{
    widgetGeometry = { slots = { ... } },
    layoutOverrides = { children = { key = { hidden = true } } },
}
```

### D3.2 Add `lib.prepareRuntimeState(node, rawGeometry, rawLayout)`

Single preparation function. Validates and caches. Returns `RuntimeNodeState`.
Owned by the caller (planner/layout). Never called inside `drawUiNode` or `getWidgetSummary`.

### D3.3 Update `drawUiNode` and `getWidgetSummary` signatures

Replace `runtimeGeometry, runtimeLayout` parameters with single `runtimeState` parameter.
Both functions become pure consumers — no internal parsing or caching.

### D3.4 Update `ResolveSlotGeometry` 

Accept explicit runtime state instead of reading `node._runtimeSlotGeometry`.
Remove the node-mutation pattern entirely.

### D3.5 Update BoonBans planner

`GetBanListGeometry` returns a `RuntimeNodeState` object instead of raw geometry.
Signature-based cache remains at the planner level — that is correct ownership.

---

## Phase D4 — Change Signaling

**Goal:** The system knows when storage values change. Expensive recomputes only happen
when relevant state changes.

### D4.1 Add dirty tracking to `uiState.set`

When `uiState.set(alias, value)` is called, mark the alias as dirty for the current frame.
Clear dirty flags at frame start.

### D4.2 Add `lib.isAliasDirty(alias, uiState)` query

Planners and layout code can check whether their relevant aliases changed before
recomputing runtime state.

### D4.3 Update BoonBans planner to use dirty checks

`GetBanListGeometry` checks `isAliasDirty` for `BanFilterText`, `BanFilterMode`, and the
ban packed int alias before recomputing. Skips rebuild if nothing changed.
This replaces the signature string comparison with a proper dirty flag mechanism.

---

## Phase D5 — Constrained `dynamicText`

**Goal:** `dynamicText` callbacks are constrained to lib-managed state only.
The draw path becomes reasonably auditable.

### D5.1 Define the constraint

`getText`/`getColor`/`getTooltip` callbacks receive only:
- `node` — the widget node itself
- `uiState` — lib-managed state accessor

They may not capture external variables or call module-level functions.
This is a documentation contract, not an enforced runtime constraint (Lua cannot enforce it).

### D5.2 Add lint/validation guidance

Document what a valid `dynamicText` callback looks like.
Add a validate-time warning if `getText` is not a function.

### D5.3 Evaluate `dynamicText` against real use cases

Under this constraint, `dynamicText.getText` reading `uiState.view` values is fine.
`dynamicText.getText` calling `GetScopeSummary(scopeKey, uiState)` is borderline —
it is a module function but takes only lib-managed state.
`dynamicText.getText` calling `GetForcedBoonStatusText(forcedBoon)` requires a boon object
that came from game data, not lib storage. That is out of bounds.

Use this audit to decide which BoonBans `dynamicText` usages are clean and which
belong in immediate draw code instead.

---

## Phase D6 — `getWidgetSummary` Redesign

**Goal:** Summary API is clean, ownership is clear, return shape is honest.

### D6.1 Decide normalized vs widget-specific shape

Two options:
- **Normalized**: `{ totalCount, visibleCount, hiddenCount, selectedCount, selectedLabel }` — partial fields by widget kind. Generic consumers can work with it without widget-type knowledge.
- **Typed wrapper**: `{ type = "radio", data = { ... } }` — honest about widget-specificity. Callers need widget-type knowledge to interpret `data`.

Normalized is cleaner for the `dynamicText` workflow. Typed wrapper is more honest.
Decision requires knowing what real callers need.

### D6.2 Rebuild `getWidgetSummary` as thin dispatcher

Under the unified runtime state model from D3:
- Accepts prepared `RuntimeNodeState` instead of raw geometry
- No internal caching
- Resolves `node._widgetType.summary` directly
- Wraps result in chosen shape

### D6.3 Re-add `summary` to widgets under clean contract

Once the return shape is decided, re-add `summary` to `radio` and `packedCheckboxList`
with the normalized or typed shape. Document the contract per widget clearly.

---

## Phase D7 — Dependency Declaration (Optional / Future)

**Goal:** Nodes declare what they depend on. System drives selective recompute.

This phase is optional. If the dirty-flag system from D4 combined with planner-owned
caching is sufficient for all real cases, skip this entirely.

Only build if there is a demonstrated performance problem or a complexity problem
that dependency declaration would solve.

### D7.1 Add `dependsOn` field to widget/layout nodes

```lua
dependsOn = { "BanFilterMode", "BanFilterText" }
```

### D7.2 Build dependency-aware draw traversal

Skip node recompute if no declared dependencies are dirty.
Reuse cached draw output for unchanged nodes.

### D7.3 Evaluate correctness cost

Dependency declaration is a maintenance surface. Module authors must keep `dependsOn`
accurate or get stale renders. This is a real cost. Only accept it if the performance
benefit is demonstrated and measurable.

---

## Summary

| Phase | Deliverable | Prerequisite |
|---|---|---|
| D1 | Design review. Decision on full-recompute acceptability. Design doc written and reviewed. | Static foundation stable. Real special modules exist. |
| D2 | Stable node identity via `quickId`. Signature rebuilds eliminated. | D1 |
| D3 | Unified `RuntimeNodeState`. Clean ownership. `drawUiNode` and `getWidgetSummary` are pure consumers. | D1 |
| D4 | Change signaling via dirty flags. Planner cache driven by dirty checks not signature strings. | D3 |
| D5 | `dynamicText` constrained and audited against real use cases. | D1 |
| D6 | `getWidgetSummary` rebuilt under clean contract. `summary` re-added to widgets. | D3, D5 |
| D7 | Dependency declaration. Only if D4 proves insufficient. | D4, D6 |

---

## Decision Gate After D1

If D1 concludes that full-recompute-every-frame is acceptable for all real special modules,
the roadmap collapses significantly:

- D2 still happens (stable identity is always worth having)
- D3 still happens (unified runtime state is cleaner regardless)
- D4 is optional (dirty flags only if performance demands it)
- D5 still happens (constrained callbacks are always better)
- D6 still happens (clean summary API is always worth having)
- D7 is skipped entirely

The reactive model is only worth building if there is a real performance or correctness
problem that requires it. Build against evidence, not speculation.
