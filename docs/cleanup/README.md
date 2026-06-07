# Cleanup Tracking

This folder is the canonical working area for post-migration cleanup across the
run-director modpack workspace. It is not module-author documentation and should
not be treated as an API contract.

Use this root folder even when the audit target is a submodule. Keeping the
audit notes here avoids splitting cleanup history between the shell repo, Lib,
Framework, and module repos.

## Process

1. Save audit notes under `audits/`.
2. Classify findings before editing.
3. Work in narrow passes with one cleanup theme per patch.
4. Check production callers before deleting or collapsing helpers.
5. Keep tests as behavior coverage, not as the only reason an obsolete surface exists.
6. Update or delete stale docs in the same pass that changes the public shape.

Use [SUBSYSTEM_AUDIT_STRATEGY.md](SUBSYSTEM_AUDIT_STRATEGY.md) for the audit
rubric and finding template.

## Finding Labels

- `keep`: current name or shape is intentional.
- `rename`: concept is still valid, but the vocabulary is stale.
- `delete`: concept is obsolete and has no production caller.
- `collapse`: helper/file exists only as a redirection layer.
- `move`: useful code lives in the wrong subsystem.
- `document`: behavior is intentional but needs a doc anchor.
- `test-only`: code only exists for tests and should be replaced with behavioral coverage or removed.

## Initial Cleanup Checklist

- [x] `runtimeOwned` naming residue now that public API is `status`.
- [x] `host` versus `module` vocabulary residue in diagnostics, docs, and internal APIs.
  Audit: [2026-06-06-host-module.md](audits/2026-06-06-host-module.md).
- [x] old `service` terminology that is either real Lib internals or leftover author-facing wording.
  Audit: [2026-06-07-service.md](audits/2026-06-07-service.md).
- [x] stale `integration`, `poll`, and `provider` references.
  Audit: [2026-06-07-integration-poll-provider.md](audits/2026-06-07-integration-poll-provider.md).
- [x] `compat`, `legacy`, `deprecated`, `shim`, and `migration` references.
  Audit: [2026-06-07-migration-residue.md](audits/2026-06-07-migration-residue.md).
- [x] broad context objects or adapter layers that survived the native API migration.
  Audit: [2026-06-07-context-adapters.md](audits/2026-06-07-context-adapters.md).
- [x] one-line helpers that only hide direct calls without adding policy.
  Audit: [2026-06-07-one-line-helpers.md](audits/2026-06-07-one-line-helpers.md).
- [x] docs that describe historical migration plans instead of current behavior.
  Audit: [2026-06-07-historical-docs.md](audits/2026-06-07-historical-docs.md).
- [x] implementation-side LuaCAT annotations that duplicated the canonical public definition file.
  Audit: [2026-06-07-luacat-surface.md](audits/2026-06-07-luacat-surface.md).

## Subsystem Audit Progress

Work from low-dependency primitives toward higher-level composition. When a
subsystem was audited before this table existed, keep the row marked complete
and add a dedicated audit note only if a future pass finds new issues.

