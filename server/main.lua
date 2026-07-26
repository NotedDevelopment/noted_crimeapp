print('^2[noted_crimeapp]^0 server starting')
-- Report store, callbacks, notifications, SOS added in later tasks.

-- server/framework.lua and server/logs.lua (listed before this file) define
-- FW and Logs. If the running manifest predates those entries — i.e. the
-- server was restarted without a `refresh` — stub them out instead of
-- crashing every callback.
if not FW then
    print('^1[noted_crimeapp]^0 server/framework.lua NOT loaded — run `refresh` then `restart noted_crimeapp`. No player will have a character until then.')
    FW = {
        CitizenId = function() return nil end,
        JobInfo = function() return nil, 0 end,
        CharName = function() return '?' end,
    }
end
if not Logs then
    print('^1[noted_crimeapp]^0 server/logs.lua NOT loaded — run `refresh` then `restart noted_crimeapp`. Webhook logging is disabled until then.')
    local noop = function() end
    Logs = {
        COLORS = {},
        Send = noop,
        Identity = function() return '?' end,
        Coords = function() return '?' end,
        SeverityColor = function() return 0 end,
    }
end

Reports = {}          -- id -> report
NextReportId = 0
local lastAction = {} -- src -> { report=os.time(), comment=..., sos=... } cooldown stamps

-- All framework access goes through the FW bridge (server/framework.lua).
local function cidOf(src) return FW.CitizenId(src) end

-- Verified badge for a player's current job, or nil.
local function badgeFor(src)
    local jobName = FW.JobInfo(src)
    return jobName and Config.Badges[jobName] or nil
end

-- Job-grade or ace moderator (may delete ANY report/comment).
function CanModerate(src)
    local jobName, grade = FW.JobInfo(src)
    local minGrade = jobName and Config.Moderation.jobs[jobName]
    if minGrade and grade >= minGrade then return true end
    return IsPlayerAceAllowed(src, Config.Moderation.acePermission)
end

function CanDelete(src, report)
    local cid = cidOf(src)
    if cid and report.author.citizenid == cid then return true end
    return CanModerate(src)
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
        account     = account,
        catalog     = BuildCatalog(),
        reports     = allReports(),
        confirmed   = confirmedBy(cid),
        canModerate = CanModerate(src),
    }
end)

lib.callback.register('noted_crimeapp:signup', function(src, data)
    local cid = cidOf(src)
    if not cid then return false, 'No character loaded.' end
    local ok, err = Accounts.Create(cid, data and data.username, data and data.password, data and data.avatar)
    if ok then
        refreshSubscriber(src)
        Logs.Send('account', 'Account created', table.concat({
            ('**By:** %s'):format(Logs.Identity(src)),
            ('**App user:** %s'):format(tostring(data and data.username)),
        }, '\n'), Logs.COLORS.green)
    end
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
    local logLines = {
        ('**By:** %s'):format(Logs.Identity(src)),
        ('**App user:** %s'):format(acc.username),
        ('**Severity:** %s'):format(Config.Severities[severity] and Config.Severities[severity].label or severity),
        ('**Where:** %s, %s (%s)'):format(report.streetLabel, report.zoneLabel, Logs.Coords(report.coords)),
    }
    if report.details ~= '' then logLines[#logLines + 1] = ('**Details:** %s'):format(report.details) end
    if #media > 0 then logLines[#logLines + 1] = ('**Media:** %d attachment(s)'):format(#media) end
    Logs.Send('report', ('Report posted — %s'):format(report.categoryLabel),
        table.concat(logLines, '\n'), Logs.SeverityColor(severity))
    return true, nil, serialized
end)

lib.callback.register('noted_crimeapp:deleteReport', function(src, id)
    local r = Reports[tonumber(id)]
    if not r then return false, 'Report not found.' end
    if not CanDelete(src, r) then return false, 'Not allowed.' end
    Reports[r.id] = nil
    BroadcastReport('remove', { id = r.id })
    local isAuthor = cidOf(src) == r.author.citizenid
    Logs.Send('deleteReport', 'Report deleted', table.concat({
        ('**By:** %s (%s)'):format(Logs.Identity(src), isAuthor and 'author' or 'moderator'),
        ('**Report:** #%d — %s by %s'):format(r.id, r.title, r.author.username),
        ('**Where:** %s, %s'):format(r.streetLabel, r.zoneLabel),
    }, '\n'), Logs.COLORS.red)
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

    r.nextCommentId = (r.nextCommentId or #r.comments) + 1
    local comment = { id = r.nextCommentId, username = acc.username, badge = badgeFor(src), text = text, time = os.time() }
    r.comments[#r.comments + 1] = comment
    BroadcastReport('update', SerializeReport(r))
    Logs.Send('comment', 'Comment posted', table.concat({
        ('**By:** %s (%s)'):format(Logs.Identity(src), acc.username),
        ('**On report:** #%d — %s'):format(r.id, r.title),
        ('**Comment:** %s'):format(text),
    }, '\n'), Logs.COLORS.grey)
    return true, nil, comment
end)

-- Moderator-only: remove a single comment from a report.
lib.callback.register('noted_crimeapp:deleteComment', function(src, data)
    local r = data and Reports[tonumber(data.id)]
    if not r then return false, 'Report not found.' end
    if not CanModerate(src) then return false, 'Not allowed.' end
    local commentId = tonumber(data.commentId)
    for i = 1, #r.comments do
        if r.comments[i].id == commentId then
            local removed = table.remove(r.comments, i)
            local serialized = SerializeReport(r)
            BroadcastReport('update', serialized)
            Logs.Send('deleteComment', 'Comment deleted', table.concat({
                ('**By:** %s'):format(Logs.Identity(src)),
                ('**On report:** #%d — %s'):format(r.id, r.title),
                ('**Comment by:** %s'):format(removed.username),
                ('**Text:** %s'):format(removed.text),
            }, '\n'), Logs.COLORS.red)
            return true, nil, serialized
        end
    end
    return false, 'Comment not found.'
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
    Logs.Send('sos', 'SOS fired', table.concat({
        ('**By:** %s'):format(Logs.Identity(src)),
        ('**Where:** %s (%s)'):format((data and data.street) or 'unknown street', Logs.Coords(coords)),
    }, '\n'), Logs.COLORS.red)
    return true
end)
