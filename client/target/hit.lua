local Resolver = OsmTargetResolver

Hit = {}

local FLAGS = 511      -- INCLUDE_ALL
local ENTITY_FLAGS = 26 -- VEHICLES | PEDS | OBJECTS (skips map geometry)
local IGNORE = 4       -- NO_COLLISION

local function describe(entity, coords)
  local entityType, model, offset = 0, nil, nil

  if entity and entity ~= 0 then
    local ok, result = pcall(GetEntityType, entity)
    entityType = ok and result or 0

    if entityType > 0 then
      local okModel, resultModel = pcall(GetEntityModel, entity)
      model = okModel and resultModel or nil
      if coords then
        local okOffset, resultOffset = pcall(GetOffsetFromEntityGivenWorldCoords, entity, coords.x, coords.y, coords.z)
        offset = okOffset and resultOffset or nil
      end
    else
      entity = 0
    end
  end

  return entity or 0, entityType, model, offset
end

---Scan interaction raycast: perform camera raycast to detect targeted entity and aimed zones.
---@return table? target
function Hit.scan()
  local origin = GetEntityCoords(cache.ped)
  local hit, entity, coords = lib.raycast.fromCamera(FLAGS, IGNORE, Config.Interaction.raycastDistance)
  local entityType, model, offset
  entity, entityType, model, offset = describe(entity, coords)

  -- Zones use the aimed world point: ox_target / qb-target test zone containment against the raycast end coords
  local zones = Store.zonesContaining(coords)

  -- Entity-only fallback ray: ox_target alternates flag 26 so entities embedded in map collision stay targetable when LOS is clear
  if entity == 0 and #zones == 0 then
    local _, entityHit, entityCoords = lib.raycast.fromCamera(ENTITY_FLAGS, IGNORE, Config.Interaction.raycastDistance)
    if entityHit and entityHit ~= 0 and HasEntityClearLosToEntity(entityHit, cache.ped, 7) then
      local found, foundType, foundModel, foundOffset = describe(entityHit, entityCoords)
      if found ~= 0 then
        hit, coords = true, entityCoords
        entity, entityType, model, offset = found, foundType, foundModel, foundOffset
      end
    end
  end

  return {
    hit = hit,
    entity = entity,
    entityType = entityType,
    model = model,
    coords = coords,
    offset = offset,
    distance = #(origin - coords),
    zones = zones,
    zone = zones[1],
  }
end

-- Bone tolerances: ox_target accepts a single bone within 2.0 and the closest of a bone list within 1.0
local BONE_TOLERANCE = 2.0
local BONE_LIST_TOLERANCE = 1.0

---Resolve option offset in world space: scale relative offsets by model dimensions like ox_target.
---@return vector3?
local function offsetWorld(target, option)
  if not target.model then return nil end

  local offset = option.offset
  if not option.absoluteOffset then
    local minimum, maximum = GetModelDimensions(target.model)
    offset = (maximum - minimum) * offset + minimum
  end

  return GetOffsetFromEntityInWorldCoords(target.entity, offset.x, offset.y, offset.z)
end

---Create spatial attachment evaluator: verify bone or model offset matching for hit target.
function Hit.makeSpatial(target)
  local entity = target.entity
  local endCoords = target.coords
  if entity and entity ~= 0 and DoesEntityExist(entity) and target.offset then
    local ok, worldCoords = pcall(GetOffsetFromEntityInWorldCoords, entity, target.offset.x, target.offset.y, target.offset.z)
    if ok and worldCoords then endCoords = worldCoords end
  end

  return function(option)
    if entity == 0 then return false end

    if option.bones then
      local bones = option.bones
      local tolerance = BONE_LIST_TOLERANCE
      if type(bones) == 'string' then bones, tolerance = { bones }, BONE_TOLERANCE end

      local bestId, bestDistance
      for i = 1, #bones do
        local boneId = GetEntityBoneIndexByName(entity, bones[i])
        if boneId ~= -1 then
          local distance = #(endCoords - GetEntityBonePosition_2(entity, boneId))
          if distance <= tolerance and (not bestDistance or distance < bestDistance) then
            bestId, bestDistance = boneId, distance
          end
        end
      end

      if not bestId then return false end
      if not option.offset then return true, bestId end
    end

    if option.offset then
      local world = offsetWorld(target, option)
      if not world or #(endCoords - world) > (option.offsetSize or 1.0) then return false end
    end

    return true
  end
end
---Create interaction predicate runner: execute canInteract safely within pcall wrapper.
function Hit.makeInteract(target)
  local coords = target.coords
  if target.entity and target.entity ~= 0 and DoesEntityExist(target.entity) and target.offset then
    local ok, worldCoords = pcall(GetOffsetFromEntityInWorldCoords, target.entity, target.offset.x, target.offset.y, target.offset.z)
    if ok and worldCoords then coords = worldCoords end
  end

  -- Untargeted parity: ox_target hands canInteract a 0 entity when nothing is aimed at
  local entity = target.entity ~= 0 and target.entity or nil
  if target.untargeted then entity = 0 end

  return function(option, distance, bone)
    local ok, allowed, reason = pcall(option.canInteract,
      entity, distance, coords, option.name, bone)
    if not ok then return false end
    return allowed, reason
  end
