MZMulticharScene = {
  owned = false,
  focusOwned = false,
  playerLocked = false
}

function MZMulticharNativeTrue(value)
  return value == true or value == 1
end

local function sceneConfig()
  return Config.SelectionScene or {}
end

local function selectionConfig()
  return Config.Selection or {}
end

local function debugLog(message, ...)
  if Config.Debug ~= true then return end
  print(('[MZ_MULTICHAR][SCENE] ' .. message):format(...))
end

local function validPed(ped)
  return ped and ped ~= 0 and MZMulticharNativeTrue(DoesEntityExist(ped))
end

local function setPlayerLocked(locked, visible)
  local ped = PlayerPedId()
  if not validPed(ped) then return false end

  FreezeEntityPosition(ped, locked == true)
  SetEntityVisible(ped, visible == true, false)
  SetEntityCollision(ped, locked ~= true or visible == true, locked ~= true or visible == true)
  SetPlayerInvincible(PlayerId(), locked == true)
  SetEntityInvincible(ped, locked == true)
  MZMulticharScene.playerLocked = locked == true
  return true
end

function MZMulticharScene.fadeOut()
  if MZMulticharNativeTrue(IsScreenFadedOut()) then return true end
  local duration = tonumber(selectionConfig().fadeOutMs) or 250
  DoScreenFadeOut(duration)
  local deadline = GetGameTimer() + duration + 1500
  while not MZMulticharNativeTrue(IsScreenFadedOut()) and GetGameTimer() < deadline do
    Wait(0)
  end
  return MZMulticharNativeTrue(IsScreenFadedOut())
end

function MZMulticharScene.fadeIn()
  local duration = tonumber(selectionConfig().fadeInMs) or 500
  DoScreenFadeIn(duration)
  local deadline = GetGameTimer() + duration + 1500
  while not MZMulticharNativeTrue(IsScreenFadedIn()) and GetGameTimer() < deadline do
    Wait(0)
  end
  return MZMulticharNativeTrue(IsScreenFadedIn())
end

function MZMulticharScene.prepare()
  local cfg = sceneConfig()
  local location = cfg.location or selectionConfig().position or {}
  local x = tonumber(location.x) or -777.54
  local y = tonumber(location.y) or 331.47
  local z = tonumber(location.z) or 211.40
  local heading = tonumber(location.heading) or 180.0
  local ped = PlayerPedId()

  debugLog('loading')
  if not MZMulticharScene.fadeOut() then return false, 'fade_out_timeout' end
  if not validPed(ped) then return false, 'invalid_player_ped' end

  MZMulticharScene.owned = true
  RequestCollisionAtCoord(x, y, z)
  SetFocusPosAndVel(x, y, z, 0.0, 0.0, 0.0)
  MZMulticharScene.focusOwned = true
  SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
  SetEntityHeading(ped, heading)
  setPlayerLocked(true, false)

  local interior = GetInteriorAtCoords(x, y, z)
  if interior and interior ~= 0 then LoadInterior(interior) end

  local deadline = GetGameTimer() + (tonumber(cfg.loadTimeoutMs) or 5000)
  local collisionReady = MZMulticharNativeTrue(HasCollisionLoadedAroundEntity(ped))
  local interiorReady = not interior or interior == 0 or MZMulticharNativeTrue(IsInteriorReady(interior))
  while (not collisionReady or not interiorReady) and GetGameTimer() < deadline do
    RequestCollisionAtCoord(x, y, z)
    Wait(50)
    collisionReady = MZMulticharNativeTrue(HasCollisionLoadedAroundEntity(ped))
    interiorReady = not interior or interior == 0 or MZMulticharNativeTrue(IsInteriorReady(interior))
  end

  if not collisionReady or not interiorReady then
    return false, 'scene_load_timeout'
  end

  ShutdownLoadingScreen()
  ShutdownLoadingScreenNui()
  debugLog('ready collision=%s interior=%s', tostring(collisionReady), tostring(interiorReady))
  return true
end

function MZMulticharScene.clearFocus()
  if not MZMulticharScene.focusOwned then return end
  ClearFocus()
  MZMulticharScene.focusOwned = false
end

function MZMulticharScene.handoff()
  MZMulticharScene.clearFocus()
  debugLog('cleanup')
end

function MZMulticharScene.release()
  MZMulticharScene.clearFocus()
  if MZMulticharScene.playerLocked then setPlayerLocked(false, true) end
  MZMulticharScene.owned = false
end

function MZMulticharScene.failSafe()
  MZMulticharScene.release()
  MZMulticharScene.fadeIn()
end

function MZMulticharScene.coreSpawnComplete()
  MZMulticharScene.clearFocus()
  MZMulticharScene.playerLocked = false
  MZMulticharScene.owned = false
end

function MZMulticharScene.creatorHandoffComplete()
  MZMulticharScene.clearFocus()
  MZMulticharScene.playerLocked = false
  MZMulticharScene.owned = false
end

function MZMulticharScene.isOwned()
  return MZMulticharScene.owned == true
end
