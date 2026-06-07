# Lib Status Lane Audit

## Purpose

Status is the runtime-authored, UI-readable data lane. It lets runtime callbacks publish small pieces of state for UI draw code without making normal config storage runtime-writable.

## Surfaces

- Author:
  - `module.status.define(...)`
  - `runtime.status.get/read/write/reset`
  - `ui.status.get/read`
- Framework/module:
  - status declarations are compiled during activation and merged into the prepared module definition as internal runtime-mode storage roots.
  - managed module reset uses `persistentState.status.countResettable(...)` and `persistentState.status.resetAll(...)`.
- Internal:
  - `src/core/status/declarations.lua`
  - `src/core/status/adapters/runtime_status.lua`
  - `src/core/status/adapters/ui_status.lua`
  - status sections inside persistent and staged module-state backends.
- Tests-only:
  - direct `persistentState.status` and `stagedState.status` tests.
  - module/action tests that write status through runtime callbacks.

## Call Graph

- `module.status.define(...)` stores declaration data in the declaration facade.
- `activation_finalizer.lua` calls `statusDeclarations.compileStorage(...)`, then merges the result with data storage before definition preparation.
- storage schema validation owns alias uniqueness, nested table-row validation, packed-bit validation, and private alias policy.
- `module_state/00_init.lua` creates public runtime/UI status adapters from persistent/staged state.
- runtime status writes through persistent state; UI status reads through staged state's committed-root adapter.

## State Ownership

- Owns:
  - status declaration lowering from a keyed map into storage roots.
  - public status adapter diagnostics and write/read/reset shape.
- Reads:
  - prepared storage alias metadata from persistent/staged state.
  - committed status values through persistent/staged state.
- Writes:
  - runtime status writes/resets through persistent state only.
  - UI status is read-only.

## Lifecycle

- Declaration:
  - status declarations must be a map keyed by stable status alias.
  - each root declaration must explicitly set `persist`.
  - root `alias`, `hash`, and `mode` are forbidden because the lane owns them.
- Activation:
  - status declarations compile to roots with `alias = key`, `mode = "runtime"`, and `hash = false`.
  - merged storage validation catches alias collisions with data/control storage.
- UI draw:
  - `ui.status` reads status values and cannot write.
- Commit:
  - status has no commit staging of its own.
  - `ui.resetAll` queues status reset through the internal reset/action path, handled in lifecycle code.
- Runtime:
  - `runtime.status` reads, writes, and resets status values.
- Reload:
  - persisted status roots hydrate through persistent state.
  - non-persisted status roots reset with state creation/reload like other non-persisted roots.
- Teardown:
  - status owns no lifecycle receipts.

## Findings

### Status Declaration Lowering Is Small And Correctly Narrow

- Rating: leave alone
- Evidence:
  - `src/core/status/declarations.lua` compiles only three lane-owned fields: `alias`, `mode`, and `hash`.
  - the compiler requires explicit `persist`, which forces authors to choose whether status survives game restarts.
  - storage schema validation owns the rest of the descriptor contract after lowering.
- Impact:
  - The public model is clean: authors declare status as named values, not as hand-authored runtime-mode storage roots.
  - The implementation stays small because it reuses normal storage validation and normalization.
- Recommendation:
  - Keep this shape.
  - Do not add a separate status schema language unless status grows behavior that storage descriptors cannot express.

### Nested Status Descriptors Inherit The Root Lane

- Rating: leave alone
- Evidence:
  - table row validation rejects row-level `persist`, `hash`, and `mode` before recursively validating row schemas.
  - packed bits only allow packed-bit fields; `persist`, `hash`, and `mode` are unknown packed-bit fields.
  - the compiled status root has `mode = "runtime"` and `hash = false`, so nested table cells and packed children inherit the root lane.
- Impact:
  - Status does not need its own recursive rejection pass for nested `mode/hash`.
  - Nested `alias` remains valid where storage needs it, such as table row fields and packed bits.
- Recommendation:
  - Leave nested validation in storage core.
  - Keep status declaration validation focused on the root map contract.

### Status Adapters Are Thin But Useful Domain Boundaries

- Rating: leave alone
- Evidence:
  - `runtime_status.lua` and `ui_status.lua` mostly delegate to storage refs, but they provide status-specific unknown-alias and wrong-surface diagnostics.
  - they also keep status out of `runtime.data` and `ui.data`, which preserves the data/status lane distinction.
- Impact:
  - Removing these adapters would push status diagnostics into generic storage refs or state backends.
  - The wrappers earn their small surface by naming the lane.
- Recommendation:
  - Keep the adapters.
  - Avoid adding behavior here unless it is specific to public status semantics.

### Declaration Validation Tests Were Thin

- Rating: safe cleanup, completed
- Evidence:
  - Behavior tests cover runtime status write/read/reset, UI read-only access, table status, packed status, reset lifecycle, and actions writing status.
  - Direct tests for `status.invalid_alias`, `status.invalid_declaration_set`, `status.invalid_declaration`, `status.invalid_field`, `status.missing_persist`, and `status.invalid_persist` are not currently visible in the focused test search.
- Impact:
  - The lane works in behavior tests, but declaration-policy regressions would be caught indirectly or through broad activation failures.
  - These are cheap unit cases and would document the intended public contract.
- Recommendation:
  - Completed: focused declaration validation tests now exercise `module.status.define(...)` through activation rather than exposing the declaration compiler directly.

### Live Runtime-Owned Naming Residue Is Gone

- Rating: leave alone
- Evidence:
  - Targeted search found no live `runtimeOwned` public/API/source hits outside cleanup-history files.
  - persistent and staged backend diagnostics now say `status`.
- Impact:
  - The current code and public docs match the status terminology.
  - Remaining historical notes in cleanup audits are useful as audit trail, not live API residue.
- Recommendation:
  - Leave cleanup-history files alone.
  - Continue to avoid `runtimeOwned` wording in new source, API docs, and author docs.

## Deferred Questions

- Should the internal storage axis name `mode = "runtime"` eventually be renamed, or is it acceptable as a backend-only implementation detail?
- Should status reset lifecycle be documented again during the actions/reset/commit audit instead of expanding the status doc now?
