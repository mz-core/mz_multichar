MZMulticharPreview = {
  entries = {},
  order = {}
}

local function sceneConfig()
  return Config.SelectionScene or {}
end

local function debugLog(message, ...)
  if Config.Debug ~= true then return end
  print(('[MZ_MULTICHAR][PREVIEW] ' .. message):format(...))
end

local function integerOr(value, fallback)
  value = tonumber(value)
  if not value then return fallback end
  return math.floor(value)
end

local function numberOr(value, fallback)
  return tonumber(value) or fallback
end

local function femaleCharacter(character)
  local gender = tostring(character and character.charinfo and character.charinfo.gender or ''):lower()
  return gender == 'f' or gender == 'female' or gender == 'feminino' or gender == '1'
end

local function resolveModel(character, appearance)
  local requested = type(appearance) == 'table' and tostring(appearance.model or '') or ''
  if MZCreatorSchema and MZCreatorSchema.allowedModels and MZCreatorSchema.allowedModels[requested] then
    return requested
  end
  return femaleCharacter(character) and 'mp_f_freemode_01' or 'mp_m_freemode_01'
end

local function loadModel(model)
  local hash = GetHashKey(model)
  if not MZMulticharNativeTrue(IsModelInCdimage(hash)) or not MZMulticharNativeTrue(IsModelValid(hash)) then
    return nil, 'invalid_model'
  end
  RequestModel(hash)
  local deadline = GetGameTimer() + (tonumber(sceneConfig().modelTimeoutMs) or 5000)
  while not MZMulticharNativeTrue(HasModelLoaded(hash)) and GetGameTimer() < deadline do Wait(25) end
  if not MZMulticharNativeTrue(HasModelLoaded(hash)) then return nil, 'model_load_timeout' end
  return hash
end

local function applyAppearance(ped, appearance)
  if type(appearance) ~= 'table' then
    SetPedDefaultComponentVariation(ped)
    ClearAllPedProps(ped)
    return true, 'default'
  end
  if type(appearance.appearance_json) == 'table' then appearance = appearance.appearance_json end

  local schema = MZCreatorSchema or {}
  local blend = appearance.headBlend or {}
  SetPedHeadBlendData(
    ped,
    integerOr(blend.shapeFirst, 0), integerOr(blend.shapeSecond, 21), integerOr(blend.shapeThird, 0),
    integerOr(blend.skinFirst, 0), integerOr(blend.skinSecond, 21), integerOr(blend.skinThird, 0),
    numberOr(blend.shapeMix, 0.5) + 0.0, numberOr(blend.skinMix, 0.5) + 0.0,
    numberOr(blend.thirdMix, 0.0) + 0.0, false
  )

  for _, feature in ipairs(schema.faceFeatureOrder or {}) do
    SetPedFaceFeature(ped, feature.index, numberOr((appearance.faceFeatures or {})[feature.key], 0.0) + 0.0)
  end
  for _, definition in ipairs(schema.headOverlayOrder or {}) do
    local overlay = (appearance.headOverlays or {})[definition.key] or {}
    local style = integerOr(overlay.style, 0)
    SetPedHeadOverlay(ped, definition.index, style, numberOr(overlay.opacity, 0.0) + 0.0)
    if definition.colorType then
      local color = integerOr(overlay.color, 0)
      SetPedHeadOverlayColor(ped, definition.index, definition.colorType, color,
        integerOr(overlay.secondaryColor, color))
    end
  end

  local hair = appearance.hair or {}
  SetPedComponentVariation(ped, 2, integerOr(hair.style, 0), integerOr(hair.texture, 0), 2)
  SetPedHairColor(ped, integerOr(hair.color, 0), integerOr(hair.highlight, 0))
  SetPedEyeColor(ped, integerOr(appearance.eyeColor, 0))

  for id in pairs(schema.componentIds or {}) do
    local value = (appearance.components or {})[id]
    if value then
      SetPedComponentVariation(ped, tonumber(id), integerOr(value.drawable, 0), integerOr(value.texture, 0), 2)
    end
  end
  ClearAllPedProps(ped)
  for id in pairs(schema.propIds or {}) do
    local value = (appearance.props or {})[id]
    local propId = tonumber(id)
    if value and propId then
      local drawable = integerOr(value.drawable, -1)
      if drawable < 0 then ClearPedProp(ped, propId)
      else SetPedPropIndex(ped, propId, drawable, integerOr(value.texture, 0), true) end
    end
  end
  return true, 'saved'
end

