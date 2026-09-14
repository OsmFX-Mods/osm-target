# System Architecture

This document provides a technical overview of **osm-target**, detailing the structural layers, evaluation pipeline, state machine, and DUI rendering lifecycle.

---

## Directory Layout

```
shared/            Pure Lua modules — independent of game natives and frameworks
  schema.lua         Unified option schema definition, table utilities, and gate helpers
  compat.lua         Dialect converters (ox_target / qb-target / qtarget -> internal schema)
  resolver.lua       Pure evaluation engine: candidates + player context -> eligibility & reason
  designs.lua        Design registry: shared tunable schema vocabulary and dynamic
                     registration entry point (`define`)

client/
  framework/         Framework adapter bridge (init.lua + framework-specific adapters)
  api/
    native.lua         ox_target-compatible client export implementation
    qb.lua             qb-target export compatibility layer
    qtarget.lua        qtarget export compatibility layer
  target/
    store.lua          Registration buckets and memory store
    player.lua         Player state cache (groups, gangs, items) for resolver
    discovery.lua      Throttled nearby interaction point discovery
    hit.lua            Raycasting, bone/offset attachment resolution, anchoring, and scaling
    input.lua          Keybind registration, control suppression, and input polling
    machine.lua        Finite state machine for interaction lifecycle
  ui/
    surfaces.lua       DUI lifecycle management, texture creation, and rendering
    nui.lua            Admin panel, player preferences, and audio bridge
  config_sync.lua    Client configuration synchronizer and event handler
  debug.lua          In-world visual diagnostics, /targetexplain, /targetbench, and /targettest
  main.lua           Client initialization and teardown lifecycle

server/
  framework/         Server-side framework adapters
  db.lua             Database schema initialization and revision persistence
  config_store.lua   Configuration validation, persistence, and client broadcasting
  version.lua        Release update checker
  main.lua           Command registration and network event dispatching

designs/           Installed modular design packs (one directory per design)
  <id>/design.lua    Descriptor: identity, tunable schema, default values
  <id>/design.js     Compiled UI bundle fetched at runtime

ui/                React / Vite application bundle (serves NUI and 3D DUI surfaces)
  src/host/          Design SDK published on `window.OsmTargetHost`
  src/designs/       Design source implementations and runtime loader
  src/designs/shared Shared utilities (text fitting, gated states, motion amplitude)
  src/surfaces/      DUI views (menu, indicator, cursor, admin panel, preferences, preview)
  src/lib/           NUI bridge, token registry, icon mappings, and synthesized sound bus

scripts/           Build and packaging tooling for design packs and public distributions
```

The UI project builds into `html/`. A single bundle serves both the screen-space NUI windows (admin panel, preferences) and the in-world DUI surfaces, differentiated via the `surface` query parameter.

Designs are built and distributed **independently** from the host bundle. `html/` exposes the SDK runtime, while `designs/<id>/design.js` provides the modular UI bundle fetched dynamically at runtime. See [Design Packs](./design-packs.md).

---

## Pure Evaluation Layer

The core decision-making logic resides in pure modules within `shared/`, completely decoupled from FiveM natives and game state:

### 1. `shared/resolver.lua`
The single authority on option eligibility:
- Evaluates group, gang, and item gates.
- Evaluates distance limits and spatial attachment requirements.
- Executes `canInteract` predicates securely via `pcall`.
- Applies visibility policies (`showDisabled`, `hideUnexplained`).
- Formats requirement and refusal reasons.
- Re-evaluates options at the moment of confirmation to prevent race conditions.

All game state is passed into the resolver via a pure `context` table, enabling headless testing and isolated evaluation.

### 2. `shared/compat.lua`
Converts external dialect option tables (`ox_target`, `qb-target`, `qtarget`) into the unified internal schema. It handles:
- Key normalization (`job` vs `groups`, `item` vs `required_item` vs `items`).
- Callback and action wrapping.
- Event routing normalization (client event, server event, command).
- Array/map structure flattening with deterministic sorting.

---

## Unified Option Schema

All registration paths convert options into a standardized internal representation:

