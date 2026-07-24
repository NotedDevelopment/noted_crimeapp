import { useState } from 'react'
import { useApp } from '../App'
import { nuiAction, nuiFetch } from '../nui'
import { isVideoUrl } from '../helpers'
import '../styles/ReportFlow.css'

type Step = { kind: 'grid' } | { kind: 'detail'; category: string; label: string; severity: string; custom?: boolean }

export default function ReportFlow() {
  const { data, go } = useApp()
  const [step, setStep] = useState<Step>({ kind: 'grid' })
  const [title, setTitle] = useState('')
  const [details, setDetails] = useState('')
  const [media, setMedia] = useState<string[]>([])
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState<string | undefined>()

  const sev = (id: string) => data.catalog.severities[id]

  const doSos = async () => {
    const p = await nuiFetch<{ streetLabel: string }>('getPosition')
    const res = await nuiAction('sos', { street: p?.streetLabel })
    if (res.ok) go({ name: 'map' })
    else setErr(res.err)
  }

  const addMedia = () => {
    if (media.length >= data.catalog.media.maxPerReport) return
    // Camera first; user can also pick from gallery via the same component options.
    ;(window as any).useCamera(
      (url: string) => setMedia(m => [...m, url].slice(0, data.catalog.media.maxPerReport)),
      { default: { type: 'Photo', camera: 'rear' }, permissions: { takePhoto: true, takeVideo: data.catalog.media.allowVideo, flipCamera: true, toggleFlash: true } }
    )
  }

  const pickGallery = () => {
    ;(window as any).components?.setGallery({
      includeImages: true, includeVideos: data.catalog.media.allowVideo, multiSelect: true,
      onSelect: (d: any) => {
        const arr = Array.isArray(d) ? d : [d]
        setMedia(m => [...m, ...arr.map((x: any) => x.src)].slice(0, data.catalog.media.maxPerReport))
      },
    })
  }

  const post = async () => {
    if (step.kind !== 'detail') return
    setBusy(true); setErr(undefined)
    const res = await nuiAction('postReport', {
      category: step.custom ? '__custom__' : step.category,
      title: step.custom ? title : undefined,
      details, media,
    })
    setBusy(false)
    if (res.ok) go({ name: 'map' })
    else setErr(res.err || 'Could not post report.')
  }

  if (step.kind === 'grid') {
    return (
      <div className="report grid-step">
        {data.catalog.sosEnabled && (
          <div className="report-actions-top">
            <button className="sos" onClick={doSos}><i className="fa-solid fa-hand" /> SOS — I need help</button>
          </div>
        )}
        <div className="report-h">Report an incident</div>
        <div className="report-sub">Let people around you know what's happening.</div>
        <div className="cat-grid">
          {data.catalog.categories.map(c => (
            <button key={c.id} className="cat-tile" onClick={() => setStep({ kind: 'detail', category: c.id, label: c.label, severity: c.severity })}>
              <i className={`fa-solid fa-${c.icon}`} style={{ color: sev(c.severity)?.color }} />
              <span>{c.label}</span>
            </button>
          ))}
          {data.catalog.customReports.enabled && (
            <button className="cat-tile" onClick={() => setStep({ kind: 'detail', category: '__custom__', label: 'Custom report', severity: data.catalog.customReports.severity, custom: true })}>
              <i className="fa-solid fa-pen" /><span>Custom</span>
            </button>
          )}
        </div>
        <button className="report-cancel" onClick={() => go({ name: 'map' })}>Cancel</button>
      </div>
    )
  }

  const canPost = step.custom ? title.trim().length > 0 : true

  return (
    <div className="report detail-step">
      <button className="report-back" onClick={() => setStep({ kind: 'grid' })}><i className="fa-solid fa-chevron-left" /> Back</button>
      <div className="report-detail-head" style={{ color: sev(step.severity)?.color }}>
        <div className="rd-title">{step.custom ? 'Custom report' : step.label}</div>
        <div className="rd-sub">{sev(step.severity)?.label} · at your location</div>
      </div>

      {step.custom && (
        <input className="rd-input" placeholder="Short title (e.g. Physical altercation)" maxLength={data.catalog.limits.title.max} value={title} onChange={e => setTitle(e.target.value)} />
      )}

      <div className="rd-label">Details (optional)</div>
      <textarea className="rd-textarea" placeholder="Add what you know…" maxLength={data.catalog.limits.details.max} value={details} onChange={e => setDetails(e.target.value)} />

      <div className="rd-label">Photos / videos (optional)</div>
      <div className="rd-media">
        {media.map((m, i) => (
          <div key={i} className="rd-media-item">
            {isVideoUrl(m) ? <video src={m} muted playsInline preload="metadata" /> : <img src={m} alt="" />}
            <button onClick={() => setMedia(media.filter((_, j) => j !== i))}><i className="fa-solid fa-xmark" /></button>
          </div>
        ))}
        {media.length < data.catalog.media.maxPerReport && (
          <>
            <button className="rd-add" onClick={addMedia}><i className="fa-solid fa-camera" /><span>Camera</span></button>
            <button className="rd-add" onClick={pickGallery}><i className="fa-solid fa-images" /><span>Gallery</span></button>
          </>
        )}
      </div>

      {err && <div className="rd-err">{err}</div>}
      <button className="rd-post" disabled={!canPost || busy} onClick={post}>{busy ? 'Posting…' : 'Post report'}</button>
    </div>
  )
}
