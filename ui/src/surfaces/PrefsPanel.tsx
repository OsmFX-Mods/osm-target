import { useEffect, useRef, useState } from 'react'
import { X } from 'lucide-react'
import { fetchNui } from '../lib/nui'
import { Button, Field, NumberSlider, SectionTitle, Toggle } from '../components/primitives'
import type { Preferences } from '../lib/types'

interface Props {
  initial: Preferences
  onClose: () => void
}

const SAVE_DEBOUNCE_MS = 300

export function PrefsPanel({ initial, onClose }: Props) {
  const [prefs, setPrefs] = useState<Preferences>(initial)
  const prefsRef = useRef(prefs)
  const saveTimeout = useRef<ReturnType<typeof setTimeout> | undefined>(undefined)

  // Flush any pending save immediately if the panel closes mid-debounce (button close or the
  // 'prefs:close' NUI event both unmount this component without waiting for the timer).
  useEffect(() => () => {
    if (saveTimeout.current) {
      clearTimeout(saveTimeout.current)
      void fetchNui('savePrefs', prefsRef.current)
    }
  }, [])

  const set = <K extends keyof Preferences>(key: K, value: Preferences[K]) => {
    const next = { ...prefs, [key]: value }
    setPrefs(next)
    prefsRef.current = next
    clearTimeout(saveTimeout.current)
    saveTimeout.current = setTimeout(() => {
      saveTimeout.current = undefined
      void fetchNui('savePrefs', next)
    }, SAVE_DEBOUNCE_MS)
  }

  return (
    <div className="pointer-events-auto absolute inset-0 flex items-center justify-center" style={{ background: 'rgba(0,0,0,0.68)' }}>
      <div
        className="animate-scale-in w-[440px] overflow-hidden rounded-xl border border-white/[0.08]"
        style={{ background: '#0b0b0c', boxShadow: 'var(--shadow-float)' }}
      >
        <div className="flex items-center justify-between border-b border-white/[0.06] px-5 py-3.5">
          <div>
            <div className="t-title">Interaction preferences</div>
            <div className="mt-0.5 text-[11px] text-white/32">Saved on this machine, for you only.</div>
          </div>
          <Button variant="ghost" icon={<X size={14} />} onClick={onClose} aria-label="Close" />
        </div>

        <div className="px-5 py-4">
          <SectionTitle>Display</SectionTitle>
          <div className="divide-y divide-white/[0.04]">
            <Field label="Interface scale" help="Scales the in-world menu, cursor and indicators.">
              <NumberSlider value={prefs.scale} min={50} max={200} step={1} unit="%" onChange={(v) => set('scale', v)} />
            </Field>
            <Field label="Reduced motion" help="Removes entrance, rotation and sweep animation.">
              <Toggle checked={prefs.reducedMotion} onChange={(v) => set('reducedMotion', v)} />
            </Field>
          </div>

          <div className="h-5" />

          <SectionTitle>Sound</SectionTitle>
          <div className="divide-y divide-white/[0.04]">
            <Field label="Volume">
              <NumberSlider value={prefs.volume} min={0} max={100} step={1} unit="%" onChange={(v) => set('volume', v)} />
            </Field>
            <Field label="Mute interaction sounds">
              <Toggle checked={prefs.muted} onChange={(v) => set('muted', v)} />
            </Field>
          </div>
        </div>
      </div>
    </div>
  )
}
