local Resolver = OsmTargetResolver

Machine = {}

local IDLE, SWEEPING, MAGNETISED, MENU_OPEN, RELEASING = 'IDLE', 'SWEEPING', 'MAGNETISED', 'MENU_OPEN', 'RELEASING'

local state = IDLE
local disabled = false
local requested = false          -- Targeting key is currently down or toggle is active

local target                     -- Active locked or hovered target descriptor
local resolved = {}              -- Resolved options for active target
local focus = 1
local menuName = nil             -- Active submenu identifier
local menuHistory = {}

local anchor                     -- World position where interface surface is anchored
local stateSince = 0
local releaseSince = nil
local lastRevalidate = 0
local lastScan = 0

-- Indicator hysteresis: angular tolerance preventing texture swapping on minor mouse movement
local NEAR_HYSTERESIS = 3.0

---Track indicator near states: preserve near focus state across discovery passes.
---@type table<any, boolean>
local nearState = {}

local function pointKey(point)
  if point.zone then return 'zone:' .. tostring(point.zone.id) end
  return point.entity or 0
end

local rad = math.rad
local deg = math.deg
local acos = math.acos

local function cameraBasis()
  local origin = GetFinalRenderedCamCoord()
  local rot = GetFinalRenderedCamRot(2)
  local pitch, yaw = rad(rot.x), rad(rot.z)
  local cosPitch = math.abs(math.cos(pitch))

  return origin, vec3(-math.sin(yaw) * cosPitch, math.cos(yaw) * cosPitch, math.sin(pitch))
end

local function angleTo(origin, forward, point)
  local dx, dy, dz = point.x - origin.x, point.y - origin.y, point.z - origin.z
  local length = math.sqrt(dx * dx + dy * dy + dz * dz)
  if length < 0.01 then return 0.0 end

  local dot = (dx * forward.x + dy * forward.y + dz * forward.z) / length
  if dot > 1.0 then dot = 1.0 elseif dot < -1.0 then dot = -1.0 end
  return deg(acos(dot))
end

local function setState(next)
  state = next
  stateSince = GetGameTimer()
end

function Machine.isActive()  return state ~= IDLE end
function Machine.hasMenu()   return state == MENU_OPEN end
function Machine.state()     return state end

function Machine.setDisabled(value)
  disabled = value and true or false
  if disabled then Machine.abort() end
end

function Machine.isDisabled() return disabled end

local function sendMenu()
  Surfaces.send('menu', 'menu:open', {
    options = Resolver.toPayload(resolved),
    focus = focus,
    menu = menuName,
    empty = #resolved == 0,
    emptyLabel = Locale('no_options'),
  })
end

local function sendFocus()
  Surfaces.send('menu', 'menu:focus', { focus = focus })
end

---Find next focusable option: iterate options in direction to locate focusable entry.
local function nextFocusable(from, direction)
  local count = #resolved
  if count == 0 then return 1 end

  local index = from
  for _ = 1, count do
    index = index + direction
    if index > count then index = 1 elseif index < 1 then index = count end
    if resolved[index].focusable then return index end
  end
  return from
end

local function firstFocusable()
  for i = 1, #resolved do
    if resolved[i].focusable then return i end
  end
  return 1
end

---Build callback response table: construct context payload for onSelect handler.
local function buildResponse(option, forServer)
  local response = {}
  for key, value in pairs(option) do
    response[key] = value
  end

  response.entity = target and target.entity ~= 0 and target.entity or nil
  response.coords = anchor or (target and target.coords) or nil
  response.distance = target and target.distance or nil
  response.zone = target and target.zone and target.zone.id or nil

  if forServer then
    if response.entity then
      response.entity = NetworkGetEntityIsNetworked(response.entity)
        and NetworkGetNetworkIdFromEntity(response.entity) or 0
    end

    -- Strip function fields: prevent serialization errors when transmitting response to server
    for key, value in pairs(response) do
      if type(value) == 'function' then response[key] = nil end
    end
  end

  response.icon, response.iconColor = nil, nil
  response.groups, response.gangs, response.items, response.anyItem = nil, nil, nil, nil
  response.excludeGroups, response.excludeGangs = nil, nil
  response.jobTypes, response.excludeJobTypes = nil, nil
  response.canInteract, response.onSelect = nil, nil
  response.export, response.event, response.serverEvent = nil, nil, nil
  response.command, response.qbCommand = nil, nil
  response.dialect, response.qb, response.qtarget = nil, nil, nil

  return response