| Order | Subsystem | Status | Notes |
| --- | --- | --- | --- |
| 1 | Lib bootstrap primitives: logging, registry, module registry, system scope, game deps, values | Done | Policy naming and duplicated diagnostics were cleaned. Audit: [2026-06-06-lib-bootstrap-primitives.md](audits/2026-06-06-lib-bootstrap-primitives.md). |
| 2 | Lib storage core and hash serialization | Done | Removed obsolete hash-packing direction, tightened profile decode behavior, and kept hash compression as a future optional direction. Audits: [storage core](audits/2026-06-06-lib-storage-core.md), [storage and hashing](audits/2026-06-06-lib-storage-and-hashing.md). |
| 3 | Lib module-state backend and storage frontends | Done | Backend adapters, persistent/staged state, and standard `ui.data`/`runtime.data` surfaces were reviewed together. Audits: [overview](audits/2026-06-06-lib-module-state-status-actions.md), [backends and refs](audits/2026-06-06-lib-state-backends-and-refs.md), [data front end](audits/2026-06-06-lib-data-front-end.md). |
| 4 | Lib status lane | Done | Public API is `module.status`, `runtime.status`, and `ui.status`; old runtime-owned vocabulary is internal only where it names backend implementation. Audit: [2026-06-06-lib-status-lane.md](audits/2026-06-06-lib-status-lane.md). |
| 5 | Lib actions, reset, and draw commit lifecycle | Done | Commit ordering is centralized and documented; reset is exposed as one UI/module operation rather than lane-specific public reset helpers. Audit: [2026-06-06-lib-actions-reset-commit-lifecycle.md](audits/2026-06-06-lib-actions-reset-commit-lifecycle.md). |
| 6 | Lib cache and shared data/events | Done | Shared emit is variant-typed through `runtime.shared` and `ui.shared`; shared publication writes are documented as immediate publication writes. Audit: [2026-06-06-lib-cache-and-shared.md](audits/2026-06-06-lib-cache-and-shared.md). |
| 7 | Lib controls | Done | Controls compile config storage only; status/actions remain module-level coordination lanes. Audit: [2026-06-07-lib-controls.md](audits/2026-06-07-lib-controls.md). |
| 8 | Lib widgets | Done | Hot draw-path helpers, option validation, and docs/API alignment were audited. Audit: [2026-06-07-widgets.md](audits/2026-06-07-widgets.md). |
| 9 | Lib hooks | Done | Declaration/install boundaries, context wrapping, and ModUtil registry interactions were audited. Audit: [2026-06-07-hooks.md](audits/2026-06-07-hooks.md). |
| 10 | Lib overlays | Done | Retained overlay lifecycle, suppression, renderer boundaries, and docs were audited. Module overlay callbacks now receive the full managed runtime context. Audit: [2026-06-07-overlays.md](audits/2026-06-07-overlays.md). |
| 11 | Lib mutations | Done | Plan generation, lifecycle sync, and framework/module integration points were audited. Audit: [2026-06-07-mutations.md](audits/2026-06-07-mutations.md). |
| 12 | Lib fallback UI and framework runtime | Done | Framework/runtime docs were aligned with `ui.status`; fallback UI now balances ImGui `Begin`/`End` on module draw errors. Audit: [2026-06-07-fallback-framework-runtime.md](audits/2026-06-07-fallback-framework-runtime.md). |
| 13 | Lib module bootstrap and activation | Done | Declaration, finalization, live-module construction, activation rollback, and lifecycle commit were audited. Audit: [2026-06-07-module-bootstrap.md](audits/2026-06-07-module-bootstrap.md). |
| 14 | Framework | Done | Runtime/profile coordination and UI/HUD surfaces were reviewed with only stale docs needing cleanup. Audit: [2026-06-07-framework.md](audits/2026-06-07-framework.md). |
| 15 | Module repos | Pending | Start after infrastructure pass; audit data, logic, UI, then main composition. |

## Production Caller Rule

Before removing a helper or file:

1. Search production code first: `src`, then module consumers if relevant.
2. Search tests second.
3. If only tests call it, decide whether the test should move to a public behavior.
4. If production calls it, classify whether it is a real boundary or an accidental redirection.

## Suggested Audit Commands

Run from the relevant repo root. For Lib-specific scans, use
`adamant-ModpackLib` as the working directory.

```powershell
rg -n "runtimeOwned|store\.runtimeOwned|stagedState\.runtimeOwned|RuntimeOwned" src tests docs API.md
rg -n "\bservices?\b|\bintegration\b|\bintegrations\b|\bpoll\b|\bprovider\b|\bproviders\b" src tests docs API.md
rg -n "\bcompat\b|\blegacy\b|\bdeprecated\b|\bshim\b|\bmigration\b|\bold\b" src tests docs API.md
rg -n "\bhost\b|Host|host\." src
rg -n "\bhost\b|Host|host\." docs API.md
rg -n "\bhost\b|Host|host\." tests
rg -n "moduleHost|hostLifecycle|applyForHost|syncForHost|revertForHost|emitForHost|installForHost|getOwnerId|HostGui" src tests docs API.md
```

Save large outputs as separate audit files instead of trying to clean them from
terminal scrollback.
