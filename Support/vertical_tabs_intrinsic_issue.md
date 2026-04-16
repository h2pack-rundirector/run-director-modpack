## Vertical Tabs Intrinsic Width Issue

### Problem

Nested vertical `tabs` in Biome Control rendered with a large empty right-side detail pane.

The same kind of nested vertical tabs in Boon Bans appeared to behave correctly, which initially made the issue look module-specific rather than a Lib layout policy problem.

### What Was Actually Happening

The two modules were not being rendered under the same width conditions.

Biome Control:
- originally used the special standalone fallback path
- that fallback called `lib.ui.drawTree(..., ResolveAvailableUiWidth(...), ...)`
- so the root tree received a real constrained `availWidth`
- nested vertical tabs then expanded the detail pane to:
  - `availWidth - navWidth - gap`

Boon Bans:
- uses a custom `DrawTab` path
- that path calls `lib.ui.drawNode(..., nil, ...)`
- so the root node is rendered without an explicit width constraint
- nested vertical tabs effectively behaved intrinsically because `availWidth` was `nil`

So Boon Bans did not prove that constrained vertical tabs were fine.
It only proved that unconstrained vertical tabs looked acceptable for this shape.

### Evidence We Gathered

Temporary logging in `adamant-ModpackLib/src/field_registry/layouts.lua` showed:

Biome Control:
- `availWidth` was a real number
- example:
  - `availWidth=655.5`
  - `navWidth=180`
  - `detailWidth=467.5`
  - `consumedWidth=655.5`

Boon Bans:
- `availWidth=nil`
- example:
  - `availWidth=nil`
  - `navWidth=260`
  - `detailWidth=0`
  - `consumedWidth=268`

This established that the visual difference came from runtime width policy, not just from authored tree shape.

### Dead Ends We Tested

These were tested and did not explain the issue:

- extra wrapper around Biome Control region tabs
- dummy width-test tabs in both modules
- `split` layout behavior
- `scrollRegion` behavior
- direct comparison of a near-identical debug subtree between modules

Those experiments ruled out the common “nested tabs are just broken” explanation.

### The `intrinsicWidth` Experiment

A temporary `tabs.intrinsicWidth` option was added to Lib to test whether vertical tabs should be allowed to size the detail pane intrinsically instead of forcing the full remaining width.

What happened:
- first implementation was wrong because `BeginChild(..., 0, ...)` in ImGui expands to remaining width rather than behaving intrinsically
- later direct-draw attempts caused coordinate bugs
- a measured child-region version was then implemented

Result:
- it did remove the empty right-pane behavior
- but it introduced fragility, including incorrect internal content placement in some grouped layouts

So `intrinsicWidth` is not considered production-ready.

### Current Stabilization Decision

Biome Control was moved onto the same render entrypoint style as Boon Bans:

- custom `DrawTab`
- `lib.ui.drawNode(ui, rootNode, uiState, nil, internal.definition.customTypes)`

This avoids the old constrained-width fallback path from `special.standaloneUI(...)`.

Current intent:
- do **not** rely on `intrinsicWidth` for Biome Control right now
- finish Biome Control using the Boon-Bans-style draw entrypoint
- revisit proper constrained vertical-tab policy later

### Important Implementation Notes

While moving Biome Control to the custom draw path, two hard bugs were found and fixed:

1. `internal.definition` was not assigned
2. `lib.ui.prepareNode(...)` was incorrectly treated as returning a prepared node

Fixes:
- `Submodules/adamant-RunDirector_BiomeControl/src/main.lua`
  - `internal.definition = public.definition`
- `Submodules/adamant-RunDirector_BiomeControl/src/mods/ui_v2.lua`
  - prepare the root in place
  - then cache `root` itself

### What Still Needs Proper Design Later

This issue is not fully solved at the Lib policy level.

Open design question:
- when vertical `tabs` are rendered under a constrained parent width, should the detail pane:
  - fill the remaining width
  - support a true intrinsic mode
  - support a capped / max-width detail policy
  - or expose multiple explicit sizing modes

That policy should be revisited after Biome Control refactor work is complete.

### Practical Next Step When Revisiting

When returning to this later:

1. compare constrained vs unconstrained vertical-tab behavior in a minimal Lib-only repro
2. decide the intended detail-pane sizing policy
3. implement it cleanly in `adamant-ModpackLib/src/field_registry/layouts.lua`
4. only then consider reintroducing an intrinsic or max-width option publicly

