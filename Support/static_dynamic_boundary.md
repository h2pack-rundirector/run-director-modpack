# Static vs Dynamic UI Boundary — Architecture Decision

## Status

This is an architecture/debate document, not the current API contract.

Use this document for:
- the reasoning that led to cutting the dynamic middle ground from main
- the boundary definition between static managed UI and future dynamic work
- evaluating whether a later dynamic system still makes architectural sense

Do not read examples of removed surfaces here as live mainline features.
Current behavior lives in the Lib docs and the current code.

## Context

This document captures an architectural discussion about where to draw the boundary between
the static declarative UI system (regular modules) and dynamic immediate-mode UI (special modules).
It is written for a second opinion review.

The immediate trigger was identifying that ModpackLib's runtime geometry system —
`buildIndexedHiddenSlotGeometry`, `runtimeGeometry` parameter threading, `PrepareRuntimeWidgetGeometry` —
was half-built and carrying unresolved ownership and lifecycle questions.

---

## The Old Boundary

The previous regular/special split was:

- Regular modules: fully lifecycle managed by lib, declarative storage and UI
- Special modules: too complex for the framework, write your own ImGui code

The problem: "too complex" is subjective. The line was invisible until you hit it.
Module authors had no principled way to know when to cross.

---

## The New Boundary

**Regular modules: fully static. No runtime decisions in the node tree.**

The node tree is prepared once. Lib owns prep, draw, state management.
The contract is total and lib can guarantee it.

**Special modules: own their frame loop. Dynamic behavior is their responsibility.**

Lib provides widget primitives, layout primitives, and static node trees as reusable building blocks.
Special modules can use all of these for their static pieces.
Lib does not try to manage what it cannot see.

The key insight: the barrier is not complexity. It is execution model.

> Does your UI need to respond to runtime state changes that lib does not own?
> If yes, you are a special module.

This is a one-sentence boundary that can be explained to any module author.

---

## What "Static" Actually Means

Static does not mean flat or dull. ImGui's own retained state provides significant
UI dynamism for free inside the static model:

- Collapsible headers remember open state
- Tab bars remember the active tab
- Scroll positions persist
- Tree nodes expand and collapse
- Hover, active, and focus states

A static node tree rendered every frame through ImGui already gets all of this.

What you cannot get from ImGui's own retained state: behavior that depends on
*your* model — filtered lists, conditional content based on saved config, derived labels
from live data. Those are the genuinely dynamic cases.

---

## What Gets Removed from Lib

The following exist in the current implementation but belong to the dynamic middle ground.
They are half-built, have unresolved ownership and lifecycle questions, and should be
removed from the main static branch into a WIP dynamic branch:

| Feature | Why it goes |
|---|---|
| `runtimeGeometry` parameter on `drawUiNode` | Runtime slot override — dynamic by definition |
| `runtimeLayout` parameter on `drawUiNode` | Runtime layout override — dynamic by definition |
| `buildIndexedHiddenSlotGeometry` | Exists only to serve runtime item hiding |
| `PrepareRuntimeWidgetGeometry` | Internal prep for runtime geometry |
| `_runtimeSlotGeometrySource` / `_runtimeSlotGeometryCache` on nodes | Runtime cache with unclear ownership |
| `getWidgetSummary` public function | Designed for live summary queries in dynamic workflows |
| `radio.summary` / `packedCheckboxList.summary` | No static use case — summary is a dynamic feature |
| `runtimeLayout` child hiding in `verticalTabs` and `panel` | Runtime structure mutation |
| `lib.WidgetHelpers` summary namespace | No static use case once summary is removed |

In BoonBans, `planner.lua` `GetBanListGeometry` and the geometry threading in the `banList`
custom widget go with it.

---

## What Stays

### `visibleIf`

`visibleIf` is a candidate for removal but defensible to keep.

It does not change the structure of the node tree at runtime. The node is always in the tree;
lib skips rendering when the condition is false. The decision is a simple read of a
lib-managed storage alias — a bool or enum value lib already owns.

The reason it works cleanly: ImGui's own flow layout absorbs the gaps. Hidden nodes in a
vertical list produce no visual artifact. No compaction required.

If the philosophy is "no runtime decisions in the node tree at all," cut it — module authors
can use an `if` statement around the node in immediate code instead.
If the philosophy is "lib handles decisions based on storage it owns," keep it — it is the
one case where that is zero-cost.

**This is a philosophical call, not a technical one.**

### Custom widgets

Keep. Custom widgets fit both halves of the model cleanly.

For regular modules: a custom widget is fully static. It has `validate`, `draw`, `binds`, slots.
Lib manages its lifecycle identically to any lib widget.

For special modules: custom widgets are reusable imperative building blocks with a consistent
interface. The module owns the frame loop but gets slot alignment and composition for free.

Policy: custom widgets registered in `customTypes` are subject to the same static contract
as lib widgets when used inside regular module node trees. If a custom widget needs dynamic
behavior it belongs in special module immediate draw code, not in `customTypes`.

