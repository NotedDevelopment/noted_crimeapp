-- Discord webhook logging. Every call is fire-and-forget; a bad/missing URL
-- can never affect gameplay callbacks.
--
-- The URL lives HERE (server-only) and not in config.lua, which is a
-- shared_script and therefore readable by every client.
local WEBHOOK_URL = '' -- paste your Discord webhook URL here

Logs = {}

Logs.COLORS = {
    green = 0x34c759,
    red   = 0xff453a,
    blue  = 0x0a84ff,
    grey  = 0x8e8e93,
}

-- Severity hex from config ('#ff9500') → Discord decimal color.
function Logs.SeverityColor(severity)
    local sev = Config.Severities[severity]
    local hex = sev and sev.color and sev.color:match('^#(%x%x%x%x%x%x)$')
    return hex and tonumber(hex, 16) or Logs.COLORS.grey
end

-- "SteamName (Char Name) — CID ABC12345"
function Logs.Identity(src)
    local p = exports.qbx_core:GetPlayer(src)
    local cid = p and p.PlayerData.citizenid or '?'
    local char = p and p.PlayerData.charinfo
        and ('%s %s'):format(p.PlayerData.charinfo.firstname, p.PlayerData.charinfo.lastname) or '?'
    return ('%s (%s) — CID %s'):format(GetPlayerName(src) or '?', char, cid)
end

function Logs.Coords(coords)
    return ('%.1f, %.1f, %.1f'):format(coords.x, coords.y, coords.z or 0.0)
end

-- kind must be a key in Config.Logging.events; unknown kinds always send.
function Logs.Send(kind, title, description, color)
    local cfg = Config.Logging
    if not cfg or not cfg.enabled or WEBHOOK_URL == '' then return end
    if cfg.events and cfg.events[kind] == false then return end
    PerformHttpRequest(WEBHOOK_URL, function(status)
        if status ~= 200 and status ~= 204 then
            print(('^3[noted_crimeapp]^0 Discord webhook returned %s — check WEBHOOK_URL in server/logs.lua'):format(tostring(status)))
        end
    end, 'POST', json.encode({
        username = cfg.botName or 'Citizen',
        embeds = {{
            title = title,
            description = description,
            color = color or Logs.COLORS.blue,
            footer = { text = 'noted_crimeapp' },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        }},
    }), { ['Content-Type'] = 'application/json' })
end
