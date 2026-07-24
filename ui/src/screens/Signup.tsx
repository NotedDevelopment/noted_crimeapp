import { useState } from 'react'
import { useApp } from '../App'
import { nuiAction } from '../nui'
import '../styles/Signup.css'

type Mode = 'landing' | 'create' | 'login'

export default function Signup() {
  const { data, refresh } = useApp()
  const lim = data.catalog.limits.username
  const plim = data.catalog.limits.password
  const [mode, setMode] = useState<Mode>('landing')
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [avatar, setAvatar] = useState<string | undefined>()
  const [err, setErr] = useState<string | undefined>()
  const [busy, setBusy] = useState(false)

  const switchMode = (m: Mode) => {
    setMode(m)
    setErr(undefined)
    setPassword('')
    setConfirm('')
  }

  const pickAvatar = () => {
    ;(window as any).components?.setGallery({
      includeImages: true, includeVideos: false, multiSelect: false,
      onSelect: (d: any) => setAvatar(Array.isArray(d) ? d[0]?.src : d?.src),
    })
  }

  const submitCreate = async () => {
    setErr(undefined)
    if (password.length < plim.min || password.length > plim.max) {
      setErr(`Password must be ${plim.min}–${plim.max} characters.`)
      return
    }
    if (password !== confirm) {
      setErr('Passwords do not match.')
      return
    }
    setBusy(true)
    const res = await nuiAction('signup', { username, password, avatar })
    setBusy(false)
    if (res.ok) refresh()
    else setErr(res.err || 'Could not create account.')
  }

  const submitLogin = async () => {
    setErr(undefined)
    setBusy(true)
    const res = await nuiAction('login', { username, password })
    setBusy(false)
    if (res.ok) refresh()
    else setErr(res.err || 'Could not log in.')
  }

  const validName = username.length >= lim.min && username.length <= lim.max

  if (mode === 'landing') {
    return (
      <div className="signup">
        <div className="signup-hero">
          <div className="signup-brand">{data.catalog.appName}</div>
          <div className="signup-tag">See what's happening around you.</div>
        </div>
        <div className="signup-landing-actions">
          <button className="signup-submit" onClick={() => switchMode('create')}>Create account</button>
          <button className="signup-alt" onClick={() => switchMode('login')}>Log in</button>
        </div>
      </div>
    )
  }

  if (mode === 'login') {
    return (
      <div className="signup">
        <button className="signup-back" onClick={() => switchMode('landing')}><i className="fa-solid fa-chevron-left" /> Back</button>
        <div className="signup-brand">Log in</div>
        <div className="signup-tag">Welcome back, reporter.</div>

        <input className="signup-input" placeholder="Username" maxLength={lim.max}
          value={username} onChange={e => setUsername(e.target.value)} />
        <input className="signup-input" type="password" placeholder="Password" maxLength={plim.max}
          value={password} onChange={e => setPassword(e.target.value)} />
        {err && <div className="signup-err">{err}</div>}

        <button className="signup-submit" disabled={!validName || password.length === 0 || busy} onClick={submitLogin}>
          {busy ? 'Logging in…' : 'Log in'}
        </button>
        <button className="signup-link" onClick={() => switchMode('create')}>New here? Create an account</button>
      </div>
    )
  }

  return (
    <div className="signup">
      <button className="signup-back" onClick={() => switchMode('landing')}><i className="fa-solid fa-chevron-left" /> Back</button>
      <div className="signup-brand">Create account</div>
      <div className="signup-tag">Set up your reporter profile</div>

      <button className="signup-avatar" onClick={pickAvatar}>
        {avatar ? <img src={avatar} alt="avatar" /> : <i className="fa-solid fa-camera" />}
      </button>

      <input className="signup-input" placeholder="Username" maxLength={lim.max}
        value={username} onChange={e => setUsername(e.target.value)} />
      <input className="signup-input" type="password" placeholder="Password" maxLength={plim.max}
        value={password} onChange={e => setPassword(e.target.value)} />
      <input className="signup-input" type="password" placeholder="Confirm password" maxLength={plim.max}
        value={confirm} onChange={e => setConfirm(e.target.value)} />
      {err && <div className="signup-err">{err}</div>}

      <button className="signup-submit" disabled={!validName || password.length === 0 || confirm.length === 0 || busy} onClick={submitCreate}>
        {busy ? 'Creating…' : 'Create account'}
      </button>
      <button className="signup-link" onClick={() => switchMode('login')}>Already have an account? Log in</button>
    </div>
  )
}
