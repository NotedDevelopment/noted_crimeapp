---@param action string
---@param data any
function SendAppMessage(action, data)
    exports["lb-phone"]:SendCustomAppMessage(Config.AppInfo.identifier, {
        action = action,
        data = data
    })
end
