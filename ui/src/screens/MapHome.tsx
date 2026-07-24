import { useEffect, useMemo, useRef, useState } from 'react'
import L from 'leaflet'
import { useApp } from '../App'
import { nuiFetch, isDev } from '../nui'
import { gameToLatLng, markerIcon, MAP, atlasUrl } from '../map'
import { distanceMeters, formatDistance, bearing, timeAgo, heatIntensity, heatColor, aggregateHeatByZone } from '../helpers'
import type { HeatCell } from '../helpers'
import type { Coords } from '../types'
import '../styles/MapHome.css'

type RangeOption = { label: string; meters: number }

const RANGES: Record<'imperial' | 'metric', RangeOption[]> = {
  imperial: [
    { label: '500 ft', meters: 152.4 },
    { label: '0.25 mi', meters: 402.3 },
    { label: '0.5 mi', meters: 804.7 },
    { label: '1 mi', meters: 1609.3 },
    { label: '2 mi', meters: 3218.7 },
    { label: '5 mi', meters: 8046.7 },
  ],
  metric: [
    { label: '250 m', meters: 250 },
    { label: '500 m', meters: 500 },
    { label: '1 km', meters: 1000 },
    { label: '2 km', meters: 2000 },
    { label: '5 km', meters: 5000 },
  ],
}

const RANGE_STORE = 'crimeapp_range'

