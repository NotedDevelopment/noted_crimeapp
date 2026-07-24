import type { Coords, Report } from './types'

export function levelForPoints(
  points: number,
  levels: { name: string; points: number }[]
): { name: string; nextName?: string; nextPoints?: number; progress: number } {
  let current = levels[0]
  let next: { name: string; points: number } | undefined
  for (const lvl of levels) {
    if (points >= lvl.points) current = lvl
    else if (!next) next = lvl
  }
  if (!next) return { name: current.name, progress: 1 }
  const span = next.points - current.points
  const progress = span <= 0 ? 0 : Math.max(0, Math.min(1, (points - current.points) / span))
  return { name: current.name, nextName: next.name, nextPoints: next.points, progress }
}

export function formatDistance(meters: number, units: 'imperial' | 'metric'): string {
  if (units === 'imperial') {
    // Feet stop being readable fast — switch to miles beyond 1000 ft.
    // Branch on the ROUNDED value so "~1000 ft" can never be displayed.
    const feet = meters * 3.28084
    const roundedFeet = Math.round(feet / 10) * 10
    if (roundedFeet < 1000) return `~${roundedFeet} ft`
    return `~${(feet / 5280).toFixed(1)} mi`
  }
  const roundedMeters = Math.round(meters / 10) * 10
  if (roundedMeters < 1000) return `~${roundedMeters} m`
  return `~${(meters / 1000).toFixed(1)} km`
}

export function distanceMeters(a: Coords, b: Coords): number {
  const dx = a.x - b.x
  const dy = a.y - b.y
  return Math.sqrt(dx * dx + dy * dy)
}

const DIRS = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW']
export function bearing(from: Coords, to: Coords): string {
  const angle = Math.atan2(to.x - from.x, to.y - from.y) * (180 / Math.PI) // 0 = North(+Y), CW
  const idx = Math.round(((angle % 360) + 360) % 360 / 45) % 8
  return DIRS[idx]
}

// ── Crime heatmap ────────────────────────────────────────────────────────
export type HeatCounts = Record<string, number>
export type HeatCell = { x: number; y: number; zone: string; counts: HeatCounts }

const SEV_WEIGHTS: Record<string, number> = { critical: 4, high: 3, medium: 2, low: 1 }

// Blob intensity: 'all' weights severe crime hotter; a specific severity
// filter shows that severity's raw count.
export function heatIntensity(counts: HeatCounts, filter: string): number {
  if (filter === 'all') {
    let sum = 0
    for (const [sev, n] of Object.entries(counts)) sum += n * (SEV_WEIGHTS[sev] ?? 1)
    return sum
  }
  return counts[filter] ?? 0
}

// 0 → cool blue, 0.5 → yellow, 1 → hot red.
export function heatColor(t: number): string {
  const c = Math.max(0, Math.min(1, t))
  const lerp = (a: number, b: number, f: number) => Math.round(a + (b - a) * f)
  const from = c < 0.5 ? [10, 132, 255] : [255, 204, 0]
  const to = c < 0.5 ? [255, 204, 0] : [255, 59, 48]
  const f = c < 0.5 ? c * 2 : (c - 0.5) * 2
  return `rgb(${lerp(from[0], to[0], f)}, ${lerp(from[1], to[1], f)}, ${lerp(from[2], to[2], f)})`
}

// Rankings: raw report counts per area under the active filter, sorted desc.
// Config-named areas are always present (zero-filled) so "Safest" can rank
// genuinely quiet places; unlabeled cells are excluded.
export function aggregateHeatByZone(
  cells: HeatCell[],
  filter: string,
  namedAreas: string[]
): { zone: string; count: number }[] {
  const totals = new Map<string, number>()
  for (const name of namedAreas) totals.set(name, 0)
  for (const cell of cells) {
    if (!cell.zone) continue
    let n = 0
    if (filter === 'all') {
      for (const v of Object.values(cell.counts)) n += v
    } else {
      n = cell.counts[filter] ?? 0
    }
    totals.set(cell.zone, (totals.get(cell.zone) ?? 0) + n)
  }
  return [...totals.entries()]
    .map(([zone, count]) => ({ zone, count }))
    .sort((a, b) => b.count - a.count || a.zone.localeCompare(b.zone))
}

// lb-phone media uploads keep their file extension — good enough to tell
// video attachments from photos at render time.
export function isVideoUrl(url: string): boolean {
  return /\.(webm|mp4|m4v|ogv|ogg|mov)(\?|#|$)/i.test(url)
}

export function timeAgo(unixSeconds: number, now = Date.now() / 1000): string {
  const s = Math.max(0, now - unixSeconds)
  if (s < 60) return 'just now'
  const m = Math.floor(s / 60)
  if (m < 60) return `${m} min ago`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h} h ago`
  return `${Math.floor(h / 24)} d ago`
}

export function filterReports(
  reports: Report[],
  f: { text?: string; category?: string; hasMedia?: boolean }
): Report[] {
  const text = (f.text || '').trim().toLowerCase()
  return reports.filter(r => {
    if (f.category && r.category !== f.category) return false
    if (f.hasMedia && r.media.length === 0) return false
    if (text) {
      const hay = `${r.title} ${r.streetLabel} ${r.zoneLabel} ${r.categoryLabel}`.toLowerCase()
      if (!hay.includes(text)) return false
    }
    return true
  })
}
