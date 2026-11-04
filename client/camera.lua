MZMulticharCamera = {
  modes = { CINEMATIC = 'CINEMATIC', CHARACTER_FOCUS = 'CHARACTER_FOCUS' },
  mode = nil,
  cam = nil,
  running = false,
  generation = 0,
  currentPosition = nil,
  currentLookAt = nil
}

local function sceneConfig()
  return Config.SelectionScene or {}
end

local function debugLog(message, ...)
  if Config.Debug ~= true then return end
  print(('[MZ_MULTICHAR][CAMERA] ' .. message):format(...))
end

local function point(value, fallback)
  value = type(value) == 'table' and value or fallback or {}
  return {
    x = tonumber(value.x) or 0.0,
    y = tonumber(value.y) or 0.0,
    z = tonumber(value.z) or 0.0
  }
end

local function interpolate(a, b, alpha)
  return a + (b - a) * alpha
end

local function smooth(alpha)
  alpha = math.max(0.0, math.min(1.0, alpha))
  return alpha * alpha * (3.0 - 2.0 * alpha)
end

local function setFrame(position, lookAt, fov)
  if not MZMulticharCamera.cam then return end
  SetCamCoord(MZMulticharCamera.cam, position.x, position.y, position.z)
  PointCamAtCoord(MZMulticharCamera.cam, lookAt.x, lookAt.y, lookAt.z)
  if fov then SetCamFov(MZMulticharCamera.cam, tonumber(fov) or 48.0) end
  MZMulticharCamera.currentPosition = point(position)
  MZMulticharCamera.currentLookAt = point(lookAt)
end

local function ensureCamera(position, lookAt, fov)
  if MZMulticharCamera.cam and MZMulticharNativeTrue(DoesCamExist(MZMulticharCamera.cam)) then
    return true
  end
  MZMulticharCamera.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', false)
  if not MZMulticharCamera.cam or MZMulticharCamera.cam == 0
    or not MZMulticharNativeTrue(DoesCamExist(MZMulticharCamera.cam)) then
    MZMulticharCamera.cam = nil
    return false
  end
  setFrame(position, lookAt, fov)
  SetCamActive(MZMulticharCamera.cam, true)
  RenderScriptCams(true, true, tonumber(sceneConfig().cameraBlendMs) or 650, true, true)
  return MZMulticharNativeTrue(IsCamActive(MZMulticharCamera.cam))
end

local function animate(fromPosition, toPosition, fromLookAt, toLookAt, duration, token, fov)
  duration = math.max(1, tonumber(duration) or 10000)
  local startedAt = GetGameTimer()
  local elapsed = 0
  while MZMulticharCamera.running and token == MZMulticharCamera.generation and elapsed < duration do
    local alpha = smooth(elapsed / duration)
    setFrame({
      x = interpolate(fromPosition.x, toPosition.x, alpha),
      y = interpolate(fromPosition.y, toPosition.y, alpha),
      z = interpolate(fromPosition.z, toPosition.z, alpha)
    }, {
      x = interpolate(fromLookAt.x, toLookAt.x, alpha),
      y = interpolate(fromLookAt.y, toLookAt.y, alpha),
      z = interpolate(fromLookAt.z, toLookAt.z, alpha)
    }, fov)
    Wait(math.max(8, tonumber(sceneConfig().cameraTickMs) or 16))
    elapsed = GetGameTimer() - startedAt
  end
  if MZMulticharCamera.running and token == MZMulticharCamera.generation then
    setFrame(toPosition, toLookAt, fov)
    return true
  end
  return false
end

function MZMulticharCamera.startCinematic(resumed)
  local paths = sceneConfig().cinematicPaths or {}
  if #paths == 0 then return false, 'cinematic_paths_missing' end

  local first = paths[1]
  local initialPosition = point(first.from)
  local initialLookAt = point(first.lookFrom)
  if not ensureCamera(initialPosition, initialLookAt, first.fov or sceneConfig().cameraFov) then
    return false, 'camera_creation_failed'
  end

  MZMulticharCamera.generation = MZMulticharCamera.generation + 1
  local token = MZMulticharCamera.generation
  MZMulticharCamera.running = true
  MZMulticharCamera.mode = MZMulticharCamera.modes.CINEMATIC
  debugLog(resumed and 'cinematicResumed' or 'cinematicStarted')

  CreateThread(function()
    if resumed and MZMulticharCamera.currentPosition and MZMulticharCamera.currentLookAt then
      local joined = animate(
        point(MZMulticharCamera.currentPosition), initialPosition,
        point(MZMulticharCamera.currentLookAt), initialLookAt,
        tonumber(sceneConfig().focusTransitionMs) or 700, token,
        first.fov or sceneConfig().cameraFov
      )
      if not joined then return end
    end
    local index = 1
    while MZMulticharCamera.running and token == MZMulticharCamera.generation do
      local path = paths[index]
      if not path then index = 1 path = paths[index] end
      local completed = animate(
        point(path.from), point(path.to, path.from),
        point(path.lookFrom), point(path.lookTo, path.lookFrom),
        path.duration, token, path.fov or sceneConfig().cameraFov
      )
      if not completed then return end
      index = index < #paths and index + 1 or 1
    end
  end)
  return true
end

function MZMulticharCamera.focus(characterId)
  local entry = MZMulticharPreview.get(characterId)
  if not entry then return false, 'preview_not_available' end
  local focus = entry.slot and entry.slot.focusCamera or {}
  local targetPosition = point(focus.coords)
  local targetLookAt = point(focus.lookAt)
  if not ensureCamera(targetPosition, targetLookAt, focus.fov or sceneConfig().focusFov) then
    return false, 'camera_creation_failed'
  end

  local fromPosition = MZMulticharCamera.currentPosition or targetPosition
  local fromLookAt = MZMulticharCamera.currentLookAt or targetLookAt
  MZMulticharCamera.generation = MZMulticharCamera.generation + 1
  local token = MZMulticharCamera.generation
  MZMulticharCamera.running = true
  MZMulticharCamera.mode = MZMulticharCamera.modes.CHARACTER_FOCUS
  debugLog('focus characterId=%s', tostring(characterId))
  CreateThread(function()
    animate(fromPosition, targetPosition, fromLookAt, targetLookAt,
      tonumber(sceneConfig().focusTransitionMs) or 700, token,
      focus.fov or sceneConfig().focusFov)
  end)
  return true
end

function MZMulticharCamera.resumeCinematic()
  return MZMulticharCamera.startCinematic(true)
end

function MZMulticharCamera.destroy()
  MZMulticharCamera.running = false
  MZMulticharCamera.generation = MZMulticharCamera.generation + 1
  MZMulticharCamera.mode = nil
  if MZMulticharCamera.cam and MZMulticharNativeTrue(DoesCamExist(MZMulticharCamera.cam)) then
    SetCamActive(MZMulticharCamera.cam, false)
    RenderScriptCams(false, true, tonumber(sceneConfig().cameraBlendMs) or 650, true, true)
    DestroyCam(MZMulticharCamera.cam, false)
    debugLog('destroyed')
  end
  MZMulticharCamera.cam = nil
  MZMulticharCamera.currentPosition = nil
  MZMulticharCamera.currentLookAt = nil
end
