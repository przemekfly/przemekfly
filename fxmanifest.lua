fx_version 'cerulean'
game 'gta5'

description 'Shop system'
author 'PrzemekFly'
version 'X'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua', 
    'server/main.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html'
}

dependencies {
    'es_extended',
    'esx_addoninventory',
    'esx_society',
    'esx_addonaccount'
}
