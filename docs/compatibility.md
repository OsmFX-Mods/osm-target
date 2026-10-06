# Compatibility Guide

**osm-target** provides comprehensive drop-in compatibility for existing FiveM targeting libraries. Existing resources designed for `ox_target`, `qb-target`, or `qtarget` function seamlessly without code modifications.

---

## Supported Dialects

All primary exports from supported targeting systems are implemented:

```lua
-- ox_target syntax
exports.ox_target:addLocalEntity(ped, { ... })

-- qb-target syntax
exports['qb-target']:AddBoxZone('bank_vault', coords, 1.5, 1.6, { ... }, { options = { ... } })

-- qtarget syntax
exports.qtarget:AddCircleZone('general_store', coords, 1.5, { ... }, { options = { ... } })
```

Dialect options are automatically parsed and translated into the unified internal schema by `shared/compat.lua`.

---

## Custom Option Fields

Custom option properties not consumed during dialect normalization are preserved and forwarded directly to callback handlers and event payloads:

```lua
exports['qb-target']:AddTargetEntity(ped, {
    options = {
        {
            label = 'Open Ammunation',
            type = 'server',
            event = 'qb-shops:server:openShop',
            shop = 'ammunation', -- Custom field forwarded into event payload
        }
    },
    distance = 2.0,
})
```

The server handler receives `data.shop == 'ammunation'`. Custom field forwarding applies consistently across `ox_target`, `qb-target`, and `qtarget` options for `onSelect`, `export`, and client/server events.

Reserved schema properties cannot be overridden by caller custom fields, preventing misrouted events or security escapes. Function references among custom fields are automatically stripped before transmitting server event payloads.

---

## Gate Coverage

| Legacy field | Dialect | Behaviour |
| --- | --- | --- |
| `job` | qb / qtarget | Job gate, grades honoured, `'all'` wildcard |
| `gang` | qb / qtarget | Gang gate, evaluated independently of `job` |
| `excludejob` | qb / qtarget | Hides the option for matching jobs |
| `excludegang` | qb / qtarget | Hides the option for matching gangs |
| `jobType` | qb / qtarget | Requires a matching job type, `'all'` wildcard |
| `excludejobType` | qb / qtarget | Hides the option for matching job types |
| `item` / `required_item` / `items` | qb / qtarget | Item gate with readable requirement |
| `citizenid` | qb / qtarget | Restricts the option to named characters |
| `groups` | ox | Satisfied by any job, any gang, or the player's own citizen id |
| `items` / `anyItem` | ox | Item gate, `anyItem` switches all/any |

On Qbox and QBCore frameworks, the `groups` gate mirrors `qbx_core.HasGroup`: secondary jobs and gangs satisfy the check alongside the active primary job. In contrast, `qb-target` and `qtarget` dialect options evaluate `job` strictly against primary job assignments.

---

## Automatic Gate Resolution

Legacy options declaring requirements via `job`, `gang`, `groups`, `item`, `required_item`, or `items` automatically benefit from formatted requirement messages on disabled options:

```lua
-- Legacy declaration
options = {
    {
        label = 'Crack Safe',
        item = 'lockpick',
        action = function(entity) ... end
    }
}
```

When a player lacks the lockpick, the menu automatically renders a disabled entry stating: **Requires Lockpick**.

---

## Extended `canInteract` Signature

In addition to standard boolean returns, `canInteract` can return a custom reason string when rejecting an interaction:

```lua
canInteract = function(entity, distance, coords, name, bone)
    if GetVehicleEngineHealth(entity) > 900 then
        return false, 'Engine is not damaged'
    end
    return true
end
```

- Returning `false, 'Reason'` displays the option in a disabled state with the custom reason.
- Returning a bare `false` hides the option by default, preserving legacy target behavior. This default can be modified globally via `Config.Options.hideUnexplained = false` or per option via `hideWhenIneligible = false`.

---

## Icon Resolution & Fallbacks

- **Phosphor Icon Identifiers**: Direct icon names (`'lockpick'`, `'car'`, `'wrench'`, `'shield'`).
- **FontAwesome Classes**: Legacy FontAwesome classes (`'fas fa-car'`, `'fas fa-user-shield'`) are dynamically resolved through an internal alias map.
- **Fallbacks**: Unmapped icon references automatically render a neutral mark to ensure UI layout stability.

---

## Behavioral Notes

1. **Mouse Aiming**: osm-target utilizes mouse wheel scrolling for option selection and does not capture NUI focus during standard targeting interactions. `EnableNUI` and `DisableNUI` calls from legacy scripts are safely handled without interfering with mouse aim.
2. **PolyZone Shims**: `qb-target` zone creation functions return a lightweight zone shim supporting `:destroy()` and `:isPointInside(coords)`.
3. **Vertical Bounding**: `minZ` and `maxZ` bounds are mapped to true 3D bounding boxes to ensure vertical zoning accuracy.
4. **Circle Zones**: `qb-target` `AddCircleZone` matches PolyZone: an unbounded vertical cylinder unless `useZ = true`, which makes it a sphere. `qtarget` `AddCircleZone` creates a sphere, matching `ox_target`'s qtarget compat.
5. **Aimed Zone Targeting**: Zones are tested against the camera raycast hit point and option distance is measured from the player to that point, exactly like `ox_target` / `qb-target`. Small zones (shop counters, ATMs) work without aiming at their centre.
6. **Network Entity IDs**: Server event payloads receive `entity` as a network ID (or `0` if non-networked), providing consistent server-side entity resolution.
7. **Entity Statebags & Relays**: Registering options on a networked entity automatically sets the `hasTargetOptions` statebag. The `ox_target:toggleEntityDoor` server event is relayed to the entity owner for compatibility with external vehicle door scripts.
8. **Built-in Vehicle Door Options**: Door, hood and trunk toggles matching `ox_target` defaults are enabled by default. Disable with `Config.Defaults.vehicleDoors = false` or `setr ox_target:defaults 0`.
9. **Disabled vs Hidden Options**: Options failing job, gang, or item checks render in an explained disabled state by default. Set `Config.Options.showDisabled = false` to replicate legacy behavior where ineligible options are hidden completely.
10. **Untargeted Global Options**: `ox_target` shows `addGlobalOption` options even when the raycast hits nothing. osm-target only does this when `Config.Interaction.globalsWithoutTarget = true` (or per option with `showWithoutTarget = true`), anchoring the menu in front of the player and passing entity `0` to `canInteract` and callbacks like `ox_target`. Enable it for scripts that register entity-independent global actions, such as escort/drag "Release" options.
