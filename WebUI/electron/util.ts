import { app } from 'electron'
import path from 'node:path'

/**
 * XDG-compliant per-user writable data directory for Linux packaged builds.
 * Resolves to $XDG_DATA_HOME/ai-playground or ~/.local/share/ai-playground.
 * All mutable backend data (venvs, downloads, models) lives here on Linux so
 * that the read-only /opt install tree (owned by root) is never written to.
 */
export const linuxDataDir = () => {
  const xdgData =
    process.env.XDG_DATA_HOME || path.join(app.getPath('home'), '.local', 'share')
  return path.join(xdgData, 'ai-playground')
}

export const externalResourcesDir = () => {
  if (app.isPackaged && process.platform === 'linux') {
    return linuxDataDir()
  }
  return path.resolve(app.isPackaged ? process.resourcesPath : path.join(__dirname, '../../external/'))
}

export const getMediaDir = () => {
  let mediaDir: string
  if (process.env.USERPROFILE) {
    mediaDir = path.join(process.env.USERPROFILE, 'Documents', 'AI-Playground', 'media')
  } else if (process.env.HOME) {
    mediaDir = path.join(process.env.HOME, 'AI-Playground', 'media')
  } else {
    mediaDir = path.join(externalResourcesDir(), 'service', 'static', 'sd_out')
  }
  return mediaDir
}
