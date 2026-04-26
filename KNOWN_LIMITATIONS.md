# Known Limitations

This file documents current design constraints that are intentional or accepted for now.

These are not hidden bugs. They are boundaries the current architecture chooses to live with until the underlying runtime or framework surface changes.

## Structural Hot Reload Rebuilds Are Immediate

When a coordinated module changes its structural contract during hot reload, Lib requests a Framework rebuild as soon as that module finishes:

- `prepareDefinition(...)`
- `createStore(...)`
- `createModuleHost(...)`
- `finalizeModuleHost(...)`

That rebuild is correct, but it is not coalesced across a multi-module reload wave.

Example:

- module A structurally reloads
- Framework rebuilds
- module B structurally reloads right after
- Framework rebuilds again

Why this exists:

- ReturnOfModdingBase reloads modules through an internal file-watcher queue
- that queue drain boundary is not exposed to Lua
- neither ROM nor ModUtil currently provides a clean "hot reload wave complete" callback

What would remove it:

- a ROM-side callback such as `mods.on_hot_reload_wave_complete(...)`
- or another clean Lua-visible boundary after `process_file_watcher_queue()` drains

## Core Is Still A Stronger Hot Reload Boundary

Ordinary module reloads can be handled incrementally:

- behavior-only changes rebuild only the module host/runtime
- structural changes trigger a Framework rebuild

Core is different.

Framework rebuilds currently reuse the pack bootstrap parameters cached by Core during its own initialization. That means Core code/config/bootstrap edits are not treated with the same hot-reload guarantees as ordinary modules.

Why this exists:

- Core owns pack bootstrap policy
- Core is the single place that drives `Framework.init(...)`
- rebuild callbacks intentionally reuse Core's last known init params

What would remove it:

- a broader Core hot-reload design
- or a rebuild path that reconstructs Framework init parameters from fresh Core state instead of cached bootstrap state

## Private Module `internal` Usage Is Convention-Driven

Lib provides clean state funnels for module authors:

- prepared definitions for structural contract
- managed storage for persisted state
- transient session state for UI/runtime staging
- host methods for behavior

But private module `internal` tables remain module-owned implementation detail. Lib does not enforce what authors store there.

Why this exists:

- `internal` is intentionally flexible module-private composition state
- trying to centrally structure or lock it down would fight legitimate module-local implementation needs

What this means in practice:

- first-party modules should use transient/session state for real UI state
- private `internal` caching is still possible, even when it is less clean
- enforcement here is by convention, review, and first-party examples, not runtime guards

What would remove it:

- a more opinionated module-internal framework layer
- which is currently considered more complexity than the problem justifies

## No General Purpose Non-UI Per-Frame Lua Callback

ROM exposes:

- `gui.add_imgui(...)`
- `gui.add_always_draw_imgui(...)`
- `gui.add_to_menu_bar(...)`

These are useful, but they are still render/UI-oriented hooks. There is no clean general-purpose Lua `on_update` or `on_tick` callback for pack logic.

Why this matters:

- it makes deferred rebuild scheduling or end-of-frame coordination awkward
- UI callbacks are the wrong abstraction for non-UI pack orchestration

What would remove it:

- a ROM-side per-frame logic callback
- or a dedicated post-hot-reload drain callback
