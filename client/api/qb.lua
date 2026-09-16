local DIALECT = 'qb'
local RESOURCE = 'qb-target'

local function ctxFor(distance, bones)
  return {
    resource = GetInvokingResource() or GetCurrentResourceName(),
    distance = distance or Config.Options.defaultDistance,
    bones = bones,
  }
end

---Unwrap parameters: extract option table and context.
local function unwrap(parameters, bones)
  parameters = parameters or {}
  local options = parameters.options or parameters
  return options, ctxFor(parameters.distance, bones)
end

local exportList = {}

---Register export helper: bind qb-target export handler.
local function register(name, fn)
  exportList[name] = fn
  ExportAs(RESOURCE, name, fn)
end

local zonesByName = {}

---Create PolyZone shim: provide destroy and isPointInside methods for legacy compatibility.
local function makeShim(name, ids, targetoptions)
  local shim = {
    name = name,
    ids = ids,
    targetoptions = targetoptions,
    center = Store.zones[ids[1]] and Store.zones[ids[1]].coords or nil,
  }

  function shim:destroy()
    for i = 1, #self.ids do Store.removeZone(self.ids[i]) end
    zonesByName[self.name] = nil
  end

  shim.remove = shim.destroy

  function shim:isPointInside(coords)
    for i = 1, #self.ids do
      local zone = Store.zones[self.ids[i]]
      if zone and zone:contains(coords) then return true end
    end
    return false
  end

  zonesByName[name] = shim
  return shim
end

local function toVec3(value)
  local kind = type(value)
  if kind == 'vector3' then return value end
  if kind == 'vector4' or kind == 'table' then
    return vec3(value[1] or value.x, value[2] or value.y, value[3] or value.z)
  end
  return value
end

---Calculate column bounds: convert minZ/maxZ bounds to center Z coordinate and thickness.
local function columnBounds(center, options)
  local minZ = options and options.minZ
  local maxZ = options and options.maxZ

  if not minZ or not maxZ then
    -- Default unbounded height: use tall column when vertical bounds omitted
    return center.z, 100.0
  end

  return (minZ + maxZ) / 2, math.abs(maxZ - minZ)
end

register('AddCircleZone', function(name, center, radius, options, targetoptions)
  local raw, ctx = unwrap(targetoptions)
  center = toVec3(center)

  local zone = Store.attachZone(lib.zones.sphere({
    name = name,
    coords = center,
    radius = (radius or 1.0) + 0.0,
    debug = options and options.debugPoly,
  }), raw, DIALECT, ctx)

  -- Unbounded circle without useZ: qb-target PolyZone CircleZone ignores height unless useZ is set
  if not (options and options.useZ) then
    zone.contains = function(self, coords, updateDistance)
      if updateDistance then self.distance = #(self.coords - coords) end
      return #(self.coords.xy - coords.xy) < self.radius
    end
  end

  return makeShim(name, { zone.id }, targetoptions)
end)

register('AddBoxZone', function(name, center, length, width, options, targetoptions)
  local raw, ctx = unwrap(targetoptions)
  center = toVec3(center)

  local z, thickness = columnBounds(center, options)
  if options and options.useZ then
    z, thickness = center.z, 2.0
  end

  local zone = Store.attachZone(lib.zones.box({
    name = name,
    coords = vec3(center.x, center.y, z),
    size = vec3(width or 2.0, length or 2.0, thickness),
    rotation = options and options.heading or 0,
    debug = options and options.debugPoly,
  }), raw, DIALECT, ctx)

  return makeShim(name, { zone.id }, targetoptions)
end)

register('AddPolyZone', function(name, points, options, targetoptions)
  local raw, ctx = unwrap(targetoptions)

  -- Determine base elevation: extract Z coordinate from polygon point if present
  local first = points[1]
  local baseZ = 0.0
  if first then
    local ok, value = pcall(function() return first.z end)
    if ok and type(value) == 'number' then baseZ = value end
  end

  local z, thickness = columnBounds({ z = baseZ }, options)
  local converted = {}
  for i = 1, #points do
    local point = points[i]
    converted[i] = vec3(point[1] or point.x, point[2] or point.y, z)
  end

  local zone = Store.attachZone(lib.zones.poly({
    name = name,
    points = converted,
    thickness = thickness,
    debug = options and options.debugPoly,
  }), raw, DIALECT, ctx)

  return makeShim(name, { zone.id }, targetoptions)
end)

