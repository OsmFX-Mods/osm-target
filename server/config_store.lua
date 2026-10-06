local Designs = OsmTargetDesigns

ConfigStore = {}

local current
local manifest

---Get default system settings: initialize fallback values from config.lua.
local function defaultSystem()
  return {
    interactDistance = Config.Interaction.distance,
    raycastDistance = Config.Interaction.raycastDistance,
    scanInterval = Config.Interaction.scanInterval,
    snapAngle = Config.Interaction.snapAngle,
    releaseAngle = Config.Interaction.releaseAngle,
    releaseTime = Config.Interaction.releaseTime,
    openTime = Config.Interaction.openTime,
    closeTime = Config.Interaction.closeTime,
    globalsWithoutTarget = Config.Interaction.globalsWithoutTarget,

    indicatorsEnabled = Config.Indicators.enabled,
    indicatorRadius = Config.Indicators.radius,
    indicatorCap = Config.Indicators.cap,
    indicatorInterval = Config.Indicators.discoveryInterval,
    indicatorNearAngle = Config.Indicators.nearAngle,
    includeGlobals = Config.Indicators.includeGlobals,

    menuSize = Config.Render.menuSize,
    indicatorSize = Config.Render.indicatorSize,
    cursorSize = Config.Render.cursorSize,
    referenceDistance = Config.Render.referenceDistance,
    scaleExponent = Config.Render.scaleExponent,
    scaleMin = Config.Render.scaleMin,
    scaleMax = Config.Render.scaleMax,
    anchorLift = Config.Render.anchorLift,

    holdMode = Config.Input.mode,
    interactKey = Config.Input.key,

    showDisabled = Config.Options.showDisabled,
    hideUnexplained = Config.Options.hideUnexplained,
    focusDisabled = Config.Options.focusDisabled,
    defaultDistance = Config.Options.defaultDistance,

    locale = Config.Locale,
    debug = Config.Debug,
  }
end

-- System parameter boundaries: define valid numerical limits for system settings
local SYSTEM_BOUNDS = {
  interactDistance = { 1.0, 20.0 },
  raycastDistance = { 2.0, 40.0 },
  scanInterval = { 0, 250 },
  snapAngle = { 1.0, 20.0 },
  releaseAngle = { 2.0, 45.0 },
  releaseTime = { 0, 1500 },
  openTime = { 0, 1200 },
  closeTime = { 0, 1200 },
  indicatorRadius = { 1.0, 20.0 },
  indicatorCap = { 1, 24 },
  indicatorInterval = { 60, 2000 },
  indicatorNearAngle = { 2.0, 60.0 },
  menuSize = { 0.1, 1.2 },
  indicatorSize = { 0.005, 0.2 },
  cursorSize = { 0.005, 0.2 },
  referenceDistance = { 0.5, 12.0 },
  scaleExponent = { 0.0, 2.0 },
  scaleMin = { 0.1, 2.0 },
  scaleMax = { 0.1, 4.0 },
  anchorLift = { -2.0, 4.0 },
  defaultDistance = { 1.0, 20.0 },
}

local BOOLEAN_KEYS = {
  'globalsWithoutTarget', 'indicatorsEnabled', 'includeGlobals', 'showDisabled', 'hideUnexplained', 'focusDisabled', 'debug',
}

local function sanitiseSystem(system)
  local out = defaultSystem()
  if type(system) ~= 'table' then return out end

  for key, bounds in pairs(SYSTEM_BOUNDS) do
    local value = tonumber(system[key])
    if value then
      if value < bounds[1] then value = bounds[1] end
      if value > bounds[2] then value = bounds[2] end
      out[key] = value
    end
  end

  for i = 1, #BOOLEAN_KEYS do
    local key = BOOLEAN_KEYS[i]
    if system[key] ~= nil then out[key] = system[key] and true or false end
  end

  if system.holdMode == 'hold' or system.holdMode == 'toggle' then out.holdMode = system.holdMode end
  if type(system.interactKey) == 'string' and #system.interactKey <= 16 then out.interactKey = system.interactKey end
  if type(system.locale) == 'string' and #system.locale <= 8 then out.locale = system.locale end

  -- Ensure hysteresis bounds: enforce release angle exceeding snap angle
  if out.releaseAngle <= out.snapAngle then out.releaseAngle = out.snapAngle + 2.0 end
  if out.indicatorNearAngle < out.snapAngle then out.indicatorNearAngle = out.snapAngle + 2.0 end
  if out.scaleMax < out.scaleMin then out.scaleMax = out.scaleMin end

  return out
end

local function defaultConfig()
  local designs = {}
  for i = 1, #Designs.order do
    local id = Designs.order[i]
    designs[id] = Designs.defaults(id)
  end

  return {
    design = Designs.fallback(),
    designs = designs,
    system = defaultSystem(),
  }
end

---Sanitize configuration payload: validate design selection, tunables, and system settings.
function ConfigStore.sanitise(payload)
  payload = type(payload) == 'table' and payload or {}

  local out = { designs = {} }

  out.design = Designs.exists(payload.design) and payload.design or Designs.fallback()

  local given = type(payload.designs) == 'table' and payload.designs or {}
  for i = 1, #Designs.order do
    local id = Designs.order[i]
    out.designs[id] = Designs.sanitise(id, given[id])
  end

  -- Preserve tunables for uninstalled designs: retain configuration across pack removals
  for id, tunables in pairs(given) do
    if not out.designs[id] and type(tunables) == 'table' then
      out.designs[id] = tunables
    end
  end

  out.system = sanitiseSystem(payload.system)

  return out
end

function ConfigStore.get() return current end

---Build client configuration payload: assemble active design, tunables, anchor, and manifest.
local function clientPayload()
  return {
    design = current.design,
    tunables = current.designs[current.design],
    -- Compute dynamic anchor bias: resolve anchor offset for active design
    anchor = Designs.anchorFor(current.design, current.designs[current.design]),
    system = current.system,
    designs = manifest,
  }
end

function ConfigStore.broadcast(target)
  if not current then return end
  TriggerClientEvent('osm-target:cl:config', target or -1, clientPayload())
end

function ConfigStore.save(payload, author)
  current = ConfigStore.sanitise(payload)
  DB.Save(current, author)
  ConfigStore.broadcast(-1)
  return current
end

function ConfigStore.revertDesign(designId, author)
  if not current or not Designs.exists(designId) then return nil end

  current.designs[designId] = Designs.defaults(designId)
  DB.Save(current, author)
  ConfigStore.broadcast(-1)
  return current
end

CreateThread(function()
  while not (Bridge and Bridge.Ready) do Wait(100) end

  DB.Init()
  manifest = Designs.manifest()

  local stored = DB.LoadLatest()

  if stored then
    current = ConfigStore.sanitise(stored)
  else
    current = defaultConfig()
    DB.Save(current, 'install')
  end

  ConfigStore.broadcast(-1)
  print(('^2[osm-target] Configuration loaded (design: %s).^7'):format(current.design))
end)

RegisterNetEvent('osm-target:sv:clientReady', function()
  if current then ConfigStore.broadcast(source) end
end)
