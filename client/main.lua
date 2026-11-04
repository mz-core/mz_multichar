local open = false
local nuiReady = false
local nuiRendered = false
local pendingState = nil
local selectionExpected = false
local selectionVisualOwned = false
local lifecycleToken = 0
local refreshInFlight = false
local selectionRefreshScheduled = false
local selectionHudSuppressed = false

local function selectionConfig()
  return Config.Selection or {}
end

local function debugLog(message, ...)
  if Config.Debug ~= true then return end
  print(('[MZ_MULTICHAR][CLIENT] ' .. message):format(...))
end

local function setSelectionHudSuppressed(suppressed, force)
  suppressed = suppressed == true
  if not force and selectionHudSuppressed == suppressed then return end
  selectionHudSuppressed = suppressed
  TriggerEvent('mz_hud:client:setSuppressed', 'mz_multichar', suppressed, {
    keepLogo = true
  })
  debugLog('hudMode=%s', suppressed and 'logo-only' or 'normal')
end

local function reportFailure(reason)
  print(('[MZ_MULTICHAR][CLIENT][ERROR] %s'):format(tostring(reason)))
  if lib and lib.notify then
    lib.notify({
      type = 'error',
      title = 'Selecao de personagem',
      description = 'O fluxo visual nao respondeu. Verifique o F8 e reconecte se ele nao se recuperar.'
    })
  end
end

local function presentationState(state)
  local brand = type(Config.Brand) == 'table' and Config.Brand or {}
  local presentation = type(state and state.presentation) == 'table' and state.presentation or {}
  local brandName = tostring(presentation.brandName or brand.name or 'MZ_CORE'):sub(1, 64)
  local out = {
    slots = tonumber(state and state.slots) or 0,
    usedSlots = tonumber(state and state.usedSlots) or 0,
    presentation = { brandName = brandName },
    characters = {}
  }
  for _, character in ipairs(type(state and state.characters) == 'table' and state.characters or {}) do
    out.characters[#out.characters + 1] = {
      characterId = tonumber(character.characterId),
      charinfo = type(character.charinfo) == 'table' and character.charinfo or {},
      createdAt = character.createdAt,
      updatedAt = character.updatedAt
    }
  end
  return out
end

local function cleanupSelectionVisuals()
  MZMulticharPreview.cleanup()
  MZMulticharCamera.destroy()
  MZMulticharScene.handoff()
  debugLog('selectionVisualCleanup')
end

local function prepareSelectionScene(state)
  selectionVisualOwned = true
  local sceneOk, sceneErr = MZMulticharScene.prepare()
  if not sceneOk then return false, sceneErr end

  local previewOk, previewResult = MZMulticharPreview.createAll(state and state.characters)
  if not previewOk then return false, previewResult end

  local cameraOk, cameraErr = MZMulticharCamera.startCinematic(false)
  if not cameraOk then return false, cameraErr end
  return true, previewResult
end

local function failSelectionVisual(reason)
  lifecycleToken = lifecycleToken + 1
  open = false
  nuiRendered = false
  SetNuiFocus(false, false)
  debugLog('nuiFocus=false')
  SendNUIMessage({ action = 'close' })
  cleanupSelectionVisuals()
  selectionVisualOwned = false
  MZMulticharScene.failSafe()
  reportFailure(reason)
  if nuiReady then
    SetNuiFocus(true, true)
    SendNUIMessage({
      action = 'error',
      message = tostring(reason or 'selection_visual_failed')
    })
    debugLog('nuiFocus=true errorState')
  end
end

local function startRenderWatchdog(token)
  local cfg = selectionConfig()
  local timeout = nuiReady
    and (tonumber(cfg.nuiRenderTimeoutMs) or 8000)
    or (tonumber(cfg.nuiReadyTimeoutMs) or 8000)
  SetTimeout(timeout, function()
    if token ~= lifecycleToken or not selectionExpected or nuiRendered then return end
    failSelectionVisual(nuiReady and 'nui_render_timeout' or 'nui_ready_timeout')
  end)
end

local function closeSelection(options)
  options = options or {}
  lifecycleToken = lifecycleToken + 1
  local wasOpen = open
  open = false
  nuiRendered = false
  pendingState = nil
  selectionExpected = false
  SetNuiFocus(false, false)
  if wasOpen or options.forceMessage then
    SendNUIMessage({ action = 'close' })
    debugLog('nuiClosed')
  end
  debugLog('nuiFocus=false')
  cleanupSelectionVisuals()

  if not options.forSpawn then
    setSelectionHudSuppressed(false)
  end

  if options.forSpawn then
    selectionVisualOwned = true
    return
  end

  if selectionVisualOwned then
    MZMulticharScene.release()
    selectionVisualOwned = false
    MZMulticharScene.fadeIn()
  end
