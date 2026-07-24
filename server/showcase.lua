-- Showcase mode: seeds the app with demo reports + heat so every feature is
-- visible without players. In-memory only (Reports table + Heat.Inject); the
-- SQL heat table and accounts are never touched. Loads after server/main.lua
-- so Reports/NextReportId/Heat exist.

if not Config.Showcase then return end

local now = os.time()
local FAR_FUTURE = now + 86400 * 365 -- exempt from the expiry sweep

-- Demo reporters. nil badge = civilian; badges must exist in Config.Badges values.
local AUTHORS = {
    { user = 'Tavarius',      badge = nil },
    { user = 'MazeWatch',     badge = nil },
    { user = 'CBzCitizen',    badge = nil },
    { user = 'SoLoSaint',     badge = nil },
    { user = 'DavisLocal',    badge = nil },
    { user = 'VespucciVibes', badge = nil },
    { user = 'D_Danvers',     badge = 'LSPD' },
    { user = 'OfficerKing',   badge = 'LSPD' },
    { user = 'MedicRuiz',     badge = 'EMS' },
    { user = 'WeazelOnScene', badge = 'Press' },
}

local COMMENTS = {
    { username = 'CBzCitizen',    text = 'Just drove past, still going on.' },
    { username = 'DavisLocal',    text = 'Heard it from two blocks away.' },
    { username = 'WeazelOnScene', badge = 'Press', text = 'Crew en route for footage.' },
    { username = 'MedicRuiz',     badge = 'EMS', text = 'Anyone hurt on scene?' },
    { username = 'SoLoSaint',     text = 'Stay away from this corner rn.' },
}

