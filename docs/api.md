# API Reference

This document details the client-side and server-side API provided by **osm-target**. 

Existing scripts written for `ox_target`, `qb-target`, or `qtarget` are supported out-of-the-box via dialect shims. For compatibility details, see the [Compatibility Guide](compatibility.md).

---

## Client Registration API

Access the client export API using:

```lua
local target = exports.osm_target -- or exports.ox_target
```

### Entity Registration

```lua
-- Register options for a client-side entity handle
target:addLocalEntity(entityHandle, options)
target:removeLocalEntity(entityHandle, optionNames?)

-- Register options for a networked entity by network ID
target:addEntity(netId, options)
target:removeEntity(netId, optionNames?)

-- Register options for all entities sharing a specific model hash
target:addModel(`prop_atm_01`, options)
target:removeModel(`prop_atm_01`, optionNames?)
```

- The first parameter for these functions accepts either a single identifier or an array of identifiers.
- `optionNames` can be a single name or an array of option names. If omitted, all options registered by the calling resource are removed. Removal is scoped to the calling resource.

### Global & Class Registration

```lua
target:addGlobalPed(options)        target:removeGlobalPed(optionNames?)
target:addGlobalVehicle(options)    target:removeGlobalVehicle(optionNames?)
target:addGlobalObject(options)     target:removeGlobalObject(optionNames?)
target:addGlobalPlayer(options)     target:removeGlobalPlayer(optionNames?)

-- Applied whenever any valid target is hit by the raycast
target:addGlobalOption(options)     target:removeGlobalOption(optionNames?)
```

Global class registrations apply to all entities matching the class when raycast. By default, they do not generate world indicators unless `Config.Indicators.includeGlobals` is enabled.

`addGlobalOption` options can also be offered when nothing is targeted by enabling `Config.Interaction.globalsWithoutTarget` or setting `showWithoutTarget = true` on the option. See the [Configuration Guide](configuration.md#untargeted-global-options).

### Zone Registration

Zones are backed by `ox_lib` spatial zones:

```lua
local id = target:addBoxZone({
    coords = vec3(x, y, z),
    size = vec3(2.0, 2.0, 3.0),
    rotation = 45.0,
    debug = false,
    options = { ... },
})

local id = target:addSphereZone({
    coords = vec3(x, y, z),
    radius = 1.5,
    options = { ... },
})

local id = target:addPolyZone({
    points = { vec3(...), vec3(...), vec3(...) },
    thickness = 4.0,
    options = { ... },
})

target:removeZone(id)
local exists = target:zoneExists(id) -- returns boolean
```

### State Management

```lua
-- Enable or disable targeting entirely
target:disableTargeting(disabled)

-- Check if the targeting interface is currently active
local active = target:isActive() -- returns boolean
```

---

## Option Schema

An option table accepts the following configuration:

```lua
{
    name = 'unique_name',        -- Unique identifier for removal and updates
    label = 'Open Trunk',        -- Primary display label (required)
    description = 'Takes a moment', -- Optional secondary description text
    icon = 'trunk',              -- Bundled icon ID or FontAwesome class
    iconColor = '#ff0000',       -- Hex color override for the icon
    badges = {                   -- Optional icon chips rendered alongside label
        { icon = 'power', color = '#3ddc97' },
        { icon = 'eye',   color = '#a06cff' },
    },
    distance = 2.5,              -- Maximum interaction distance in meters

    -- Declarative gates
    groups = 'police',           -- String, array of jobs, or map with grades: { police = 2 }
    gangs = 'ballas',            -- String, array of gangs, or map with grades: { ballas = 1 }
    items = 'lockpick',          -- String, array of items, or map with counts: { lockpick = 2 }
    anyItem = true,              -- If true, possessing ANY declared item satisfies the gate
    citizenid = 'XYZ12345',      -- Specific character identifier requirement
    canInteract = function(entity, distance, coords, name, bone) end,
    showWithoutTarget = true,    -- Global options only: also offer when nothing is targeted (overrides Config.Interaction.globalsWithoutTarget)

    -- Spatial attachments
    bones = { 'boot', 'bonnet' },-- Attached entity bones
    offset = vec3(0.0, 0.0, 0.5),-- Model-space offset vector
    offsetSize = 1.0,            -- Interaction radius around offset
    absoluteOffset = false,      -- true for meters, false for model-dimension fraction

    -- Actions (only one is executed on confirmation)
    onSelect = function(data) end,
    event = 'client:event:name',
    serverEvent = 'server:event:name',
    command = 'command_name',
    export = 'exportName',       -- Invoked on the registering resource
    openMenu = 'submenu_name',   -- Navigates to a submenu
    menuName = 'submenu_name',   -- Specifies that this option belongs to a submenu
}
```

`options` may be passed as a single option table, an array of tables, or a dictionary keyed by option names/labels.

---

## Declarative Gate Requirements

Declared item and group requirements automatically render formatted requirement messages on disabled options:

| Declaration | Rendered Requirement |
|---|---|
| `items = 'lockpick'` | **Requires Lockpick** |
| `items = { lockpick = 2 }` | **Requires Lockpick x2** |
| `items = { 'item_a', 'item_b' }, anyItem = true` | **Requires Item A or Item B** |
| `groups = 'police'` | **Police Only** |
| `groups = { police = 4 }` | **Police (Grade 4) Only** |

Item and group display names are automatically retrieved from the active framework or inventory provider, falling back to prettified identifier strings.

---

## Conditional Interactions (`canInteract`)

Custom predicates can return a boolean and an optional rejection reason string:

```lua
canInteract = function(entity, distance, coords, name, bone)
    if GetVehicleEngineHealth(entity) > 900 then
        return false, 'Engine is not damaged'
    end
    return true
end
```

### Evaluation Hierarchy
1. **Target Validation**: `canInteract` executes to confirm the option applies to the specific entity or context.
2. **Gate Checking**: Job and item gates are evaluated.
3. **Reason Precedence**: If `canInteract` returns `false` with a custom reason string, that reason is displayed. If a declarative gate fails, the gate requirement is formatted and displayed.
4. **Opaque Predicates**: Returning `false` without a reason string hides the option by default (controlled by `Config.Options.hideUnexplained`).
5. **Confirmation Revalidation**: Option eligibility is verified both when rendering the menu and immediately before action execution.

---

## Callback Payload (`onSelect`)

When an option is selected and confirmed, the `onSelect` callback receives a context table:

```lua
onSelect = function(data)
    -- data.entity    Entity handle (nil for zone interactions, 0 for untargeted global options)
    -- data.coords    Vector3 world position of the raycast hit
    -- data.distance  Distance from player to target at confirmation
    -- data.zone      Zone ID (when interaction originated from a zone)
    -- Plus all custom properties defined on the original option table
end
```

For legacy `qb-target` and `qtarget` registrations, the `action` callback maintains backward compatibility and receives the raw entity handle directly.

---

## Icons and Visual Metadata

Options support icons through bundled Phosphor icons or FontAwesome class strings:

```lua
icon = 'lockpick'      -- Bundled Phosphor icon ID
icon = 'fas fa-car'    -- FontAwesome icon class
```

- Unrecognized icon identifiers gracefully fall back to a standard neutral icon.
- `badges`: Accepts an array of up to 3 icon/color pairs for designs that support visual tags (such as Target VI).

---

## Server API

The server module exposes helper exports for configuration and design inspection:

```lua
-- Retrieve active server configuration
local config = exports.osm_target:GetConfig()

-- Retrieve registered designs and tunable schemas
local designs = exports.osm_target:GetDesigns()
```
