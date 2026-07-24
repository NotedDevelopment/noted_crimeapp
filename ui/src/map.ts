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

export function markerIcon(category: Category | undefined, color: string): L.DivIcon {
  const glyph = category?.icon ?? 'triangle-exclamation'
  return L.divIcon({
    className: 'crime-marker',
    html: `<div class="crime-marker-dot" style="--mk:${color}"><i class="fa-solid fa-${glyph}"></i></div>`,
    iconSize: [30, 30],
    iconAnchor: [15, 15],
  })
}
