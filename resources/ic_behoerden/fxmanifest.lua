fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ic_behoerden'
author 'zMike07'
description 'IC-Gründung von Unternehmen und Fraktionen: Gewerbeamt und Bürgeramt mit Terminvergabe'
version '0.1.0'

dependencies {
    'oxmysql',
}

-- Nur Orte und Bedienung. Alles andere (Gebühren, Webhooks, Hooks) liegt in config_server.lua und erreicht nie den Client.
shared_scripts {
    'config.lua',
    'shared/util.lua',
    'shared/rules.lua',
    'shared/protocol.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config_server.lua',
    'server/store.lua',
    'server/persist.lua',
    'server/bridge.lua',
    'server/bridge_standalone.lua',
    'server/bridge_esx.lua',
    'server/bridge_qb.lua',
    'server/core.lua',
    'server/duty.lua',
    'server/register.lua',
    'server/applications.lua',
    'server/appointments.lua',
    'server/staff.lua',
    'server/api.lua',
    'server/net.lua',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/css/*.css',
    'web/js/*.js',
}
