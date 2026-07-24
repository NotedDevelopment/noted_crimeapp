import { useState } from 'react'
import { useApp } from '../App'
import { nuiAction } from '../nui'
import { levelForPoints, timeAgo } from '../helpers'
import '../styles/Profile.css'

export default function Profile() {
  const { data, setData, go, refresh } = useApp()
  const acc = data.account
  const [subscribed, setSubscribed] = useState(!!acc?.subscribed)
  const [pwOpen, setPwOpen] = useState(false)
  const [pwCurrent, setPwCurrent] = useState('')
  const [pwNew, setPwNew] = useState('')
  const [pwConfirm, setPwConfirm] = useState('')
  const [pwMsg, setPwMsg] = useState<{ ok: boolean; text: string } | null>(null)
  const [pwBusy, setPwBusy] = useState(false)

  if (!acc) { go({ name: 'signup' }); return null }

  const plim = data.catalog.limits.password
  const lvl = levelForPoints(acc.points, data.catalog.levels)
  const mine = data.reports.filter(r => r.author.username === acc.username)

  const toggleSub = async () => {
    const next = !subscribed
    setSubscribed(next)
    const res = await nuiAction('setSubscribed', { value: next })
    if (res.ok) setData({ ...data, account: { ...acc, subscribed: next } })
    else setSubscribed(!next)
  }

  const submitPassword = async () => {
    setPwMsg(null)
    if (pwNew.length < plim.min || pwNew.length > plim.max) {
      setPwMsg({ ok: false, text: `New password must be ${plim.min}–${plim.max} characters.` })
      return
    }
    if (pwNew !== pwConfirm) {
      setPwMsg({ ok: false, text: 'New passwords do not match.' })
      return
    }
    setPwBusy(true)
    const res = await nuiAction('changePassword', { current: pwCurrent, new: pwNew })
    setPwBusy(false)
    if (res.ok) {
      setPwMsg({ ok: true, text: 'Password updated.' })
      setPwCurrent(''); setPwNew(''); setPwConfirm('')
    } else {
      setPwMsg({ ok: false, text: res.err || 'Could not update password.' })
    }
  }

  const signOut = async () => {
    await nuiAction('logout')
    refresh() // re-hydrates with no account → routes to the auth screen
  }

  return (
    <div className="profile">
      <div className="profile-top">
        <button className="profile-back" onClick={() => go({ name: 'map' })}><i className="fa-solid fa-chevron-left" /></button>
        <div className="profile-title">Profile</div>
      </div>

      <div className="profile-avatar">{acc.avatar ? <img src={acc.avatar} alt="" /> : <i className="fa-solid fa-user" />}</div>
      <div className="profile-name">{acc.username}</div>
      <div className="profile-handle">@{acc.username}</div>
      {acc.badge && <div className="profile-badge"><i className="fa-solid fa-shield-halved" /> {acc.badge}</div>}

      <div className="rep-card">
        <div className="rep-row"><span className="rep-level"><i className="fa-solid fa-star" /> {lvl.name}</span><span className="rep-pts">{acc.points} pts</span></div>
        <div className="rep-bar"><div className="rep-fill" style={{ width: `${Math.round(lvl.progress * 100)}%` }} /></div>
        {lvl.nextName && <div className="rep-next">{(lvl.nextPoints ?? 0) - acc.points} pts to {lvl.nextName}</div>}
      </div>

      <label className="sub-toggle">
        <span><i className="fa-solid fa-bell" /> Nearby alert notifications</span>
        <input type="checkbox" checked={subscribed} onChange={toggleSub} />
      </label>

      <button className="pw-toggle" onClick={() => { setPwOpen(o => !o); setPwMsg(null) }}>
        <span><i className="fa-solid fa-key" /> Reset password</span>
        <i className={`fa-solid fa-chevron-${pwOpen ? 'up' : 'down'}`} />
      </button>
      {pwOpen && (
        <div className="pw-form">
          <input type="password" placeholder="Current password" maxLength={plim.max}
            value={pwCurrent} onChange={e => setPwCurrent(e.target.value)} />
          <input type="password" placeholder="New password" maxLength={plim.max}
            value={pwNew} onChange={e => setPwNew(e.target.value)} />
          <input type="password" placeholder="Confirm new password" maxLength={plim.max}
            value={pwConfirm} onChange={e => setPwConfirm(e.target.value)} />
          {pwMsg && <div className={pwMsg.ok ? 'pw-ok' : 'pw-err'}>{pwMsg.text}</div>}
          <button className="pw-submit" disabled={pwBusy || pwNew.length === 0 || pwConfirm.length === 0} onClick={submitPassword}>
            {pwBusy ? 'Updating…' : 'Update password'}
          </button>
        </div>
      )}

      <div className="profile-section">YOUR REPORTS · {mine.length}</div>
      <div className="profile-reports">
        {mine.length === 0 && <div className="profile-empty">You haven't reported anything yet.</div>}
        {mine.map(r => (
          <button key={r.id} className="profile-report" onClick={() => go({ name: 'incident', id: r.id })}>
            <span>{r.title}</span><span className="pr-time">{timeAgo(r.createdAt)}</span>
          </button>
        ))}
      </div>

      <button className="sign-out" onClick={signOut}><i className="fa-solid fa-right-from-bracket" /> Sign out</button>
    </div>
  )
}
