import { useEffect, useRef, useState } from 'react'
import L from 'leaflet'
import { useApp } from '../App'
import { nuiFetch, nuiAction } from '../nui'
import { gameToLatLng, markerIcon, MAP, atlasUrl } from '../map'
import { timeAgo, isVideoUrl } from '../helpers'
import type { Comment } from '../types'
import '../styles/Incident.css'

export default function Incident({ id }: { id: number }) {
  const { data, setData, go } = useApp()
  const report = data.reports.find(r => r.id === id)
  const miniRef = useRef<HTMLDivElement>(null)
  const [comment, setComment] = useState('')
  const [videoView, setVideoView] = useState<string | null>(null)
  const [canDelete, setCanDelete] = useState(false)
  const confirmed = !!data.confirmed[id]

  useEffect(() => {
    nuiFetch<boolean>('canDelete', { id }).then(v => setCanDelete(!!v))
  }, [id])

  useEffect(() => {
    if (!miniRef.current || !report) return
    const size = MAP.imageSize
    const bounds: L.LatLngBoundsExpression = [[0, 0], [size, size]]
    const map = L.map(miniRef.current, {
      crs: L.CRS.Simple, zoomControl: false, attributionControl: false,
      dragging: false, scrollWheelZoom: false, doubleClickZoom: false, boxZoom: false, keyboard: false,
      touchZoom: false,
      minZoom: MAP.minZoom, maxZoom: MAP.maxZoom,
    })
    L.imageOverlay(atlasUrl, bounds).addTo(map)
    const cat = data.catalog.categories.find(c => c.id === report.category)
    const color = data.catalog.severities[report.severity]?.color || '#ff9500'
    L.marker(gameToLatLng(report.coords.x, report.coords.y), { icon: markerIcon(cat, color) }).addTo(map)
    map.setView(gameToLatLng(report.coords.x, report.coords.y), 2)
    setTimeout(() => map.invalidateSize(), 60)
    return () => { map.remove() }
  }, [id])

  if (!report) {
    return <div className="incident"><button className="inc-back" onClick={() => go({ name: 'map' })}><i className="fa-solid fa-chevron-left" /></button><div className="inc-gone">This report is no longer available.</div></div>
  }

  const sev = data.catalog.severities[report.severity]

  const doConfirm = async () => {
    if (confirmed) return
    const res = await nuiAction<number>('confirmReport', { id })
    if (res.ok) {
      setData({
        ...data,
        confirmed: { ...data.confirmed, [id]: true },
        reports: data.reports.map(r => r.id === id ? { ...r, confirmCount: res.extra ?? r.confirmCount + 1 } : r),
      })
    }
  }

  const doComment = async () => {
    const text = comment.trim()
    if (!text) return
    const res = await nuiAction<Comment>('commentReport', { id, text })
    if (res.ok && res.extra) {
      setComment('')
      setData({ ...data, reports: data.reports.map(r => r.id === id ? { ...r, comments: [...r.comments, res.extra!] } : r) })
    }
  }

  const doDelete = async () => {
    const res = await nuiAction('deleteReport', { id })
    if (res.ok) { setData({ ...data, reports: data.reports.filter(r => r.id !== id) }); go({ name: 'map' }) }
  }

  // Videos get our own overlay player — lb-phone's fullscreen viewer is image-only.
  const openMedia = (src: string) => {
    if (isVideoUrl(src)) setVideoView(src)
    else (window as any).components?.setFullscreenImage(src)
  }

  return (
    <div className="incident">
      <div className="inc-map" ref={miniRef} />
      <button className="inc-back" onClick={() => go({ name: 'map' })}><i className="fa-solid fa-chevron-left" /></button>

      <div className="inc-body">
        <div className="inc-sev" style={{ color: sev?.color }}>● {sev?.label} · {report.categoryLabel}</div>
        <div className="inc-title">{report.title}</div>

        <div className="inc-author">
          {report.author.avatar ? <img src={report.author.avatar} alt="" /> : <span className="inc-avatar-fallback"><i className="fa-solid fa-user" /></span>}
          <div>
            <div className="inc-author-name">{report.author.username}{report.author.badge && <span className="inc-badge">{report.author.badge}</span>}</div>
            <div className="inc-author-time">reported {timeAgo(report.createdAt)}</div>
          </div>
        </div>

        {report.details ? <div className="inc-details">{report.details}</div> : null}

        {report.media.length > 0 && (
          <div className="inc-media">
            {report.media.map((m, i) => (
              <button key={i} className="inc-media-item" onClick={() => openMedia(m)}>
                {isVideoUrl(m)
                  ? <>
                      <video src={m} muted playsInline preload="metadata" />
                      <span className="inc-media-play"><i className="fa-solid fa-play" /></span>
                    </>
                  : <img src={m} alt="evidence" />}
              </button>
            ))}
          </div>
        )}

        <div className="inc-loc"><i className="fa-solid fa-location-dot" /> {report.streetLabel || report.zoneLabel}</div>

        <div className="inc-counts">
          <div className="inc-count"><b>{report.confirmCount}</b><span>Reports</span></div>
          <div className="inc-count"><b>{report.comments.length}</b><span>Comments</span></div>
        </div>

        <div className="inc-actions">
          <button className={`inc-confirm ${confirmed ? 'done' : ''}`} onClick={doConfirm} disabled={confirmed}>
            <i className="fa-solid fa-check" /> {confirmed ? 'Confirmed' : 'I see it too'}
          </button>
          <button className="inc-directions" onClick={() => nuiAction('setWaypoint', { x: report.coords.x, y: report.coords.y })}>
            <i className="fa-solid fa-diamond-turn-right" /> Directions
          </button>
        </div>

        <div className="inc-comments">
          <div className="inc-comments-h">COMMENTS</div>
          {report.comments.length === 0 && <div className="inc-comments-empty">No comments yet. Add what you know.</div>}
          {report.comments.map((c, i) => (
            <div key={i} className="inc-comment">
              <b>{c.username}{c.badge && <span className="inc-badge">{c.badge}</span>}</b> {c.text}
            </div>
          ))}
          <div className="inc-comment-box">
            <input placeholder="Add what you know…" value={comment} maxLength={data.catalog.limits.comment.max} onChange={e => setComment(e.target.value)} />
            <button onClick={doComment}><i className="fa-solid fa-paper-plane" /></button>
          </div>
        </div>

        {canDelete && <button className="inc-delete" onClick={doDelete}><i className="fa-solid fa-trash" /> Delete incident</button>}
      </div>

      {videoView && (
        <div className="inc-video-overlay" onClick={() => setVideoView(null)}>
          <video src={videoView} controls autoPlay playsInline onClick={e => e.stopPropagation()} />
          <button className="inc-video-close" onClick={() => setVideoView(null)}><i className="fa-solid fa-xmark" /></button>
        </div>
      )}
    </div>
  )
}