end

---Execute callback: handle dialect-specific parameter requirements.
local function execute(option)
  if option.onSelect then
    if option.qb or option.qtarget then
      option.onSelect(target and target.entity ~= 0 and target.entity or nil)
    else
      option.onSelect(buildResponse(option))
    end
  elseif option.export then
    local resource = option.resource or (target and target.zone and target.zone.resource)
    if resource then
      exports[resource][option.export](nil, buildResponse(option))
    end
  elseif option.event then
    TriggerEvent(option.event, buildResponse(option))
  elseif option.serverEvent then
    TriggerServerEvent(option.serverEvent, buildResponse(option, true))
  elseif option.command then
    ExecuteCommand(option.command)
  elseif option.qbCommand then
    TriggerServerEvent('QBCore:CallCommand', option.qbCommand, buildResponse(option, true))
  end
end

local BACK_OPTION = {
  label = nil,
  name = 'osm:goback',
  icon = 'arrow-left',
  openMenu = 'home',
  distance = math.huge,
  dialect = 'ox',
  resource = 'osm-target',
}

---Resolve target options: populate active options from precomputed candidate list.
local function resolveTarget(preserveFocusName, precomputed)
  if not target then
    resolved = {}
    return
  end

  resolved = precomputed or Hit.resolve(target, menuName)

  if menuName then
    BACK_OPTION.label = Locale('go_back')
    table.insert(resolved, 1, {
      index = 1,
      option = BACK_OPTION,
      enabled = true,
      focusable = true,
    })
    for i = 1, #resolved do resolved[i].index = i end
  end

  if preserveFocusName then
    for i = 1, #resolved do
      if resolved[i].option.name == preserveFocusName then
        focus = i
        return
      end
    end
  end

  focus = firstFocusable()
end

---Acquire interactive target: check direct raycast hit, containing zone, or nearest snap indicator.
local function acquire(origin, forward)
  local scan = Hit.scan()
  local reach = Config.Interaction.distance

  if scan.entity ~= 0 and scan.distance <= reach then
    local list = Hit.resolve(scan, menuName)
    if #list > 0 then
      scan.resolved = list
      scan.angle = 0.0
      scan.anchor = Hit.anchor(scan, list)
      return scan
    end
  end

  -- Check containing zones: evaluate zones encompassing the hit coordinates
  local zones = Store.zonesContaining(scan.coords)
  for i = 1, #zones do
    local zone = zones[i]
    local distance = #(GetEntityCoords(cache.ped) - zone.coords)
    if distance <= reach then
      local candidate = {
        entity = 0, entityType = 0, model = nil,
        coords = scan.coords, distance = distance, zone = zone,
      }
      local list = Hit.resolve(candidate, menuName)
      if #list > 0 then
        candidate.resolved = list
        candidate.angle = angleTo(origin, forward, zone.coords)
        candidate.anchor = zone.coords
        return candidate
      end
    end
  end

  -- Evaluate nearby indicators: locate nearest indicator within snap angle threshold
  local points = Discovery.points
  local best, bestAngle

  for i = 1, #points do
    local point = points[i]
    local angle = angleTo(origin, forward, point.coords)
    point.angle = angle

    if angle <= Config.Interaction.snapAngle and (not bestAngle or angle < bestAngle) then
      best, bestAngle = point, angle
    end
  end

  if not best then return nil end

  local candidate
  if best.kind == 'zone' then
    candidate = {
      entity = 0, entityType = 0, model = nil,
      coords = best.coords, distance = best.distance, zone = best.zone,
    }
  else
    candidate = {
      entity = best.entity, entityType = best.entityType, model = best.model,
      coords = best.coords, distance = best.distance,
    }
  end

  local list = Hit.resolve(candidate, menuName)
  if #list == 0 then return nil end

  candidate.resolved = list
  candidate.angle = bestAngle
  candidate.anchor = best.coords
  candidate.point = best
  return candidate