-- { category, x, y, street, zone, ageMinutes, confirms, opts { title, severity, details, comments } }
-- Coords are approximate on purpose — close enough to light the right blocks.
local PRESETS = {
    -- Davis / Strawberry / Grove — the hot core
    { 'shooting',  172.0,  -1871.0, 'Grove Street',        'Davis',        12,   4, { details = 'Multiple shots heard near the cul-de-sac.' } },
    { 'shooting',   89.0,  -1959.0, 'Grove Street',        'Davis',        95,   3, { comments = { COMMENTS[1], COMMENTS[5] } } },
    { 'fight',     240.0,  -1990.0, 'Brouge Avenue',       'Davis',        25,   2, { details = 'A fight in front of the south barber!!' } },
    { 'shooting',  120.0,  -1800.0, 'Carson Avenue',       'Davis',       360,   5, {} },
    { 'theft',     205.0,  -1750.0, 'Carson Avenue',       'Davis',       520,   1, {} },
    { 'suspicious', 155.0, -1920.0, 'Davis Avenue',        'Davis',       780,   1, { comments = { COMMENTS[2] } } },
    { 'fight',     280.0,  -1660.0, 'Forum Drive',         'Strawberry',   45,   2, {} },
    { 'reckless',  330.0,  -1750.0, 'Alta Street',         'Strawberry',  130,   1, {} },
    { 'shooting',  360.0,  -1830.0, 'Jamestown Street',    'Strawberry',  610,   2, { details = 'Drive-by, dark sedan heading north.' } },
    { 'vandalism', 435.0,  -1710.0, 'Innocence Boulevard', 'Strawberry', 1480,   0, {} },
    { 'shooting',  460.0,  -1870.0, 'Jamestown Street',    'Rancho',      210,   3, {} },
    { 'fight',     490.0,  -1770.0, 'Roy Lowenstein Blvd', 'Rancho',     1900,   1, {} },
    { 'fire',      520.0,  -1930.0, 'Roy Lowenstein Blvd', 'Rancho',     2600,   2, { details = 'Dumpster fire spreading to a fence.' } },

    -- Downtown / Legion / Textile
    { 'gathering', 195.0,   -934.0, 'San Andreas Avenue',  'Legion Square', 35,  2, { details = 'Big crowd forming by the fountain.' } },
    { 'theft',     230.0,   -870.0, 'Sinner Street',       'Legion Square', 240, 1, {} },
    { 'collision', 150.0,  -1040.0, 'Strawberry Avenue',   'Pillbox Hill', 75,   1, {} },
    { 'suspicious', 415.0,  -780.0, 'Sinner Street',       'Textile City', 880,  0, {} },
    { '__custom__', 380.0,  -710.0, 'Atlee Street',        'Textile City', 150,  1, { title = 'Person shouting at passing cars', severity = 'low' } },

    -- Mirror Park / La Mesa / East LS
    { 'fight',    1130.0,   -640.0, 'Mirror Park Blvd',    'Mirror Park', 1300,  1, { details = 'Assault reported near the lake path.' } },
    { 'theft',    1042.0,   -730.0, 'West Mirror Drive',   'Mirror Park',  420,  0, {} },
    { 'vandalism', 720.0,   -960.0, 'Popular Street',      'La Mesa',      960,  1, {} },
    { 'reckless', 1330.0,  -1650.0, 'El Rancho Boulevard', 'El Burro Heights', 300, 1, {} },
    { '__custom__', 900.0, -1350.0, 'Amanda Way',          'Murrieta Heights', 55, 2, { title = 'Active pursuit moving through the area', severity = 'high', comments = { COMMENTS[3] } } },

    -- Vinewood / Hawick / Alta
    { 'suspicious', 300.0,   180.0, 'Vinewood Boulevard',  'Vinewood',     620,  1, { comments = { COMMENTS[4] } } },
    { 'reckless',   120.0,   250.0, 'Milton Road',         'Vinewood',    1750,  0, {} },
    { 'gathering',  395.0,    60.0, 'Meteor Street',       'Downtown Vinewood', 480, 3, {} },
    { 'theft',     -380.0,   -80.0, 'Hawick Avenue',       'Hawick',       200,  1, { details = 'Bag snatched outside the coffee shop.' } },
    { 'collision', -140.0,  -620.0, 'San Vitus Boulevard', 'Alta',         110,  1, {} },
    { 'vandalism', -570.0,  -160.0, 'Perth Street',        'Burton',      2200,  0, {} },

    -- West side — Little Seoul / Vespucci / Del Perro / Rockford
    { 'fight',     -640.0, -1100.0, 'Palomino Avenue',     'Little Seoul', 340,  1, {} },
    { '__custom__', -520.0, -1220.0, 'San Andreas Avenue', 'Little Seoul', 720,  2, { title = 'Vehicle taken by force near the area', severity = 'high' } },
    { 'theft',    -1200.0, -1500.0, 'Bay City Avenue',     'Vespucci',     260,  2, {} },
    { 'gathering', -1400.0, -1300.0, 'Vespucci Boulevard', 'Vespucci Canals', 90, 1, { details = 'Street performers drawing a big rowdy crowd.' } },
    { 'suspicious', -1600.0, -1000.0, 'Palomino Avenue',   'Del Perro',   1100,  0, {} },
    { 'collision', -1850.0, -1231.0, 'Great Ocean Highway', 'Del Perro Beach', 40, 2, { comments = { COMMENTS[4] } } },
    { 'theft',     -900.0,  -400.0, 'Eastbourne Way',      'Rockford Hills', 3000, 0, {} },

    -- South — airport / docks
    { 'suspicious', -1037.0, -2738.0, 'Exceptionalists Way', 'LSIA',       1500,  0, {} },
    { 'reckless',   -900.0, -2450.0, 'New Empire Way',      'LSIA',        640,  1, {} },
    { 'fire',        180.0, -2450.0, 'Elysian Fields Fwy',  'Elysian Island', 2100, 1, {} },
    { 'suspicious',  480.0, -2160.0, 'Expansion Avenue',    'Cypress Flats', 1250, 0, {} },

    -- County — Sandy / Grapeseed / Paleto / hills
    { 'shooting',   1960.0,  3740.0, 'Alhambra Drive',      'Sandy Shores', 800,  2, { details = 'Shots by the liquor store, everyone scattered.' } },
    { 'fight',      1890.0,  3680.0, 'Zancudo Avenue',      'Sandy Shores', 2300, 1, {} },
    { 'theft',      1690.0,  4750.0, 'Grapeseed Main St',   'Grapeseed',   3900,  0, {} },
    { 'reckless',    550.0,  2670.0, 'Route 68',            'Harmony',     1650,  1, {} },
    { 'suspicious', -275.0,  6230.0, 'Paleto Boulevard',    'Paleto Bay',  4300,  0, {} },
    { 'collision',  -110.0,  6420.0, 'Great Ocean Highway', 'Paleto Bay',  5200,  1, {} },
    { 'gathering',  -600.0,   680.0, 'Baytree Canyon Road', 'Vinewood Hills', 2800, 0, {} },
    { 'vandalism', -3160.0,  1000.0, 'Barbareno Road',      'Chumash',     6200,  0, {} },
}

