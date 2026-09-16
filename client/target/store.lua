local Compat = OsmTargetCompat

Store = {}

Store.global = {}
Store.peds = {}
Store.vehicles = {}
Store.objects = {}
Store.players = {}
Store.models = {}
Store.entities = {}
Store.localEntities = {}

---Track internal zones: store zone definitions registered through osm-target.
Store.zones = {}

---Version counter: increment when registered models list changes.
Store.modelsVersion = 0

---Remove existing entries: replace existing registrations with matching names.
local function removeNamed(bucket, names, resource)
  if not names or #names == 0 then return end

  local lookup = {}
  for i = 1, #names do lookup[names[i]] = true end

  for i = #bucket, 1, -1 do
    local option = bucket[i]
    if option.resource == resource and option.name and lookup[option.name] then
      table.remove(bucket, i)
    end
  end
end

---@param bucket table[] destination
---@param options table   raw options in `dialect` form
---@param dialect 'ox'|'qb'|'qtarget'
---@param ctx table { resource, distance, bones }
function Store.add(bucket, options, dialect, ctx)
  local normalised = Compat.normalise(options, dialect, ctx)
  if #normalised == 0 then return end

  local names = {}
  for i = 1, #normalised do
    local option = normalised[i]
    if option.name then names[#names + 1] = option.name end
  end

  removeNamed(bucket, names, ctx.resource)

  for i = 1, #normalised do
    bucket[#bucket + 1] = normalised[i]
  end
end

---@param bucket table[]
---@param names string | string[] | nil
---@param resource string
function Store.remove(bucket, names, resource)
  if names == nil then
    for i = #bucket, 1, -1 do
      if bucket[i].resource == resource then table.remove(bucket, i) end
    end
    return
  end

  if type(names) ~= 'table' then names = { names } end
  removeNamed(bucket, names, resource)
end

---Add keyed options: insert options into map and purge empty key entries.
function Store.addKeyed(map, key, options, dialect, ctx)
  if not map[key] then map[key] = {} end
  Store.add(map[key], options, dialect, ctx)
  if #map[key] == 0 then map[key] = nil end
  if map == Store.models then Store.modelsVersion = Store.modelsVersion + 1 end
end

function Store.removeKeyed(map, key, names, resource)
  local bucket = map[key]
  if not bucket then return end
  Store.remove(bucket, names, resource)
  if #bucket == 0 then map[key] = nil end
  if map == Store.models then Store.modelsVersion = Store.modelsVersion + 1 end
end

local function append(out, bucket, distance)
  if not bucket then return end
  for i = 1, #bucket do
    out[#out + 1] = { option = bucket[i], distance = distance }
  end
end

---Collect entity candidates: gather global, class-wide, model, and entity-specific options.
---@param entity number 0 when nothing was hit
---@param entityType number 1 ped, 2 vehicle, 3 object
---@param model number|nil
---@param distance number
---@param specificOnly boolean? skip class-wide registrations
---@return table[] candidates
function Store.candidatesForEntity(entity, entityType, model, distance, specificOnly)
  local out = {}

  -- Filter class globals: exclude global class options from indicator markers if disabled
  if not specificOnly then
    -- Append global options: include global options with zero distance
    append(out, Store.global, 0)
  end

  if entity and entity ~= 0 then
    if not specificOnly then
      if entityType == 1 and IsPedAPlayer(entity) then
        append(out, Store.players, distance)
      elseif entityType == 1 then
        append(out, Store.peds, distance)
      elseif entityType == 2 then
        append(out, Store.vehicles, distance)
      elseif entityType then
        append(out, Store.objects, distance)
      end
    end

    if model then append(out, Store.models[model], distance) end

    if NetworkGetEntityIsNetworked(entity) then
      append(out, Store.entities[NetworkGetNetworkIdFromEntity(entity)], distance)
    end

    append(out, Store.localEntities[entity], distance)
  end

  return out
end

---Append zone candidates: tag each option with its zone so responses report the right zone id.
---@param out table[]
---@param zone table an ox_lib zone we own
---@param distance number
function Store.appendZone(out, zone, distance)
  local options = zone.options
  if not options then return end
  for i = 1, #options do
    out[#out + 1] = { option = options[i], distance = distance, zone = zone }
  end
end

---@param zone table an ox_lib zone we own
---@param distance number
function Store.candidatesForZone(zone, distance)
  local out = {}
  append(out, Store.global, 0)
  Store.appendZone(out, zone, distance)
  return out
end

---Find zones containing coordinates, sorted by nearest first.
---@return table[] zones
function Store.zonesContaining(coords)
  local nearby = lib.zones.getNearbyZones()
  local out = {}

  for i = 1, #nearby do
    local zone = nearby[i]
    if zone.osmTarget and zone:contains(coords) then
      out[#out + 1] = zone
    end
  end

  table.sort(out, function(a, b) return (a.distance or 0) < (b.distance or 0) end)
  return out
end

---@param zone table an ox_lib zone
---@param options table raw options
---@param dialect string
---@param ctx table
function Store.attachZone(zone, options, dialect, ctx)
  zone.osmTarget = true
  zone.resource = ctx.resource
  zone.options = {}
  Store.add(zone.options, options, dialect, ctx)
  Store.zones[zone.id] = zone
  return zone
end

function Store.removeZone(id)
  local zone = Store.zones[id]
  if not zone then return false end
  Store.zones[id] = nil
  if zone.remove then zone:remove() end
  return true
end

function Store.findZonesByName(name)
  local out = {}
  for _, zone in pairs(Store.zones) do
    if zone.name == name then out[#out + 1] = zone end
  end
  return out
end

---Purge resource registrations: remove all entries created by stopped resource.
function Store.cleanupResource(resource)
  local flat = { Store.global, Store.peds, Store.vehicles, Store.objects, Store.players }
  for i = 1, #flat do
    Store.remove(flat[i], nil, resource)
  end

  local keyed = { Store.models, Store.entities, Store.localEntities }
  for i = 1, #keyed do
    local map = keyed[i]
    local keys = {}
    for key in pairs(map) do keys[#keys + 1] = key end
    for j = 1, #keys do
      Store.removeKeyed(map, keys[j], nil, resource)
    end
  end

  local zoneIds = {}
  for id, zone in pairs(Store.zones) do
    if zone.resource == resource then zoneIds[#zoneIds + 1] = id end
  end
  for i = 1, #zoneIds do
    Store.removeZone(zoneIds[i])
  end
end

AddEventHandler('onClientResourceStop', function(resource)
  if resource == GetCurrentResourceName() then return end
  Store.cleanupResource(resource)
end)

-- Periodically prune deleted entities: remove stale entity registrations
CreateThread(function()
  while true do
    Wait(60000)
    for handle in pairs(Store.localEntities) do
      if not DoesEntityExist(handle) then Store.localEntities[handle] = nil end
    end
    for netId in pairs(Store.entities) do
      if not NetworkDoesNetworkIdExist(netId) then Store.entities[netId] = nil end
    end
  end
end)
