print('^2[noted_crimeapp]^0 server starting')
-- Report store, callbacks, notifications, SOS added in later tasks.

Reports = {}          -- id -> report
NextReportId = 0
local lastAction = {} -- src -> { report=os.time(), comment=..., sos=... } cooldown stamps

local function getPlayer(src) return exports.qbx_core:GetPlayer(src) end
local function cidOf(src)
    local p = getPlayer(src); return p and p.PlayerData.citizenid or nil
end

-- Verified badge for a player's current job, or nil.
local function badgeFor(src)
    local p = getPlayer(src)
    if not p then return nil end
    local jobName = p.PlayerData.job and p.PlayerData.job.name
    return jobName and Config.Badges[jobName] or nil
end

function CanDelete(src, report)
    local cid = cidOf(src)
    if cid and report.author.citizenid == cid then return true end
    local p = getPlayer(src)
    if p then
        local job = p.PlayerData.job
        local minGrade = job and Config.Moderation.jobs[job.name]
        if minGrade and job.grade and (job.grade.level or 0) >= minGrade then return true end
    end
    if IsPlayerAceAllowed(src, Config.Moderation.acePermission) then return true end
    return false
end

-- Cooldown check + stamp. kind = 'report'|'comment'|'sos'. Returns true if allowed.
local function passCooldown(src, kind)
    local now = os.time()
    lastAction[src] = lastAction[src] or {}
    local last = lastAction[src][kind]
    local cd = Config.Cooldowns[kind] or 0
    if last and (now - last) < cd then return false, ('Please wait %ds.'):format(cd - (now - last)) end
    lastAction[src][kind] = now
    return true
end

