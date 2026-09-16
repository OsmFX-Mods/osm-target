# Changelog

## [1.0.3] - 2026-09-16
- Fixed zone interactions (e.g. ox_inventory Ammunation counters) not opening. Zones are now tested against the aimed raycast point with player-to-hit distance, matching ox_target / qb-target, instead of requiring the crosshair within 4 degrees of the zone centre.
- Entity and zone options under the crosshair are now merged into one menu like ox_target, and `response.zone` is only set for options that came from a zone.
- Added ox_target's entity-only fallback raycast (flag 26 with line-of-sight check) so props embedded in map collision stay targetable.
- Bone lists now use ox_target's 1.0 tolerance (single bones keep 2.0). Menus for offset options (hood, trunk) anchor at the offset point.
- Raycast length raised to 20 m (ox_target parity).
- qb-target `AddCircleZone` without `useZ` is now an unbounded vertical cylinder, matching PolyZone.
- Default vehicle door, hood and trunk options are now enabled by default like ox_target (`Config.Defaults.vehicleDoors`, or `setr ox_target:defaults 0`), with ox_target labels.

## [1.0.2] - 2026-09-15
- Fixed target options appearing but not working on click by removing strict function type checks in `qb-target` / `qtarget` compat layers. Cross-resource callbacks arrive as funcrefs (callable tables) in FiveM. (Thanks to cookieocore2026 and koda.codes!)
- Fixed target immediately re-activating after clicking an option while holding the interact key. Selecting an option now cleanly resets the session to idle until the key is pressed again.

## [1.0.1] - 2026-09-12
- Preserved custom keys (`shop`, `args`, custom fields) in option tables passed to callbacks and events.
- Added parity for `ox_target` group checks against gangs and citizen IDs on Qbox.
- Added multi-job and gang resolution via `PlayerData.jobs` and `PlayerData.gangs`.
- Added support for `excludejob`, `excludegang`, `jobType`, and `excludejobType`.
- Added `ox_target:setEntityHasOptions` statebag trigger and `ox_target:toggleEntityDoor` event relay.
- Added default vehicle door options (`Config.Defaults.vehicleDoors`).
- Fixed stop iteration safety and ESX item counting.
- Network payload serialization now strips non-serializable Lua functions.

## [1.0.0] - 2026-09-11
- Initial public release of osm-target.
