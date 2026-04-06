# UI Layout Direction

## Context

This note captures an architectural discussion about where the Lib/Framework UI system appears to be heading after:

- `definition.storage` / `definition.ui`
- alias-backed managed state
- module-defined `customTypes`
- promoted generic widgets like `packedCheckboxList`

The immediate trigger was Boon Bans and Framework both using similar sidebar/detail panel shells while still living in different implementation layers.

The goal of this document is not to prescribe an immediate patch. It is to preserve the design direction and tradeoffs so this can be resumed later.

## Current State

The current system already has most of the pieces of a declarative UI layer on top of ImGui:

- typed persisted storage
- alias-backed staged UI state
- widget registry
- layout registry
- hosted rendering for regular modules
- reusable widget drawing for special modules
- module-scoped `customTypes` for widgets/layouts that should not live in Lib

This means the old hard split between `regular` and `special` modules is already weakening.

Today:

- regular modules can express more complex UI through declarative layout
- special modules can reuse managed widgets instead of fully reimplementing them

This is moving the system toward one shared pipeline with escape hatches, instead of two mostly separate UI systems.

## Key Observation

The most valuable next convergence point is probably not deeper widget purity first.

The most productive next convergence point is the shared panel/sidebar shell pattern already duplicated in:

- Framework category/module presentation
- Boon Bans domain/root presentation

That duplication is more worth attacking than forcing Boon Bans deeper into declarative custom widgets just to prove that it can be done.

## Architectural Fork

Two expansion directions were identified.

### 1. Top-down

Start from larger containers:

- tabs
- sidebar/detail layouts
- panels

Then let those containers host either:

- custom draw callbacks
- or declarative child widget/layout trees

Pros:

- pays off immediately for Framework and Boon Bans
- reduces duplicated shell code
- creates shared layout behavior faster

Cons:

- lower-level widget composition remains ad hoc for longer

### 2. Bottom-up

Start from smaller pieces:

- simple widgets
- more complex widgets
- panel-arranging widgets
- tab containers

Pros:

- cleaner long-term composition story
- stronger declarative purity

Cons:

- slower practical payoff
- higher risk of infrastructure work that does not improve real modules yet

## Recommended Direction

Favor the top-down path first.

More specifically:

1. Define a reusable panel model.
2. Build tab/sidebar layouts around panels.
3. Continue enriching inner widget composition only when repeated real module needs justify it.

This is the path most likely to reduce current maintenance cost.

## Panel Model

Tabs should not be designed in isolation.

A useful tab or sidebar layout needs a notion of a panel item.

Minimum panel shape:

```lua
{
    key = "Olympians",
    label = "Olympians",
    draw = function(ui, uiState, theme) ... end,
}
```

or:

```lua
{
    key = "Olympians",
    label = "Olympians",
    children = {
        -- declarative ui nodes
    },
}
```

This gives the layout a simple responsibility:

- render the panel list
- track selection
- render the selected panel body

The layout should not own domain semantics.

## What Should Be Shared

Good candidates for shared layout extraction:

- sidebar/detail split shell
- width ratio
- selection state shell
- optional grouped headings
- optional empty-state handling
- optional presentation options like spacing and separators

Bad candidates for direct sharing:

- Framework category/module semantics
- Boon Bans root/scope/view semantics
- domain-specific badges, summaries, enable toggles, or business rules

The abstraction should be presentational, not semantic.

## Proposed Intermediate Shape

The likely practical next step is a shared layout helper or layout type that accepts runtime-built panels.

Conceptually:

```lua
lib.drawSidebarDetail(ui, {
    sidebarWidthRatio = 0.28,
    panels = panels,
    selectedKey = selectedKey,
    onSelect = function(key) ... end,
})
```

Each panel would provide either:

- `draw`
- or `children`

This allows gradual migration:

- existing custom modules can keep imperative panel bodies
- simpler modules can use declarative child trees
- both go through the same shell

## Relationship To Regular vs Special

This does not completely remove the regular/special distinction.

Instead it changes the split from:

- separate UI systems

to:

- one shared UI pipeline with localized escape hatches

That is a better split.

It means:

- fully declarative panels
- mixed panels
- fully custom panels

can coexist inside one architecture.

This is preferable to a module-level binary where a whole module is either "regular" or "special" because the framework is too weak.

## Custom Widgets

Module-defined `customTypes` already move the system toward a declarative UI library on top of ImGui.

That is acceptable and likely beneficial, but it should stay grounded in real reuse.

The discussion concluded:

- splitting module custom widgets into their own files is worthwhile cleanup
- forcing Boon Bans deeper into declarative widgetization right now is mostly demonstrative
- shared layout extraction is more productive than pushing more widget-level purity today

In other words:

- custom widgets are useful
- but layout convergence currently has better payoff

## Rarity Widget Example

`rarityBadge` was used as a proof of custom widget support.

That experiment has value, but it does not currently justify a larger refactor by itself.

It remains a good future reference point for:

- module-local reusable widgets
- possible packed child alias modeling later

It was explicitly tabled in favor of layout work.

## Long-Term Direction

The system is trending toward a domain-specific declarative UI library on top of ImGui.

That is not inherently bad.

It becomes bad only if:

- infrastructure starts getting ahead of real use cases
- abstractions are added to prove elegance rather than solve repeated module problems

The best guardrail is:

- only promote patterns that immediately reduce maintenance or duplication
- prefer concrete shared shells over speculative composition machinery

## Recommended Future Sequence

If this work is resumed later, the recommended order is:

1. Extract a shared sidebar/detail panel shell.
2. Decide whether it should first exist as:
   - a helper function
   - or a true layout type
3. Model runtime-built panels with:
   - `key`
   - `label`
   - `draw` or `children`
4. Use that shell in Boon Bans and Framework.
5. Re-evaluate whether additional layout primitives are now clearly justified:
   - side tabs
   - vertical tabs
   - collapsing list layouts
6. Only after that, revisit deeper widget composition if a real module still needs it.

## Practical Conclusion

There is real merit here, but it does not need to be done immediately.

The high-value part is:

- reducing duplicated panel/layout code across Framework and complex modules

The lower-value part, for now, is:

- proving maximal declarative purity inside Boon Bans

If resumed later, start from shared panel/layout extraction, not from deeper widget abstraction.
