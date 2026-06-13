local manifestPath = arg and arg[1] or "tests/smoke_manifest.lua"
local manifest = dofile(manifestPath)
local smokeRunner = dofile(manifest.smokeRunnerPath or "adamant-ModpackLib/tests/harness/smoke_runner.lua")

smokeRunner.assertManifest(manifest)

local coordinatorCount = manifest.coordinator and 1 or 0
local moduleCount = type(manifest.modules) == "table" and #manifest.modules or 0
print(string.format(
    "Smoke manifest passed: %d module entrypoints, %d coordinator pipeline.",
    moduleCount,
    coordinatorCount
))
