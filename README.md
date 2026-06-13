# Run Director Modpack

Shell repo for the Run Director modpack. Contains the coordinator, shared Lib/runtime tooling submodules, and the game-module submodules for this pack.

## Structure

```text
run-director-modpack/
|- adamantRunDirector-RunDirector_Modpack/ # Coordinator: pack identity, config, profiles
|- adamant-ModpackLib/                     # Shared module and modpack runtime
|- ModpackTools/                           # Pack maintenance scripts
'- Submodules/                             # Game modules (one repo each)
```

## Local Development

```bash
git clone --recurse-submodules https://github.com/h2pack-rundirector/run-director-modpack.git
lua tests/smoke.lua
lua tests/test_all.lua
ModpackTools/run ModpackTools/local_test/all.py
ModpackTools/run ModpackTools/local_deploy/deploy_all.py
```

Commit CI only runs the shell smoke script. Local deploy runs that same smoke preflight before writing to the live profile. Release All checks platform dependency edges and verifies selected child repos have successful CI for the exact release branch commits before dispatching child releases.

When adding or removing module submodules, use the registration tool so
`.gitmodules` and coordinator dependencies stay aligned. Smoke derives its
module roster from `.gitmodules`.

```bash
ModpackTools/run ModpackTools/new_module/register_submodules.py
ModpackTools/run ModpackTools/new_module/register_submodules.py --prune
```

On Windows Command Prompt or PowerShell, use `ModpackTools\run.bat` instead of
`ModpackTools/run`. The launcher picks an available Python 3 command
(`python3`, `python`, or `py -3`).

For the full new-pack workflow, use
[ModpackBootstrap Getting Started](https://github.com/h2-modpack/ModpackBootstrap/blob/main/docs/GETTING_STARTED.md).

## Releasing

Use the **Release All** workflow (`Actions -> Release All`) to publish a new version across all modules.
The release workflow validates platform dependency edges, checks selected child release refs against their branch heads, and requires successful child CI before dispatching release workflows.

## Shared Docs

Use the stable repo-root entrypoints for shared docs:

- [ModpackLib README.md](https://github.com/h2-modpack/adamant-ModpackLib/blob/main/README.md)
- [Modpack Coordinator Guide](https://github.com/h2-modpack/adamant-ModpackLib/blob/main/docs/modpack-authors/COORDINATOR_GUIDE.md)
- [Module Authoring Guide](https://github.com/h2-modpack/adamant-ModpackLib/blob/main/docs/module-authors/MODULE_AUTHORING.md)
- [Hot Reload Architecture](https://github.com/h2-modpack/adamant-ModpackLib/blob/main/docs/lib-contributors/HOT_RELOAD_ARCHITECTURE.md)
- [Known Limitations](https://github.com/h2-modpack/adamant-ModpackLib/blob/main/docs/references/KNOWN_LIMITATIONS.md)

This shell repo should only document pack-specific structure and composition.
