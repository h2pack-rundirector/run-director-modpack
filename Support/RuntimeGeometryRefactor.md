Refactor Runtime Geometry Ownership in ModpackLib
Summary
Refactor Lib so prepared nodes keep only static/prepared state, while runtime geometry/layout preparation is moved out of drawUiNode(...) and getWidgetSummary(...) into an explicit runtime-preparation layer.

The goal is to remove per-call runtime geometry parsing/caching from draw/query functions, make runtime ownership unambiguous, and keep getWidgetSummary(...) and drawUiNode(...) as consumers of already-prepared runtime state rather than hidden preparers.

Key Changes
1. Introduce explicit prepared runtime state
Add an internal/public-preparable runtime state object for one prepared node, covering:

widget runtime slot geometry
layout runtime overrides
any node-local runtime cache currently stored on the node for draw/query
Use one stable shape, e.g. a prepared runtime object passed into both draw and summary paths. It should be caller-owned for the current interaction/frame lifecycle and never mutate repo-owned node structure beyond existing static prep fields.

Chosen direction:

keep static prep on the node via prepareUiNode(...) / prepareWidgetNode(...)
add explicit runtime prep helpers instead of having drawUiNode(...) / getWidgetSummary(...) parse raw runtime inputs
node no longer owns _runtimeSlotGeometrySource, _runtimeSlotGeometryCache, or equivalent per-pass runtime cache
2. Make draw/query pure consumers of prepared runtime state
Change Lib runtime flow so:

drawUiNode(...) consumes prepared runtime state and does not call PrepareRuntimeWidgetGeometry(...) itself
getWidgetSummary(...) consumes prepared runtime state and does not parse/cache raw runtime geometry
ResolveSlotGeometry(...) should prefer an explicit prepared runtime override object passed down from caller/runtime state rather than reading node-attached _runtimeSlotGeometry
Keep the prepared-node requirement intact:

drawUiNode(...) and getWidgetSummary(...) both expect prepared nodes
missing _widgetType / _layoutType remains a visible warning or contract error path, not implicit preparation
3. Unify layout-side runtime prep
Lift existing fragmented runtime prep into one ownership model:

widget runtime prep currently in PrepareRuntimeWidgetGeometry(...)
tab/panel runtime prep currently in PrepareRuntimeTabbedLayout(...) and PrepareRuntimePanelLayout(...)
Refactor these into one coordinated runtime-preparation path so planner/layout code can prepare:

widget geometry overrides
layout child overrides
for the same node tree without duplicate hidden caching.
Keep existing behaviors:

panel runtime child overrides
verticalTabs / horizontalTabs runtime layout behavior
hidden/line widget runtime overrides
no runtime creation of new slots
4. Keep public call ergonomics, but change what they accept
Retain the public high-level API names where possible, but change semantics from “raw runtime input” to “prepared runtime input”.

Planned interface direction:

prepareUiNode(...) / prepareWidgetNode(...): static prep only
add runtime-prep helper(s) for prepared nodes/tree
drawUiNode(...): accepts prepared runtime state object instead of raw runtimeGeometry / runtimeLayout
getWidgetSummary(...): same prepared runtime object instead of raw runtime geometry
If backward compatibility is needed internally during migration, use a short-lived bridge only inside Lib, not as a documented long-term contract.

5. Update Boon Bans planner usage
Adjust Boon Bans to use the new runtime-prep layer instead of handing raw runtime geometry directly into Lib draw/query functions.

Primary target:

ban list planner/runtime filtering in planner.lua
any current or future summary/dynamicText workflows that query widgets with runtime overrides
The planner should own cache invalidation by signature/input state, then hand prepared runtime state to Lib.

Test Plan
Existing Lib suite stays green after refactor.
Add focused tests for:
prepared runtime widget geometry is reused across draw and summary without reparsing
drawUiNode(...) does not mutate node with per-pass runtime cache fields
getWidgetSummary(...) does not mutate node with per-pass runtime cache fields
prepared runtime state correctly drives radio hidden/visible summary counts
prepared runtime state correctly drives packedCheckboxList hidden/visible summary counts
panel runtime child overrides still work after moving runtime prep ownership
verticalTabs active-tab fallback still works with prepared runtime layout state
Add one integration-style test covering:
planner prepares runtime state once
same prepared runtime state is used for both draw and summary on the same node
no duplicate parsing path is invoked
Assumptions
This refactor is for long-term architecture health, not to preserve the exact current raw-runtime-geometry API shape.
Prepared nodes remain module-owned lifecycle objects; runtime prepared state becomes separate transient Lib-managed data.
Static geometry/default geometry remains node prep data.
Runtime slot/layout state remains fixed-schema-only; no runtime invention of new slots or child targets.
Summary stays as an optional widget capability on widget definitions, and lib.getWidgetSummary(...) remains the public wrapper around that capability.