local function severityFor(categoryId)
    for _, c in ipairs(Config.Categories) do
        if c.id == categoryId then return c.severity, c.label end
    end
    return Config.CustomReports.severity, nil
end

CreateThread(function()
    Wait(1000) -- let main.lua finish registering globals

    local seeded = 0
    for i, p in ipairs(PRESETS) do
        local cat, x, y, street, zone, age, confirms, opts = p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8] or {}
        local severity, label = severityFor(cat)
        if opts.severity then severity = opts.severity end
        local title = opts.title or label or 'Incident reported'
        local author = AUTHORS[(i % #AUTHORS) + 1]

        local confirmList = {}
        for c = 1, confirms do confirmList[c] = ('SHOWCASE_CONFIRM_%d_%d'):format(i, c) end

        local comments = {}
        for ci, cm in ipairs(opts.comments or {}) do
            comments[ci] = {
                username = cm.username, badge = cm.badge, text = cm.text,
                time = now - (age * 60) + 600 * ci,
            }
        end

        NextReportId = NextReportId + 1
        Reports[NextReportId] = {
            id = NextReportId,
            category = cat, categoryLabel = label or title, severity = severity,
            title = title, details = opts.details or '',
            coords = { x = x, y = y, z = 30.0 },
            streetLabel = street, zoneLabel = zone,
            author = { citizenid = ('SHOWCASE_%d'):format(i), username = author.user, avatar = nil, badge = author.badge },
            media = {}, confirms = confirmList, comments = comments,
            createdAt = now - age * 60,
            expiresAt = FAR_FUTURE,
        }
        seeded = seeded + 1

        -- Every showcase report also warms its block.
        Heat.Inject(x, y, severity, 2 + confirms, zone)
    end

    -- Extra heat so districts read clearly on the map beyond the seeded pins:
    -- (x, y, severity, count, zone)
    local EXTRA_HEAT = {
        { 150.0, -1880.0, 'critical', 14, 'Davis' },
        { 220.0, -1930.0, 'high',     11, 'Davis' },
        {  90.0, -1830.0, 'medium',    8, 'Davis' },
        { 320.0, -1740.0, 'high',      9, 'Strawberry' },
        { 300.0, -1810.0, 'medium',    7, 'Strawberry' },
        { 470.0, -1850.0, 'critical',  8, 'Rancho' },
        { 200.0,  -950.0, 'medium',    6, 'Legion Square' },
        { 170.0, -1020.0, 'low',       5, 'Pillbox Hill' },
        { -620.0, -1140.0, 'high',     5, 'Little Seoul' },
        { -1230.0, -1480.0, 'medium',  6, 'Vespucci' },
        { -1420.0, -1320.0, 'low',     4, 'Vespucci Canals' },
        { 1120.0,  -660.0, 'medium',   4, 'Mirror Park' },
        { 1950.0,  3730.0, 'high',     6, 'Sandy Shores' },
        { -890.0,  -410.0, 'low',      2, 'Rockford Hills' },
        { 310.0,    170.0, 'low',      3, 'Vinewood' },
    }
    for _, h in ipairs(EXTRA_HEAT) do
        Heat.Inject(h[1], h[2], h[3], h[4], h[5])
    end

    print(('^2[noted_crimeapp]^0 SHOWCASE MODE: seeded %d demo reports + heat data (disable Config.Showcase for live)'):format(seeded))
end)
