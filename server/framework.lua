-- Framework bridge — qbox / qbcore / esx behind one tiny server-side API.
-- Config.Framework picks one explicitly, or 'auto' detects in order:
-- qbox → qbcore → esx. Resolution is lazy (first use), so start order
-- relative to the framework resource never matters.
--
--   FW.name          → 'qbox' | 'qbcore' | 'esx' (nil until resolved)
--   FW.CitizenId(src) → stable character id (citizenid / ESX identifier)
--   FW.JobInfo(src)   → jobName|nil, gradeLevel (number)
--   FW.CharName(src)  → "First Last" or '?'
FW = { name = nil }

local impl

local BUILDERS = {
    qbox = function()
        return {
            player = function(src) return exports.qbx_core:GetPlayer(src) end,
            cid    = function(p) return p.PlayerData.citizenid end,
            job    = function(p)
                local j = p.PlayerData.job
                return j and j.name or nil, (j and j.grade and j.grade.level) or 0
            end,
            name   = function(p)
                local ci = p.PlayerData.charinfo
                return ci and ('%s %s'):format(ci.firstname, ci.lastname) or nil
            end,
        }
    end,
    qbcore = function()
        local QBCore = exports['qb-core']:GetCoreObject()
        return {
            player = function(src) return QBCore.Functions.GetPlayer(src) end,
            cid    = function(p) return p.PlayerData.citizenid end,
            job    = function(p)
                local j = p.PlayerData.job
                return j and j.name or nil, (j and j.grade and j.grade.level) or 0
            end,
            name   = function(p)
                local ci = p.PlayerData.charinfo
                return ci and ('%s %s'):format(ci.firstname, ci.lastname) or nil
            end,
        }
    end,
    esx = function()
        local ESX = exports.es_extended:getSharedObject()
        return {
            player = function(src) return ESX.GetPlayerFromId(src) end,
            cid    = function(p) return p.identifier end,
            job    = function(p)
                local j = p.job
                return j and j.name or nil, (j and j.grade) or 0
            end,
            name   = function(p) return p.getName and p.getName() or nil end,
        }
    end,
}

local RESOURCES = { qbox = 'qbx_core', qbcore = 'qb-core', esx = 'es_extended' }
local AUTO_ORDER = { 'qbox', 'qbcore', 'esx' }

local function detect()
    local want = tostring(Config.Framework or 'auto'):lower()
    if BUILDERS[want] then return want end
    if want ~= 'auto' then
        print(('^1[noted_crimeapp]^0 Unknown Config.Framework %q — falling back to auto-detect'):format(want))
    end
    for _, name in ipairs(AUTO_ORDER) do
        if GetResourceState(RESOURCES[name]) == 'started' then return name end
    end
    return nil
end

local warned = false
local function ensure()
    if impl then return impl end
    local name = detect()
    if not name then
        if not warned then
            warned = true
            print('^1[noted_crimeapp]^0 No framework found (qbx_core / qb-core / es_extended) — set Config.Framework or start one.')
        end
        return nil
    end
    local ok, built = pcall(BUILDERS[name])
    if not ok or not built then
        if not warned then
            warned = true
            print(('^1[noted_crimeapp]^0 Could not initialize framework %q: %s'):format(name, tostring(built)))
        end
        return nil
    end
    impl = built
    FW.name = name
    print(('^2[noted_crimeapp]^0 framework: %s'):format(name))
    return impl
end

local function playerOf(src)
    local i = ensure()
    if not i then return nil, nil end
    local ok, p = pcall(i.player, src)
    if not ok or not p then return nil, i end
    return p, i
end

function FW.CitizenId(src)
    local p, i = playerOf(src)
    if not p then return nil end
    local ok, cid = pcall(i.cid, p)
    return ok and cid or nil
end

function FW.JobInfo(src)
    local p, i = playerOf(src)
    if not p then return nil, 0 end
    local ok, jobName, grade = pcall(i.job, p)
    if not ok then return nil, 0 end
    return jobName, grade or 0
end

function FW.CharName(src)
    local p, i = playerOf(src)
    if not p then return '?' end
    local ok, n = pcall(i.name, p)
    return (ok and n) or '?'
end
