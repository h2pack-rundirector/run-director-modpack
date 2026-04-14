# Layout Substrate Big Picture

## Status

This is not an implementation plan and not an API contract.

This document exists to capture the current architectural context around Lib layout work:
- what is already stable
- what still feels incomplete
- why the remaining issue is specifically the layout substrate
- what kind of future direction seems desirable

Use this as a high-level framing document before any detailed v2 layout plan is written.

---

## Why This Exists

The current Lib has reached a stable point in most of its architecture:
- regular vs special module boundary
- storage and schema model
- persisted vs transient UI state
- aliases and bind surface
- hash/config layering
- declarative UI tree
- prepared node model
- special-module state and draw orchestration

After the BoonBans cleanup, the main remaining large architectural concern is not state or storage.
It is layout.

That does **not** mean the current layout system is unusable or invalid.
It means the current declarative tree is stronger than the layout substrate beneath it.

The feeling is:
- the tree model is now fairly strong
- the layout substrate is serviceable
- but the substrate is still the weakest foundational layer in the system

That is the context this document is meant to preserve.

---

## What Is Already Working

The current system should not be described as "broken layout."

The existing Lib layout model now has real strengths:

- structured declarative tree
- prepared nodes with stable identities
- explicit binding model
- explicit transient UI state
- explicit tab selection binding
- explicit `panel.id` support when an extra ImGui scope is needed
- a clearer distinction between layouts and widgets than before
- `runDerivedText(...)` for derived transient display strings
- `getCachedPreparedNode(...)` for prepared-node reuse

The first-pass `Y` ownership work also materially improved the live substrate:
- `DrawWidgetSlots(...)` owns row `Y` more explicitly
- `panel.render` owns row settlement more explicitly
- `verticalTabs` no longer relies on the old ambient split behavior
- structured child start/end settlement is more deliberate than before

This means the current system is now:
- coherent
- usable
- stable enough to finish and document as a real generation of the framework

That matters.
The point of this document is not to declare v1 a failure.

---

## What Still Feels Incomplete

Even after the cleanup, the layout substrate still feels weaker than the rest of the framework.

The root issues are:

### 1. The declarative tree is stronger than the placement model

The tree now expresses:
- structure
- state ownership
- visibility
- tab grouping
- selection
- widget configuration

But the layout engine under that tree still reflects a more transitional model:
- row-dominant composition
- explicit `X` in many places
- more limited `Y` semantics
- some remaining dependence on flow-style assumptions

### 2. `X` and `Y` are not equal in the layout language

Today:
- `X` has richer authored geometry concepts
  - `start`
  - `width`
  - `align`
- `Y` is still more row-oriented
  - `line`
  - measured row settlement
  - accumulated row advance

That asymmetry is not automatically wrong.
For list-heavy UI, row-dominant structure is often the right public model.

But it does mean the substrate is still only partially geometric.

### 3. The current model still shows its seams in custom-widget authoring

The most important lesson from BoonBans was not that declarative UI failed.
It was that the current substrate has a sharp boundary:

- layouts can compose layouts and widgets
- widgets should generally behave as leaf renderers
- recursively drawing a full slot-based widget from inside another widget is not a healthy default

That is a strong and useful boundary, but it also exposes where the substrate is fragile:
- custom widgets that need mini internal layout still require care
- cursor settlement remains part of the contract

### 4. The layout model was stabilized, but not chosen from scratch

The current row-dominant layout model is now coherent enough to keep.
But it is also clear that it largely evolved from ImGui’s default flow model rather than being designed from first principles.

That is acceptable for a stabilized v1.
It is also a signal that a future clean-slate substrate could likely be cleaner.

---

## What Was Learned From BoonBans

BoonBans was the pressure case that clarified a lot of boundaries.

## Good outcomes

- the static tree approach is viable
- derived transient text belongs in Lib as a small helper
- tab selection as transient UI state is a good pattern
- prepared-node caching is a valid reusable mechanism
- the current model can support a complex special module without reviving planner/runtime geometry

