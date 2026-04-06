# Padding Notes

## Purpose

This document is not an implementation plan.

It exists to capture:

- what the game does
- what the mod is trying to preserve or change
- where the tensions are
- what success should look like

Any new implementation should be derived from these constraints, not from old code.

## User Model

`BoonBans` is ban-first.

The player sees a list of boons for a god and bans individual boons.
There is no explicit "force" control.

That means user intent is inferred from what remains unbanned:

- if 1 boon remains unbanned, the player effectively wants that boon
- if 2 remain unbanned, the player effectively wants those 2
- if 3 or more remain unbanned, randomness is acceptable

## Game Facts

### Visible Offer Count

The offer UI shows up to `3` choices.

### Vanilla Behavior

Vanilla boon generation includes several interacting behaviors:

- normal eligibility filtering
- direct priority-style insertions
- replacement / exchange chance
- rarity rolling
- fail-safe logic if the offer list is too small

### Replacement / Exchange Traits

Replacement traits are a specific vanilla offer type.

They are not just generic fallback boons.

Semantics:

- the player has a small set of core boon slots
- gods can offer alternative boons for those same slots
- if picked, a replacement offer removes an existing slotted boon and gives a new boon in that slot
- non-slotted supportive traits are not part of this replacement system

Observed vanilla behavior and code meaning are aligned here:

- normal gameplay can roll replacement offers through a random replacement chance
- if a god's menu would otherwise be too small, vanilla can also use exchange traits as shortage filler

So replacement offers should be understood as:

- "exchange one owned slotted boon for another slotted boon"

not as:

- "generic extra boon"

### Repeated Generation

The game may generate or inspect loot choices multiple times before the player actually picks one.

This means:

- preview-time generation is not always final menu truth
- tier advancement should only be trusted after actual boon acquisition

### Future Offer Pressure

There is a game difficulty modifier that prevents boons that were offered and not picked from being offered later.

This matters because filler offers are not harmless:

- showing a boon now can consume it as a future possibility

## Mod Controls

### `EnablePadding`

When enabled, the mod may use otherwise banned boons to keep the offer menu full.

### `Padding_AvoidFutureAllowed`

This control exists to respect future offer plans.

Meaning in plain language:

- do not spend later-useful boons as filler now unless necessary

This control has no direct gameplay value beyond preserving future offer structure.

## Core Tensions

These goals can conflict:

1. Respect the player's bans
2. Keep the menu full
3. Preserve vanilla behavior
4. Preserve future later-tier offer plans

The system may not be able to maximize all four at once in every case.

## Important Observations

### Dense vs Sparse Bans

`Padding_AvoidFutureAllowed` works better when bans are dense than when bans are sparse.

Reason:

- with dense bans, the player's intended set is narrow and easier to preserve
- with sparse bans, many boons remain in play and "do not use future-useful boons as filler" becomes harder to satisfy while also keeping menus full

### Implied Preference Strength

The fewer unbanned boons remain, the stronger the implied player intent becomes.

This matters more than whether the code internally calls something "forced".

### Replacement Is Desired

Vanilla replacement chance should remain active if possible.

The goal is not to disable vanilla systems.
The goal is to preserve player intent while keeping vanilla behavior recognizable.

## Desired Outcomes

### Strong Preference Cases

If only `1` boon is unbanned:

- that boon should appear

If only `2` boons are unbanned:

- both should appear

### More Than Three Allowed

If `3` or more boons are unbanned:

- the system does not need to guarantee exactly which 3 appear
- randomness is acceptable

## Replacement Expectations

Desired behavior:

- `1 allowed`: that boon should still appear even if another slot is occupied by a replacement-style offer
- `2 allowed`: those 2 should still appear even if another slot is occupied by a replacement-style offer
- `3+ allowed`: replacement behavior may affect any slot, consistent with normal randomness

## Padding Expectations

Padding exists to prevent collapse of the menu when bans become too restrictive.

But padding should not erase the meaning of bans.

In plain terms:

- unbanned boons are the real preference
- banned boons are fallback material

## Questions Any New Implementation Must Answer

1. At what point in the vanilla flow is the final visible offer list actually stable?
2. Which vanilla insertion paths bypass the normal filtering assumptions?
3. How should replacement behavior interact with the `1 / 2 / 3 allowed` guarantees?
4. When `Padding_AvoidFutureAllowed` is enabled, what exactly counts as "too important for later to spend now"?
5. What information can be trusted at preview time, and what must wait until actual pick time?

## Acceptance Cases

Any replacement implementation should be tested against at least these cases:

### Case 1: One Allowed

- ban all but one boon
- verify that the remaining boon appears

### Case 2: Two Allowed

- ban all but two boons
- verify that both appear

### Case 3: Three Allowed

- ban all but three boons
- verify that randomness is acceptable and replacement may affect any slot

### Case 4: More Than Three Allowed

- leave four or more boons unbanned
- verify that the result is acceptable even if not deterministic

### Case 5: Padding Enabled

- create a state where the allowed pool alone cannot fill the menu
- verify that banned filler can appear when enabled

### Case 6: Padding Avoid Future Allowed

- create a multi-tier setup where some currently banned boons are intended for later
- verify whether current filler behavior preserves that plan

### Case 7: Replacement Chance

- test with replacement chance active
- verify that the `1 / 2 / 3 allowed` expectations still hold

### Case 8: Preview vs Actual Pick

- verify that repeated preview generation does not corrupt tier tracking
- verify that tier advancement only reflects actual acquired boons

## Logging Guidance

When debugging this system, distinguish between:

- preview / precompute generation
- final visible menu generation
- actual boon pick

If logs mix those together, they will be misleading.
