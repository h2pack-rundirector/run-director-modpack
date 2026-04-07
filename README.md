# Run Director Modpack

Shell repo for the Run Director modpack. Contains the coordinator, shared Lib/Framework submodules, setup helpers, and the game-module submodules for this pack.

## Structure

```text
run-director-modpack/
|- adamant-RunDirector_Core/        # Coordinator: pack identity, config, profiles
|- adamant-ModpackFramework/        # Shared UI, discovery, hash, HUD
|- adamant-ModpackLib/              # Shared utilities and module runtime
|- Setup/                           # Scaffold and deploy helpers
|- Submodules/                      # Game modules (one repo each)
'- Support/                         # Internal notes for this shell repo
```

## Setup

```bash
git clone --recurse-submodules https://github.com/h2pack-rundirector/run-director-modpack.git
python Setup/deploy/deploy_all.py
```

## Shared Docs

Use the stable repo-root entrypoints for shared docs:

- [ModpackFramework README.md](https://github.com/h2-modpack/adamant-ModpackFramework/blob/main/README.md)
- [ModpackLib README.md](https://github.com/h2-modpack/adamant-ModpackLib/blob/main/README.md)

This shell repo should only document pack-specific structure and composition.

## Releasing

Use the **Release All** workflow in GitHub Actions to publish a new version across the shell and submodules.
