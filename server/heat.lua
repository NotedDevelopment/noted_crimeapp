-- Crime heat tracking: per-cell, per-severity report counts with periodic
-- decay. Memory is authoritative at runtime; SQL (crimeapp_heat) mirrors it
-- when Config.Heatmap.enabled so hotspots survive restarts. Showcase mode
-- runs memory-only via Heat.Inject (never touches SQL).

Heat = {}

-- cells[key] = { cx, cy, zone, counts = { [severity] = n } }
local cells = {}

local function heatActive()
    return Config.Heatmap.enabled or Config.Showcase
end

local function cellOf(x, y)
    local s = Config.Heatmap.cellSize
    return math.floor(x / s), math.floor(y / s)
end

local function keyOf(cx, cy)
    return cx .. ':' .. cy
end

-- Named-area override: a config circle wins over the game's zone label.
local function areaLabelFor(x, y, fallback)
    for _, a in ipairs(Config.Heatmap.areas) do
        local dx, dy = x - a.center.x, y - a.center.y
        if (dx * dx + dy * dy) <= (a.radius * a.radius) then
            return a.label
        end
    end
    return fallback
end

local function bumpMemory(cx, cy, severity, amount, zone)
    local k = keyOf(cx, cy)
    local cell = cells[k]
    if not cell then
        cell = { cx = cx, cy = cy, zone = zone, counts = {} }
        cells[k] = cell
    end
    if zone and zone ~= '' then cell.zone = zone end
    local n = (cell.counts[severity] or 0) + amount
    cell.counts[severity] = math.min(n, Config.Heatmap.maxCount)
    return cell
end

-- Called for every posted report (server/main.lua).
function Heat.Bump(coords, severity, zoneLabel)
    if not heatActive() then return end
    local cx, cy = cellOf(coords.x, coords.y)
    local zone = areaLabelFor(coords.x, coords.y, zoneLabel or '')
    bumpMemory(cx, cy, severity, 1, zone)

    if Config.Heatmap.enabled then
        MySQL.prepare(
            [[INSERT INTO crimeapp_heat (cell_x, cell_y, severity, count, zone)
              VALUES (?, ?, ?, 1, ?)
              ON DUPLICATE KEY UPDATE count = LEAST(count + 1, ?), zone = VALUES(zone)]],
            { cx, cy, severity, zone, Config.Heatmap.maxCount })
    end
end

-- Showcase seeding: memory only, never SQL — so demo data can't pollute the
-- real table when both showcase and SQL tracking happen to be on.
function Heat.Inject(x, y, severity, count, zoneLabel)
    local cx, cy = cellOf(x, y)
    local zone = areaLabelFor(x, y, zoneLabel or '')
    bumpMemory(cx, cy, severity, count, zone)
end

-- Serialized for the UI: world-space cell centers + per-severity counts.
function Heat.Serialize()
    local out = {}
    local s = Config.Heatmap.cellSize
    for _, cell in pairs(cells) do
        out[#out + 1] = {
            x = (cell.cx + 0.5) * s,
            y = (cell.cy + 0.5) * s,
            zone = cell.zone or '',
            counts = cell.counts,
        }
    end
    return out
end

lib.callback.register('noted_crimeapp:getHeat', function()
    if not heatActive() then return { cells = {} } end
    return { cells = Heat.Serialize() }
end)

-- SQL bootstrap + reload into memory.
CreateThread(function()
    if not Config.Heatmap.enabled then return end
    while GetResourceState('oxmysql') ~= 'started' do Wait(200) end

    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS crimeapp_heat (
                cell_x   SMALLINT    NOT NULL,
                cell_y   SMALLINT    NOT NULL,
                severity VARCHAR(16) NOT NULL,
                count    INT         NOT NULL DEFAULT 0,
                zone     VARCHAR(60) DEFAULT '',
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (cell_x, cell_y, severity)
            )]])
    end)
    if not ok then
        print(('^1[noted_crimeapp]^0 FAILED creating heat table: %s'):format(tostring(err)))
        return
    end

    local rows = MySQL.query.await('SELECT cell_x, cell_y, severity, count, zone FROM crimeapp_heat') or {}
    for _, r in ipairs(rows) do
        bumpMemory(r.cell_x, r.cell_y, r.severity, r.count, r.zone)
    end
    print(('^2[noted_crimeapp]^0 heat table ready (%d cells loaded)'):format(#rows))
end)

-- Cooling pass: every cell loses decayAmount per interval; empty cells vanish.
CreateThread(function()
    local cfg = Config.Heatmap
    if cfg.decayEvery <= 0 or cfg.decayAmount <= 0 then return end
    while true do
        Wait(cfg.decayEvery * 1000)
        if heatActive() then
            for k, cell in pairs(cells) do
                local empty = true
                for sev, n in pairs(cell.counts) do
                    local left = n - cfg.decayAmount
                    if left > 0 then
                        cell.counts[sev] = left
                        empty = false
                    else
                        cell.counts[sev] = nil
                    end
                end
                if empty then cells[k] = nil end
            end
            if cfg.enabled then
                MySQL.update('UPDATE crimeapp_heat SET count = count - ? WHERE count > 0', { cfg.decayAmount })
                MySQL.update('DELETE FROM crimeapp_heat WHERE count <= 0')
            end
        end
    end
end)