end

local function magnetise(candidate)
  target = candidate
  anchor = candidate.anchor
  menuName = nil
  menuHistory = {}
  releaseSince = nil

  resolveTarget(nil, candidate.resolved)
  if #resolved == 0 then
    target = nil
    return
  end

  setState(MAGNETISED)
  Surfaces.send('active', 'indicator:activate', { duration = Config.Interaction.openTime })
  Nui.sfx('magnetise')
end

local function openMenu()
  setState(MENU_OPEN)
  lastRevalidate = GetGameTimer()
  sendMenu()
end

---Release active target: transition state machine to releasing and reset UI.
local releaseToken = 0

local function release()
  if state == IDLE then return end

  releaseToken = releaseToken + 1
  local token = releaseToken

  setState(RELEASING)
  releaseSince = nil
  Surfaces.send('menu', 'menu:close', {})
  Surfaces.send('active', 'indicator:reset', {})

  CreateThread(function()
    Wait(Config.Interaction.closeTime)
    -- Validate release token: ensure release transition has not been superseded
    if state ~= RELEASING or releaseToken ~= token then return end

    target, anchor = nil, nil
    resolved = {}
    menuName, menuHistory = nil, {}

    if requested then
      setState(SWEEPING)
      lastScan = 0
    else
      setState(IDLE)
      Machine.teardown()
    end
  end)
end

---Abort interaction immediately: perform immediate state reset and surface cleanup.
function Machine.abort()
  if state == IDLE then return end
  requested = false
  state = IDLE
  target, anchor, resolved = nil, nil, {}
  menuName, menuHistory, releaseSince = nil, {}, nil
  Machine.teardown()
end

function Machine.cancel()
  if state == IDLE then return end
  if state == MENU_OPEN or state == MAGNETISED then
    Nui.sfx('cancel')
    release()
  else
    Machine.abort()
  end
end

function Machine.teardown()
  Surfaces.send('menu', 'menu:close', {})
  Surfaces.send('active', 'indicator:reset', {})
  Discovery.clear()
  nearState = {}
end

local function moveFocus(direction)
  if #resolved == 0 then return end

  local index = nextFocusable(focus, direction)
  if index == focus then return end

  focus = index
  sendFocus()
  Nui.sfx(resolved[focus].enabled and 'scroll' or 'reject')
end

