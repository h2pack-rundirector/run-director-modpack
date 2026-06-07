# Lib Storage Core Audit

## Purpose

Storage core validates storage descriptors, prepares root/alias metadata, normalizes typed values, exposes table and packed-field helpers, and provides alias read/write primitives for state backends.

## Surfaces

- Author: no direct public surface; authors reach this through `module.data.define(...)`, `module.status.define(...)`, controls, widgets, and `ui.data` / `runtime.data` / status refs.
- Framework/module: prepared storage schemas consumed by definition preparation, persistent state, staged state, hashing, controls, and status adapters.
- Internal: `storage.validate`, root/alias getters, value normalization/equality, `storage.field`, `storage.table`, `storage.packed`, and `storage.readAlias` / `storage.writeAlias`.
- Tests-only: harness access to packed alias helpers and direct storage validation/state tests.

## Call Graph

- Callers:
  - definition preparation validates merged data/status/control storage.
  - persistent and staged module state use root and alias metadata to read, write, reset, and flush values.
  - status adapters reuse storage-backed runtime-mode nodes.
  - controls compile private aliases and then rely on storage validation with trusted internal nodes.
  - widgets consume field/table refs built on top of storage handles.
  - hashing delegates `toHash`, `fromHash`, and token validation to storage types.
- Dependencies:
  - storage core depends only on logging, values, packed helpers, and table helpers.
  - it does not depend on module bootstrap, Framework, phase orchestration, actions, controls, or widgets.
- Direction notes:
  - Dependency direction is clean. Storage core is a low-level service and does not know about author lifecycle phases.

## State Ownership

- Owns:
  - prepared descriptor metadata: roots, persisted roots, staged roots, aliases, packed child aliases, table row metadata.
  - typed normalization and hash serialization rules.
- Reads:
  - descriptor declarations passed to `storage.validate`.
  - backend root values through alias/table handles.
- Writes:
  - schema metadata in place during validation.
  - values only through backend callbacks supplied by persistent/staged/status owners.

## Lifecycle

- Declaration:
  - validates descriptor shape, aliases, axes, defaults, table rows, packed bits, and private/internal alias policy.
- Activation:
  - prepared schemas are treated as stable metadata by module state.
- UI draw:
  - core storage is phase-free; UI phase rules are enforced by `storage_ref_adapter` and state facades.
- Commit:
  - persistent/staged owners decide when writes flush. Storage core only normalizes and compares values.
- Runtime:
  - status/runtime-mode nodes use the same storage metadata with a different owner adapter.
- Reload:
  - schemas are rebuilt from declarations and validated again.
- Teardown:
  - storage core owns no live teardown state.

## Findings

### Hash Packing Metadata Was Prepared But Unused

- Rating: safe cleanup, completed
- Evidence:
  - Before cleanup, `adamant-ModpackLib/src/core/storage/schema.lua` prepared `_hashPackable` and `_packWidth`.
  - Before cleanup, `adamant-ModpackLib/src/core/storage/types.lua` exposed `packWidth` functions for `bool`, bounded `int`, and `packedInt`.
  - `adamant-ModpackLib/src/core/hashing/hashing.lua` only delegates `toHash`, `fromHash`, and token validation; no current hashing path consumed `_hashPackable`, `_packWidth`, or `packWidth`.
- Impact:
  - This was not a runtime bug. It was residue from the abandoned automatic hash-packing direction.
  - Leaving it in place would have kept storage descriptors carrying metadata with no current owner, which could mislead future readers into thinking greedy packing exists.
- Recommendation:
  - Completed: remove `_hashPackable`, `_packWidth`, `packWidth`, standalone `int.width`, and future-doc references to semantic packing as a live direction. Keep explicit `packedInt` behavior.

### Status Still Uses Runtime Mode As Internal Storage Axis

- Rating: leave alone for this pass
- Evidence:
  - `adamant-ModpackLib/src/core/status/declarations.lua` compiles `module.status.define(...)` declarations into storage nodes with `mode = "runtime"` and `hash = false`.
  - `adamant-ModpackLib/src/core/storage/schema.lua` still validates the internal storage axis as `"setting"` or `"runtime"`.
  - `storage.hash_requires_setting` has a modern policy description, but the concrete violation string still says `mode='runtime' requires hash=false`.
- Impact:
  - This is not author-facing in normal use because status declarations forbid `mode` and data declarations treat unknown modes as storage validation errors.
  - Internally, the name still reflects the old runtime-owned implementation rather than the public `status` concept.
- Recommendation:
  - Keep it during the storage-core audit. Revisit in the module-state/status audit, where the tradeoff is clearer: either keep `runtime` as the backend axis name or rename internals and diagnostics around status.

### Private Alias Boundary Is Coherent

- Rating: leave alone
- Evidence:
  - `adamant-ModpackLib/src/core/storage/schema.lua` accepts `_Control:Field` style aliases only for trusted internal nodes.
  - `adamant-ModpackLib/src/core/controls/compiler.lua` generates private aliases for controls and rejects status-mode storage in controls.
  - `adamant-ModpackLib/src/core/module_state/storage_ref_adapter.lua` rejects private aliases on public field/table APIs.
  - `adamant-ModpackLib/tests/TestControls.lua` covers semantic schemas for controls and rejects generated internal aliases through public control fields/table rows.
  - `adamant-ModpackLib/tests/TestStorageValidation.lua` covers public rejection of private aliases.
- Impact:
  - Controls can own hidden storage without forcing generated alias names into UI/runtime code.
  - Public `ui.data`, `runtime.data`, and status refs remain stable-alias surfaces.
- Recommendation:
  - Keep the current split: storage core permits trusted internal aliases; public adapters reject private aliases.

### Table Storage Has The Right Runtime/Hash Split

- Rating: leave alone
- Evidence:
  - `adamant-ModpackLib/src/core/storage/table.lua` keeps table values live and flexible through row handles, append/insert/remove/clear, snapshots, and cell writes.
  - The same file serializes/deserializes tables only for hash/profile tokens with length-prefixed row cells.
  - Persistent-state tests verify snapshots are copies and table roots cannot be replaced wholesale through status writes.
- Impact:
  - This preserves the important design split: tables stay operationally table-shaped at runtime, while hashing gets a deterministic flattened representation.
- Recommendation:
  - Keep this shape. Any future hash compression should layer on the serialized snapshot path, not flatten table storage during normal runtime.

### Storage Core Is Correctly Phase-Free

- Rating: leave alone
- Evidence:
  - `adamant-ModpackLib/src/core/storage/00_init.lua` wires storage without phase-gate, module, Framework, controls, or widget dependencies.
  - Phase checks live above storage in state/ref adapters.
- Impact:
  - This matches the current architecture: phase rules belong to UI/runtime/status surfaces, not typed storage normalization.
- Recommendation:
  - Keep storage core phase-free. Do not move phase or lifecycle checks into storage core.

## Deferred Questions

- Should the internal storage axis name `mode = "runtime"` eventually become status terminology, or is it acceptable as a backend-only implementation name?
