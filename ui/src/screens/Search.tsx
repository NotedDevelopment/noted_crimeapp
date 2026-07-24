import { useMemo, useState } from 'react'
import { useApp } from '../App'
import { filterReports, timeAgo } from '../helpers'
import '../styles/Search.css'

const COLLAPSED_CHIPS = 4

export default function Search() {
  const { data, go } = useApp()
  const [text, setText] = useState('')
  const [category, setCategory] = useState<string | undefined>()
  const [hasMedia, setHasMedia] = useState(false)
  const [catsOpen, setCatsOpen] = useState(false)
  const [zonesOpen, setZonesOpen] = useState(false)

  const zones = useMemo(
    () => Array.from(new Set(data.reports.map(r => r.zoneLabel).filter(Boolean))),
    [data.reports]
  )

  const results = filterReports(data.reports, { text, category, hasMedia })

  const visibleCats = catsOpen ? data.catalog.categories : data.catalog.categories.slice(0, COLLAPSED_CHIPS)
  const visibleZones = zonesOpen ? zones : zones.slice(0, COLLAPSED_CHIPS)

  return (
    <div className="search">
      <div className="search-bar">
        <button className="search-back" onClick={() => go({ name: 'map' })}><i className="fa-solid fa-chevron-left" /></button>
        <input autoFocus placeholder="Search alerts, streets, areas…" value={text} onChange={e => setText(e.target.value)} />
      </div>

      <div className="search-section">CATEGORY</div>
      <div className="chip-row">
        <button className={`chip ${!category ? 'on' : ''}`} onClick={() => setCategory(undefined)}>All</button>
        {visibleCats.map(c => (
          <button key={c.id} className={`chip ${category === c.id ? 'on' : ''}`} onClick={() => setCategory(c.id)}>{c.label}</button>
        ))}
        {data.catalog.categories.length > COLLAPSED_CHIPS && (
          <button className="chip chip-more" onClick={() => setCatsOpen(o => !o)}>
            {catsOpen ? <i className="fa-solid fa-chevron-left" /> : <>+{data.catalog.categories.length - COLLAPSED_CHIPS} <i className="fa-solid fa-chevron-right" /></>}
          </button>
        )}
      </div>

      {zones.length > 0 && (
        <>
          <div className="search-section">NEIGHBOURHOOD</div>
          <div className="chip-row">
            {visibleZones.map(z => (
              <button key={z} className={`chip ${text.toLowerCase() === z.toLowerCase() ? 'on' : ''}`} onClick={() => setText(z)}>{z}</button>
            ))}
            {zones.length > COLLAPSED_CHIPS && (
              <button className="chip chip-more" onClick={() => setZonesOpen(o => !o)}>
                {zonesOpen ? <i className="fa-solid fa-chevron-left" /> : <>+{zones.length - COLLAPSED_CHIPS} <i className="fa-solid fa-chevron-right" /></>}
              </button>
            )}
          </div>
        </>
      )}

      <button className={`media-toggle ${hasMedia ? 'on' : ''}`} onClick={() => setHasMedia(v => !v)}>
        <i className="fa-solid fa-image" /> With photos / videos
      </button>

      <div className="search-count">{results.length} RESULTS</div>
      <div className="search-results">
        {results.map(r => (
          <button key={r.id} className="search-row" onClick={() => go({ name: 'incident', id: r.id })}>
            <span className="search-icon" style={{ color: data.catalog.severities[r.severity]?.color }}>
              <i className={`fa-solid fa-${data.catalog.categories.find(c => c.id === r.category)?.icon ?? 'triangle-exclamation'}`} />
            </span>
            <span className="search-body">
              <span className="search-meta">{timeAgo(r.createdAt)}</span>
              <span className="search-title">{r.title}</span>
              <span className="search-street"><i className="fa-solid fa-location-dot" /> {r.zoneLabel || r.streetLabel}</span>
            </span>
          </button>
        ))}
      </div>
    </div>
  )
}
