/**
 * Vitest stub for the `electron` package.
 * Imported whenever tests resolve `import ... from 'electron'`.
 * Individual tests can override specific exports via vi.mock('electron', factory).
 */
import { vi } from 'vitest'

export const app = {
  isPackaged: false,
  getPath: vi.fn(() => '/tmp'),
  getVersion: vi.fn(() => '0.0.0'),
  getName: vi.fn(() => 'ai-playground-test'),
  quit: vi.fn(),
  on: vi.fn(),
  whenReady: vi.fn(() => Promise.resolve()),
}

export const BrowserWindow = class {
  webContents = { send: vi.fn() }
  on = vi.fn()
  loadURL = vi.fn()
  show = vi.fn()
  hide = vi.fn()
  close = vi.fn()
  isDestroyed = vi.fn(() => false)
  static getAllWindows = vi.fn(() => [])
}

export const net = {
  fetch: vi.fn(),
  request: vi.fn(),
}

export const ipcMain = {
  on: vi.fn(),
  handle: vi.fn(),
  removeHandler: vi.fn(),
}

export const shell = {
  openExternal: vi.fn(),
  openPath: vi.fn(),
}

export const dialog = {
  showOpenDialog: vi.fn(),
  showMessageBox: vi.fn(),
}

export const nativeTheme = {
  themeSource: 'system',
  shouldUseDarkColors: false,
}