## Important boundaries discovered

- widgets are best treated as leaf renderers
- custom widgets may use immediate-mode internals, but they should present an atomic footprint to their parent
- row settlement must be owned deliberately; ambient cursor flow is not a strong enough substrate
- Lib can and should provide small reusable mechanics
  - it should not try to infer module semantics automatically

## Performance lesson

The performance regression did not come from the declarative idea itself.
It came from churn:
- unnecessary per-frame node preparation
- unnecessary signature rebuilding
- repeated allocation in hot paths

That was partially fixed with:
- prepared-node caching
- root-level signature caching

So the current system’s performance story is:
- not free
- but manageable when the substrate respects hot-path costs

---

## Current Judgment On The Live System

The current live system should be treated as:
- a valid stable generation of the framework
- not the final ideal layout substrate

That distinction matters.

It means:
- the right short-term move is to strengthen and document v1
- the wrong short-term move is to force v1 to become a clean-slate v2 by accretion on `main`

The system is good enough to finish.
It is not obviously the forever substrate.

That is a healthy place to be.

---

## Big Picture Direction For A Future Layout Substrate

This section is not a plan.
It is the current directional intuition for what a future substrate would probably want.

## 1. Keep structured authoring

The future system should still be declarative and structured.

It should **not** become:
- raw coordinate soup
- authors placing every widget manually by `x/y`

For this kind of UI, structured composition remains the right public authoring model.

## 2. Use a symmetric internal placement model

A future substrate likely wants internal rect-based placement:
- `x`
- `y`
- `width`
- `height`

That does not require exposing raw absolute coordinates as the authoring model.
It means the engine itself has a cleaner geometry contract than the current row/slot hybrid.

## 3. Separate layout containers from region containers

This is one of the clearest conceptual needs.

Future substrate should distinguish:

- layout containers
  - stack/row/grid-like composition
  - shared tracks/alignment
  - spacing and sizing rules

- region containers
  - child windows
  - clipping
  - scrolling
  - tab panes

This boundary already matters in practice because `BeginChild`-style regions are not the same thing as layout.

## 4. Unify inner and outer layout concepts

One of the biggest clean-slate ideas is:
- outer layout
- inner widget slot layout

are currently two versions of the same problem.

A future substrate would ideally avoid maintaining:
- one geometry language for outer layout
- another mini-layout language inside widgets

Instead, it would use one coherent internal model for both.

## 5. Keep widgets from owning surrounding flow

A future substrate should preserve one of the best lessons from the current system:

- parent/layout owns placement
- widget renders within the placement it was given
- widget does not decide sibling placement by side effect

ImGui remains the rendering substrate.
But layout should not depend on ambient cursor aftermath.

---

## What This Document Is Not Arguing For

This document is **not** saying:

- rewrite Lib immediately
- abandon the current row-based public surface tomorrow
- build a CSS engine on top of ImGui
- force all authors to declare absolute `x/y/width/height`
- reopen a broad dynamic-layout system on `main`

Those would be the wrong conclusions.

The correct conclusion is narrower:
- the current foundation is mostly complete
- layout is the last major foundational weakness
- a future layout-generation rewrite should be treated as its own deliberate effort, not as incidental cleanup

---

## Practical Next Step

The practical sequence should be:

1. tighten and document the current implementation
2. treat the current static generation as stable
3. write a more detailed future layout-substrate plan later
4. if that plan still feels right, do the layout rewrite on a dedicated branch

This preserves the current progress instead of destabilizing it.

---

## Summary

The current Lib is no longer blocked on:
- storage
- state
- aliases
- hashing
- special/regular boundaries
- declarative UI language

The remaining large architectural question is layout substrate.

The current layout substrate is:
- usable
- coherent
- worth finishing

But it is also:
- the least mature foundational layer remaining
- likely not the final ideal form

That is the big-picture context this file is meant to preserve.
