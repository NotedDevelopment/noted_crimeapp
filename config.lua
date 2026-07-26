Config = {}

-- Framework bridge: 'qbox' | 'qbcore' | 'esx', or 'auto' to detect in that
-- order (qbx_core → qb-core → es_extended).
-- Note: fxmanifest.lua lists qbx_core as a dependency — comment that line out
-- when running qbcore or esx.
Config.Framework = 'auto'

Config.AppInfo = {
    identifier  = 'noted_crimeapp',
    name        = 'Citizen',
    description = 'See what is happening around you. Report incidents. Stay safe.',
    developer   = 'NotedDevelopment',
    defaultApp  = true,   -- installed by default, cannot be uninstalled
    size        = 62000,  -- kb, cosmetic
}

-- Report categories shown in the report grid. Add/remove freely.
-- severity must be a key in Config.Severities.
Config.Categories = {
    { id = 'fight',      label = 'Fight in progress',  icon = 'hand-fist',      severity = 'high' },
    { id = 'suspicious', label = 'Suspicious activity', icon = 'eye',           severity = 'medium' },
    { id = 'reckless',   label = 'Reckless driving',    icon = 'car',           severity = 'medium' },
    { id = 'vandalism',  label = 'Vandalism',           icon = 'spray-can',     severity = 'low' },
    { id = 'theft',      label = 'Theft',               icon = 'sack-dollar',   severity = 'medium' },
    { id = 'fire',       label = 'Fire reported',       icon = 'fire',          severity = 'high' },
    { id = 'gathering',  label = 'Large gathering',     icon = 'people-group',  severity = 'low' },
    { id = 'collision',  label = 'Traffic collision',   icon = 'car-burst',     severity = 'medium' },
    { id = 'shooting',   label = 'Shots fired',         icon = 'gun',           severity = 'critical' },
}

-- Free-text "Custom" tile in the report grid.
Config.CustomReports = { enabled = true, severity = 'medium' }

-- Severity → display color (used for tags/markers). label is UI copy.
Config.Severities = {
    critical = { label = 'CRITICAL', color = '#ff3b30' },
    high     = { label = 'HIGH',     color = '#ff9500' },
    medium   = { label = 'MEDIUM',   color = '#eab308' },
    low      = { label = 'LOW',      color = '#34c759' },
}

-- Reputation.
Config.Points = { post = 5, confirmReceived = 3 }
Config.Levels = { -- ascending; first with points <= player's points is their level
    { name = 'Reporter',        points = 0 },
    { name = 'Trusted Citizen', points = 150 },
    { name = 'Local Watch',     points = 400 },
    { name = 'Guardian',        points = 900 },
}

-- Job → verified badge label. Checked against the player's job name
-- (any framework).
Config.Badges = {
    police    = 'LSPD',
    ambulance = 'EMS',
    reporter  = 'Press',
}

-- Who may delete ANY report (author can always delete their own).
Config.Moderation = {
    jobs = { police = 2 },              -- job name → minimum grade.level
    acePermission = 'admin',   -- ace permission fallback for admins
}

-- Proximity notifications.
Config.Notifications = {
    enabled = true,           -- master switch; false = skip subscriber registry entirely
    radius = 1600.0,          -- metres; players within this of a new report get pinged
    defaultSubscribed = true, -- default subscribed flag for a brand-new account
}

Config.ReportLifetime = 120   -- minutes a report stays live; swept every ~60s

Config.Cooldowns = { report = 60, comment = 10, sos = 120, login = 3 } -- seconds, per player

Config.Media = { maxPerReport = 3, allowVideo = true }

-- Input length caps (server-enforced).
Config.Limits = {
    username = { min = 3, max = 20 },
    password = { min = 4, max = 32 },
    title    = { max = 60 },
    details  = { max = 300 },
    comment  = { max = 200 },
}

Config.Units = 'imperial' -- 'imperial' (ft/mi) or 'metric' (m/km)

-- Crime heatmap. Tracks how many reports of each severity land in each map
-- cell, persisted to SQL (crimeapp_heat, auto-created) so hotspots survive
-- restarts. Heat cools over time via the decay pass. The heatmap button only
-- appears in the app when this is enabled OR Config.Showcase is on.
Config.Heatmap = {
    enabled     = false,  -- requires oxmysql writes; false = no tracking, no button
    cellSize    = 250.0,  -- metres per heat cell (block-ish granularity)
    maxCount    = 200,    -- cap per cell + severity
    decayEvery  = 3600,   -- seconds between cooling passes
    decayAmount = 1,      -- count removed from every cell per pass

    -- Optional named areas: any report landing inside a circle is tracked
    -- under YOUR label instead of the game's zone name, and named areas
    -- always appear in the Dangerous/Safest rankings (even at 0 reports).
    areas = {
        -- { label = 'South Central',  center = vec2(150.0, -1900.0), radius = 700.0 },
        -- { label = 'Vespucci Beach', center = vec2(-1200.0, -1500.0), radius = 500.0 },
    },
}

-- Showcase mode: fills the app with generated demo reports + heat data so
-- every feature can be seen without players (heatmap works without SQL).
-- In-memory only; normal posting still works alongside. Turn OFF for live.
Config.Showcase = true

-- Discord webhook logging. Fire-and-forget; fully off unless enabled AND the
-- webhook URL is set in server/logs.lua (server-only — this file is shared
-- with clients, so the URL must never live here).
Config.Logging = {
    enabled = true,
    botName = 'Citizen',          -- webhook display name
    events = {                    -- set any to false to silence that event
        report        = true,     -- new report posted
        deleteReport  = true,     -- report deleted (author or moderator)
        comment       = true,     -- comment posted
        deleteComment = true,     -- comment deleted by a moderator
        sos           = true,     -- SOS fired to dispatch
        account       = true,     -- account created
    },
}

-- SOS bridge. Return nothing. Default targets ps-dispatch.
Config.SOS = {
    enabled = false,
    dispatch = function(src, coords, street)
        -- Default: ps-dispatch CustomAlert. Swap for your dispatch of choice.
        local ped = GetPlayerPed(src)
        exports['ps-dispatch']:CustomAlert({
            coords = coords,
            message = 'Citizen SOS — help requested',
            dispatchCode = 'SOS',
            description = ('Emergency SOS near %s'):format(street or 'unknown location'),
            radius = 0,
            sprite = 61,
            color = 1,
            scale = 1.0,
            length = 3,
            sound = 'Lose_1st',
            sound2 = 'GTAO_FM_Events_Soundset',
            offset = false,
            flash = false,
        })
    end,
}
