fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mz_multichar'
author 'Mazus / MZ Architecture'
description 'Character selection and creation orchestration for MZ Framework'
version '0.1.0'

ui_page 'web/index.html'

shared_scripts {
  '@ox_lib/init.lua',
  'config.lua'
}

server_script 'server/main.lua'

client_scripts {
  '@mz_creator/shared/appearance_schema.lua',
  'client/scene.lua',
  'client/preview_peds.lua',
  'client/camera.lua',
  'client/main.lua'
}

files {
  'web/index.html',
  'web/style.css',
  'web/app.js'
}

dependencies {
  'ox_lib',
  'mz_core',
  'mz_creator'
}