end

local function beginTransition(kind)
  MZMulticharScene.fadeOut()
  open = false
  nuiRendered = false
  SetNuiFocus(false, false)
  debugLog('nuiFocus=false')
  SendNUIMessage({ action = 'close' })
  debugLog('nuiClosed transition=%s', kind)
  cleanupSelectionVisuals()

  lifecycleToken = lifecycleToken + 1
  local token = lifecycleToken
  SetTimeout(tonumber(selectionConfig().transitionTimeoutMs) or 15000, function()
    if token ~= lifecycleToken or not selectionExpected then return end
    failSelectionVisual(('%s_transition_timeout'):format(kind))
  end)
end

local function enterSelection(state)
  local cfg = selectionConfig()
  setSelectionHudSuppressed(true)
  debugLog('enterSelection')
  local prepared, prepareError = prepareSelectionScene(state)
  if not prepared then
    failSelectionVisual(prepareError or 'selection_scene_failed')
    return
  end

  open = true
  nuiRendered = false
  SetNuiFocus(true, true)
  debugLog('nuiFocus=true')
  SendNUIMessage({
    action = 'open',
    state = presentationState(state),
    debug = Config.Debug == true,
    requestTimeoutMs = tonumber(cfg.nuiRequestTimeoutMs) or 10000
  })
  debugLog('nuiMessageSent')
  if not MZMulticharScene.fadeIn() then
    failSelectionVisual('fade_in_timeout')
    return
  end

  lifecycleToken = lifecycleToken + 1
  startRenderWatchdog(lifecycleToken)
end

local function showSelection(state)
  pendingState = state
  selectionExpected = true

  if not nuiReady then
    local token = lifecycleToken + 1
    lifecycleToken = token
    startRenderWatchdog(token)
    return
  end

  if not open then
    enterSelection(state)
    return
  end

  nuiRendered = false
  SendNUIMessage({
    action = 'open',
    state = presentationState(state),
    debug = Config.Debug == true,
    requestTimeoutMs = tonumber(selectionConfig().nuiRequestTimeoutMs) or 10000
  })
  debugLog('nuiMessageSent')
  lifecycleToken = lifecycleToken + 1
  startRenderWatchdog(lifecycleToken)
end

