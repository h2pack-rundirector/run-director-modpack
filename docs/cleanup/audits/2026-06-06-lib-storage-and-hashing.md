# Lib Storage And Hashing Audit

## Purpose

Storage owns typed value semantics and prepared hash roots; Lib hashing exposes the minimal Framework-facing adapter over those storage primitives; Framework builds canonical profile strings around that adapter.

## Surfaces

- Author:
  - `module.data.define(...)` declares persisted, transient, and hash participation axes.
  - `module.status.define(...)` declares runtime-authored status values that compile to non-hash storage.
  - controls compile to private storage and inherit storage hash behavior.
- Framework/module:
  - `frameworkRuntime.hashing` exposes storage metadata and value codecs to Framework.
  - Framework `config_hash` uses this to generate/apply profile hashes.
  - Framework profile audit uses hash roots to detect stale keys in saved profiles.
- Internal:
  - storage validation, type codecs, table serialization, packedInt helpers, field/table handles, and alias access.
  - Framework hash codec for canonical key/value escaping.
- Tests-only:
  - direct Lib storage/hash tests.
  - Framework config hash and saved-profile audit tests.

## Call Graph

- Callers:
  - Lib definition preparation validates data/status/control storage.
  - Lib module state reads/writes prepared storage roots and aliases.
  - Lib hashing wraps storage `getRoots`, `valuesEqual`, `toHash`, `fromHash`, and token validation.
  - Framework `config_hash.lua` consumes hashing roots/codecs to serialize config and apply imported hashes.
  - Framework `profiles/audit.lua` uses hashing roots to warn about stale profile keys.
- Dependencies:
  - storage depends on logging, values, table storage, and packed storage helpers.
  - Lib hashing depends only on storage.
  - Framework hash depends on Lib hashing, module registry snapshots, config, logging, `rom` deep copy, and hash codec.
- Direction notes:
  - Direction is clean: storage has no Framework knowledge; Framework does not import full storage internals.
  - The Lib hashing adapter is intentionally thin after removing semantic hash-packing metadata.

## State Ownership

- Storage owns:
  - root/alias metadata.
  - type normalization.
  - value equality.
  - type-level hash tokens.
  - deterministic table snapshot serialization.
- Lib hashing owns:
  - no state; it is a Framework-facing projection.
- Framework hash owns:
  - canonical string construction.
  - hash versioning.
  - key/value escaping.
  - fingerprinting.
  - apply rollback orchestration.

## Lifecycle

- Declaration:
  - storage validates hash/persist/mode axes and prepares hash roots.
- Activation:
  - Framework discovers prepared module storage from the module registry.
- UI draw:
  - no direct storage/hash lifecycle. UI writes staged values.
- Commit:
  - Framework hash reads committed/persisted snapshots when generating hashes.
- Profile apply:
  - Framework decodes storage values, stages roots, flushes modules, reloads state, then toggles module enabled state.
  - On failure, Framework stages captured values back, flushes, then restores enabled state.
- Runtime:
  - status roots are excluded from hashes.
- Reload:
  - storage shape changes are represented by rebuilt prepared storage and Framework profile audit warnings.

## Findings

### Lib Hashing Is A Thin But Useful Boundary

- Rating: leave alone
- Evidence:
  - `adamant-ModpackLib/src/core/hashing/hashing.lua` only delegates to storage primitives.
  - `adamant-ModpackFramework/src/core/hash/config_hash.lua` uses the adapter rather than importing storage.
  - `adamant-ModpackFramework/src/core/profiles/audit.lua` uses the same adapter to list hash roots.
- Impact:
  - The file looks almost redundant, but it protects the Lib/Framework boundary. Framework receives only hash/profile operations instead of the whole storage service.
- Recommendation:
  - Keep the adapter. Treat it as Framework API, not as an independent hashing engine.

### `frameworkRuntime.hashing.getAliases` Looks Like Dead Framework Surface

- Rating: safe cleanup, completed
- Evidence:
  - Before cleanup, `adamant-ModpackLib/src/core/hashing/hashing.lua` exposed `getAliases`.
  - Before cleanup, `adamant-ModpackLib/API.md` documented `frameworkRuntime.hashing.getAliases(storage)`.
  - `adamant-ModpackFramework/src/core/hash/config_hash.lua` and `adamant-ModpackFramework/src/core/profiles/audit.lua` do not use it.
