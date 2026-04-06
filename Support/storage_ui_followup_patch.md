# Storage/UI Follow-Up Patch Brief

## Purpose
This document captures the known follow-up work after the hard-cut Storage/UI redesign.

It is intentionally narrower than the migration blueprint:
- the blueprint explains the new model and how modules were migrated
- this document records the remaining design debt, correctness gaps, documentation mismatches, and deferred cleanup work for the next patch

This is not a decision to revert the redesign. It is a review-driven follow-up list for stabilizing and generalizing the new architecture.

## Confirmed Follow-Up Issues

### 1. Multi-bind widgets need a real contract
Current problem:
- `steppedRange` is hardcoded in two places in `adamant-ModpackLib/src/field_registry.lua`
- bind validation special-cases `bindMin` / `bindMax`
- draw dispatch special-cases `steppedRange`

Why this matters:
- `steppedRange` is proving that widgets can need multiple bindings
- the current implementation solves one widget, not the general class
- any future multi-bind widget would require editing framework dispatch again

Fix direction:
- add a declared bind contract on widget types
- widget types should describe their bind requirements
- generic validation should walk those declared binds
- generic draw should resolve those declared binds and pass them to the widget

Target outcome:
- no widget-specific branching in generic bind validation
- no widget-specific branching in generic draw dispatch
- `steppedRange` becomes the first consumer of the generalized mechanism

### 2. `prepareUiNode(...)` has a timing contract bug
Current problem:
- `prepareUiNode(node, ..., storage)` validates against storage alias metadata
- that metadata is populated during storage validation inside `createStore(...)`
- ad-hoc callers that run `prepareUiNode(...)` before `createStore(...)` do not get real bind validation

Concrete example:
- `Submodules/adamant-BiomeControl/src/main.lua` calls `lib.prepareUiNode(...)` during registration
- this can happen before store creation and before alias metadata is prepared

Why this matters:
- the public helper appears to validate binds reliably
- in some real call paths it silently cannot
- this makes the helper contract misleading

Fix direction:
- either make `prepareUiNode(...)` self-sufficient by preparing/deriving storage alias metadata from raw storage definitions
- or change the contract so callers must pass prepared storage metadata, not raw storage declarations

Preferred outcome:
- `prepareUiNode(...)` should reliably validate binds from the inputs it receives
- callers should not need to know hidden ordering requirements

### 3. Layout nodes must propagate changed state
Current problem:
- layout nodes currently discard changed-state information when drawn through generic UI traversal
- a layout containing child widgets can return `false` even when a child changed

Why this matters:
- the generic UI API should be internally consistent
- callers using `drawUiTree(...)` should be able to trust its changed-state return value
- even if hosted flows currently rely more on dirty-state tracking, the public helper contract should still be correct

Fix direction:
- make layout drawing accumulate and return child changed-state
- the generic draw traversal should preserve the result from child widgets

Target outcome:
- layout nodes are presentation-only, but they do not swallow change signals from descendants

### 4. `visibleIf` is too narrow for current module needs
Current problem:
- `visibleIf` currently supports only a bool alias
- this does not cover common mode-driven UI cases such as:
  - show range controls when mode equals `"forced"`
  - show controls for one of several named enum values

Concrete example:
- `Submodules/adamant-BiomeControl/src/mods/ui.lua` still carries custom visibility logic because the built-in form is too limited

Why this matters:
- the redesign introduced a declarative visibility system
- it currently cannot express several of the real use cases that motivated it

Fix direction:
- keep the bool-alias form as the simple case
- add a structured conditional form such as:

```lua
visibleIf = { alias = "Mode", value = "forced" }
```

- consider a small extension for multiple allowed values:

```lua
visibleIf = { alias = "Mode", anyOf = { "forced", "charybdis" } }
```

Target outcome:
- common conditional visibility cases move out of custom draw code
- BiomeControl and similar modules can use the declarative system more fully

### 5. Cached bind references are computed but unused
Current problem:
- UI prep stores cached bind metadata such as `_bindStorage`
- generic draw currently resolves through alias lookups again instead of using those cached references

Why this matters:
- the current prep work suggests an optimization / validation artifact that the draw path does not actually consume
- this adds mental overhead without clear value

Fix direction:
- either use the cached bind metadata in generic draw
- or stop computing and storing it

Target outcome:
- prep and draw should agree on what binding metadata is needed
- no dead scaffolding