---Register combo zone: combine multiple zone definitions under single name.
register('AddComboZone', function(zones, options, targetoptions)
  local name = (options and options.name) or ('combo:' .. tostring(math.random(1, 1e9)))
  local ids = {}

  for i = 1, #(zones or {}) do
    local part = zones[i]
    if type(part) == 'table' then
      if part.ids then
        for j = 1, #part.ids do ids[#ids + 1] = part.ids[j] end
        -- Reassign zone options: update member zone options with combo options
        for j = 1, #part.ids do
          local zone = Store.zones[part.ids[j]]
          if zone then
            local raw, ctx = unwrap(targetoptions)
            zone.options = {}
            Store.add(zone.options, raw, DIALECT, ctx)
          end
        end
        zonesByName[part.name] = nil
      end
    end
  end

  return makeShim(name, ids, targetoptions)
end)

register('AddEntityZone', function(name, entity, options, targetoptions)
  -- Track entity options: register options directly on entity handle
  local raw, ctx = unwrap(targetoptions)
  Store.addKeyed(Store.localEntities, entity, raw, DIALECT, ctx)

  local shim = { name = name, entity = entity, ids = {} }
  function shim:destroy()
    Store.removeKeyed(Store.localEntities, self.entity, nil, ctx.resource)
    zonesByName[self.name] = nil
  end
  shim.remove = shim.destroy
  function shim:isPointInside() return false end

  zonesByName[name] = shim
  return shim
end)

register('RemoveZone', function(name)
  local shim = zonesByName[name]
  if shim then return shim:destroy() end

  local found = Store.findZonesByName(name)
  for i = 1, #found do Store.removeZone(found[i].id) end
end)

-- Register vehicle bone options: attach options globally to vehicle class
register('AddTargetBone', function(bones, parameters)
  if type(bones) ~= 'table' then bones = { bones } end
  local raw, ctx = unwrap(parameters, bones)
  Store.add(Store.vehicles, raw, DIALECT, ctx)
end)

register('RemoveTargetBone', function(_bones, labels)
  Store.remove(Store.vehicles, labels, GetInvokingResource() or GetCurrentResourceName())
end)

register('AddTargetEntity', function(entities, parameters)
  if type(entities) ~= 'table' then entities = { entities } end
  local raw, ctx = unwrap(parameters)

  for i = 1, #entities do
    local entity = entities[i]
    if NetworkGetEntityIsNetworked(entity) then
      Store.addKeyed(Store.entities, NetworkGetNetworkIdFromEntity(entity), raw, DIALECT, ctx)
    else
      Store.addKeyed(Store.localEntities, entity, raw, DIALECT, ctx)
    end
  end
end)

register('RemoveTargetEntity', function(entities, labels)
  if type(entities) ~= 'table' then entities = { entities } end
  local resource = GetInvokingResource() or GetCurrentResourceName()

  for i = 1, #entities do
    local entity = entities[i]
    if NetworkGetEntityIsNetworked(entity) then
      Store.removeKeyed(Store.entities, NetworkGetNetworkIdFromEntity(entity), labels, resource)
    else
      Store.removeKeyed(Store.localEntities, entity, labels, resource)
    end
  end
end)

register('AddTargetModel', function(models, parameters)
  if type(models) ~= 'table' then models = { models } end
  local raw, ctx = unwrap(parameters)

  for i = 1, #models do
    local model = tonumber(models[i]) or joaat(models[i])
    Store.addKeyed(Store.models, model, raw, DIALECT, ctx)
  end
end)

register('RemoveTargetModel', function(models, labels)
  if type(models) ~= 'table' then models = { models } end
  local resource = GetInvokingResource() or GetCurrentResourceName()

  for i = 1, #models do
    local model = tonumber(models[i]) or joaat(models[i])
    Store.removeKeyed(Store.models, model, labels, resource)
  end
end)

local TYPE_BUCKET = { [1] = 'peds', [2] = 'vehicles', [3] = 'objects' }

register('AddGlobalType', function(entityType, parameters)
  local bucket = Store[TYPE_BUCKET[entityType]]
  if not bucket then return end
  local raw, ctx = unwrap(parameters)
  Store.add(bucket, raw, DIALECT, ctx)
end)

register('RemoveGlobalType', function(entityType, labels)
  local bucket = Store[TYPE_BUCKET[entityType]]
  if not bucket then return end
  Store.remove(bucket, labels, GetInvokingResource() or GetCurrentResourceName())
end)

-- Alias export: map RemoveType to RemoveGlobalType
register('RemoveType', function(entityType, labels)
  exportList.RemoveGlobalType(entityType, labels)
end)

local GLOBALS = {
  Ped = { bucket = 'peds', type = 1 },
  Vehicle = { bucket = 'vehicles', type = 2 },
  Object = { bucket = 'objects', type = 3 },
  Player = { bucket = 'players' },
}

for suffix, meta in pairs(GLOBALS) do
  register('AddGlobal' .. suffix, function(parameters)
    local raw, ctx = unwrap(parameters)
    Store.add(Store[meta.bucket], raw, DIALECT, ctx)
  end)

  register('RemoveGlobal' .. suffix, function(labels)
    Store.remove(Store[meta.bucket], labels, GetInvokingResource() or GetCurrentResourceName())
  end)
