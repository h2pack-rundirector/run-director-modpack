# Run Director Modpack

Shell repo for the Run Director modpack. Contains the coordinator, shared Lib/Framework submodules, pack maintenance tools, and the game-module submodules for this pack.

## Structure

```text
run-director-modpack/
|- adamantRunDirector-RunDirector_Modpack/ # Coordinator: pack identity, config, profiles
|- adamant-ModpackFramework/               # Shared UI, discovery, hash, HUD
|- adamant-ModpackLib/                     # Shared utilities
|- ModpackTools/                           # Pack maintenance scripts
'- Submodules/                             # Game modules (one repo each)
```

## Local Development

```bash
git clone --recurse-submodules https://github.com/h2pack-rundirector/run-director-modpack.git
python ModpackTools/local_deploy/deploy_all.py
```

For the full new-pack workflow, use
[ModpackBootstrap Getting Started](https://github.com/h2-modpack/ModpackBootstrap/blob/main/docs/GETTING_STARTED.md).

## Releasing

Use the **Release All** workflow (`Actions -> Release All`) to publish a new version across all modules.

## Shared Docs

Use the stable repo-root entrypoints for shared docs:

- [ModpackFramework README.md](https://github.com/h2-modpack/adamant-ModpackFramework/blob/main/README.md)
- [ModpackLib README.md](https://github.com/h2-modpack/adamant-ModpackLib/blob/main/README.md)
- [Hot Reload Architecture](https://github.com/h2-modpack/adamant-ModpackLib/blob/main/docs/lib-contributors/HOT_RELOAD_ARCHITECTURE.md)
- [Known Limitations](https://github.com/h2-modpack/adamant-ModpackLib/blob/main/docs/references/KNOWN_LIMITATIONS.md)

This shell repo should only document pack-specific structure and composition.
