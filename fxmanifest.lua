fx_version 'cerulean'
game 'gta5'

lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'osm-target'
author 'OsmFX Mods'
description 'OSM Target - world-space DUI interaction system. Drop-in replacement for ox_target / qb-target / qtarget with multiple bespoke designs, explained disabled states, and a SQL-backed in-game admin panel.'
version '1.0.2'
repository 'https://github.com/OsmFX-Mods/osm-target'

ui_page 'html/index.html'

shared_scripts {
  '@ox_lib/init.lua',
  'config.lua',
  'locales/locale.lua',
  'locales/*.lua',
  'shared/schema.lua',
  'shared/compat.lua',
  'shared/resolver.lua',
  -- Register design system: load registry before individual pack descriptors
  'shared/designs.lua',
  'designs/**/design.lua',
}

client_scripts {
  'client/framework/init.lua',
  'client/framework/esx.lua',
  'client/framework/ox.lua',
  'client/framework/qbcore.lua',
  'client/framework/qbox.lua',
  'client/framework/standalone.lua',
  'client/target/player.lua',
  'client/target/store.lua',
  'client/api/native.lua',
  'client/api/qb.lua',
  'client/api/qtarget.lua',
  'client/ui/surfaces.lua',
  'client/target/discovery.lua',
  'client/target/hit.lua',
  'client/target/input.lua',
  'client/target/machine.lua',
  'client/target/defaults.lua',
  'client/ui/nui.lua',
  'client/config_sync.lua',
  'client/debug.lua',
  'client/main.lua',
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/framework/init.lua',
  'server/framework/esx.lua',
  'server/framework/ox.lua',
  'server/framework/qbcore.lua',
  'server/framework/qbox.lua',
  'server/framework/standalone.lua',
  'server/db.lua',
  'server/config_store.lua',
  'server/version.lua',
  'server/main.lua',
}

files {
  'html/index.html',
  'html/assets/*.js',
  'html/assets/*.css',
  -- Dynamic design bundles: runtime UI scripts loaded by NUI host
  'designs/**/design.js',
  'locales/*.lua',
}

-- Provide legacy target interfaces: satisfy resource dependencies for drop-in compatibility
provide 'ox_target'
provide 'qb-target'
provide 'qtarget'

dependencies {
  'ox_lib',
  'oxmysql',
}

escrow_ignore {
  '*',
  '**/*',
}
