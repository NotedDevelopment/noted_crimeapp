fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'NotedDevelopment'
description 'Citizen-style community safety app for LB Phone — live crime reports, reputation, verified badges, SOS to dispatch'
version '0.1.0'

shared_script '@ox_lib/init.lua'
shared_script 'config.lua'

client_scripts {
    'client/functions.lua', -- template helper: SendAppMessage
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/framework.lua',
    'server/logs.lua',
    'server/accounts.lua',
    'server/heat.lua',
    'server/main.lua',
    'server/showcase.lua',
}

-- During UI development use the Vite dev server; for production build the UI
-- (npm run build) and switch to the dist line below.
-- ui_page 'http://localhost:3000/'
ui_page 'ui/dist/index.html'

files {
    'ui/dist/index.html',
    'ui/dist/**/*',
}

dependencies {
    'ox_lib',
    'qbx_core',
    'oxmysql',
    'lb-phone',
}