### `confirmButton`

Stays. It is a lib widget with per-node armed state. The state is internal to the widget,
not reactive to external model changes. It has one known bug: the arm-press returns `true`
when no data changed. Fix before calling the static system stable.

### `dynamicText`

Borderline. `getText`/`getColor`/`getTooltip` are callbacks — they fire every frame and
can read arbitrary state. That is dynamic behavior by definition. If the static system
means no callbacks into module code during draw, `dynamicText` goes to the WIP branch.
If callbacks reading lib-managed state are acceptable, it can stay with that constraint documented.

---

## The Asymmetry Between Regular and Special

Special modules can use static widgets. Static widgets have no lifecycle requirements —
they work anywhere you call them. The dependency is one-way.

Regular modules cannot use dynamic features from special modules. Regular modules have a
lifecycle contract — lib owns prep, draw, state management. Injecting dynamic behavior
into a managed tree breaks that contract at the seam.

The 10%-special/90%-regular module that wants one dynamic interaction has two options:

1. Give up the dynamic interaction and stay regular
2. Go special and use static node trees for the 90%

There is no sandbox middle ground. A partial contract is worse than a clear one in both directions.
The 90%-static special module loses nothing practical — it gets full lib widget reuse for its static pieces.

---

## The Widget Encapsulation Principle

This is the key insight that resolves the ban list question.

**A widget may make any internal presentation decision that is fully derivable
from its own declared bindings and declared configuration.**

Reading another widget's state, querying game entities, or calling module-level functions
violates the boundary. Reading declared storage aliases through `uiState` does not —
that is the widget's own declared world.

### Implication: `filteredCheckboxList`

The ban list is special today not because of inherent complexity but because ImGui has no
managed scrollable list with built-in filtering and compaction. The module had to build
that infrastructure in `planner.lua` + runtime geometry.

A lib widget `filteredCheckboxList` with:

- `filterTextAlias` — storage alias for the search text input
- `filterModeAlias` — storage alias for the filter mode radio (all/banned/allowed/special)
- internal compaction of visible items

...would be a fully static lib widget. It reads only its own declared bindings.
BoonBans ban list becomes a node declaration. No planner, no runtime geometry, no special module.

This is the correct long-term direction. The widget owns the presentation behavior because
the behavior is about how it presents its own data. That is encapsulation, not coupling.

The earlier advice that "widgets should be dumb renderers" was applying the principle at
the wrong granularity. Individual slot draw functions should be dumb. The widget coordinating
its own item visibility based on declared predicates is appropriate responsibility.

---

## Where the Dynamic System Went Wrong

The runtime geometry approach was an attempt to get dynamic filtering behavior without
a real change signaling or dependency model. The signature-based rebuild in `GetDomainTabsNode`
is the same thing — manually approximating what a proper dependency tracker would do automatically.

Each dynamic need produced a new ad hoc mechanism with its own cache ownership question,
its own invalidation strategy, its own edge cases. That is the pattern of building the
symptoms of a reactivity system without building the reactivity system.

A proper dynamic system on top of retained ImGui needs:

- **Change signaling** — something that says "this data changed, dependent views are stale"
- **Dependency tracking** — which nodes depend on which state
- **Stable identity across rebuilds** — consistent ImGui IDs when trees are rebuilt
- **Lifecycle hooks** — on mount, on unmount, on update

These are what React/Elm/similar frameworks solve. They are not trivial to build correctly
in Lua over ImGui. The immediate mode escape hatch exists precisely because building this
layer properly is a significant undertaking.

The decision: do not half-build it. Remove what exists, keep a WIP branch, revisit when
real repeated patterns across multiple special modules demand it and the design can be done right.

---

## Branch Strategy

**Main branch:** static system only. Narrow, guaranteed contract. Remove all dynamic middle ground.

**WIP dynamic branch:** preserve current runtime geometry work, summary system, `dynamicText`,
`buildIndexedHiddenSlotGeometry`. Revisit when the full reactive model is designed properly.

The static system is ready to branch on. Two known issues to fix first:

1. `confirmButton` arm-press returning `true` when no data changed
2. `getWidgetSummary` writing a runtime geometry cache it should not own
   (read-if-warm is acceptable, write is not — ownership belongs to the draw path)

---

## Open Questions for Second Opinion

1. Should `visibleIf` stay or go? The argument for removal: it is a runtime decision even if
   a cheap one, and cutting it makes the static contract unambiguous. The argument for keeping:
   it costs nothing, ImGui absorbs the visual gap, and it is the one declarative feature
   that is clearly within lib's ownership.

2. Should `dynamicText` stay in the static branch with a constraint that `getText` may only
   read lib-managed storage? Or does any callback during draw disqualify it?

3. Is the `filteredCheckboxList` widget the right next lib widget to build, given that it
   would move BoonBans ban list back into the regular module model?

4. The `confirmButton` arm-press bug — fix in static branch before branching, or fix in both?