- Impact:
  - This leaked more storage metadata than Framework currently needs.
  - It made the Framework hashing surface look broader than the actual profile/hash use case.
- Recommendation:
  - Completed: removed `getAliases` from `frameworkRuntime.hashing`, updated `API.md` / `def.lua`, and moved Lib tests that need aliases to `self.storage.getAliases(...)`.

### Framework-Level Table Hash Round Trip Is Under-Tested

- Rating: safe cleanup, completed
- Evidence:
  - `adamant-ModpackLib/tests/TestModuleState_StagedState.lua` covers table `toHash` / `fromHash`, including delimiter-bearing strings.
  - Before cleanup, `adamant-ModpackFramework/tests/TestConfigHash.lua` covered scalar string escaping and invalid table tokens, but not a valid table root through the full Framework canonical hash codec.
- Impact:
  - Storage table serialization and Framework key/value escaping were individually tested, but the combined boundary was not explicit.
- Recommendation:
  - Completed: added a Framework config-hash test for a table root containing a string cell with `|`, `=`, and `%`, then applying the hash and verifying the restored table.

### Stale Docs Still Mention Profile Packing

- Rating: safe cleanup, completed
- Evidence:
  - Before cleanup, `adamant-ModpackLib/docs/module-authors/capabilities/MANAGED_STATE.md` said packed widths are validated so "hashes and profile packing can trust prepared metadata."
  - Before cleanup, `adamant-ModpackLib/docs/lib-contributors/CONTROL_ERGONOMICS.md` listed "hash/profile grouping" as one of the old split concerns that controls can help collect.
- Impact:
  - The implementation no longer has semantic/profile packing after the storage cleanup. The docs needed to say packedInt width validation protects explicit packed values and ordinary storage hash serialization, not profile packing.
- Recommendation:
  - Completed: reworded the managed-state packed section and the controls ergonomics wording to remove the implication that profile packing remains an active direction.

### Hash Codec Tolerates Unknown And Malformed Input Without A Written Policy

- Rating: careful cleanup, completed
- Evidence:
  - `adamant-ModpackFramework/src/core/hash/codec.lua` silently ignores entries that do not match `key=value`.
  - `adamant-ModpackFramework/src/core/hash/config_hash.lua` applies only known module/root keys and ignores unknown hash keys.
  - `adamant-ModpackFramework/src/core/profiles/audit.lua` intentionally ignores unknown module namespaces and warns only for unknown fields under known module ids.
- Impact:
  - Ignoring unknown keys is useful for compatibility and optional modules.
  - Ignoring malformed loose segments is now an explicit best-effort profile-load policy.
- Recommendation:
  - Completed: documented the import policy and added focused tests.
  - Policy:
    - malformed loose segments are ignored;
    - unknown module namespaces are ignored;
    - unknown keys under known modules are ignored at apply time but warned by profile audit;
    - unsupported versions reject the whole hash;
    - invalid values for known keys reject the whole apply and roll back.

### Storage And Hashing Are Now Properly Semantic

- Rating: leave alone
- Evidence:
  - Hash roots come from `storage.getRoots(...)`, which includes only persisted hash-participating roots.
  - `mode = "runtime"` status roots and transient staged roots are excluded.
  - `packedInt` remains explicit storage behavior, while implicit hash-packing metadata has been removed.
  - Table storage serializes deterministic hash snapshots without flattening live table operations.
- Impact:
  - This matches the current design: canonical hashes are stable key/value maps, with optional future whole-string compression as the only preferred size optimization.
- Recommendation:
  - Keep this direction. Do not reintroduce semantic packing without a measured need and a compatibility plan.

## Deferred Questions

- After the lean-down pass is finished, consider whether `frameworkRuntime.hashing` should be renamed to a more precise storage-hash adapter name such as `storageHash` or `storageCodec`. This is minor naming polish only; avoid touching it during the current cleanup unless the surrounding code is already changing.