function BuildCatalog()
    return {
        categories   = Config.Categories,
        customReports = Config.CustomReports,
        severities   = Config.Severities,
        levels       = Config.Levels,
        units        = Config.Units,
        media        = Config.Media,
        limits       = Config.Limits,
        appName      = Config.AppInfo.name,
        sosEnabled   = Config.SOS.enabled,
        heatmap      = {
            enabled  = Config.Heatmap.enabled or Config.Showcase,
            cellSize = Config.Heatmap.cellSize,
            -- Named areas always appear in Dangerous/Safest rankings; centers
            -- let the UI fly to them even when they have no heat cells yet.
            areas    = (function()
                local out = {}
                for _, a in ipairs(Config.Heatmap.areas) do
                    out[#out + 1] = { label = a.label, x = a.center.x, y = a.center.y }
                end
                return out
            end)(),
        },
    }
end

function SerializeReport(r)
    return {
        id = r.id, category = r.category, categoryLabel = r.categoryLabel,
        severity = r.severity, title = r.title, details = r.details,
        coords = { x = r.coords.x, y = r.coords.y, z = r.coords.z },
        streetLabel = r.streetLabel, zoneLabel = r.zoneLabel,
        author = { username = r.author.username, avatar = r.author.avatar, badge = r.author.badge }, media = r.media,
        confirmCount = #r.confirms, comments = r.comments,
        createdAt = r.createdAt,
    }
end

local function allReports()
    local out = {}
    for _, r in pairs(Reports) do out[#out + 1] = SerializeReport(r) end
    return out
end

-- confirmed[reportId]=true for reports this citizen has confirmed.
local function confirmedBy(cid)
    local out = {}
    if not cid then return out end
    for id, r in pairs(Reports) do
        for i = 1, #r.confirms do
            if r.confirms[i] == cid then out[id] = true; break end
        end
    end
    return out
end

local function clamp(str, max)
    str = tostring(str or '')
    if #str > max then str = str:sub(1, max) end
    return str
end

lib.callback.register('noted_crimeapp:getAppData', function(src)
    local cid = cidOf(src)
    local acc = cid and Accounts.Get(cid) or nil
    local account
    if acc then
        local lvl = Accounts.LevelFor(acc.points)
        account = {
            username = acc.username, avatar = acc.avatar_url, points = acc.points,
            level = lvl, badge = badgeFor(src), subscribed = acc.subscribed,
        }
    end
    refreshSubscriber(src)
    return {
        account   = account,
        catalog   = BuildCatalog(),
        reports   = allReports(),
        confirmed = confirmedBy(cid),
    }
end)

lib.callback.register('noted_crimeapp:signup', function(src, data)
    local cid = cidOf(src)
    if not cid then return false, 'No character loaded.' end
    local ok, err = Accounts.Create(cid, data and data.username, data and data.password, data and data.avatar)
    if ok then refreshSubscriber(src) end
    return ok, err
end)

lib.callback.register('noted_crimeapp:login', function(src, data)
    local cid = cidOf(src)
    if not cid then return false, 'No character loaded.' end
    local okCd, cdErr = passCooldown(src, 'login')
    if not okCd then return false, cdErr end
    local ok, err = Accounts.Login(cid, data and data.username, data and data.password)
    if ok then refreshSubscriber(src) end
    return ok, err
end)

lib.callback.register('noted_crimeapp:logout', function(src)
    local cid = cidOf(src)
    if not cid then return false end
    Accounts.Logout(cid)
    refreshSubscriber(src)
    return true
end)

lib.callback.register('noted_crimeapp:changePassword', function(src, data)
    local cid = cidOf(src)
    if not cid then return false, 'No character.' end
    return Accounts.ChangePassword(cid, data and data.current, data and data.new)
end)

lib.callback.register('noted_crimeapp:postReport', function(src, data)
    local cid = cidOf(src)
    if not cid then return false, 'No character.' end
    local acc = Accounts.Get(cid)
    if not acc then return false, 'Create an account first.' end
    if type(data) ~= 'table' then return false, 'Bad request.' end

    -- Resolve category / severity server-side.
    local category, severity, categoryLabel, title
    if data.category == '__custom__' then
        if not Config.CustomReports.enabled then return false, 'Custom reports are disabled.' end
        title = clamp(data.title, Config.Limits.title.max)
        if #title == 0 then return false, 'A title is required for custom reports.' end
        category, severity, categoryLabel = '__custom__', Config.CustomReports.severity, title
    else
        local def
        for _, c in ipairs(Config.Categories) do if c.id == data.category then def = c break end end
        if not def then return false, 'Unknown category.' end
        category, severity, categoryLabel = def.id, def.severity, def.label
        title = def.label
    end

    local okCd, cdErr = passCooldown(src, 'report')
    if not okCd then return false, cdErr end

    -- Media caps.
    local media = {}
    if type(data.media) == 'table' then
        for i = 1, math.min(#data.media, Config.Media.maxPerReport) do
            media[#media + 1] = tostring(data.media[i])
        end
    end

    -- Coordinates: SERVER reads the poster's ped, never trust the client.
    local ped = GetPlayerPed(src)
    local pc = GetEntityCoords(ped)

    NextReportId = NextReportId + 1
    local report = {
        id = NextReportId,
        category = category, categoryLabel = categoryLabel, severity = severity,
        title = title, details = clamp(data.details, Config.Limits.details.max),
        coords = { x = pc.x, y = pc.y, z = pc.z },
        streetLabel = clamp(data.streetLabel, 60), zoneLabel = clamp(data.zoneLabel, 60),
        author = { citizenid = cid, username = acc.username, avatar = acc.avatar_url, badge = badgeFor(src) },
        media = media, confirms = {}, comments = {},
        createdAt = os.time(),
        expiresAt = os.time() + Config.ReportLifetime * 60,
    }
    Reports[report.id] = report
    Accounts.AddPoints(cid, Config.Points.post)

    local serialized = SerializeReport(report)
    Heat.Bump(report.coords, severity, report.zoneLabel ~= '' and report.zoneLabel or report.streetLabel)
    NotifyNewReport(report)              -- defined in Task 5 (no-op safe if absent)
    BroadcastReport('add', serialized)   -- defined in Task 7 push (guarded)
    return true, nil, serialized
end)

lib.callback.register('noted_crimeapp:deleteReport', function(src, id)
    local r = Reports[tonumber(id)]
    if not r then return false, 'Report not found.' end
    if not CanDelete(src, r) then return false, 'Not allowed.' end
    Reports[r.id] = nil
    BroadcastReport('remove', { id = r.id })
    return true
end)

lib.callback.register('noted_crimeapp:canDelete', function(src, id)
    local r = Reports[tonumber(id)]
    if not r then return false end
    return CanDelete(src, r)
end)

lib.callback.register('noted_crimeapp:confirmReport', function(src, id)
    local cid = cidOf(src)
    if not cid then return false, 'No character.' end
    if not Accounts.Get(cid) then return false, 'Create an account first.' end
    local r = Reports[tonumber(id)]
    if not r then return false, 'Report not found.' end
    for i = 1, #r.confirms do
        if r.confirms[i] == cid then return false, 'Already confirmed.', #r.confirms end
    end
    r.confirms[#r.confirms + 1] = cid
    -- Credit the author (not the confirmer), unless confirming your own report.
    if r.author.citizenid ~= cid then
        -- Credit by account name — works even if the author logged out.
        Accounts.AddPointsByName(r.author.username, Config.Points.confirmReceived)
    end
    BroadcastReport('update', SerializeReport(r))
    return true, nil, #r.confirms
end)

lib.callback.register('noted_crimeapp:commentReport', function(src, data)
    local cid = cidOf(src)
    if not cid then return false, 'No character.' end
    local acc = Accounts.Get(cid)
    if not acc then return false, 'Create an account first.' end
    local r = data and Reports[tonumber(data.id)]
    if not r then return false, 'Report not found.' end
    local text = clamp(data.text, Config.Limits.comment.max)
    if #text == 0 then return false, 'Empty comment.' end
    local okCd, cdErr = passCooldown(src, 'comment')
    if not okCd then return false, cdErr end

    local comment = { username = acc.username, badge = badgeFor(src), text = text, time = os.time() }
    r.comments[#r.comments + 1] = comment
    BroadcastReport('update', SerializeReport(r))
    return true, nil, comment
end)

OnlineSubscribers = {} -- src -> citizenid (only players opted in)

function refreshSubscriber(src)
    if not Config.Notifications.enabled then return end
    local cid = cidOf(src)
    if not cid then OnlineSubscribers[src] = nil return end
    local acc = Accounts.Get(cid)
    OnlineSubscribers[src] = (acc and acc.subscribed) and cid or nil
end

function NotifyNewReport(report)
    if not Config.Notifications.enabled then return end
    local rc = report.coords
    local origin = vector3(rc.x, rc.y, rc.z)
    local radius = Config.Notifications.radius
    for sub, subCid in pairs(OnlineSubscribers) do
        if subCid ~= report.author.citizenid then
            local ped = GetPlayerPed(sub)
            if ped and ped ~= 0 then
                local d = #(GetEntityCoords(ped) - origin)
                if d <= radius then
                    TriggerClientEvent('noted_crimeapp:notify', sub, {
                        title = ('%s reported nearby'):format(report.categoryLabel),
                        body = report.streetLabel ~= '' and report.streetLabel or report.zoneLabel,
                        reportId = report.id,
                    })
                end
            end
        end
    end
end

lib.callback.register('noted_crimeapp:setSubscribed', function(src, bool)
    local cid = cidOf(src)
    if not cid then return false end
    Accounts.SetSubscribed(cid, bool and true or false)
    refreshSubscriber(src)
    return true
end)

-- Populate registry when a player's account loads / on join.
RegisterNetEvent('noted_crimeapp:clientReady', function()
    refreshSubscriber(source)
end)

function BroadcastReport(kind, report)
    TriggerClientEvent('noted_crimeapp:reports', -1, kind, report)
end

-- Periodic sweep of expired reports.
CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for id, r in pairs(Reports) do
            if r.expiresAt and now >= r.expiresAt then
                Reports[id] = nil
                BroadcastReport('remove', { id = id })
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    lastAction[source] = nil
    OnlineSubscribers[source] = nil
end)

lib.callback.register('noted_crimeapp:sos', function(src, data)
    if not Config.SOS.enabled then return false, 'SOS is disabled.' end
    if not cidOf(src) then return false, 'No character.' end
    local okCd, cdErr = passCooldown(src, 'sos')
    if not okCd then return false, cdErr end
    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    local ok = pcall(function()
        Config.SOS.dispatch(src, coords, data and data.street)
    end)
    if not ok then
        print('^1[noted_crimeapp]^0 SOS dispatch function errored — check Config.SOS.dispatch')
        if lastAction[src] then lastAction[src].sos = nil end
        return false, 'Dispatch unavailable.'
    end
    return true
end)