local function playPose(ped, animation)
  if type(animation) ~= 'table' or type(animation.dict) ~= 'string' or type(animation.name) ~= 'string' then
    return true
  end
  RequestAnimDict(animation.dict)
  local deadline = GetGameTimer() + (tonumber(sceneConfig().animationTimeoutMs) or 2500)
  while not MZMulticharNativeTrue(HasAnimDictLoaded(animation.dict)) and GetGameTimer() < deadline do Wait(25) end
  if not MZMulticharNativeTrue(HasAnimDictLoaded(animation.dict)) then return false end
  TaskPlayAnim(ped, animation.dict, animation.name, 8.0, -8.0, -1, 1, 0.0, false, false, false)
  SetPedKeepTask(ped, true)
  return true
end

local function slotZ(slot, character)
  local z = slot.coords and slot.coords.z
  if type(slot.zByGender) == 'table' then
    z = femaleCharacter(character) and slot.zByGender.female or slot.zByGender.male
  end
  return numberOr(z, 0.0) + numberOr(slot.zOffset, 0.0)
end

local function createPreview(character, slot, slotIndex)
  local appearance = character.previewAppearance
  local model = resolveModel(character, appearance)
  local hash, modelErr = loadModel(model)
  if not hash then return nil, modelErr end

  local coords = slot.coords or {}
  local ped = CreatePed(
    4, hash,
    numberOr(coords.x, 0.0), numberOr(coords.y, 0.0), slotZ(slot, character),
    numberOr(slot.heading, 0.0), false, false
  )
  if not ped or ped == 0 or not MZMulticharNativeTrue(DoesEntityExist(ped)) then
    SetModelAsNoLongerNeeded(hash)
    return nil, 'ped_creation_failed'
  end
  if MZMulticharNativeTrue(NetworkGetEntityIsNetworked(ped)) then
    DeleteEntity(ped)
    SetModelAsNoLongerNeeded(hash)
    return nil, 'preview_ped_networked'
  end

  SetEntityAsMissionEntity(ped, true, true)
  SetEntityInvincible(ped, true)
  SetEntityCollision(ped, false, false)
  SetEntityVisible(ped, true, false)
  FreezeEntityPosition(ped, true)
  SetBlockingOfNonTemporaryEvents(ped, true)
  SetPedCanRagdoll(ped, false)
  SetPedDiesWhenInjured(ped, false)
  SetPedFleeAttributes(ped, 0, false)
  SetPedCombatAttributes(ped, 17, true)

  local appearanceOk, appearanceMode = applyAppearance(ped, appearance)
  if not appearanceOk then
    DeleteEntity(ped)
    SetModelAsNoLongerNeeded(hash)
    return nil, 'appearance_apply_failed'
  end
  playPose(ped, slot.animation)
  SetModelAsNoLongerNeeded(hash)

  local characterId = tonumber(character.characterId)
  local entry = { ped = ped, characterId = characterId, slot = slot, slotIndex = slotIndex }
  debugLog('created characterId=%s slot=%s', tostring(characterId), tostring(slotIndex))
  debugLog('appearanceApplied characterId=%s mode=%s', tostring(characterId), tostring(appearanceMode))
  return entry
end

function MZMulticharPreview.createAll(characters)
  MZMulticharPreview.cleanup(true)
  characters = type(characters) == 'table' and characters or {}
  local slots = sceneConfig().slots or {}
  local maximum = math.min(#characters, #slots, tonumber(sceneConfig().maxPreviewPeds) or 5)
  for index = 1, maximum do
    local character = characters[index]
    local characterId = tonumber(character and character.characterId)
    if not characterId then
      MZMulticharPreview.cleanup()
      return false, 'invalid_preview_character'
    end
    local entry, err = createPreview(character, slots[index], index)
    if not entry then
      MZMulticharPreview.cleanup()
      return false, err
    end
    MZMulticharPreview.entries[characterId] = entry
    MZMulticharPreview.order[#MZMulticharPreview.order + 1] = characterId
  end
  return true, maximum
end

function MZMulticharPreview.get(characterId)
  return MZMulticharPreview.entries[tonumber(characterId)]
end

function MZMulticharPreview.cleanup(silent)
  local count = 0
  for _, entry in pairs(MZMulticharPreview.entries) do
    local ped = entry and entry.ped
    if ped and ped ~= 0 and MZMulticharNativeTrue(DoesEntityExist(ped)) then
      ClearPedTasksImmediately(ped)
      DeleteEntity(ped)
      count = count + 1
    end
  end
  MZMulticharPreview.entries = {}
  MZMulticharPreview.order = {}
  if silent ~= true then debugLog('cleanup count=%s', tostring(count)) end
  return count
end
