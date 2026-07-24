const devMode = !(window as any)?.['invokeNative']

export async function nuiFetch<T>(event: string, data?: unknown): Promise<T> {
  if (devMode) return undefined as unknown as T
  return await fetchNui<T>(event, data)
}

export type ActionResult<E = any> = { ok: boolean; err?: string; extra?: E }

export async function nuiAction<E = any>(event: string, data?: unknown): Promise<ActionResult<E>> {
  if (devMode) return { ok: true }
  return await fetchNui<ActionResult<E>>(event, data)
}

export function onNui<T>(event: string, cb: (data: T) => void) {
  if (devMode) return
  useNuiEvent<T>(event, cb)
}

export const isDev = devMode
