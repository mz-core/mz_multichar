local function closedPayload(payload, allowed, maximumFields)
  if type(payload) ~= 'table' then return false end
  local count = 0
  for key in pairs(payload) do
    count = count + 1
    if count > maximumFields or allowed[key] ~= true then return false end
  end
  return true
end

local function requestKey(value)
  value = tostring(value or '')
  if #value < 8 or #value > 96 or not value:match('^[%w%._:%-]+$') then return nil end
  return value
end

local function debugSession(eventName, source, requestedCharacterId, errorCode)
  if not Config or Config.Debug ~= true then return end
  local ok, session = pcall(function()
    return exports['mz_core']:GetPlayerSession(source)
  end)
  if not ok then session = nil end
  print(('[MZ_MULTICHAR][SERVER] %s source=%s accountId=%s characterId=%s sessionId=%s lifecycle=%s isActive=%s activeCharacterId=%s error=%s'):format(
    tostring(eventName),
    tostring(source),
    tostring(session and session.accountId or 'nil'),
    tostring(requestedCharacterId or (session and session.characterId) or 'nil'),
    tostring(session and (session.id or session.sessionId) or 'nil'),
    tostring(session and session.lifecycle or 'nil'),
    tostring(session and session.isActive == true),
    tostring(session and session.activeCharacterId or 'nil'),
    tostring(errorCode or 'nil')
  ))
end

local selectionReadyAttempts = {}

local function cleanBrandName(value)
  value = tostring(value or '')
    :gsub('[%c]', ' ')
    :gsub('%s+', ' ')
    :match('^%s*(.-)%s*$') or ''
  return value:sub(1, 64)
end

local function selectionBrandName()
  local brand = type(Config.Brand) == 'table' and Config.Brand or {}
  if brand.useServerProjectName ~= false then
    local projectName = cleanBrandName(GetConvar('sv_projectName', ''))
    if projectName ~= '' then return projectName end
  end

  local configured = cleanBrandName(brand.name)
  return configured ~= '' and configured or 'MZ_CORE'
end

local function attachPreviewAppearances(roster)
  if type(roster) ~= 'table' then return roster end
  roster.presentation = { brandName = selectionBrandName() }
  if type(roster.characters) ~= 'table' then return roster end
  for _, character in ipairs(roster.characters) do
    local citizenid = type(character) == 'table' and tostring(character.citizenid or '') or ''
    if citizenid ~= '' then
      local ok, saved = pcall(function()
        return exports['mz_creator']:GetAppearance(citizenid)
      end)
      if ok and type(saved) == 'table' and type(saved.appearance_json) == 'table' then
        character.previewAppearance = saved.appearance_json
      end
    end
  end
  return roster
end

local function replaySelectionSignal(source, eventName)
  local ok, session = pcall(function()
    return exports['mz_core']:GetPlayerSession(source)
  end)
  if not ok or not session then
    debugSession(eventName or 'selectionSignalReplayFailed', source, nil,
      ok and 'session_unavailable' or 'core_unavailable')
    return false
  end
  if session.lifecycle ~= 'CHARACTER_SELECTION' or session.activeCharacterId then
    debugSession(eventName or 'selectionSignalReplayIgnored', source, nil, 'selection_not_required')
    return false
  end

  debugSession(eventName or 'selectionSignalReplayed', source)
  TriggerClientEvent('mz_core:client:characterSelectionRequired', source, {
    accountId = session.accountId,
    sessionId = session.id or session.sessionId,
    lifecycle = session.lifecycle
  })
  return true
end