local function confirm()
  local entry = resolved[focus]
  if not entry then return end

  if not entry.enabled then
    Nui.sfx('reject')
    Surfaces.send('menu', 'menu:reject', { focus = focus })
    return
  end

  local option = entry.option

  -- Navigate submenu: update menu level without executing external action
  if option.openMenu then
    Nui.sfx('confirm')

    if option.name == 'osm:goback' then
      menuName = table.remove(menuHistory) or nil
    else
      menuHistory[#menuHistory + 1] = menuName
      menuName = option.openMenu ~= 'home' and option.openMenu or nil
    end

    resolveTarget()
    sendMenu()
    return
  end

  -- Revalidate before execution: verify option eligibility before running action
  Player.refresh()
  local allowed, reason = Resolver.canExecute(option, Hit.context(target, menuName), target.distance)

  if not allowed then
    Nui.sfx('reject')
    resolveTarget(option.name)
    sendMenu()
    if reason then Bridge.Notify(reason, 'error') end
    return
  end

  Nui.sfx('confirm')
  -- End session on execute: key must be pressed again to re-target (ox_target / qb-target parity)
  requested = false
  execute(option)
  release()
end

---Check blocking conditions: verify player is alive and no modal overlays are active.
local function blocked()
  return disabled
    or IsPauseMenuActive()
    or IsPlayerDead(cache.playerId)
    or IsCutsceneActive()
    or IsNuiFocused()
    or (type(lib.progressActive) == 'function' and lib.progressActive())
end

local function targetStillValid()
  if not target then return false end

  if target.zone then
    return Store.zones[target.zone.id] ~= nil
  end

  if target.entity and target.entity ~= 0 then
    return DoesEntityExist(target.entity)
  end

  return true
end

local function logicTick()
  local now = GetGameTimer()
  local origin, forward = cameraBasis()

  if state == SWEEPING then
    if now - lastScan >= Config.Interaction.scanInterval then
      lastScan = now
      Discovery.run()

      local candidate = acquire(origin, forward)

      if candidate and candidate.angle <= Config.Interaction.snapAngle then
        magnetise(candidate)
      end
    end
    return
  end

  if state == MAGNETISED then
    if not targetStillValid() then
      release()
      return
    end

    anchor = Hit.anchor(target, resolved)

    if now - stateSince >= Config.Interaction.openTime then
      openMenu()
    end
    return
  end

  if state == MENU_OPEN then
    if not targetStillValid() then
      release()
      return
    end

    -- Update anchor position: track entity coordinates in real-time
    anchor = Hit.anchor(target, resolved)
    target.distance = Hit.distance(target, anchor, resolved)

    if target.distance > Config.Interaction.distance + 1.5 then
      release()
      return
    end

    local angle = angleTo(origin, forward, anchor)

    if angle > Config.Interaction.releaseAngle then
      local lookingAtTarget = false
      if target.entity and target.entity ~= 0 then
        local scan = Hit.scan()
        if scan and scan.entity == target.entity then
          lookingAtTarget = true
        end
      end

      if lookingAtTarget then
        releaseSince = nil
      else
        releaseSince = releaseSince or now
        if now - releaseSince >= Config.Interaction.releaseTime then
          release()
          return
        end
      end
    else
      releaseSince = nil
    end

    -- Periodically refresh options: revalidate gates while menu remains open
    if now - lastRevalidate >= 400 then
      lastRevalidate = now
      local focusName = resolved[focus] and resolved[focus].option.name
      local before = #resolved
      resolveTarget(focusName)

      if #resolved == 0 then
        release()
      elseif #resolved ~= before then
        sendMenu()
      end
    end
  end
end

local EMPTY_ANCHOR = { x = 0.0, y = 0.0 }

local function drawTick()
  local aspect = GetAspectRatio(true)
  local render = Config.Render
  -- Calculate scale multiplier: combine design tuning scale and player preferences
  local designScale = tonumber(Appearance.tunables.scale) or 100
  local scaleFactor = (designScale / 100) * ((Appearance.prefs.scale or 100) / 100)

  -- Render indicator markers: draw world-space indicator sprites at active discovery points
  if Config.Indicators.enabled then
    local points = Discovery.points
    local nearAngle = Config.Indicators.nearAngle
    local exitAngle = nearAngle + NEAR_HYSTERESIS
    local anchorPoint = anchor
    local origin, forward = cameraBasis()

    for i = 1, #points do
      local point = points[i]

      -- Skip magnetized anchor: avoid rendering idle indicator under active menu
      if not (anchorPoint and #(point.coords - anchorPoint) < 0.05) then
        -- Calculate point angle: compute angle from camera forward vector per frame
        local angle = angleTo(origin, forward, point.coords)
        point.angle = angle

        local key = pointKey(point)
        local near = nearState[key] and angle <= exitAngle or angle <= nearAngle
        nearState[key] = near

        local size = render.indicatorSize * Hit.scaleFor(point.distance) * scaleFactor
        local fade = 1.0 - math.min(point.distance / Config.Indicators.radius, 1.0)
        local alpha = 90 + fade * 140

        Surfaces.drawWorld(near and 'near' or 'idle', point.coords, size, aspect, alpha)
      end
    end
  end

  -- Render aiming cursor: draw screen-space reticle or animate transition on target lock
  if state == SWEEPING then
    Surfaces.drawScreen('cursor', 0.5, 0.5, render.cursorSize * scaleFactor, aspect, 255)
  elseif state == MAGNETISED and anchor and not Appearance.prefs.reducedMotion then
    local openTime = math.max(1, Config.Interaction.openTime)
    local t = (GetGameTimer() - stateSince) / openTime
    if t < 0.0 then t = 0.0 elseif t > 1.0 then t = 1.0 end

    local eased = t * t * (3.0 - 2.0 * t)
    -- Fade reticle alpha: calculate smooth ease-out opacity during transition
    local alpha = 255.0 * (1.0 - eased * eased)

    if alpha > 1.0 then
      local x, y = 0.5, 0.5
      local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(anchor.x, anchor.y, anchor.z)

      if onScreen then
        x = 0.5 + (screenX - 0.5) * eased
        y = 0.5 + (screenY - 0.5) * eased
      end

      Surfaces.drawScreen('cursor', x, y,
        render.cursorSize * scaleFactor * (1.0 - 0.45 * eased), aspect, alpha)
    end
  end

  if (state == MAGNETISED or state == MENU_OPEN or state == RELEASING) and anchor then
    local scale = Hit.scaleFor(target and target.distance or render.referenceDistance)
    local menuUp = state ~= MAGNETISED

    -- Yield the anchor to the menu: designs that draw their own mark on the world
    -- point would otherwise show the active indicator behind their option list.
    local alpha = 255.0
    if menuUp and OsmTargetDesigns.hidesIndicator(Appearance.design) then
      if state == RELEASING or Appearance.prefs.reducedMotion then
        alpha = 0.0
      else
        -- Fades over the same window the menu opens in, so the indicator is
        -- absorbed by the list rather than cut away from under it.
        local t = (GetGameTimer() - stateSince) / math.max(1, Config.Interaction.openTime)
        if t > 1.0 then t = 1.0 elseif t < 0.0 then t = 0.0 end
        alpha = 255.0 * (1.0 - t)
      end
    end

    if alpha > 1.0 then
      Surfaces.drawWorld('active', anchor, render.indicatorSize * scale * scaleFactor, aspect, alpha)
    end

    if menuUp then
      local bias = Appearance.anchor or EMPTY_ANCHOR
      Surfaces.drawWorld('menu', anchor, render.menuSize * scale * scaleFactor, aspect, 255,
        bias.x, bias.y)
    end
  end
end

function Machine.start()
  if disabled then return end
  requested = true
  if state ~= IDLE then return end
  if blocked() then return end

  Surfaces.init()
  Discovery.run(true)
  setState(SWEEPING)
  lastScan = 0
  Nui.sfx('sweep')

  CreateThread(function()
    while state ~= IDLE do
      Input.suppress()
      drawTick()

      if state == MENU_OPEN then
        local delta = Input.scrollDelta()
        if delta ~= 0 then moveFocus(delta) end
        if Input.confirmPressed() then confirm() end
        if Input.cancelPressed() then Machine.cancel() end
      elseif state == SWEEPING then
        if Input.cancelPressed() then Machine.abort() end
      end

      Wait(0)
    end
  end)

  CreateThread(function()
    while state ~= IDLE do
      if blocked() then
        Machine.abort()
        break
      end
      logicTick()
      Wait(state == MENU_OPEN and 30 or 0)
    end
  end)
end

---Stop interaction: initiate release transition or abort sweep.
function Machine.stop()
  requested = false

  if state == SWEEPING then
    Machine.abort()
  elseif state == MAGNETISED or state == MENU_OPEN then
    release()
  end
end

CreateThread(function()
  while true do
    if state ~= IDLE and (IsPauseMenuActive() or IsPlayerDead(cache.playerId) or IsCutsceneActive()) then
      Machine.abort()
    end
    Wait(250)
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  Machine.abort()
end)
