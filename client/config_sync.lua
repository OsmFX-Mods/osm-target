Appearance = {
  design = Config.Design,
  tunables = {},
  designs = {},
  -- Anchor offset: world point fraction relative to sprite center
  anchor = { x = 0.0, y = 0.0 },
  prefs = {
    scale = 100,
    volume = 70,
    muted = false,
    reducedMotion = false,
  },
}

-- Validate initial design: fallback to default if configured design is not installed
if not OsmTargetDesigns.exists(Appearance.design) then
  Appearance.design = OsmTargetDesigns.fallback() or Appearance.design
end

local function applySystem(system)
  if type(system) ~= 'table' then return end

  local interaction = Config.Interaction
  if system.interactDistance ~= nil then interaction.distance = system.interactDistance end
  if system.raycastDistance ~= nil then interaction.raycastDistance = system.raycastDistance end
  if system.scanInterval ~= nil then interaction.scanInterval = system.scanInterval end
  if system.snapAngle ~= nil then interaction.snapAngle = system.snapAngle end
  if system.releaseAngle ~= nil then interaction.releaseAngle = system.releaseAngle end
  if system.releaseTime ~= nil then interaction.releaseTime = system.releaseTime end
  if system.openTime ~= nil then interaction.openTime = system.openTime end
  if system.closeTime ~= nil then interaction.closeTime = system.closeTime end
  if system.globalsWithoutTarget ~= nil then interaction.globalsWithoutTarget = system.globalsWithoutTarget and true or false end

  local indicators = Config.Indicators
  if system.indicatorsEnabled ~= nil then indicators.enabled = system.indicatorsEnabled and true or false end
  if system.indicatorRadius ~= nil then indicators.radius = system.indicatorRadius end
  if system.indicatorCap ~= nil then indicators.cap = system.indicatorCap end
  if system.indicatorInterval ~= nil then indicators.discoveryInterval = system.indicatorInterval end
  if system.indicatorNearAngle ~= nil then indicators.nearAngle = system.indicatorNearAngle end
  if system.includeGlobals ~= nil then indicators.includeGlobals = system.includeGlobals and true or false end

  local render = Config.Render
  if system.menuSize ~= nil then render.menuSize = system.menuSize end
  if system.indicatorSize ~= nil then render.indicatorSize = system.indicatorSize end
  if system.cursorSize ~= nil then render.cursorSize = system.cursorSize end
  if system.referenceDistance ~= nil then render.referenceDistance = system.referenceDistance end
  if system.scaleExponent ~= nil then render.scaleExponent = system.scaleExponent end
  if system.scaleMin ~= nil then render.scaleMin = system.scaleMin end
  if system.scaleMax ~= nil then render.scaleMax = system.scaleMax end
  if system.anchorLift ~= nil then render.anchorLift = system.anchorLift end

  local options = Config.Options
  if system.showDisabled ~= nil then options.showDisabled = system.showDisabled and true or false end
  if system.hideUnexplained ~= nil then options.hideUnexplained = system.hideUnexplained and true or false end
  if system.focusDisabled ~= nil then options.focusDisabled = system.focusDisabled and true or false end
  if system.defaultDistance ~= nil then options.defaultDistance = system.defaultDistance end

  -- Update interaction mode: apply hold or toggle preference
  if system.holdMode then Config.Input.mode = system.holdMode end

  -- Store keybind default: persist key identifier for future sessions
  if system.interactKey then Config.Input.key = system.interactKey end

  if system.debug ~= nil then Config.Debug = system.debug and true or false end
  if system.locale then Config.Locale = system.locale end
end

RegisterNetEvent('osm-target:cl:config', function(payload)
  if type(payload) ~= 'table' then return end

  Appearance.design = payload.design or Appearance.design
  Appearance.tunables = payload.tunables or Appearance.tunables
  Appearance.designs = payload.designs or Appearance.designs
  Appearance.anchor = payload.anchor or Appearance.anchor

  applySystem(payload.system)

  -- Reset active interaction: close open menu before applying new appearance settings
  Machine.abort()
  Surfaces.applyAppearance()
end)

-- Request initial configuration: notify server on client startup
local configRequested = false

AddEventHandler('onClientResourceStart', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  configRequested = true
  TriggerServerEvent('osm-target:sv:clientReady')
end)

CreateThread(function()
  Wait(1500)
  if not configRequested then
    TriggerServerEvent('osm-target:sv:clientReady')
  end
end)
