# Agent Instructions

This is the Run Director modpack shell repo. It owns submodule assembly,
pack-level tooling, smoke tests, deployment, and release orchestration. Most
active module work happens inside submodules, especially:

- `Submodules/adamantRunDirector-Run_Planner`
- `adamantRunDirector-RunDirector_Modpack`
- `adamant-ModpackLib` when intentionally updating shared Lib infra

The previous Lib-heavy agent guidance is preserved in `AGENTS.lib-infra.md`.
Read that file when the task is actually about ModpackLib internals. For normal
Run Director shell/module work, this file is the primary guidance.

## Repository Workflow

Always inspect the live worktree before acting. The shell repo can look clean
while a submodule is dirty, and a shell pointer can be stale while the child
repo already has the real change.

Use the shell repo root for pack-level tooling:

- Smoke layout: `lua tests/smoke.lua`
- Full assembled local tests: `ModpackTools/run ModpackTools/local_test/all.py`
- Dependency validation: `ModpackTools/run ModpackTools/validate_platform_versions.py`
- Local deploy: `ModpackTools/run ModpackTools/local_deploy/deploy_all.py --fast`
- Full relink/regeneration deploy only when needed:
  `ModpackTools/run ModpackTools/local_deploy/deploy_all.py --overwrite`

On Windows shells, use `ModpackTools\run.bat` instead of `ModpackTools/run`.
Treat older `Setup/...` commands as stale unless a specific module still owns
one.

Do not edit deployed r2modman profile copies directly. Edit the repo source and
deploy through `ModpackTools`.

## Git And Submodules

When changing a submodule, commit and push the child repo first. Then commit and
push the shell repo pointer. A shell commit that points at an unpushed child
revision is broken for everyone else.

Recommended closeout order:

1. In the child repo, run focused validation.
2. Commit the child repo with a Conventional Commit message.
3. Push the child repo.
4. In the shell repo, stage the submodule pointer.
5. Commit the pointer with a Conventional Commit message.
6. Push the shell repo.

Use `git status --short --branch` in both the shell and relevant submodules
before declaring the work complete.

Do not revert user changes in unrelated submodules or files. If an unrelated
submodule pointer is dirty, leave it alone unless the user explicitly asks for
that pointer update.

## Run_Planner Shape

Run Planner is declarative first and runtime second. Prefer improving the data
model and planning layer before adding runtime special cases.

Important areas:

- `src/mods/biomes/`: biome declarations, layout metadata, parser, and catalog.
- `src/mods/controls/`: UI control templates and their runtime snapshots.
- `src/mods/rewards/`: reward primitives, bundles, surfaces, storage, UI, and
  reward declaration rules.
- `src/mods/route/`: row engine, timeline, run context, targets, markers, and
  reward planning.
- `src/mods/logic/`: runtime hooks that consume the execution plan and apply it
  to game generation.

The execution path should stay simple:

1. Controls produce route snapshots.
2. Route context walks routes in run order and validates rooms/rewards/NPCs/
   features.
3. Execution plan compiles validated snapshots.
4. Runtime hooks consume the plan with minimal interpretation.

Avoid making runtime hooks re-solve UI/data decisions. If runtime needs complex
logic, check whether the plan should carry a clearer value instead.

## Data Modeling

Use game-domain language where possible. If the game models something as a
reward, do not model it as a room merely because that is easier in the UI.
Recent examples: Clockwork Goal and Devotion/Trial routing.

Keep biome-structure rules in biome declarations or biome reward files. Keep
global reward primitive/bundle rules in `src/mods/rewards/declarations/`.

Separate these concepts:

- `biomeDepthCache`: biome-local depth cache behavior.
- `biomeEncounterDepth`: encounter-depth counter, including bounded min/max
  when vanilla/unknown choices make it ambiguous.
- `roomHistoryOrdinal`: route-wide room-history spacing axis for NPCs and
  route features.

Do not let a generic row coordinate stand in for those counters.

Chaos gates are intentionally deferred as route-structural detours, not ordinary
features. Natural Chaos is currently suppressed for route predictability. Do
not re-enable Chaos routing without reading the Chaos notes in
`Submodules/adamantRunDirector-Run_Planner/docs/REWARD_GENERATION_MODEL.md`.

## UI And Performance

The planner UI is a hot path. Avoid fresh allocations during draw. Prefer:

- cached option tables,
- mutable value-state/color tables,
- dirty-state rebuilds,
- shared decoration helpers,
- stable dropdown value lists where context changes should color values instead
  of reallocating or reshaping them.

Use one UI language:

- Declaration-time impossible options can be hidden.
- Context-invalid options should remain visible and be colored invalid.
- Downstream content after the first blocking invalid can be greyed/inactive.
- Enrichment colors are allowed only when the full route is valid.
- Inline invalid labels should not be reintroduced; route status and markers are
  the common invalid-reporting path.

When a bug is really a control/template contract issue, fix the contract rather
than patching each caller. Keep caller-owned draw option tables read-only.

## Validation And Trust Boundaries

Validate at contact points, then trust constructed internals. Do not add broad
defensive nil/type checks in inner loops just to restate construction
invariants. Optional callbacks may be nil; validated internal services should
not need repeated shape checks.

Good validation boundaries in this repo:

- biome/reward/NPC/feature declaration parsing,
- storage/control preparation,
- route snapshot creation,
- route context target and legality builders,
- execution-plan compilation,
- runtime game-state translation at hook boundaries.

For impossible internal states, prefer a clear invariant failure at the boundary
and a focused test. Do not scatter hot-reload or partial-state guards through
the draw/runtime path.

Use LuaCATS annotations for internal parameter shape when helpful. Do not add
runtime type checks only to restate annotations.

## Testing

For Run_Planner module edits, use:

- `lua tests/all.lua`
- `luacheck src tests`
- `rtk git diff --check`

For shell-level changes, use the narrowest appropriate shell validation:

- docs-only: `rtk git diff --check`
- pack layout: `lua tests/smoke.lua`
- broad local assembled checkout: `ModpackTools/run ModpackTools/local_test/all.py`

Run performance/allocation tests when touching planner draw paths, route
context rebuilds, value-state decoration, or dropdown option generation.

## Documentation

When data/modeling decisions change, update the nearest module doc in
`Submodules/adamantRunDirector-Run_Planner/docs/`. Do not leave design notes in
comments when they belong in the design/audit docs.

Keep docs honest about current behavior. If a feature is deferred or disabled,
say that directly instead of describing the intended future state as live.
