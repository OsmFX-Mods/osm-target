## What's Changed

- **Fixed zone interactions not opening** (e.g. Ammunation and other ox_inventory shop counters): zones are now checked at the point you aim at, with distance measured from the player to that point, exactly like ox_target / qb-target. Small and thin zones work without aiming at their exact centre.
- **Entity + zone options merged** into one menu like ox_target; `response.zone` only set for zone options.
- **Entity fallback raycast** from ox_target so props embedded in map collision stay targetable.
- **Default vehicle interactions enabled**: toggle doors, hood and trunk, matching ox_target defaults. Disable with `Config.Defaults.vehicleDoors = false` or `setr ox_target:defaults 0`.
- **qb-target circle zones** without `useZ` now ignore height, matching PolyZone.
- Raycast length 20 m, ox_target bone-list tolerance, hood/trunk menus anchor at the offset point.
