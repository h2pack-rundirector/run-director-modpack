# Run Director Modpack

Shell repo for the Run Director modpack. Contains the coordinator, shared Lib/Framework submodules, setup helpers, and the game-module submodules for this pack.

## Structure

```text
run-director-modpack/
|- adamant-ModpackRunDirectorCore/  # Coordinator: pack identity, config, profiles
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

The shared architecture and authoring contract live in the upstream repos:

- [ModpackFramework COORDINATOR_GUIDE.md](https://github.com/h2-modpack/ModpackFramework/blob/main/COORDINATOR_GUIDE.md)
- [ModpackFramework HASH_PROFILE_ABI.md](https://github.com/h2-modpack/ModpackFramework/blob/main/HASH_PROFILE_ABI.md)
- [ModpackLib MODULE_AUTHORING.md](https://github.com/h2-modpack/ModpackLib/blob/main/MODULE_AUTHORING.md)
- [ModpackLib API.md](https://github.com/h2-modpack/ModpackLib/blob/main/API.md)
- [ModpackLib FIELD_TYPES.md](https://github.com/h2-modpack/ModpackLib/blob/main/FIELD_TYPES.md)

This shell repo should only document pack-specific structure and composition.

## Releasing

Use the **Release All** workflow in GitHub Actions to publish a new version across the shell and submodules.
