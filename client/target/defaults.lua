-- Default vehicle doors: register built-in vehicle door options for ox_target parity
if not (Config.Defaults and Config.Defaults.vehicleDoors) then return end
-- Honour ox_target convar: servers that disabled ox_target defaults keep them disabled after switching
if GetConvarInt('ox_target:defaults', 1) ~= 1 then return end

local DOOR_BONES = {
  [0] = 'dside_f',
  [1] = 'pside_f',
  [2] = 'dside_r',
  [3] = 'pside_r',
}

---Toggle vehicle door: open or close specified door index if vehicle is unlocked.
local function toggleDoor(vehicle, door)
  if GetVehicleDoorLockStatus(vehicle) == 2 then return end

  if GetVehicleDoorAngleRatio(vehicle, door) > 0.0 then
    SetVehicleDoorShut(vehicle, door, false)
  else
    SetVehicleDoorOpen(vehicle, door, false, false)
  end
end

---Validate door interaction: verify distance to door bone or offset coordinates.
local function canInteractWithDoor(entity, coords, door, useOffset)
  if not GetIsDoorValid(entity, door)
    or GetVehicleDoorLockStatus(entity) > 1
    or IsVehicleDoorDamaged(entity, door)
    or cache.vehicle
  then
    return false
  end

  if useOffset then return true end

  local boneName = DOOR_BONES[door]
  if not boneName then return false end

  local doorBone = GetEntityBoneIndexByName(entity, 'door_' .. boneName)
  if doorBone == -1 then return false end

  if #(coords - GetEntityBonePosition_2(entity, doorBone)) < 0.5 then return true end

  local seatBone = GetEntityBoneIndexByName(entity, 'seat_' .. boneName)
  if seatBone == -1 then return false end

  return #(coords - GetEntityBonePosition_2(entity, seatBone)) < 0.72
end

---Dispatch door toggle: execute locally on owned entities or relay to network owner via server event.
local function onSelectDoor(data, door)
  local entity = data.entity
  if not entity or entity == 0 then return end

  if NetworkGetEntityOwner(entity) == cache.playerId then
    return toggleDoor(entity, door)
  end

  TriggerServerEvent('ox_target:toggleEntityDoor', VehToNet(entity), door)
end

RegisterNetEvent('ox_target:toggleEntityDoor', function(netId, door)
  local entity = NetToVeh(netId)
  if entity and entity ~= 0 then toggleDoor(entity, door) end
end)

local function doorOption(name, localeKey, door, spatial)
  local option = {
    name = 'ox_target:' .. name,
    label = Locale(localeKey),
    icon = spatial.icon,
    distance = 2.0,
    bones = spatial.bones,
    offset = spatial.offset,
    canInteract = function(entity, _distance, coords)
      return canInteractWithDoor(entity, coords, door, spatial.offset ~= nil)
    end,
    onSelect = function(data)
      onSelectDoor(data, door)
    end,
  }
  return option
end

CreateThread(function()
  -- Delay registration: ensure locale strings and targeting store are initialized
  Wait(0)

  Api.addGlobalVehicle({
    doorOption('driverF', 'door_front_driver', 0,
      { icon = 'door', bones = { 'door_dside_f', 'seat_dside_f' } }),
    doorOption('passengerF', 'door_front_passenger', 1,
      { icon = 'door', bones = { 'door_pside_f', 'seat_pside_f' } }),
    doorOption('driverR', 'door_rear_driver', 2,
      { icon = 'door', bones = { 'door_dside_r', 'seat_dside_r' } }),
    doorOption('passengerR', 'door_rear_passenger', 3,
      { icon = 'door', bones = { 'door_pside_r', 'seat_pside_r' } }),
    doorOption('bonnet', 'door_hood', 4,
      { icon = 'car', offset = vec3(0.5, 1.0, 0.5) }),
    doorOption('trunk', 'door_trunk', 5,
      { icon = 'trunk', offset = vec3(0.5, 0.0, 0.5) }),
  })
end)
