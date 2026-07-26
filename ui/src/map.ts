import L from 'leaflet'
import type { Category } from './types'

// Same atlas + projection constants noted_gangzones ships.
export const MAP = {
  image: '/ui/dist/img/gtamap.webp',
  imageSize: 4096,
  latBase: 1338, latScale: 0.329,
  lngBase: 1878, lngScale: 0.332,
  minZoom: -3, maxZoom: 3, defaultZoom: 1,
}

// In dev the atlas is served from /img (Vite public/); in prod from /ui/dist/img.
export const atlasUrl = (window as any)?.['invokeNative'] ? MAP.image : '/img/gtamap.webp'

export function gameToLatLng(x: number, y: number): L.LatLngExpression {
  return [MAP.latBase + MAP.latScale * y, MAP.lngBase + MAP.lngScale * x]
}

// Bright marker colors (yellow/orange) drown a white glyph — pick a dark one.
// TESTING: forced to white for now to judge whether the size bump alone is
// enough; restore the luminance line to re-enable dark glyphs.
function glyphColor(_hex: string): string {
  return '#fff'
  // const m = /^#?([0-9a-f]{6})/i.exec(_hex)
  // if (!m) return '#fff'
  // const n = parseInt(m[1], 16)
  // const lum = 0.299 * ((n >> 16) & 255) + 0.587 * ((n >> 8) & 255) + 0.114 * (n & 255)
  // return lum > 160 ? '#141416' : '#fff'
}

export function markerIcon(category: Category | undefined, color: string): L.DivIcon {
  const glyph = category?.icon ?? 'triangle-exclamation'
  return L.divIcon({
    className: 'crime-marker',
    html: `<div class="crime-marker-dot" style="--mk:${color};--mk-fg:${glyphColor(color)}"><i class="fa-solid fa-${glyph}"></i></div>`,
    iconSize: [36, 36],
    iconAnchor: [18, 18],
  })
}
