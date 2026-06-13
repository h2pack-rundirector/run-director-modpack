local manifestPath = arg and arg[1] or "tests/smoke_manifest.lua"
local manifest = dofile(manifestPath)

local LUA_RUNNER = os.getenv("LUA") or "lua"
local PYTHON_RUNNER = os.getenv("PYTHON") or "python3"

local commands = {}

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function fileExists(path)
    local file = io.open(path, "r")
    if file == nil then
        return false
    end
    file:close()
    return true
end

local function repoRootFromSrcDir(srcDir)
    return srcDir:gsub("/src$", "")
end

local function baseName(path)
    return path:gsub("/$", ""):match("([^/]+)$") or path
end

local function addCommand(name, cwd, command)
    commands[#commands + 1] = {
        name = name,
        cwd = cwd,
        command = command,
    }
end

local function addRepoTestIfPresent(name, repoDir)
    local luaTestPath = "tests/all.lua"
    if fileExists(repoDir .. "/" .. luaTestPath) then
        addCommand(name, repoDir, { LUA_RUNNER, luaTestPath })
        return
    end

    local pythonTestPath = "tests/all.py"
    if fileExists(repoDir .. "/" .. pythonTestPath) then
        addCommand(name, repoDir, { PYTHON_RUNNER, pythonTestPath })
    end
end

local function commandToString(command)
    local parts = {}
    for index, part in ipairs(command) do
        parts[index] = shellQuote(part)
    end
    return table.concat(parts, " ")
end

local function runCommand(record)
    print("")
    print("=== " .. record.name .. " ===")
    local command = "cd " .. shellQuote(record.cwd) .. " && " .. commandToString(record.command)
    local ok, reason, status = os.execute(command)
    if ok == true or ok == 0 then
        return true
    end
    if type(status) == "number" then
        print(string.format("%s failed: %s %d", record.name, tostring(reason), status))
    else
        print(string.format("%s failed", record.name))
    end
    return false
end

addCommand("Shell smoke", ".", { LUA_RUNNER, "tests/smoke.lua", manifestPath })

local libRepoDir = repoRootFromSrcDir(manifest.libSrcDir)
addRepoTestIfPresent(baseName(libRepoDir), libRepoDir)

if type(manifest.modules) == "table" then
    for _, module in ipairs(manifest.modules) do
        addRepoTestIfPresent(module.pluginGuid, repoRootFromSrcDir(module.moduleSrcDir))
    end
end

if type(manifest.coordinator) == "table" then
    addRepoTestIfPresent(manifest.coordinator.pluginGuid, repoRootFromSrcDir(manifest.coordinator.srcDir))
end

addRepoTestIfPresent("ModpackTools", "ModpackTools")

local failures = {}
for _, command in ipairs(commands) do
    if not runCommand(command) then
        failures[#failures + 1] = command.name
    end
end

print("")
print("=== Summary ===")
if #failures > 0 then
    print(string.format("%d failed: %s", #failures, table.concat(failures, ", ")))
    os.exit(1)
end

print(string.format("%d passed.", #commands))