end

---Build resolution context: assemble player state, spatial checker, and interaction runner.
function Hit.context(target, menu)
  local coords = target.coords
  if target.entity and target.entity ~= 0 and DoesEntityExist(target.entity) and target.offset then
    local ok, worldCoords = pcall(GetOffsetFromEntityInWorldCoords, target.entity, target.offset.x, target.offset.y, target.offset.z)
    if ok and worldCoords then coords = worldCoords end
  end

  return {
    distance = target.distance,
    entity = target.entity ~= 0 and target.entity or nil,
    coords = coords,
    menu = menu,
    player = Player.state(),
    policy = Config.Options,
    spatial = Hit.makeSpatial(target),
    interact = Hit.makeInteract(target),
  }
end

---@return table[] resolved, table candidates
function Hit.resolve(target, menu)
  -- Untargeted sessions only ever resolve opted-in global options
  if target.untargeted then
    local candidates = Store.candidatesUntargeted()
    -- Skip context build when nothing opted in: keeps the disabled default free while sweeping
    if #candidates == 0 then return {}, candidates end
    return Resolver.resolve(candidates, Hit.context(target, menu)), candidates
  end

  local candidates = Store.candidatesForEntity(target.entity, target.entityType, target.model, target.distance)

  -- Merge aimed zone options: ox_target lists entity and containing zone options together
  local zones = target.zones or (target.zone and { target.zone })
  if zones then
    for i = 1, #zones do Store.appendZone(candidates, zones[i], target.distance) end
  end

  return Resolver.resolve(candidates, Hit.context(target, menu)), candidates
end

-- Untargeted anchor: reach ahead of the player along camera heading, lifted towards chest height
local UNTARGETED_REACH = 1.5
local UNTARGETED_LIFT = 0.4

---Calculate untargeted anchor: place menu in front of the player since there is no entity or zone to attach to.
---@return vector3
function Hit.untargetedAnchor()
  local coords = GetEntityCoords(cache.ped)
  local yaw = math.rad(GetFinalRenderedCamRot(2).z)
  local lift = UNTARGETED_LIFT + (Config.Render.anchorLift or 0.0)

  return vec3(
    coords.x - math.sin(yaw) * UNTARGETED_REACH,
    coords.y + math.cos(yaw) * UNTARGETED_REACH,
    coords.z + lift
  )
end

---Calculate world anchor: resolve bone coordinate, option offset, model bounding center, or aimed zone point.
---@return vector3
function Hit.anchor(target, resolved)
  if target.untargeted then return Hit.untargetedAnchor() end

  if target.entity and target.entity ~= 0 and DoesEntityExist(target.entity) then
    if resolved then
      for i = 1, #resolved do
        local entry = resolved[i]
        if entry.bone then
          return GetWorldPositionOfEntityBone(target.entity, entry.bone)
        end
        if entry.option.offset and not entry.option.bones then
          local world = offsetWorld(target, entry.option)
          if world then return world end
        end
      end
    end

    return Discovery.entityAnchor(target.entity, target.model)
  end

  -- Zone anchor: aimed point for raycast zone hits, zone centre for indicator snaps
  return target.coords or (target.zone and target.zone.coords)
end
---Calculate interaction distance: measure physical distance to bone, surface contact point, or anchor.
---@param target table
---@param anchor vector3?
---@param resolved table[]?
---@return number
function Hit.distance(target, anchor, resolved)
  local origin = GetEntityCoords(cache.ped)

  if resolved then
    for i = 1, #resolved do
      local bone = resolved[i].bone
      if bone and target.entity and target.entity ~= 0 and DoesEntityExist(target.entity) then
        local boneCoords = GetWorldPositionOfEntityBone(target.entity, bone)
        if boneCoords then return #(origin - boneCoords) end
      end
    end
  end

  if target.entity and target.entity ~= 0 and DoesEntityExist(target.entity) and target.offset then
    local ok, worldCoords = pcall(GetOffsetFromEntityInWorldCoords, target.entity, target.offset.x, target.offset.y, target.offset.z)
    if ok and worldCoords then
      return #(origin - worldCoords)
    end
  end

  if anchor then
    return #(origin - anchor)
  end

  if target.coords then
    return #(origin - target.coords)
  end

  return 0.0
end

---Calculate distance scale factor: compute non-linear scale multiplier based on target distance.
---@return number
function Hit.scaleFor(distance)
  local render = Config.Render
  if distance <= 0.01 then return render.scaleMax end

  local ratio = render.referenceDistance / distance
  local scale = ratio ^ render.scaleExponent

  if scale < render.scaleMin then return render.scaleMin end
  if scale > render.scaleMax then return render.scaleMax end
  return scale
end
