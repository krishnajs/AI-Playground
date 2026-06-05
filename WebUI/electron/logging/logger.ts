import WebContents = Electron.WebContents
import fs from 'fs'
import path from 'node:path'
import { app } from 'electron'

class Logger {
  webContents: WebContents | null = null
  private pathToLogFiles: string = path.resolve(
    // In packaged builds, write logs to the user's app data directory
    // (e.g. ~/.config/ai-playground on Linux) which is always writable.
    // process.resourcesPath is root-owned in a deb install and logs would be silently dropped.
    app.isPackaged ? app.getPath('userData') : path.join(__dirname, '../../external/'),
  )
  // Rotate log file when it exceeds this size (5 MB per session is plenty for diagnostics).
  private readonly MAX_LOG_SIZE_BYTES = 5 * 1024 * 1024
  private startupMessageCache: {
    message: string
    source: string
    level: 'error' | 'warn' | 'info'
  }[] = []

  constructor() {}

  onWebcontentReady(webContents: WebContents) {
    this.webContents = webContents
    this.startupMessageCache.forEach((logEntry) => {
      this.webContents!.send('debugLog', logEntry)
    })
    this.startupMessageCache = []
  }

  info(message: string, source: string, alsoLogToFile: boolean = false) {
    if (alsoLogToFile) {
      this.logMessageToFile(message, source)
    }
    console.info(`[${source}]: ${message}`)
    if (this.webContents) {
      try {
        this.webContents.send('debugLog', { level: 'info', source, message })
      } catch (_error) {
        console.error('Could not send debug log to renderer process')
      }
    } else {
      this.startupMessageCache.push({ level: 'info', source, message })
    }
  }

  warn(message: string, source: string, alsoLogToFile: boolean = false) {
    if (alsoLogToFile) {
      this.logMessageToFile(message, source)
    }
    console.warn(`[${source}]: ${message}`)
    if (this.webContents) {
      try {
        this.webContents.send('debugLog', { level: 'warn', source, message })
      } catch (_error) {
        console.error('Could not send debug log to renderer process')
      }
    } else {
      this.startupMessageCache.push({ level: 'error', source, message })
    }
  }

  error(message: string, source: string, alsoLogToFile: boolean = false) {
    if (alsoLogToFile) {
      this.logMessageToFile(message, source)
    }

    console.error(`[${source}]: ${message}`)

    if (this.webContents) {
      try {
        this.webContents.send('debugLog', { level: 'error', source, message })
      } catch (_error) {
        console.error('Could not send debug log to renderer process')
      }
    } else {
      this.startupMessageCache.push({ level: 'error', source, message })
    }
  }

  logMessageToFile(message: string, source: string) {
    const fileName = `${this.getDebugFileName()}.log`
    const filePath = path.join(this.pathToLogFiles, fileName)
    const currentDate = new Date()
    const hours = currentDate.getHours().toString().padStart(2, '0')
    const minutes = currentDate.getMinutes().toString().padStart(2, '0')
    const seconds = currentDate.getSeconds().toString().padStart(2, '0')
    const formattedTime = `${hours}:${minutes}:${seconds}`
    const logMessage = `${formattedTime}|${source}|${message}`

    try {
      // Rotate when the daily log file exceeds the size limit.
      let fileSize = 0
      try {
        fileSize = fs.statSync(filePath).size
      } catch {
        // File doesn't exist yet — that's fine.
      }
      if (fileSize > this.MAX_LOG_SIZE_BYTES) {
        // Truncate rather than append: preserve the path so the user can still find the file.
        fs.writeFileSync(filePath, `--- rotated ${new Date().toISOString()} (previous content exceeded size limit) ---\r\n${logMessage}\r\n`)
        return
      }
      fs.appendFileSync(filePath, logMessage + '\r\n')
    } catch {
      // Swallow write errors (e.g. ENOSPC) so logging never crashes the app.
    }
  }

  getDebugFileName(): string {
    const currentDate = new Date()
    const formattedDate = currentDate.toISOString().split('T')[0]
    return `aip-${formattedDate}`
  }
}

export const appLoggerInstance = new Logger()
