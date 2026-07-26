export type Coords = { x: number; y: number; z: number }

export type Comment = { id?: number; username: string; badge?: string; text: string; time: number }

export type Category = { id: string; label: string; icon: string; severity: string }

export type Report = {
  id: number
  category: string
  categoryLabel: string
  severity: string
  title: string
  details: string
  coords: Coords
  streetLabel: string
  zoneLabel: string
  author: { username: string; avatar?: string; badge?: string } // citizenid intentionally NOT sent to clients
  media: string[]
  confirmCount: number
  comments: Comment[]
  createdAt: number
}

export type Level = { name: string; nextName?: string; nextPoints?: number }

export type Account = {
  username: string
  avatar?: string
  points: number
  level: Level
  badge?: string
  subscribed: boolean
}

export type Catalog = {
  categories: Category[]
  customReports: { enabled: boolean; severity: string }
  severities: Record<string, { label: string; color: string }>
  levels: { name: string; points: number }[]
  units: 'imperial' | 'metric'
  media: { maxPerReport: number; allowVideo: boolean }
  limits: {
    username: { min: number; max: number }
    password: { min: number; max: number }
    title: { max: number }
    details: { max: number }
    comment: { max: number }
  }
  appName: string
  sosEnabled: boolean
  heatmap: {
    enabled: boolean
    cellSize: number
    areas: { label: string; x: number; y: number }[]
  }
}

export type AppData = {
  account?: Account
  catalog: Catalog
  reports: Report[]
  confirmed: Record<number, boolean>
  canModerate?: boolean
}

export type Screen =
  | { name: 'map' }
  | { name: 'incident'; id: number }
  | { name: 'report' }
  | { name: 'search' }
  | { name: 'profile' }
  | { name: 'signup' }
