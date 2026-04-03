# Bridal Glow Dropdown Performance Issue

## Status

Open issue. The `Bridal Glow` controls added to the Boon Bans `Settings` tab are still much slower than expected when either dropdown is opened in-game.

This persists even after several targeted optimizations.

## Feature Context

The UI lives in:

- `Submodules/adamant-RunDirectorBoonBans/src/mods/ui/views.lua`

Persistence currently uses a schema-backed string field:

- `BridalGlowTargetBoon`

Declared in:

- `Submodules/adamant-RunDirectorBoonBans/src/config.lua`
- `Submodules/adamant-RunDirectorBoonBans/src/main.lua`

Backend helper currently available:

- `internal.GetBridalGlowTargetBoonKey(uiState)` in
  `Submodules/adamant-RunDirectorBoonBans/src/mods/utilities.lua`

## Symptom

When the `Eligible God` or `Eligible Boon` combo is opened, the UI becomes significantly slower than expected.

The slowdown is much worse than the rest of the Boon Bans UI and feels out of proportion to the amount of data involved.

## Important Finding

The slowdown does **not** appear to come from the generic Lib `string` field type itself.

The Bridal Glow controls are custom-rendered and do not use the generic `string` field draw widget. They only persist through a schema-backed string key.

So the likely cause is still in the custom Bridal Glow hot path, not in `adamant-ModpackLib`'s `FieldTypes.string`.

## What Was Already Tried

### 1. Removed packed-int workaround

Originally this feature used a packed `int32` plus encode/decode helpers.

That was removed after adding a reusable Lib `string` field type. The feature now stores the boon key directly as a string.

### 2. Cached eligible boon lists per root

Added:

- `uiData.bridalGlowBoonsByRoot`

So `GetBridalGlowEligibleBoons(root)` no longer rebuilds the same rarity-eligible boon list every frame.

### 3. Removed unnecessary stored-key validation scan from the footer text

The Settings footer used to re-scan runtime boon data just to print the currently stored key.

That was simplified.

### 4. Cached eligible Olympian roots for Bridal Glow

Added:

- `uiData.bridalGlowEligibleRoots`

So the Bridal Glow controls no longer call the live Olympian visibility path every frame.

This was intended to remove repeated God Pool filtering from the dropdown-open hot path.

## Remaining Suspects

### A. ImGui combo-open cost in this exact settings layout

The remaining slowdown may be tied to how the combo is rendered inside the Settings tab rather than the data scan alone.

Worth checking:

- whether the combo body is being rebuilt in a way that causes excessive widget cost
- whether this tab has a pathological interaction with the broader Settings render path

### B. `uiState` dirty/write behavior during combo interaction

Even though the value is only set on selection, it is still worth verifying whether the combo-open path is causing unexpected dirty-state or commit-related work.

Places to inspect:

- `adamant-ModpackLib/src/special.lua`
- `adamant-ModpackLib/src/core.lua`

### C. Hidden repeated work in the visible-root / God Pool dependency path

Even after local caching, there may still be a dependency causing more work than expected.

Relevant files:

- `Submodules/adamant-RunDirectorBoonBans/src/mods/ui/views.lua`
- `Submodules/adamant-RunDirectorBoonBans/src/mods/ui/roots.lua`
- `Submodules/adamant-RunDirectorGodPool/src/mods/logic.lua`

### D. Need real in-game instrumentation

At this point, further guessing is likely lower-value than instrumenting the Bridal Glow draw path directly.

Recommended next step:

- add temporary timing/logging around:
  - `DrawBridalGlowControls`
  - `GetBridalGlowEligibleRoots`
  - `GetBridalGlowEligibleBoons`
  - combo-open branches
- compare idle settings-tab frame time vs combo-open frame time

## Caveat About Current Cache

`uiData.bridalGlowEligibleRoots` is currently cached.

That means Bridal Glow's eligible god list may not live-update immediately if God Pool settings change in the same session unless the cache is invalidated or the module reloads.

Helper currently present:

- `uiData.InvalidateBridalGlowCaches()`

but automatic invalidation is not yet wired.

## Suggested Resume Point

When revisiting this:

1. Reproduce in-game with the current code.
2. Instrument `DrawBridalGlowControls` directly.
3. Confirm whether slowdown is:
   - data scanning
   - combo/widget rendering cost
   - `uiState` lifecycle cost
   - a cross-module dependency
4. Only then decide whether to keep the current custom control or redesign it.