end

-- Option lookup helper: search bucket for matching name or label
local function findByLabel(bucket, label)
  if not bucket then return nil end
  for i = 1, #bucket do
    if bucket[i].name == label or bucket[i].label == label then return bucket[i], i end
  end
  return nil
end

local function replaceByLabel(bucket, label, data)
  if not bucket then return end
  local _, index = findByLabel(bucket, label)
  local ctx = ctxFor()
  local normalised = OsmTargetCompat.normalise({ data }, DIALECT, ctx)
  if not normalised[1] then return end

  if index then
    bucket[index] = normalised[1]
  else
    bucket[#bucket + 1] = normalised[1]
  end
end

register('GetGlobalTypeData', function(entityType, label)
  return findByLabel(Store[TYPE_BUCKET[entityType]], label)
end)
register('GetGlobalPedData', function(label) return findByLabel(Store.peds, label) end)
register('GetGlobalVehicleData', function(label) return findByLabel(Store.vehicles, label) end)
register('GetGlobalObjectData', function(label) return findByLabel(Store.objects, label) end)
register('GetGlobalPlayerData', function(label) return findByLabel(Store.players, label) end)
register('GetTargetBoneData', function(_bone, label) return findByLabel(Store.vehicles, label) end)
register('GetTargetModelData', function(model, label)
  return findByLabel(Store.models[tonumber(model) or joaat(model)], label)
end)
register('GetTargetEntityData', function(entity, label)
  return findByLabel(Store.localEntities[entity] or Store.entities[entity], label)
end)
register('GetZoneData', function(name) return zonesByName[name] end)

register('UpdateGlobalTypeData', function(entityType, label, data)
  replaceByLabel(Store[TYPE_BUCKET[entityType]], label, data)
end)
register('UpdateGlobalPedData', function(label, data) replaceByLabel(Store.peds, label, data) end)
register('UpdateGlobalVehicleData', function(label, data) replaceByLabel(Store.vehicles, label, data) end)
register('UpdateGlobalObjectData', function(label, data) replaceByLabel(Store.objects, label, data) end)
register('UpdateGlobalPlayerData', function(label, data) replaceByLabel(Store.players, label, data) end)
register('UpdateTargetBoneData', function(_bone, label, data) replaceByLabel(Store.vehicles, label, data) end)
register('UpdateTargetModelData', function(model, label, data)
  replaceByLabel(Store.models[tonumber(model) or joaat(model)], label, data)
end)
register('UpdateTargetEntityData', function(entity, label, data)
  replaceByLabel(Store.localEntities[entity] or Store.entities[entity], label, data)
end)

register('UpdateZoneData', function(name, targetoptions)
  local shim = zonesByName[name]
  if not shim or not shim.ids then return end
  local raw, ctx = unwrap(targetoptions)
  for i = 1, #shim.ids do
    local zone = Store.zones[shim.ids[i]]
    if zone then
      zone.options = {}
      Store.add(zone.options, raw, DIALECT, ctx)
    end
  end
  shim.targetoptions = targetoptions
end)

register('RaycastCamera', function(flag)
  local hit, entity, coords = lib.raycast.fromCamera(flag or 511, 4, Config.Interaction.raycastDistance)
  local distance = #(GetEntityCoords(cache.ped) - coords)
  local entityType = 0
  if entity and entity ~= 0 then
    local ok, result = pcall(GetEntityType, entity)
    entityType = ok and result or 0
  end
  return coords, distance, entity, entityType, hit
end)

register('DisableNUI', function() Machine.cancel() end)
register('LeftTarget', function() Machine.cancel() end)
register('DisableTarget', function(force) if force ~= false then Machine.cancel() end end)
register('EnableNUI', function() end)

register('DrawOutlineEntity', function(entity, enable)
  if not entity or entity == 0 then return end
  SetEntityDrawOutline(entity, enable and true or false)
end)

-- Default vehicle bones: standard bone identifiers for vehicle interaction
VehicleBones = {
  'door_dside_f', 'door_dside_r', 'door_pside_f', 'door_pside_r',
  'wheel_lf', 'wheel_rf', 'wheel_lr', 'wheel_rr',
  'bonnet', 'boot', 'engine', 'exhaust', 'seat_dside_f', 'seat_pside_f',
  'seat_dside_r', 'seat_pside_r', 'windscreen', 'petrolcap', 'petroltank',
}

---Find closest vehicle bone: check bone coordinates against entity.
---@return number|false boneId, vector3? position, string? name
function ClosestBone(coords, entity, boneList)
  boneList = boneList or VehicleBones
  local closestBone, closestDistance, closestPos, closestName = -1, math.huge, nil, nil

  for i = 1, #boneList do
    local name = boneList[i]
    local boneId = GetEntityBoneIndexByName(entity, name)
    if boneId ~= -1 then
      local pos = GetWorldPositionOfEntityBone(entity, boneId)
      local distance = #(coords - pos)
      if distance < closestDistance then
        closestBone, closestDistance, closestPos, closestName = boneId, distance, pos, name
      end
    end
  end

  if closestBone == -1 then return false end
  return closestBone, closestPos, closestName
end

register('CheckBones', ClosestBone)
register('CheckEntity', function() end)
register('AllowTargeting', function(allow) Machine.setDisabled(not allow) end)
register('IsTargetActive', function() return Machine.isActive() end)
register('IsTargetSuccess', function() return Machine.hasMenu() end)

-- Track spawned peds: manage entity lifecycle for peds spawned via qb-target API
local qbPeds = {}
local spawned = {}

local function applyPedConfig(ped, v)
  if v.freeze then FreezeEntityPosition(ped, true) end
  if v.invincible then SetEntityInvincible(ped, true) end
  if v.blockevents then SetBlockingOfNonTemporaryEvents(ped, true) end

  if v.animDict and v.anim then
    lib.requestAnimDict(v.animDict)
    TaskPlayAnim(ped, v.animDict, v.anim, 8.0, 0.0, -1, v.flag or 1, 0.0, false, false, false)
  end

  if v.scenario then
    SetPedCanPlayAmbientAnims(ped, true)
    TaskStartScenarioInPlace(ped, v.scenario, 0, true)
  end

  if v.pedrelations and type(v.pedrelations.groupname) == 'string' then
    local hash = joaat(v.pedrelations.groupname)
    if not DoesRelationshipGroupExist(hash) then AddRelationshipGroup(v.pedrelations.groupname) end
    SetPedRelationshipGroupHash(ped, hash)
    if v.pedrelations.toplayer then
      SetRelationshipBetweenGroups(v.pedrelations.toplayer, hash, joaat('PLAYER'))
    end
    if v.pedrelations.toowngroup then
      SetRelationshipBetweenGroups(v.pedrelations.toowngroup, hash, hash)
    end
  end

  if v.weapon then
    local weapon = type(v.weapon.name) == 'string' and joaat(v.weapon.name) or v.weapon.name
    if IsWeaponValid(weapon) then
      SetCanPedEquipWeapon(ped, weapon, true)
      GiveWeaponToPed(ped, weapon, v.weapon.ammo or 0, v.weapon.hidden or false, true)
      SetPedCurrentWeaponVisible(ped, not v.weapon.hidden, true, true, true)
    end
  end

  if v.target then
    if v.target.useModel then
      exportList.AddTargetModel(v.model, { options = v.target.options, distance = v.target.distance })
    else
      exportList.AddTargetEntity(ped, { options = v.target.options, distance = v.target.distance })
    end
  end

  if v.action then v.action(v) end
end

local function spawnOnePed(v, missionPed)
  local model = type(v.model) == 'string' and joaat(v.model) or v.model
  lib.requestModel(model)

  local z = v.minusOne and (v.coords.z - 1.0) or v.coords.z
  local ped = CreatePed(0, model, v.coords.x, v.coords.y, z, v.coords.w or 0.0, v.networked or false, missionPed)
  SetModelAsNoLongerNeeded(model)

  applyPedConfig(ped, v)
  spawned[#spawned + 1] = ped
  return ped
end

register('SpawnPed', function(data)
  if type(data) ~= 'table' then return end

  local key, value = next(data)
  local isList = type(value) == 'table' and type(key) ~= 'string'

  local entries = isList and data or { data }
  for _, v in pairs(entries) do
    if v.spawnNow then v.currentpednumber = spawnOnePed(v, true) end
    qbPeds[#qbPeds + 1] = v
  end
end)

register('DeletePeds', function()
  for i = 1, #qbPeds do
    local ped = qbPeds[i].currentpednumber
    if ped and ped ~= 0 and DoesEntityExist(ped) then DeletePed(ped) end
    qbPeds[i].currentpednumber = 0
  end
end)

register('RemoveSpawnedPed', function(peds)
  if type(peds) == 'table' then
    for k, ped in pairs(peds) do
      if DoesEntityExist(ped) then DeletePed(ped) end
      if qbPeds[k] then qbPeds[k].currentpednumber = 0 end
    end
  elseif type(peds) == 'number' and DoesEntityExist(peds) then
    DeletePed(peds)
  end
end)

register('GetPeds', function() return qbPeds end)
register('UpdatePedsData', function(index, data) qbPeds[index] = data end)

-- Clean up spawned peds: delete entities on resource stop
AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  for i = 1, #spawned do
    if DoesEntityExist(spawned[i]) then DeletePed(spawned[i]) end
  end
end)