export default function MapHome() {
  const { data, go } = useApp()
  const units = data.catalog.units === 'metric' ? 'metric' : 'imperial'
  const ranges = RANGES[units]

  const mapRef = useRef<HTMLDivElement>(null)
  const leaflet = useRef<L.Map | null>(null)
  const markerLayer = useRef<L.LayerGroup | null>(null)
  const heatLayer = useRef<L.LayerGroup | null>(null)
  const meMarker = useRef<L.Marker | null>(null)
  const centeredOnMe = useRef(false)

  const [me, setMe] = useState<Coords>({ x: 0, y: 0, z: 0 })
  const [area, setArea] = useState('Los Santos')
  const [rangeOpen, setRangeOpen] = useState(false)
  const [heatOn, setHeatOn] = useState(false)
  const [heatFilter, setHeatFilter] = useState('all')
  const [heatCells, setHeatCells] = useState<HeatCell[] | null>(null)
  const [rankTab, setRankTab] = useState<'dangerous' | 'safest' | null>(null)

  const heatAvailable = !!data.catalog.heatmap?.enabled
  const namedAreas = Array.isArray(data.catalog.heatmap?.areas) ? data.catalog.heatmap.areas : []

  // Alerts sheet: three snap heights (fraction of screen). 'peek' tucks the
  // reports almost fully away so the map is unobstructed and fully draggable.
  const SNAPS = { peek: 0.15, mid: 0.34, full: 0.82 } as const
  type SheetPos = keyof typeof SNAPS
  const rootRef = useRef<HTMLDivElement>(null)
  const [sheet, setSheet] = useState<SheetPos>('mid')
  const [dragH, setDragH] = useState<number | null>(null)
  const dragInfo = useRef<{ startY: number; startH: number; moved: boolean } | null>(null)

  const sheetFrac = dragH ?? SNAPS[sheet]
  const expanded = sheet === 'full'

  const startSheetDrag = (e: React.PointerEvent) => {
    const H = rootRef.current?.clientHeight
    if (!H) return
    dragInfo.current = { startY: e.clientY, startH: dragH ?? SNAPS[sheet], moved: false }

    const move = (ev: PointerEvent) => {
      const d = dragInfo.current
      if (!d) return
      const dy = ev.clientY - d.startY
      if (Math.abs(dy) > 6) d.moved = true
      setDragH(Math.min(0.9, Math.max(0.12, d.startH - dy / H)))
    }
    const up = () => {
      window.removeEventListener('pointermove', move)
      window.removeEventListener('pointerup', up)
      const d = dragInfo.current
      dragInfo.current = null
      setDragH(cur => {
        if (d && !d.moved) {
          // Treat as a tap: peek → mid, mid ↔ full.
          setSheet(s => (s === 'peek' ? 'mid' : s === 'mid' ? 'full' : 'mid'))
          return null
        }
        if (cur != null) {
          let best: SheetPos = 'mid'
          let bestDist = Infinity
          for (const k of Object.keys(SNAPS) as SheetPos[]) {
            const dist = Math.abs(SNAPS[k] - cur)
            if (dist < bestDist) { bestDist = dist; best = k }
          }
          setSheet(best)
        }
        return null
      })
    }
    window.addEventListener('pointermove', move)
    window.addEventListener('pointerup', up)
  }
  const [rangeIdx, setRangeIdx] = useState(() => {
    // getItem() is null when never saved — Number(null) is 0, which would
    // silently pass the guards and default everyone to the smallest range.
    const raw = localStorage.getItem(RANGE_STORE)
    const saved = raw === null ? NaN : Number(raw)
    return Number.isInteger(saved) && saved >= 0 && saved < ranges.length ? saved : Math.min(3, ranges.length - 1)
  })
  const range = ranges[rangeIdx]

  const pickRange = (i: number) => {
    setRangeIdx(i)
    localStorage.setItem(RANGE_STORE, String(i))
    setRangeOpen(false)
  }

  // Keep the atlas covering the viewport: the lowest zoom allowed is the one
  // where the 4096px image still fills the container, so no void is visible.
  const applyCoverZoom = (map: L.Map) => {
    const el = mapRef.current
    if (!el || el.clientWidth < 10 || el.clientHeight < 10) return
    // The alerts sheet hides the bottom ~34% of the viewport. Requiring the
    // atlas to be that much taller than the screen keeps vertical panning
    // available at full zoom-out, so the covered strip can be pulled up into
    // view — while the bounds still guarantee no void is ever visible.
    const effectiveH = el.clientHeight * 1.45
    const cover = Math.log2(Math.max(el.clientWidth, effectiveH) / MAP.imageSize)
    map.setMinZoom(cover)
    if (map.getZoom() < cover) map.setZoom(cover)
  }

  // Poll my position for header, distances, and the blue "me" dot.
  useEffect(() => {
    let alive = true
    const tick = async () => {
      if (isDev) return
      const p = await nuiFetch<{ coords: Coords; streetLabel: string; zoneLabel: string }>('getPosition')
      if (!alive || !p) return
      setMe(p.coords)
      setArea(p.streetLabel || p.zoneLabel || 'Los Santos')

      const map = leaflet.current
      if (!map) return
      const at = gameToLatLng(p.coords.x, p.coords.y)
      if (!meMarker.current) {
        meMarker.current = L.marker(at, {
          icon: L.divIcon({ className: 'me-marker', html: '<div class="me-dot"></div>', iconSize: [18, 18], iconAnchor: [9, 9] }),
          interactive: false, zIndexOffset: 1000,
        }).addTo(map)
      } else {
        meMarker.current.setLatLng(at)
      }
      // First fix: open the map on the player, not the map centre.
      if (!centeredOnMe.current) {
        centeredOnMe.current = true
        map.setView(at, Math.max(0.8, map.getMinZoom()))
      }
    }
    tick()
    const iv = setInterval(tick, 3000)
    return () => { alive = false; clearInterval(iv) }
  }, [])

  // Init Leaflet once.
  useEffect(() => {
    if (!mapRef.current || leaflet.current) return
    const size = MAP.imageSize
    const bounds: L.LatLngBoundsExpression = [[0, 0], [size, size]]
    const map = L.map(mapRef.current, {
      crs: L.CRS.Simple, minZoom: MAP.minZoom, maxZoom: MAP.maxZoom,
      zoomControl: false, attributionControl: false, zoomSnap: 0,
      maxBounds: bounds, maxBoundsViscosity: 1,
      fadeAnimation: false, // snappier on the NUI webview
    })
    L.imageOverlay(atlasUrl, bounds).addTo(map)
    map.setView(gameToLatLng(0, -1000), MAP.defaultZoom)
    markerLayer.current = L.layerGroup().addTo(map)
    // Heat blobs live in their own blurred pane between the atlas (400) and
    // markers (600) — the blur melts adjacent cells into one smooth wave.
    const heatPane = map.createPane('heat')
    heatPane.style.zIndex = '450'
    heatPane.style.pointerEvents = 'none'
    heatPane.style.filter = 'blur(9px)'
    heatLayer.current = L.layerGroup().addTo(map)
    leaflet.current = map

    // Size settles a beat after the phone opens; then lock the cover zoom and
    // keep both fresh if the container resizes (display-size setting, etc).
    setTimeout(() => { map.invalidateSize(); applyCoverZoom(map) }, 60)
    let ro: ResizeObserver | undefined
    if (window.ResizeObserver) {
      ro = new ResizeObserver(() => {
        if (!leaflet.current) return
        leaflet.current.invalidateSize()
        applyCoverZoom(leaflet.current)
      })
      ro.observe(mapRef.current)
    }

    return () => {
      ro?.disconnect()
      leaflet.current?.remove()
      leaflet.current = null
      markerLayer.current = null
      heatLayer.current = null
      meMarker.current = null
    }
  }, [])

  // Toggle heat view: fetch cells lazily on first enable.
  const toggleHeat = async () => {
    const next = !heatOn
    setHeatOn(next)
    if (!next) { setRankTab(null); return }
    if (!heatCells) {
      const res = await nuiFetch<{ cells: HeatCell[] }>('getHeat')
      setHeatCells(Array.isArray(res?.cells) ? res.cells : [])
    }
  }

  // Draw/redraw heat blobs when the view, filter, or data changes.
  useEffect(() => {
    const layer = heatLayer.current
    if (!layer) return
    layer.clearLayers()
    mapRef.current?.classList.toggle('heat-dim', heatOn)
    if (!heatOn || !heatCells) return

    let max = 0
    for (const c of heatCells) max = Math.max(max, heatIntensity(c.counts, heatFilter))
    if (max <= 0) return

    const radius = data.catalog.heatmap.cellSize * MAP.latScale * 1.35
    for (const c of heatCells) {
      const t = heatIntensity(c.counts, heatFilter) / max
      if (t <= 0) continue
      L.circle(gameToLatLng(c.x, c.y), {
        pane: 'heat', radius,
        stroke: false, fillColor: heatColor(t), fillOpacity: 0.3 + 0.4 * t,
      }).addTo(layer)
    }
  }, [heatOn, heatFilter, heatCells])

  // Draw markers whenever reports change.
  useEffect(() => {
    const layer = markerLayer.current
    if (!layer) return
    layer.clearLayers()
    for (const r of data.reports) {
      const cat = data.catalog.categories.find(c => c.id === r.category)
      const color = data.catalog.severities[r.severity]?.color || '#ff9500'
      L.marker(gameToLatLng(r.coords.x, r.coords.y), { icon: markerIcon(cat, color) })
        .addTo(layer)
        .on('click', () => go({ name: 'incident', id: r.id }))
    }
  }, [data.reports])

  // Fly the map to a ranked area: centroid of its heat cells, or the config
  // circle's center for a named area with no heat yet.
  const flyToZone = (zone: string) => {
    const map = leaflet.current
    if (!map) return
    const zoneCells = (heatCells ?? []).filter(c => c.zone === zone)
    let x: number, y: number
    if (zoneCells.length > 0) {
      x = zoneCells.reduce((s, c) => s + c.x, 0) / zoneCells.length
      y = zoneCells.reduce((s, c) => s + c.y, 0) / zoneCells.length
    } else {
      const named = namedAreas.find(a => a.label === zone)
      if (!named) return
      x = named.x
      y = named.y
    }
    setRankTab(null)
    map.setView(gameToLatLng(x, y), Math.max(0.6, map.getMinZoom() + 1), { animate: true })
  }

  const recenter = () => {
    const map = leaflet.current
    // Before the first GPS fix `me` is (0,0,0) — recentering would jump to
    // the world origin, so wait until we actually know where the player is.
    if (!map || !centeredOnMe.current) return
    map.setView(gameToLatLng(me.x, me.y), Math.max(0.8, map.getMinZoom()), { animate: true })
  }

  const withDist = useMemo(() => data.reports
    .map(r => ({ r, d: distanceMeters(me, r.coords) }))
    .sort((a, b) => b.r.createdAt - a.r.createdAt), [data.reports, me])
  const nearby = withDist.filter(x => x.d <= range.meters).length

  const SEV_ORDER = ['critical', 'high', 'medium', 'low']
  const sevChips = SEV_ORDER.filter(s => data.catalog.severities[s])
  const rankings = useMemo(
    () => (rankTab && heatCells ? aggregateHeatByZone(heatCells, heatFilter, namedAreas.map(a => a.label)) : []),
    [rankTab, heatCells, heatFilter, namedAreas]
  )
  const rankRows = rankTab === 'safest' ? [...rankings].reverse().slice(0, 7) : rankings.slice(0, 7)
  const rankMax = Math.max(1, ...rankings.map(r => r.count))

  return (
    <div
      ref={rootRef}
      className={`maphome ${dragH != null ? 'dragging' : ''}`}
      style={{ ['--sheet-h' as string]: `${sheetFrac * 100}%` }}
    >
      <div className="map-header">
        <div className="map-loc"><span className="map-loc-dot" /> {area}</div>
        <div className="map-header-actions">
          {heatAvailable && (
            <button className={heatOn ? 'hdr-on' : ''} onClick={toggleHeat} title="Crime heatmap">
              <i className="fa-solid fa-fire" />
            </button>
          )}
          <button onClick={() => go({ name: 'search' })}><i className="fa-solid fa-magnifying-glass" /></button>
          <button className="map-avatar" onClick={() => go({ name: 'profile' })}>
            {data.account?.avatar ? <img src={data.account.avatar} alt="me" /> : <i className="fa-solid fa-user" />}
          </button>
        </div>
      </div>

      <div ref={mapRef} className="map-canvas" />

      {heatOn && (
        <div className="heat-chips">
          <button className={`heat-chip ${heatFilter === 'all' ? 'on' : ''}`} onClick={() => setHeatFilter('all')}>All</button>
          {sevChips.map(s => (
            <button key={s} className={`heat-chip ${heatFilter === s ? 'on' : ''}`} onClick={() => setHeatFilter(s)}>
              <span className="heat-chip-dot" style={{ background: data.catalog.severities[s].color }} />
              {data.catalog.severities[s].label}
            </button>
          ))}
        </div>
      )}

      {heatOn && (
        <button className="rank-btn" onClick={() => setRankTab(t => (t ? null : 'dangerous'))} title="Area rankings">
          <i className="fa-solid fa-ranking-star" />
        </button>
      )}

      {rankTab && (
        <div className="rank-panel">
          <div className="rank-tabs">
            <button className={rankTab === 'dangerous' ? 'on' : ''} onClick={() => setRankTab('dangerous')}>Most Dangerous</button>
            <button className={rankTab === 'safest' ? 'on' : ''} onClick={() => setRankTab('safest')}>Safest</button>
            <button className="rank-close" onClick={() => setRankTab(null)}><i className="fa-solid fa-xmark" /></button>
          </div>
          <div className="rank-rows">
            {rankRows.map((r, i) => (
              <button key={r.zone} className="rank-row" onClick={() => flyToZone(r.zone)}>
                <span className="rank-num">{i + 1}</span>
                <span className="rank-zone">{r.zone}</span>
                <span className="rank-bar"><span style={{ width: `${Math.round((r.count / rankMax) * 100)}%`, background: rankTab === 'dangerous' ? '#ff453a' : '#34c759' }} /></span>
                <span className="rank-count">{r.count}</span>
                <i className="fa-solid fa-location-arrow rank-go" />
              </button>
            ))}
            {rankRows.length === 0 && <div className="rank-empty">No heat data yet.</div>}
          </div>
        </div>
      )}

      <button className="recenter-btn" onClick={recenter} title="Center on me">
        <i className="fa-solid fa-location-crosshairs" />
      </button>

      <div className={`alerts-sheet ${expanded ? 'expanded' : ''}`}>
        <button className="sheet-grab" onPointerDown={startSheetDrag}>
          <span className="sheet-grab-bar" />
        </button>
        <div className="alerts-head">
          <button className="alerts-head-text" onClick={() => setSheet(s => (s === 'full' ? 'mid' : 'full'))}>
            <span className="alerts-count">{data.reports.length} Active Alerts</span>
            <span
              className="alerts-sub"
              onClick={ev => { ev.stopPropagation(); setRangeOpen(o => !o) }}
            >
              {nearby} within {range.label} · nearby <i className="fa-solid fa-chevron-down alerts-sub-chev" />
            </span>
          </button>
          <button className="report-btn" onClick={() => go({ name: 'report' })}>
            <i className="fa-solid fa-plus" /> Report
          </button>
        </div>

        {rangeOpen && (
          <div className="range-row">
            {ranges.map((opt, i) => (
              <button key={opt.label} className={`range-chip ${i === rangeIdx ? 'on' : ''}`} onClick={() => pickRange(i)}>
                {opt.label}
              </button>
            ))}
          </div>
        )}

        <div className="alerts-list">
          {withDist.map(({ r, d }) => {
            const sev = data.catalog.severities[r.severity]
            return (
              <button key={r.id} className="alert-row" onClick={() => go({ name: 'incident', id: r.id })}>
                <span className="alert-icon" style={{ color: sev?.color }}>
                  <i className={`fa-solid fa-${data.catalog.categories.find(c => c.id === r.category)?.icon ?? 'triangle-exclamation'}`} />
                </span>
                <span className="alert-body">
                  <span className="alert-meta">{timeAgo(r.createdAt)} · {formatDistance(d, units)} {bearing(me, r.coords)}</span>
                  <span className="alert-title">{r.title}</span>
                  <span className="alert-street"><i className="fa-solid fa-location-dot" /> {r.streetLabel || r.zoneLabel}</span>
                  <span className="alert-author">{r.author.username}{r.author.badge ? ` · ${r.author.badge}` : ''}</span>
                </span>
                <i className="fa-solid fa-chevron-right alert-chev" />
              </button>
            )
          })}
          {data.reports.length === 0 && <div className="alerts-empty">No active alerts nearby.</div>}
        </div>
      </div>
    </div>
  )
}
