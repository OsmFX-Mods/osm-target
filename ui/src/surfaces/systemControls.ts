export interface SystemControl {
  key: string
  label: string
  type: 'number' | 'boolean' | 'select' | 'text'
  min?: number
  max?: number
  step?: number
  unit?: string
  help?: string
  options?: { value: string; label: string }[]
}

export interface SystemGroup {
  title: string
  blurb?: string
  controls: SystemControl[]
}

export const SYSTEM_GROUPS: SystemGroup[] = [
  {
    title: 'Interaction',
    blurb: 'The magnetise thresholds are one mechanism, not three sliders. A snap cone wider than the release cone, or no dwell time, makes the menu flicker while scrolling.',
    controls: [
      { key: 'interactDistance', label: 'Interaction distance', type: 'number', min: 1, max: 20, step: 0.5, unit: 'm', help: 'Furthest an interaction can be entered.' },
      { key: 'snapAngle', label: 'Snap angle', type: 'number', min: 1, max: 20, step: 0.5, unit: '°', help: 'Entering this cone locks the target.' },
      { key: 'releaseAngle', label: 'Release angle', type: 'number', min: 2, max: 45, step: 0.5, unit: '°', help: 'Must be exceeded before the menu can let go.' },
      { key: 'releaseTime', label: 'Release dwell', type: 'number', min: 0, max: 1500, step: 10, unit: 'ms', help: 'How long the player must look away before it releases.' },
      { key: 'openTime', label: 'Open animation', type: 'number', min: 0, max: 1200, step: 10, unit: 'ms' },
      { key: 'closeTime', label: 'Dissolve', type: 'number', min: 0, max: 1200, step: 10, unit: 'ms' },
      { key: 'raycastDistance', label: 'Raycast reach', type: 'number', min: 2, max: 40, step: 1, unit: 'm' },
      { key: 'scanInterval', label: 'Scan interval', type: 'number', min: 0, max: 250, step: 5, unit: 'ms', help: 'Time between raycasts while sweeping. Higher is cheaper.' },
    ],
  },
  {
    title: 'Indicators',
    blurb: 'Discovery only runs while the interact key is held, so these settings cost nothing when nobody is interacting.',
    controls: [
      { key: 'indicatorsEnabled', label: 'Show indicators', type: 'boolean', help: 'Off runs a minimal presentation: no world markers, menus only.' },
      { key: 'indicatorRadius', label: 'Indicator radius', type: 'number', min: 1, max: 20, step: 0.5, unit: 'm' },
      { key: 'indicatorCap', label: 'Maximum on screen', type: 'number', min: 1, max: 24, step: 1, help: 'Nearest first. The engine allows 32 draw origins per frame in total.' },
      { key: 'indicatorInterval', label: 'Discovery interval', type: 'number', min: 60, max: 2000, step: 10, unit: 'ms' },
      { key: 'indicatorNearAngle', label: 'Near angle', type: 'number', min: 2, max: 60, step: 1, unit: '°', help: 'Where an indicator switches to its near state.' },
      { key: 'includeGlobals', label: 'Mark every ped and vehicle', type: 'boolean', help: 'Off by default: a global option would otherwise mark every parked car.' },
    ],
  },
  {
    title: 'Rendering',
    blurb: 'Scaling is damped rather than linear, so distance reads as depth without costing legibility at the far end of the range.',
    controls: [
      { key: 'menuSize', label: 'Menu size', type: 'number', min: 0.1, max: 1.2, step: 0.01, help: 'Fraction of screen height at the reference distance.' },
      { key: 'indicatorSize', label: 'Indicator size', type: 'number', min: 0.005, max: 0.2, step: 0.001 },
      { key: 'cursorSize', label: 'Cursor size', type: 'number', min: 0.005, max: 0.2, step: 0.001 },
      { key: 'referenceDistance', label: 'Reference distance', type: 'number', min: 0.5, max: 12, step: 0.1, unit: 'm' },
      { key: 'scaleExponent', label: 'Scale damping', type: 'number', min: 0, max: 2, step: 0.05, help: '0 is flat, 1 is fully linear with distance.' },
      { key: 'scaleMin', label: 'Minimum scale', type: 'number', min: 0.1, max: 2, step: 0.05 },
      { key: 'scaleMax', label: 'Maximum scale', type: 'number', min: 0.1, max: 4, step: 0.05 },
      { key: 'anchorLift', label: 'Anchor lift', type: 'number', min: -2, max: 4, step: 0.1, unit: 'm', help: 'Raises the anchor so a menu on a small prop does not sit inside it.' },
    ],
  },
  {
    title: 'Options',
    blurb: 'Gated options explain themselves from the item and job requirements resources already declare, so this works on scripts you did not write.',
    controls: [
      { key: 'showDisabled', label: 'Show gated options', type: 'boolean', help: 'Off hides them, exactly like older target scripts.' },
      { key: 'hideUnexplained', label: 'Hide unexplained gates', type: 'boolean', help: 'A legacy check that refuses without a reason. On keeps the historical behaviour.' },
      { key: 'focusDisabled', label: 'Gated options are focusable', type: 'boolean', help: 'Needed for the player to scroll onto one and read the requirement.' },
      { key: 'defaultDistance', label: 'Default option distance', type: 'number', min: 1, max: 20, step: 0.5, unit: 'm' },
      { key: 'globalsWithoutTarget', label: 'Global options without a target', type: 'boolean', help: 'Offers addGlobalOption options when nothing is aimed at, in front of the player, like ox_target. Needed for escort "Release" style actions.' },
    ],
  },
  {
    title: 'Input',
    controls: [
      { key: 'holdMode', label: 'Key behaviour', type: 'select', options: [{ value: 'hold', label: 'Hold' }, { value: 'toggle', label: 'Toggle' }] },
      { key: 'interactKey', label: 'Default key', type: 'text', help: 'Applies on next resource start; players can rebind it in FiveM key settings.' },
      { key: 'debug', label: 'Diagnostics overlay', type: 'boolean', help: 'Draws every registration in-world. Server-wide; use /targetdebug for yourself.' },
    ],
  },
]
