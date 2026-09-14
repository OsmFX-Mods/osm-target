# Changelog

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