| Field | Type | Description |
|---|---|---|
| `label` | `string` | Primary display label. |
| `description` | `string?` | Secondary descriptive text. |
| `name` | `string?` | Unique option identifier for targeted removal and updates. |
| `icon` | `string?` | Bundled icon identifier or FontAwesome icon class. |
| `iconColor` | `string?` | Hex color string override for the icon. |
| `badges` | `table[]?` | Array of visual badge descriptors `{ icon, color }`. |
| `distance` | `number` | Maximum interaction distance in meters. |
| `groups` | `gate?` | Job/group requirement. |
| `gangs` | `gate?` | Gang requirement. |
| `items` | `gate?` | Item requirement. |
| `anyItem` | `boolean?` | If true, having any single required item satisfies the gate. |
| `citizenid` | `gate?` | Character identifier requirement. |
| `bones` | `string\|string[]?` | Vehicle/ped bone attachment identifier(s). |
| `offset` | `vector3\|table?` | Model-space offset vector. |
| `offsetSize` | `number?` | Bounding sphere radius around offset. |
| `absoluteOffset` | `boolean?` | If true, offset is in meters; if false, model fraction. |
| `canInteract` | `function?` | Predicate function `(entity, distance, coords, name, bone)`. |
| `hideWhenIneligible`| `boolean?` | Option-level visibility override when ineligible. |
| `onSelect` / `event` / `serverEvent` / `command` | `various` | Action to invoke upon selection. |
| `openMenu` / `menuName` | `string?` | Submenu navigation target / submenu identity. |
| `order` | `number?` | Explicit sort priority (derived from legacy `num` parameter). |
| `resource` | `string` | Registering resource name (used for cleanup). |
| `dialect` | `string` | Dialect used during initial registration (`'ox'`, `'qb'`, `'qtarget'`). |

---

## Registration Store

All registrations are stored in categorized buckets in `client/target/store.lua`:

| Bucket | Purpose |
|---|---|
| `global` | Global options evaluated for all raycast hits. |
| `peds` / `vehicles` / `objects` / `players` | Options registered for specific entity classes. |
| `models[hash]` | Options registered for specific model hashes. |
| `entities[netId]` | Options registered for specific networked entity IDs. |
| `localEntities[handle]` | Options registered for local client entity handles. |
| `zones[id]` | Spatial zones registered via `ox_lib`. |

Resource cleanup is fully automated: when a consuming resource stops, all associated entries across all buckets are removed immediately.

---

## Finite State Machine

The interaction loop operates on a finite state machine:

```
[ IDLE ]
   │  (Hold / Toggle Key)
   ▼
[ SWEEPING ] ──────── (Ray within snapAngle) ────────► [ MAGNETISED ]
   │                                                         │
   │ (Release / Cancel)                                      │ (Open Animation Complete)
   │                                                         ▼
[ IDLE ] ◄────── (Ray beyond releaseAngle / Timeout) ── [ MENU_OPEN ]
                                                             │
                                                             │ (Confirm Selection)
                                                             ▼
                                                        [ EXECUTE & RELEASE ]
```

- **Hysteresis Controls**: `snapAngle`, `releaseAngle`, and `releaseTime` work in tandem to ensure stable locking and prevent unwanted menu closing during camera adjustments.
- **Target Lock**: Once in the `MAGNETISED` or `MENU_OPEN` state, the targeting raycast locks to the active entity until explicitly released.
- **Session End on Execute**: Confirming an actionable option ends the targeting session and returns to `IDLE`, even if the key is still held. The key must be released and pressed again to re-target (matches ox_target / qb-target). Cancelling or looking away while the key is held returns to `SWEEPING` instead.

---

## Spatial Discovery Pipeline

Discovery identifies nearby interactive entities and zones to render world-space indicator markers:

1. **Throttling**: Runs on a configurable timer (default: every 250ms) and only while in the `SWEEPING` state.
2. **Three-Stage Processing**:
   - **Gather**: Collects `(coords, distance)` tuples for nearby zones, explicit entity registrations, and shortlisted model entities.
   - **Order**: Sorts gathered points by distance.
   - **Accept**: Evaluates candidates up to the indicator limit (capped at 24) using lightweight visibility checks.
3. **Pool Scanning**: Object, ped, and vehicle pool scans are cached over an extended radius with distance slack, avoiding per-frame enumeration.

---

## DUI Surface Architecture

Rather than creating DUI browsers per interactive object, browsers are allocated per **surface class**:

| Surface | Instance Count | Resolution | Purpose |
|---|---|---|---|
| `menu` | 1 | 1024x1024 | Active interaction menu. |
| `idle` | 1 | 256x256 | Idle indicator marker sprite. |
| `near` | 1 | 256x256 | Near-focused indicator marker sprite. |
| `active` | 1 | 256x256 | Magnetized indicator marker sprite. |
| `cursor` | 1 | 128x128 | Screen-space aiming reticle. |

All indicator markers in the world share the same DUI texture instances and are drawn at multiple world coordinates within a single frame using native sprite drawing functions.

---

## Performance Optimizations

- **Zero Idle Overhead**: When targeting is inactive, only the keybind listener is registered; no per-frame processing or raycasting occurs.
- **Throttled Operations**: Heavy operations (raycasting, discovery, pool scans) run on dedicated intervals rather than every frame.
- **Deterministic Teardown**: Full cleanup is enforced upon player death, entering pause menu, playing cutscenes, entity despawns, or resource stopping.