local function refresh(openWhenReady, attempt)
  attempt = tonumber(attempt) or 1
  if refreshInFlight then
    debugLog('rosterRequestCoalesced')
    return
  end
  refreshInFlight = true
  debugLog('rosterRequested attempt=%s', attempt)
  local requestCompleted = false
  if openWhenReady then
    SetTimeout(tonumber(selectionConfig().nuiReadyTimeoutMs) or 8000, function()
      if requestCompleted or not selectionExpected or open or pendingState then return end
      failSelectionVisual('roster_request_timeout')
    end)
  end
  local callbackOk, state = pcall(function()
    return lib.callback.await('mz_multichar:server:getState', false)
  end)
  requestCompleted = true
  refreshInFlight = false

  if not callbackOk or not state or state.ok ~= true then
    local maximum = tonumber(selectionConfig().rosterMaxAttempts) or 5
    if openWhenReady and attempt < maximum then
      SetTimeout(tonumber(selectionConfig().rosterRetryMs) or 1500, function()
        refresh(true, attempt + 1)
      end)
    elseif openWhenReady then
      selectionExpected = true
      failSelectionVisual(('roster_request_failed error=%s'):format(
        tostring(callbackOk and state and state.error or state)
      ))
    end
    return
  end

  if state.data and state.data.active == true then
    closeSelection()
    return
  end
  if state.data and state.data.creating == true then
    closeSelection()
    return
  end

  local characters = state.data and state.data.characters
  debugLog('rosterReceived count=%s', type(characters) == 'table' and #characters or 0)
  showSelection(state.data or {})
end

RegisterNetEvent('mz_core:client:characterSelectionRequired', function()
  debugLog('characterSelectionRequired')
  if selectionRefreshScheduled or refreshInFlight or open or pendingState then
    debugLog('characterSelectionRequired duplicateIgnored')
    return
  end
  setSelectionHudSuppressed(true)
  selectionExpected = true
  selectionRefreshScheduled = true
  CreateThread(function()
    selectionRefreshScheduled = false
    refresh(true, 1)
  end)
end)

RegisterNetEvent('mz_core:client:playerLoaded', function()
  if not selectionExpected and not open and not pendingState then return end
  debugLog('spawnStart')
  MZMulticharScene.fadeOut()
  closeSelection({ forSpawn = true })
  local token = lifecycleToken
  SetTimeout(tonumber(selectionConfig().spawnTimeoutMs) or 20000, function()
    if token ~= lifecycleToken or not selectionVisualOwned then return end
    failSelectionVisual('spawn_timeout')
  end)
end)

RegisterNetEvent('mz_core:client:pedModelReady', function(payload)
  if type(payload) ~= 'table' or payload.reason ~= 'core_spawn_complete' then return end
  debugLog('spawnComplete')
  lifecycleToken = lifecycleToken + 1
  selectionVisualOwned = false
  MZMulticharScene.coreSpawnComplete()
  MZMulticharScene.fadeIn()
  setSelectionHudSuppressed(false)
end)

RegisterNUICallback('ready', function(_, cb)
  nuiReady = true
  debugLog('nuiReady')
  cb({
    ok = true,
    debug = Config.Debug == true,
    requestTimeoutMs = tonumber(selectionConfig().nuiRequestTimeoutMs) or 10000
  })
  if pendingState then
    showSelection(pendingState)
  end
end)

RegisterNUICallback('rendered', function(data, cb)
  if not selectionExpected or not open then
    cb({ ok = false, error = 'selection_not_open' })
    return
  end
  nuiRendered = true
  debugLog('nuiRendered count=%s', tostring(data and data.count or 0))
  cb({ ok = true })
end)

RegisterNUICallback('refresh', function(_, cb)
  local callbackOk, state = pcall(function()
    return lib.callback.await('mz_multichar:server:getState', false)
  end)
  if callbackOk and state and state.ok == true and type(state.data) == 'table'
    and state.data.active ~= true and state.data.creating ~= true then
    local fullState = state.data
    state.data = presentationState(state.data)
    showSelection(fullState)
  end
  cb(callbackOk and state or { ok = false, error = 'request_failed' })
end)

RegisterNUICallback('focus', function(data, cb)
  if not selectionExpected or not open or not nuiRendered then
    cb({ ok = false, error = 'selection_not_ready' })
    return
  end

  local characterId = tonumber(data and data.characterId)
  if not characterId then
    local resumed, resumeErr = MZMulticharCamera.resumeCinematic()
    cb({ ok = resumed == true, error = resumed == true and nil or resumeErr })
    return
  end

  local owned = false
  for _, character in ipairs(type(pendingState and pendingState.characters) == 'table'
    and pendingState.characters or {}) do
    if tonumber(character.characterId) == characterId then owned = true break end
  end
  if not owned then
    cb({ ok = false, error = 'character_not_in_roster' })
    return
  end

  local focused, focusErr = MZMulticharCamera.focus(characterId)
  cb({ ok = focused == true, error = focused == true and nil or focusErr })
end)

RegisterNUICallback('select', function(data, cb)
  local previousState = pendingState
  debugLog('characterSelected characterId=%s', tostring(data and data.characterId))
  beginTransition('select')
  local callbackOk, result = pcall(function()
    return lib.callback.await('mz_multichar:server:select', false, {
      characterId = data and data.characterId,
      requestId = data and data.requestId
    })
  end)
  result = callbackOk and result or { ok = false, error = 'request_failed' }
  if not result or result.ok ~= true then
    showSelection(previousState or {})
  end
  cb(result or { ok = false, error = 'request_failed' })
end)

RegisterNUICallback('create', function(data, cb)
  local previousState = pendingState
  beginTransition('create')
  local callbackOk, result = pcall(function()
    return lib.callback.await('mz_multichar:server:create', false, {
      requestId = data and data.requestId
    })
  end)
  result = callbackOk and result or { ok = false, error = 'request_failed' }
  if result and result.ok == true then
    lifecycleToken = lifecycleToken + 1
    selectionExpected = false
    pendingState = nil
    selectionVisualOwned = false
    MZMulticharScene.creatorHandoffComplete()
    setSelectionHudSuppressed(false)
  else
    showSelection(previousState or {})
  end
  cb(result or { ok = false, error = 'request_failed' })
end)

RegisterNUICallback('close', function(_, cb)
  cb({ ok = false, error = 'active_character_required' })
end)

AddEventHandler('onClientResourceStart', function(resourceName)
  if resourceName == 'mz_hud' and selectionHudSuppressed then
    setSelectionHudSuppressed(true, true)
    return
  end
  if resourceName ~= GetCurrentResourceName() then return end
  debugLog('selectionClientReady')
  TriggerServerEvent('mz_multichar:server:selectionClientReady')
end)

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then return end
  closeSelection({ forceMessage = true })
  nuiReady = false
end)