## Documentation Severity Mismatch

### 6. Alias requirement is stricter in docs than in implementation
Current implementation:
- root storage aliases are effectively optional
- if a root alias is omitted, the framework derives it from `configKey`
- packed child aliases are still required

Current docs:
- several docs currently describe aliases as required for all storage nodes

Why this matters:
- readers will author to a stricter contract than the system actually enforces
- review and migration discussion keep circling alias strictness because the docs and code do not match

Fix direction:
- update docs to reflect the real implemented rule:
  - root alias optional, defaults to `configKey`
  - packed child alias required
- decide whether to keep that policy or tighten it later, but document the current truth correctly now

Affected docs:
- `adamant-ModpackLib/FIELD_REGISTRY.md`
- `adamant-ModpackLib/API.md`
- `adamant-ModpackLib/MODULE_AUTHORING.md`
- `adamant-ModpackLib/MIGRATION_PATCH_1.md`
- `Setup/migrate/storage_ui_blueprint.md`

## Open Design Discussion

### 7. Nested `configKey` support remains unresolved
Status:
- no decision yet

Current concern:
- nested `configKey` paths add complexity across the system:
  - hashing
  - alias derivation
  - validation
  - docs
  - tests
  - migration reasoning

Observed tradeoff:
- the practical benefit appears small relative to the amount of support cost
- flat keys map more naturally to alias-first storage

What should be evaluated before deciding:
- whether any current module truly benefits from nested persisted paths
- whether nested paths are worth keeping in the new architecture
- whether they should be:
  - kept as-is
  - deprecated
  - or removed in a later cleanup patch

Current guidance:
- do not make the decision inside the fix patch for the five issues
- review the redesign first, then decide whether nested keys deserve continued support

## Deferred Cleanup and Stabilization Work

### 8. BiomeControl migration should be cleaned up after the architecture settles
Current state:
- BiomeControl was migrated mechanically
- registration uses many repeated `AddStorageNode(...)` / `RegisterUiNode(...)` calls
- the result works, but is noisy and harder to review than it needs to be

Why this happened:
- the migration prioritized correctness and full cut-over
- it did not yet add a cleaner builder layer for repeated patterns

Cleanup direction:
- factor repeated registration patterns into small helpers or descriptor-driven builders
- reduce one-off boilerplate in:
  - scalar control registration
  - range node registration
  - repeated dropdown/checkbox sections

Target outcome:
- BiomeControl remains on the new architecture
- but its module definition becomes significantly easier to read and maintain

### 9. Special-module guidance after the timing fix
Status:
- resolved

What changed:
- `lib.prepareUiNode(...)` now accepts raw `definition.storage`
- `lib.validateUi(...)` also prepares raw storage metadata on demand
- special-module docs were updated to reflect that store creation is not required before preparation

Current guidance:
- special modules may prepare reusable UI nodes directly against raw `definition.storage`
- callers do not need hidden ordering knowledge about `createStore(...)`
- prepared storage metadata is still valid input, but it is no longer required

Remaining note:
- this item no longer needs a dedicated code fix
- future special-module cleanup can assume the public helper contract is now stable

### 10. The current redesign should be reviewed for additional opportunities to reduce mechanical boilerplate
Known example:
- BiomeControl registration noise

Possible broader opportunity:
- small helper builders around common storage + widget pairs
- especially for modules that remain declarative but repetitive

Note:
- this is not a request for a compatibility layer
- it is a follow-up readability pass on top of the new model

## Suggested Fix Order

If these items are addressed in a dedicated follow-up patch, the recommended order is:

1. Generalize multi-bind widgets
2. Do module cleanup work such as BiomeControl registration refactors
3. Return to the nested `configKey` decision separately

## Non-Goals of the Follow-Up Patch
- do not revert the Storage/UI redesign
- do not reintroduce compatibility with `stateSchema` / `options`
- do not decide the nested `configKey` question prematurely
- do not hide module-owned persistence design behind automatic storage allocation

## Summary
The redesign is still the intended architecture.

The next patch should focus on:
- turning one-off solutions into generalized mechanisms
- fixing public helper contract gaps
- aligning docs with implementation reality
- cleaning up the noisiest migration artifacts

The most important architectural debt is the same one that surfaced immediately:
- widgets can have more than one binding
- the framework should model that directly instead of hardcoding `steppedRange`
