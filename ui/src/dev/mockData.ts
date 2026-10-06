import type { DesignManifestEntry, Preferences, StoredConfig, Tunables } from '../lib/types'
import type { MockDesign } from '../designs/shared/mockSchema'

/**
 * Development test fixtures: mock configuration payloads and design manifests for browser preview.
 */
const MOCKS = import.meta.glob<{ mock: MockDesign }>('../designs/*/mock.ts', { eager: true })

/** Sort registered mock designs by directory path order. */
const RAW_DESIGNS: MockDesign[] = Object.keys(MOCKS)
  .sort()
  .map((path) => MOCKS[path].mock)

/** Retrieve default tunables for mock design ID. */
export function defaultsFor(id: string): Tunables {
  const design = RAW_DESIGNS.find((d) => d.id === id)
  if (!design) return {}
  const out: Tunables = {}
  for (const control of design.schema) out[control.key] = control.default
  return { ...out, ...design.overrides }
}

/** Generate mock design manifest entries with default tunables. */
export const MOCK_DESIGNS: DesignManifestEntry[] = RAW_DESIGNS.map((design) => ({
  ...design,
  defaults: defaultsFor(design.id),
}))

/** Initial fallback design ID for local development harness. */
const FIRST_DESIGN = RAW_DESIGNS.some((d) => d.id === 'radial') ? 'radial' : (RAW_DESIGNS[0]?.id ?? '')

function defaultDesignTunables(): Record<string, Tunables> {
  const out: Record<string, Tunables> = {}
  for (const design of RAW_DESIGNS) out[design.id] = defaultsFor(design.id)
  return out
}

export const MOCK_PREFS: Preferences = { scale: 100, volume: 70, muted: false, reducedMotion: false }

const store: { config: StoredConfig } = {
  config: {
    design: FIRST_DESIGN,
    designs: defaultDesignTunables(),
    system: {
      interactDistance: 7, raycastDistance: 12, scanInterval: 50,
      snapAngle: 4, releaseAngle: 9, releaseTime: 180, openTime: 220, closeTime: 160, globalsWithoutTarget: false,
      indicatorsEnabled: true, indicatorRadius: 5, indicatorCap: 8,
      indicatorInterval: 250, indicatorNearAngle: 12, includeGlobals: false,
      menuSize: 0.4, indicatorSize: 0.042, cursorSize: 0.03,
      referenceDistance: 2.5, scaleExponent: 0.5, scaleMin: 0.75, scaleMax: 1.15, anchorLift: 0,
      holdMode: 'hold', interactKey: 'LMENU',
      showDisabled: true, hideUnexplained: true, focusDisabled: true, defaultDistance: 7,
      locale: 'en', debug: false,
    },
  },
}

export function mockConfig(): StoredConfig {
  return clone(store.config)
}

/** Deep clone object using JSON serialization. */
const clone = <T,>(value: T): T => JSON.parse(JSON.stringify(value)) as T

const delay = (ms = 140) => new Promise((resolve) => setTimeout(resolve, ms))

export async function mockData<T = unknown>(event: string, data?: unknown): Promise<T> {
  await delay()

  switch (event) {
    case 'saveConfig':
      store.config = clone(data as StoredConfig)
      return { ok: true } as T

    case 'revertDesign': {
      const { design } = (data ?? {}) as { design: string }
      if (design) store.config.designs[design] = defaultsFor(design)
      return { ok: true } as T
    }

    case 'importConfig': {
      const { blob } = (data ?? {}) as { blob: string }
      try {
        store.config = JSON.parse(blob)
      } catch {
        // Ignore invalid import JSON: prevent applying malformed configuration
      }
      return { ok: true } as T
    }

    default:
      return { ok: true } as T
  }
}
