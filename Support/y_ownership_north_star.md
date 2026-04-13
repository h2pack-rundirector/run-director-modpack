# Y Ownership North Star

## Purpose

This document is not an API contract.
It is a design north star for the remaining Lib layout work around explicit `Y` ownership.

The goal is to define what Lib actually needs structurally, instead of reducing the problem to:
- "replace `line` with `y`"
- or "use `SameLine()` less"

The real problem is that the declarative UI tree already exists, but the structured layout substrate under that tree is still only partially owned by Lib.

---

## What The System Needs

## 1. Local layout origin

Each layout node needs a clear local origin:
- `originX`
- `originY`

Children should be positioned relative to that origin, not relative to incidental ImGui cursor flow left behind by previous draws.

This is the first requirement for making the tree "stand on something" spatially.

---

## 2. Explicit row model

Structured layouts need actual row ownership.

That means Lib needs to own:
- row baseline/start `y`
- row height
- row spacing
- next-row computation

The real issue is not the absence of a public `y` field.
The real issue is that rows still inherit too much from implicit ImGui item flow.

---

## 3. Positioned child and slot rendering

For every structured child or slot, Lib should:
- compute final `x`
- compute final `y`
- call positioned draw
- measure consumed footprint

In practice this likely means:
- `SetCursorPos(x, y)` before structured draws
- avoiding reliance on the post-draw cursor as the authoritative next position

This is the core of Lib owning both axes rather than only horizontal placement.

---

## 4. Footprint settlement contract

A parent layout cannot own `Y` unless it knows how much space each child consumed.

Under the current immediate-mode ImGui model, Lib should not try to become a generic pre-measurement system for every widget type.
Instead, the contract should be:

- parent/layout assigns the child start position
- child must begin drawing from that assigned start
- child must leave the cursor at the bottom of the space it consumed
- parent uses that settled end position as the child's footprint signal

This keeps the contract realistic for ImGui while still giving parent layouts deterministic row advancement.

Width policy and overflow policy remain widget-owned.
The critical layout signal here is vertical footprint settlement.

Normal render paths should remain assertion-free.
Misbehaving structured children are expected to manifest as visible layout issues, and any stronger diagnostics should be opt-in tooling rather than default hot-path validation.

---

## 5. End-of-layout cursor settlement

After a layout finishes drawing, it must explicitly place the outer cursor at the correct next position.

That means:
- parent does not inherit "whatever ImGui happened to do"
- parent decides the final cursor location after children render

This is necessary for nested structured layouts to remain stable.

---

## 6. Clear boundary between structured layout and raw immediate mode

Not all rendering should be forced into the structured system.

Lib needs an explicit rule:
- layouts/panels/tabs own placement
- widgets are generally leaf renderers
- custom widgets may still use local immediate-mode drawing internally

This preserves escape hatches while keeping the structured layout system honest.

---

## 7. Nested layout safety

The system must support:
- layout inside layout
- widget inside layout
- nested structured trees

without relying on `SameLine()` side effects or ambient cursor state.

This is one of the main reasons `Y` ownership matters in the first place.

---

## 8. Backward-compatible authoring surface

Authors should not need to rewrite the whole API around raw pixel `y` values just to get stable layout behavior.

Likely direction:
- keep `line` as the public row selector for now
- internally resolve lines to actual `y`
- add explicit `y` only if later demand justifies it

This keeps the public surface stable while improving the internal substrate.

---

## 9. Region semantics should stay separate from layout semantics

`panel` should not automatically mean:
- child window
- clipping region
- scrolling surface

Those are region/container semantics, not layout semantics.

`BeginChild/EndChild` may still be useful as an optional implementation tool in some cases, but they should not become the default meaning of `panel`.

The default panel should remain:
- a layout abstraction
- over the current window space
- with Lib-owned coordinate and row settlement

---

## 10. Instrumentation and debugability

If Lib takes full `Y` ownership, it should be possible to inspect:
- row origins
- resolved child positions
- row heights
- final cursor settlement

Otherwise layout bugs will become hard to reason about.

This does not have to be a public polished debugger first, but the implementation should leave room for it.

---

## Practical Interpretation

This is not a request for a full CSS-like layout engine.

The intended direction is narrower:
- a declarative composition tree
- a real Lib-owned structured layout substrate
- deterministic row placement in both `X` and `Y`
- leaf widgets that render atomically inside their assigned positions

That is enough to make the current static UI model structurally sound without reopening the broader dynamic-layout problem.
