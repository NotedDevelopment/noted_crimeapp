-- Wait for lb-phone, then register the app. Full bridge added in Task 7.
CreateThread(function()
    while GetResourceState('lb-phone') ~= 'started' do Wait(500) end
    Wait(1000) -- let the AddCustomApp export come up

    local url = GetResourceMetadata(GetCurrentResourceName(), 'ui_page', 0)
    local res = GetCurrentResourceName()

    local function AddApp()
        local added, err = exports['lb-phone']:AddCustomApp({
            identifier  = Config.AppInfo.identifier,
            name        = Config.AppInfo.name,
            description = Config.AppInfo.description,
            developer   = Config.AppInfo.developer,
            defaultApp  = Config.AppInfo.defaultApp,
            size        = Config.AppInfo.size,
            ui          = url:find('http') and url or (res .. '/' .. url),
            icon        = url:find('http') and (url .. '/public/icon.svg')
                          or ('https://cfx-nui-' .. res .. '/ui/dist/icon.svg'),
            fixBlur     = true,
        })
        if not added then
            print(('^1[noted_crimeapp]^0 Could not add app: %s'):format(tostring(err)))
        else
            print('^2[noted_crimeapp]^0 App registered with lb-phone')
        end
    end

    AddApp()
    AddEventHandler('onResourceStart', function(r)
        if r == 'lb-phone' then AddApp() end
    end)
end)

-- Small helper: forward a server callback result to the NUI cb as {ok, err, extra}.
local function action(name, payload, cb)
    lib.callback(name, false, function(ok, err, extra)
        cb({ ok = ok, err = err, extra = extra })
    end, payload)
end

-- Current street + area label from the player's position.
local function positionLabels()
    local coords = GetEntityCoords(PlayerPedId())
    local s1 = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(s1)
    local zoneCode = GetNameOfZone(coords.x, coords.y, coords.z)
    local area = GetLabelText(zoneCode)
    if area == 'NULL' or area == nil then area = zoneCode end
    return coords, street or '', area or ''
end

RegisterNUICallback('getPosition', function(_, cb)
    local coords, street, area = positionLabels()
    cb({ coords = { x = coords.x, y = coords.y, z = coords.z }, streetLabel = street, zoneLabel = area })
end)

RegisterNUICallback('getAppData', function(_, cb)
    lib.callback('noted_crimeapp:getAppData', false, function(data) cb(data or {}) end)
end)

RegisterNUICallback('signup',         function(data, cb) action('noted_crimeapp:signup', data, cb) end)
RegisterNUICallback('login',          function(data, cb) action('noted_crimeapp:login', data, cb) end)
RegisterNUICallback('logout',         function(_, cb)    action('noted_crimeapp:logout', nil, cb) end)
RegisterNUICallback('changePassword', function(data, cb) action('noted_crimeapp:changePassword', data, cb) end)
RegisterNUICallback('confirmReport', function(data, cb) action('noted_crimeapp:confirmReport', data.id, cb) end)
RegisterNUICallback('commentReport', function(data, cb) action('noted_crimeapp:commentReport', data, cb) end)
RegisterNUICallback('deleteReport',  function(data, cb) action('noted_crimeapp:deleteReport', data.id, cb) end)
RegisterNUICallback('getHeat', function(_, cb)
    lib.callback('noted_crimeapp:getHeat', false, function(data) cb(data or { cells = {} }) end)
end)

RegisterNUICallback('canDelete', function(data, cb)
    lib.callback('noted_crimeapp:canDelete', false, function(v) cb(v == true) end, data.id)
end)
RegisterNUICallback('sos',           function(data, cb) action('noted_crimeapp:sos', data, cb) end)
RegisterNUICallback('setSubscribed', function(data, cb) action('noted_crimeapp:setSubscribed', data.value, cb) end)

-- postReport: enrich with authoritative-side labels (coords come from server).
RegisterNUICallback('postReport', function(data, cb)
    local _, street, area = positionLabels()
    data.streetLabel, data.zoneLabel = street, area
    action('noted_crimeapp:postReport', data, cb)
end)

RegisterNUICallback('setWaypoint', function(data, cb)
    if data and data.x and data.y then SetNewWaypoint(data.x + 0.0, data.y + 0.0) end
    cb('ok')
end)

-- Server pushes → UI (only meaningful while app is open; harmless otherwise).
RegisterNetEvent('noted_crimeapp:reports', function(kind, report)
    SendAppMessage('reports', { kind = kind, report = report })
end)

RegisterNetEvent('noted_crimeapp:notify', function(payload)
    -- Phone notification (works even if the app isn't focused).
    exports['lb-phone']:SendNotification({
        app = Config.AppInfo.identifier,
        title = payload.title,
        content = payload.body,
    })
    SendAppMessage('notify', payload)
end)

-- Tell the server we're ready so it can register us as a subscriber.
CreateThread(function()
    while GetResourceState('lb-phone') ~= 'started' do Wait(500) end
    Wait(1500)
    TriggerServerEvent('noted_crimeapp:clientReady')
end)