lib.callback.register('mz_multichar:server:getState', function(source)
  local activeOk, active = pcall(function()
    return exports['mz_core']:IsCharacterActive(source)
  end)
  if activeOk and active == true then
    return { ok = true, data = { active = true } }
  end

  debugSession('rosterRequest', source)
  local ok, roster, err = pcall(function()
    return exports['mz_core']:GetCharacterRosterForSource(source)
  end)
  if not ok then
    debugSession('rosterRequestFailed', source, nil, 'core_unavailable')
    return { ok = false, error = 'core_unavailable' }
  end
  if not roster then
    debugSession('rosterRequestFailed', source, nil, err or 'session_unavailable')
    return { ok = false, error = err or 'session_unavailable' }
  end
  if roster.lifecycle == 'CHARACTER_CREATING' then
    local pendingOk, pending = pcall(function()
      return exports['mz_core']:GetPendingCharacterSnapshot(source)
    end)
    if pendingOk and pending then
      pcall(function() exports['mz_creator']:OpenCreator(source, 'multichar_create') end)
      return { ok = true, data = { creating = true, lifecycle = roster.lifecycle } }
    end
  end
  return { ok = true, data = attachPreviewAppearances(roster) }
end)

lib.callback.register('mz_multichar:server:select', function(source, payload)
  if not closedPayload(payload, { characterId = true, requestId = true }, 2) then
    return { ok = false, error = 'invalid_payload' }
  end
  local characterId = tonumber(payload.characterId)
  local correlation = requestKey(payload.requestId)
  if not characterId or characterId <= 0 or characterId % 1 ~= 0 or not correlation then
    return { ok = false, error = 'invalid_payload' }
  end
  local ok, player, err = pcall(function()
    return exports['mz_core']:ActivateCharacter(source, characterId, correlation)
  end)
  if not ok then
    debugSession('activateCharacterFailed', source, characterId, 'core_unavailable')
    return { ok = false, error = 'core_unavailable' }
  end
  if not player then
    debugSession('activateCharacterFailed', source, characterId, err or 'activation_failed')
    return { ok = false, error = err or 'activation_failed' }
  end
  return { ok = true, data = player }
end)

lib.callback.register('mz_multichar:server:create', function(source, payload)
  if not closedPayload(payload, { requestId = true }, 1) then
    return { ok = false, error = 'invalid_payload' }
  end
  local correlation = requestKey(payload.requestId)
  if not correlation then return { ok = false, error = 'invalid_payload' } end
  local ok, draft, err = pcall(function()
    return exports['mz_core']:CreateCharacterDraft(source, correlation)
  end)
  if not ok then return { ok = false, error = 'core_unavailable' } end
  if not draft then return { ok = false, error = err or 'create_failed' } end

  local creatorOk, opened = pcall(function()
    return exports['mz_creator']:OpenCreator(source, 'multichar_create')
  end)
  if not creatorOk or opened ~= true then
    pcall(function() exports['mz_core']:CancelPendingCharacter(source) end)
    return { ok = false, error = 'creator_unavailable' }
  end
  return { ok = true, data = draft }
end)

RegisterNetEvent('mz_multichar:server:selectionClientReady', function()
  local source = tonumber(source)
  if not source or source <= 0 then return end
  local now = GetGameTimer()
  local previous = selectionReadyAttempts[source]
  if previous and now >= previous and now - previous < 1000 then return end
  selectionReadyAttempts[source] = now
  replaySelectionSignal(source, 'selectionClientReady')
end)

AddEventHandler('playerDropped', function()
  local sourceId = tonumber(source)
  if sourceId then selectionReadyAttempts[sourceId] = nil end
end)

AddEventHandler('onResourceStart', function(resourceName)
  if resourceName ~= GetCurrentResourceName() and resourceName ~= 'mz_creator' then return end
  CreateThread(function()
    Wait(1000)
    for _, source in ipairs(GetPlayers()) do
      source = tonumber(source)
      local ok, session = pcall(function() return exports['mz_core']:GetPlayerSession(source) end)
      if ok and session and session.lifecycle == 'CHARACTER_CREATING' then
        pcall(function() exports['mz_creator']:OpenCreator(source, 'multichar_create') end)
      elseif ok and session and session.lifecycle == 'CHARACTER_SELECTION'
        and not session.activeCharacterId then
        replaySelectionSignal(source, 'characterSelectionRecovery')
      end
    end
  end)
end)
