import { describe, it, expect } from 'vitest'
import { levelForPoints, formatDistance, bearing, filterReports, isVideoUrl, heatIntensity, heatColor, aggregateHeatByZone } from './helpers'
import type { Report } from './types'

const LEVELS = [
  { name: 'Reporter', points: 0 },
  { name: 'Trusted Citizen', points: 150 },
  { name: 'Local Watch', points: 400 },
]

describe('levelForPoints', () => {
  it('returns first level at 0 points with progress to next', () => {
    const r = levelForPoints(0, LEVELS)
    expect(r.name).toBe('Reporter')
    expect(r.nextName).toBe('Trusted Citizen')
    expect(r.progress).toBeCloseTo(0)
  })
  it('returns mid level and correct progress fraction', () => {
    const r = levelForPoints(300, LEVELS)
    expect(r.name).toBe('Trusted Citizen')
    expect(r.nextName).toBe('Local Watch')
    // (300-150)/(400-150) = 0.6
    expect(r.progress).toBeCloseTo(0.6)
  })
  it('caps at top level with no next', () => {
    const r = levelForPoints(999, LEVELS)
    expect(r.name).toBe('Local Watch')
    expect(r.nextName).toBeUndefined()
    expect(r.progress).toBe(1)
  })
})

describe('formatDistance', () => {
  it('imperial: <1 mile shows feet', () => {
    expect(formatDistance(213.36, 'imperial')).toBe('~700 ft')
  })
  it('imperial: >=1 mile shows miles', () => {
    expect(formatDistance(3218.7, 'imperial')).toBe('~2.0 mi')
  })
  it('imperial: switches to miles above 1000 ft (no huge feet values)', () => {
    // 1600 m ≈ 5249 ft — should read as ~1.0 mi, never "~5250 ft"
    expect(formatDistance(1600, 'imperial')).toBe('~1.0 mi')
    // 457.2 m = 1500 ft → ~0.3 mi
    expect(formatDistance(457.2, 'imperial')).toBe('~0.3 mi')
  })
  it('metric: <1km shows metres', () => {
    expect(formatDistance(700, 'metric')).toBe('~700 m')
  })
  it('metric: >=1km shows km', () => {
    expect(formatDistance(2500, 'metric')).toBe('~2.5 km')
  })
  it('never displays the rounded boundary value in the small unit', () => {
    // 304 m = 997.4 ft, rounds to 1000 → must switch to miles, not "~1000 ft"
    expect(formatDistance(304, 'imperial')).toBe('~0.2 mi')
    expect(formatDistance(997, 'metric')).toBe('~1.0 km')
  })
})

describe('heatIntensity', () => {
  it('all = severity-weighted sum (critical counts most)', () => {
    expect(heatIntensity({ critical: 2, low: 3 }, 'all')).toBe(2 * 4 + 3 * 1)
  })
  it('specific severity = that raw count only', () => {
    expect(heatIntensity({ critical: 2, low: 3 }, 'low')).toBe(3)
    expect(heatIntensity({ critical: 2 }, 'medium')).toBe(0)
  })
})

describe('heatColor', () => {
  it('cold is blue, hot is red, mid is warm', () => {
    expect(heatColor(0)).toBe('rgb(10, 132, 255)')
    expect(heatColor(1)).toBe('rgb(255, 59, 48)')
    expect(heatColor(0.5)).toBe('rgb(255, 204, 0)')
  })
  it('clamps out-of-range input', () => {
    expect(heatColor(-5)).toBe(heatColor(0))
    expect(heatColor(9)).toBe(heatColor(1))
  })
})

describe('aggregateHeatByZone', () => {
  const cells = [
    { x: 0, y: 0, zone: 'Davis', counts: { critical: 3, low: 1 } },
    { x: 1, y: 1, zone: 'Davis', counts: { high: 2 } },
    { x: 2, y: 2, zone: 'Vinewood', counts: { low: 1 } },
    { x: 3, y: 3, zone: '', counts: { high: 9 } }, // unlabeled — excluded
  ]
  it('sums raw report counts per zone, sorted desc', () => {
    expect(aggregateHeatByZone(cells, 'all', [])).toEqual([
      { zone: 'Davis', count: 6 },
      { zone: 'Vinewood', count: 1 },
    ])
  })
  it('filters by severity', () => {
    expect(aggregateHeatByZone(cells, 'critical', [])).toEqual([
      { zone: 'Davis', count: 3 },
      { zone: 'Vinewood', count: 0 },
    ])
  })
  it('always includes config-named areas, even at zero', () => {
    const out = aggregateHeatByZone(cells, 'all', ['Rockford Hills'])
    expect(out[out.length - 1]).toEqual({ zone: 'Rockford Hills', count: 0 })
  })
})

describe('isVideoUrl', () => {
  it('detects common video extensions', () => {
    expect(isVideoUrl('https://x/y/clip.webm')).toBe(true)
    expect(isVideoUrl('https://x/y/clip.mp4?sig=abc')).toBe(true)
    expect(isVideoUrl('https://x/y/photo.png')).toBe(false)
    expect(isVideoUrl('https://x/y/photo.webp')).toBe(false)
  })
})

describe('bearing', () => {
  it('north when target is +Y', () => {
    expect(bearing({ x: 0, y: 0, z: 0 }, { x: 0, y: 100, z: 0 })).toBe('N')
  })
  it('east when target is +X', () => {
    expect(bearing({ x: 0, y: 0, z: 0 }, { x: 100, y: 0, z: 0 })).toBe('E')
  })
})

describe('filterReports', () => {
  const base: Report = {
    id: 1, category: 'fight', categoryLabel: 'Fight in progress', severity: 'high',
    title: 'Fight in progress', details: '', coords: { x: 0, y: 0, z: 0 },
    streetLabel: 'Carson Avenue', zoneLabel: 'Davis',
    author: { username: 'x' }, media: [], confirmCount: 0, comments: [], createdAt: 0,
  }
  const reports: Report[] = [
    base,
    { ...base, id: 2, category: 'theft', categoryLabel: 'Theft', zoneLabel: 'Vinewood', media: ['u'] },
  ]
  it('filters by text against title/street/zone', () => {
    expect(filterReports(reports, { text: 'vinewood' }).map(r => r.id)).toEqual([2])
  })
  it('filters by category', () => {
    expect(filterReports(reports, { category: 'fight' }).map(r => r.id)).toEqual([1])
  })
  it('filters by hasMedia', () => {
    expect(filterReports(reports, { hasMedia: true }).map(r => r.id)).toEqual([2])
  })
})
