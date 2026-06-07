# Shared Infrastructure Cleanup

This document summarizes the closed Lib and Framework cleanup pass.

## Scope

Covered:
- `adamant-ModpackLib`
- `adamant-ModpackFramework`
- shell-repo cleanup tracking docs

Not covered:
- module implementation audits
- future feature design

## Outcome

Shared infrastructure is considered cleaned up for the current post-migration
phase. Lib and Framework now use the current API language consistently enough
that remaining work is module-specific or future design.

## Lib Summary

Completed areas:
- bootstrap primitives
- storage core and hash serialization
- module-state backends and data frontends
- status lane
- actions, reset, and draw commit lifecycle
- cache and shared data/events
- controls
- widgets
- hooks
- overlays
- mutations
- fallback UI and framework runtime
- module bootstrap and activation

Key results:
- Public runtime-owned language became `status`.
- Shared data/events are exposed through `runtime.shared` and `ui.shared`.
- Controls compile config storage only; status and actions remain module-level
  coordination lanes.
- Reset is a single UI/module operation instead of multiple lane-specific
  public reset helpers.
- Draw commit ordering is centralized and documented.
- Historical migration docs and duplicate LuaCAT implementation annotations were removed.
- Tests were kept as behavior coverage rather than as reasons to preserve old
  surfaces.

## Framework Summary

Completed areas:
- coordinator bootstrap and pack replacement
- module registry and live-module snapshotting
- profile/hash load and rollback behavior
- UI runtime coordination
- HUD hash marker runtime
- docs/examples

Key results:
- Framework docs now use the current explicit dependency-injection module style.
- Private helper naming in Framework internals was normalized.
- Runtime/profile coordination and UI/HUD files were kept grouped because their
  boundaries are still useful and well-covered by tests.

## Deferred Ideas

These are not cleanup blockers:
- optional generic string compression for hashes if real-world hashes become too long
- possible future action/status/task unification
- tiny Framework UI helper duplication such as local `TextColored` wrappers

## Next Audit Direction

Module audits should not reuse the infrastructure rubric directly. A better
module rubric should focus on:
- what data leaves the module data layer
- whether resolvers hide control names and game-data translation cleanly
- whether controls own repeated UI/data patterns instead of catalogs leaking them
- whether logic files are named by concrete gameplay behavior
- whether UI files read as layout and composition instead of metadata plumbing
- whether `main.lua` is a thin composition root
