import { createContext, useContext, useEffect, useState } from 'react'
import './App.css'
import type { AppData, Report, Screen } from './types'
import { nuiFetch, onNui, isDev } from './nui'
import Signup from './screens/Signup'
import MapHome from './screens/MapHome'
import Incident from './screens/Incident'
import ReportFlow from './screens/ReportFlow'
import Search from './screens/Search'
import Profile from './screens/Profile'

type Ctx = {
  data: AppData
  setData: (d: AppData) => void
  screen: Screen
  go: (s: Screen) => void
  refresh: () => Promise<void>
  adminMode: boolean
  setAdminMode: (on: boolean) => void
}
const AppCtx = createContext<Ctx>(null as any)
export const useApp = () => useContext(AppCtx)

const DEV_DATA: AppData = {
  account: undefined,
  catalog: {
    categories: [
      { id: 'fight', label: 'Fight in progress', icon: 'hand-fist', severity: 'high' },
      { id: 'shooting', label: 'Shots fired', icon: 'gun', severity: 'critical' },
    ],
    customReports: { enabled: true, severity: 'medium' },
    severities: {
      critical: { label: 'CRITICAL', color: '#ff3b30' }, high: { label: 'HIGH', color: '#ff9500' },
      medium: { label: 'MEDIUM', color: '#eab308' }, low: { label: 'LOW', color: '#34c759' },
    },
    levels: [{ name: 'Reporter', points: 0 }, { name: 'Trusted Citizen', points: 150 }],
    units: 'imperial', media: { maxPerReport: 3, allowVideo: true },
    limits: { username: { min: 3, max: 20 }, password: { min: 4, max: 32 }, title: { max: 60 }, details: { max: 300 }, comment: { max: 200 } },
    appName: 'Citizen',
    sosEnabled: true,
    heatmap: { enabled: true, cellSize: 250, areas: [] },
  },
  reports: [], confirmed: {},
  canModerate: true,
}

const App = () => {
  const [data, setData] = useState<AppData | null>(null)
  const [screen, setScreen] = useState<Screen>({ name: 'map' })
  const [adminMode, setAdminMode] = useState(false)

  const refresh = async (attempt = 0) => {
    const d = isDev ? DEV_DATA : await nuiFetch<AppData>('getAppData')
    // A server-side error (or a cold boot mid-startup) yields an empty
    // payload — never render from it. Retry briefly instead of crashing.
    if (!d?.catalog?.limits) {
      if (attempt < 8) setTimeout(() => refresh(attempt + 1), 1000)
      return
    }
    setData(d)
    setScreen(d.account ? { name: 'map' } : { name: 'signup' })
  }

  useEffect(() => {
    if (isDev) document.body.style.visibility = 'visible'
    refresh()

    // Live report pushes from the server.
    onNui<{ kind: 'add' | 'update' | 'remove'; report: Report }>('reports', ({ kind, report }) => {
      setData(prev => {
        if (!prev) return prev
        let reports = prev.reports
        if (kind === 'remove') reports = reports.filter(r => r.id !== report.id)
        else if (kind === 'add') reports = [report, ...reports.filter(r => r.id !== report.id)]
        else reports = reports.map(r => (r.id === report.id ? report : r))
        return { ...prev, reports }
      })
    })
  }, [])

  if (!data) return <div className="app loading" />

  const ctx: Ctx = {
    data,
    setData: d => setData(d),
    screen,
    go: setScreen,
    refresh,
    adminMode: adminMode && !!data.canModerate,
    setAdminMode,
  }

  return (
    <AppCtx.Provider value={ctx}>
      <div className="app">
        {screen.name === 'signup' && <Signup />}
        {screen.name === 'map' && <MapHome />}
        {screen.name === 'incident' && <Incident id={screen.id} />}
        {screen.name === 'report' && <ReportFlow />}
        {screen.name === 'search' && <Search />}
        {screen.name === 'profile' && <Profile />}
      </div>
    </AppCtx.Provider>
  )
}

export default App
