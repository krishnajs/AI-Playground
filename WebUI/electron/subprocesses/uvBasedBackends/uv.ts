import { app } from 'electron'
import { appLoggerInstance } from '../../logging/logger.ts'
import path from 'path'
import fs from 'fs'
import { spawn } from 'child_process'
import z from 'zod'
import { linuxDataDir } from '../../util.ts'

export const aipgBaseDir = app.isPackaged
  ? process.platform === 'linux'
    ? linuxDataDir()
    : process.resourcesPath
  : path.join(__dirname, '../../../')
// buildResources always points to the read-only resources bundle (contains the uv binary, wheels, etc.)
export const buildResources = app.isPackaged
  ? process.resourcesPath
  : path.join(aipgBaseDir, 'build', 'resources')
const uvBinary = process.platform === 'win32' ? 'uv.exe' : 'uv'
export const uvPath = path.join(buildResources, uvBinary)
const uvEnv = (extraEnv: Record<string, string> = {}) => {
  const linuxTmpDir = (): string | undefined => {
    if (process.platform !== 'linux' || process.env.TMPDIR) return undefined
    // Use /dev/shm for temp files during wheel builds — it is RAM-backed and typically
    // much larger than the root filesystem's /tmp (which shares disk with / and fills up
    // during large installs like OpenVINO/PyTorch).
    const shmTmp = '/dev/shm/aipg-tmp'
    try {
      fs.mkdirSync(shmTmp, { recursive: true })
      return shmTmp
    } catch {
      // /dev/shm unavailable (containers) — fall back to app data dir
      const fallbackTmp = path.join(aipgBaseDir, 'tmp')
      fs.mkdirSync(fallbackTmp, { recursive: true })
      return fallbackTmp
    }
  }

  const tmpDir = linuxTmpDir()

  return {
    ...process.env,
    UV_NO_ENV_FILE: '1',
    UV_NO_CONFIG: '1',
    UV_PYTHON_INSTALL_DIR: path.join(aipgBaseDir, 'python-interpreter'),
    UV_CACHE_DIR: path.join(aipgBaseDir, '.uv-cache'),
    VIRTUAL_ENV: undefined,
    ...(tmpDir ? { TMPDIR: tmpDir } : {}),
    ...extraEnv,
  }
}

const assertUv = async (logger: ReturnType<typeof loggerFor>) => {
  try {
    await fs.promises.access(uvPath, fs.constants.X_OK)
    logger.info(`Found UV executable at ${uvPath}`)
  } catch {
    logger.error(`UV executable not found at ${uvPath}`)
    throw new Error('UV executable not found')
  }
}

const loggerFor = (source: string) => ({
  info: (message: string) => {
    appLoggerInstance.info(message, source)
  },
  error: (message: string) => {
    appLoggerInstance.error(message, source)
  },
  warn: (message: string) => {
    appLoggerInstance.warn(message, source)
  },
})

const uv = (
  uvCommand: string[],
  logger: ReturnType<typeof loggerFor>,
  extraEnv?: Record<string, string>,
) =>
  new Promise<void>((resolve, reject) => {
    logger.info(`Spawning UV process with command: ${uvCommand.join(' ')}`)
    const uvProcess = spawn(uvPath, uvCommand, {
      env: uvEnv(extraEnv),
    })

    const stdoutChunks: string[] = []
    const stderrChunks: string[] = []

    uvProcess.stdout.on('data', (data: Buffer) => {
      const text = data.toString()
      stdoutChunks.push(text)
      logger.info(`UV: ${text}`)
    })

    uvProcess.stderr.on('data', (data: Buffer) => {
      const text = data.toString()
      stderrChunks.push(text)
      logger.error(`UV Error: ${text}`)
    })

    uvProcess.on('close', (code: number) => {
      if (code === 0) {
        logger.info(`UV process completed successfully`)
        resolve()
      } else {
        const stdout = stdoutChunks.join('').trim()
        const stderr = stderrChunks.join('').trim()
        const errorMessage = stderr || stdout || `UV process exited with code ${code}`
        logger.error(`UV process exited with code ${code}`)
        reject(new Error(errorMessage))
      }
    })
  })

const uvWithJsonOutput = (
  uvCommand: string[],
  logger: ReturnType<typeof loggerFor>,
  extraEnv?: Record<string, string>,
) =>
  new Promise<{ exitCode: number; jsonOutput: unknown; stdout: string; stderr: string }>(
    (resolve, reject) => {
      logger.info(`Spawning UV process with command: ${uvCommand.join(' ')}`)
      const uvProcess = spawn(uvPath, uvCommand, {
        env: uvEnv(extraEnv),
      })

      let stdout = ''
      let stderr = ''
      let jsonOutput: unknown = null

      uvProcess.stdout.on('data', (data: Buffer) => {
        const output = data.toString()
        stdout += output
        logger.info(`UV: ${output}`)
      })

      uvProcess.stderr.on('data', (data: Buffer) => {
        const output = data.toString()
        stderr += output
        logger.error(`UV Error: ${output}`)
      })

      uvProcess.on('close', (code: number) => {
        // Try to parse JSON from complete stdout after process closes
        // This handles cases where JSON might be split across multiple chunks
        try {
          // Look for JSON in stdout - it might be on a single line or multiple lines
          const lines = stdout.trim().split('\n')
          for (const line of lines) {
            const trimmed = line.trim()
            if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
              jsonOutput = JSON.parse(trimmed)
              break
            }
          }
          // If no single-line JSON found, try parsing the entire stdout as JSON
          if (!jsonOutput && stdout.trim().startsWith('{')) {
            jsonOutput = JSON.parse(stdout.trim())
          }
        } catch {
          // Not JSON or invalid JSON, jsonOutput remains null
          logger.warn('Could not parse JSON output from uv command')
        }

        resolve({ exitCode: code, jsonOutput, stdout, stderr })
      })

      uvProcess.on('error', (error) => {
        reject(error)
      })
    },
  )

/**
 * Detect if an error message indicates a UV cache hash mismatch
 */
const isHashMismatchError = (errorMessage: string): boolean => {
  return /hash mismatch/i.test(errorMessage)
}

export const ensureBackendVenv = async (backend: string, extraEnv?: Record<string, string>) => {
  const logger = loggerFor(`uv.venv.${backend}`)
  await assertUv(logger)
  const uvVenvCommand = [
    'venv',
    '--directory',
    aipgBaseDir,
    '--project',
    backend,
    '--allow-existing',
    '--relocatable',
  ]
  logger.info(`Ensuring venv for backend: ${backend} with ${JSON.stringify(uvVenvCommand)}`)
  await uv(uvVenvCommand, logger, extraEnv)
}

/**
 * Install packages from requirements.txt into the backend venv using `uv pip`
 * (does not mutate pyproject.toml dependencies — unlike `uv add -r`).
 */
export const pipInstallRequirementsFromFile = async (
  backend: string,
  requirementsTxtPath: string,
  onCacheCorruptionDetected?: () => void,
  extraEnv?: Record<string, string>,
  reinstallPackages?: string[],
) => {
  const logger = loggerFor(`uv.pip-req.${backend}`)
  await assertUv(logger)
  const projectDir = path.join(aipgBaseDir, backend)
  const uvCommand = ['pip', 'install', '--directory', projectDir, '-r', requirementsTxtPath]
  if (reinstallPackages) {
    for (const pkg of reinstallPackages) {
      uvCommand.push('--reinstall-package', pkg)
    }
  }
  logger.info(`pip install -r via uv: ${JSON.stringify(uvCommand)}`)
  try {
    await uv(uvCommand, logger, extraEnv)
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error)
    if (isHashMismatchError(errorMessage)) {
      logger.warn('Hash mismatch in UV cache during pip install, retrying with --no-cache')
      onCacheCorruptionDetected?.()
      await uv([...uvCommand, '--no-cache'], logger, extraEnv)
      return
    }
    throw error
  }
}

export const installBackend = async (
  backend: string,
  onCacheCorruptionDetected?: () => void,
  extraEnv?: Record<string, string>,
) => {
  const logger = loggerFor(`uv.sync.${backend}`)
  await assertUv(logger)
  const uvVenvCommand = [
    'venv',
    '--directory',
    aipgBaseDir,
    '--project',
    backend,
    '--allow-existing',
    '--relocatable',
  ]
  const uvSyncCommand = ['sync', '--directory', aipgBaseDir, '--project', backend]
  logger.info(
    `Installing backend: ${backend} with ${JSON.stringify(uvVenvCommand)} and ${JSON.stringify(uvSyncCommand)}`,
  )
  try {
    await uv(uvVenvCommand, logger, extraEnv)
    return await uv(uvSyncCommand, logger, extraEnv)
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error)

    if (isHashMismatchError(errorMessage)) {
      logger.warn('Hash mismatch detected in UV cache, retrying with --no-cache')
      onCacheCorruptionDetected?.()
      await uv(uvVenvCommand, logger, extraEnv)
      const noCacheCommand = [...uvSyncCommand, '--no-cache']
      return await uv(noCacheCommand, logger, extraEnv)
    }

    throw error
  }
}

export type UvExtra = 'xpu' | 'cuda' | 'cpu'

/**
 * Install a backend using uv sync with a specific extra (e.g. 'xpu', 'cuda', 'cpu').
 */
export const installBackendWithExtra = async (
  backend: string,
  extra: UvExtra,
  onCacheCorruptionDetected?: () => void,
  extraEnv?: Record<string, string>,
) => {
  const logger = loggerFor(`uv.sync-extra.${backend}.${extra}`)
  await assertUv(logger)
  const uvVenvCommand = [
    'venv',
    '--directory',
    aipgBaseDir,
    '--project',
    backend,
    '--allow-existing',
    '--relocatable',
  ]
  const uvSyncCommand = ['sync', '--directory', aipgBaseDir, '--project', backend, '--extra', extra]
  logger.info(
    `Installing backend w/ extra: ${backend} (${extra}) with ${JSON.stringify(uvVenvCommand)} and ${JSON.stringify(uvSyncCommand)}`,
  )
  try {
    await uv(uvVenvCommand, logger, extraEnv)
    return await uv(uvSyncCommand, logger, extraEnv)
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error)

    if (isHashMismatchError(errorMessage)) {
      logger.warn('Hash mismatch detected in UV cache during sync-extra, retrying with --no-cache')
      onCacheCorruptionDetected?.()
      await uv(uvVenvCommand, logger, extraEnv)
      const noCacheCommand = [...uvSyncCommand, '--no-cache']
      return await uv(noCacheCommand, logger, extraEnv)
    }

    throw error
  }
}

export const checkBackend = async (backend: string) => {
  const logger = loggerFor(`uv.check.${backend}`)
  await assertUv(logger)
  const uvCommand = ['sync', '--check', '--directory', aipgBaseDir, '--project', backend]
  logger.info(`Checking backend: ${backend} with ${JSON.stringify(uvCommand)}`)

  return uv(uvCommand, logger)
}

export interface BackendCheckDetails {
  venvExists: boolean
  action: 'create' | 'check' | 'sync' | 'unknown'
  needsInstallation: boolean
  envMismatch: boolean
  exitCode: number
  jsonOutput?: unknown
  stdout?: string
  stderr?: string
}

/**
 * Check backend environment with detailed information about state
 * For ComfyUI, this checks if venv exists rather than exact lockfile match
 */
export const checkBackendWithDetails = async (
  backend: string,
  venvPath: string,
  options?: { skipLockfileCheck?: boolean },
): Promise<BackendCheckDetails> => {
  const logger = loggerFor(`uv.check-details.${backend}`)
  await assertUv(logger)

  // Check if venv directory exists
  let venvExists = false
  try {
    await fs.promises.access(venvPath, fs.constants.F_OK)
    venvExists = true
    logger.info(`Venv directory exists at ${venvPath}`)
  } catch {
    logger.info(`Venv directory does not exist at ${venvPath}`)
    venvExists = false
  }

  if (options?.skipLockfileCheck && venvExists) {
    logger.info(`Skipping uv lockfile check for ${backend} (flexible ComfyUI deps mode)`)
    return {
      venvExists: true,
      action: 'check',
      needsInstallation: false,
      envMismatch: false,
      exitCode: 0,
    }
  }

  // Run uv sync --check with JSON output
  const uvCommand = [
    'sync',
    '--check',
    '--output-format',
    'json',
    '--directory',
    aipgBaseDir,
    '--project',
    backend,
  ]
  logger.info(`Checking backend with details: ${backend} with ${JSON.stringify(uvCommand)}`)

  try {
    const result = await uvWithJsonOutput(uvCommand, logger)
    const parsedResult = z
      .object({
        sync: z.object({
          action: z.enum(['create', 'check', 'sync', 'unknown']),
        }),
      })
      .parse(result.jsonOutput)
    const action = parsedResult.sync.action

    // If exit code is 0, environment is in sync
    if (result.exitCode === 0) {
      return {
        venvExists,
        action,
        needsInstallation: false,
        envMismatch: false,
        exitCode: result.exitCode,
        jsonOutput: result.jsonOutput,
        stdout: result.stdout,
        stderr: result.stderr,
      }
    }

    // Exit code != 0 means environment doesn't match
    // If action is 'create', venv doesn't exist yet
    // If action is 'check', venv exists but doesn't match
    const needsInstallation = !venvExists || action === 'create'
    const envMismatch = venvExists && action === 'check'

    return {
      venvExists,
      action,
      needsInstallation,
      envMismatch,
      exitCode: result.exitCode,
      jsonOutput: result.jsonOutput,
      stdout: result.stdout,
      stderr: result.stderr,
    }
  } catch (error) {
    // If command fails completely, assume environment needs installation if venv doesn't exist
    logger.error(`Failed to check backend details: ${error}`)
    return {
      venvExists,
      action: 'unknown',
      needsInstallation: !venvExists,
      envMismatch: venvExists, // If venv exists but check failed, it's a mismatch
      exitCode: -1,
    }
  }
}

export const installWheel = async (backend: string, wheelPath: string) => {
  const logger = loggerFor(`uv.wheel.${backend}`)
  await assertUv(logger)
  const uvCommand = [
    'pip',
    'install',
    '--no-deps',
    '--directory',
    path.join(aipgBaseDir, backend),
    wheelPath,
  ]
  logger.info(`Installing wheel: ${wheelPath} with ${JSON.stringify(uvCommand)}`)

  return uv(uvCommand, logger)
}

export const installExtraWheels = async (backend: string) => {
  const logger = loggerFor(`uv.wheels.${backend}`)
  const wheelDir = app.isPackaged ? aipgBaseDir : path.join(aipgBaseDir, 'WebUI', 'external')
  logger.info(`Scanning for extra wheels in ${wheelDir}`)
  let entries: string[]
  try {
    entries = await fs.promises.readdir(wheelDir)
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
      logger.info(`No extra wheels directory found at ${wheelDir}`)
      return
    }
    throw error
  }
  const wheelFiles = entries.filter((e) => e.endsWith('.whl'))
  logger.info(`Found extra wheels: ${JSON.stringify(wheelFiles)}`)
  for (const whl of wheelFiles) {
    await installWheel(backend, path.join(wheelDir, whl))
  }
}

/**
 * Check if a Python package is installed in a backend's environment
 */
export const isPackageInstalled = async (
  backend: string,
  packageName: string,
): Promise<boolean> => {
  const logger = loggerFor(`uv.check-package.${backend}`)
  await assertUv(logger)

  // Extract package name from package specifier (handle .whl files and version specs)
  let pkgName = packageName
  if (packageName.endsWith('.whl')) {
    pkgName = packageName.split('/').pop()?.split('-')[0] || packageName
  } else {
    pkgName = packageName.split('==')[0].split('>=')[0].split('<=')[0].trim()
  }

  try {
    // Use uv pip show to check if package is installed
    // This returns exit code 0 if package exists, non-zero if not
    const uvCommand = ['pip', 'show', '--directory', path.join(aipgBaseDir, backend), pkgName]
    logger.info(`Checking if package ${pkgName} is installed`)

    await uv(uvCommand, logger)
    return true
  } catch (_error) {
    // Package not found - this is expected behavior, not an error
    logger.info(`Package ${pkgName} is not installed`)
    return false
  }
}

/**
 * Install a Python package using uv pip
 */
export const installPypiPackage = async (
  backend: string,
  packageSpecifier: string,
  extraEnv?: Record<string, string>,
): Promise<void> => {
  const logger = loggerFor(`uv.install-package.${backend}`)
  await assertUv(logger)

  let pipSpecifier = packageSpecifier

  // Handle .whl files - download if it's a URL
  if (packageSpecifier.endsWith('.whl') && packageSpecifier.startsWith('http')) {
    const fileName = packageSpecifier.split('/').pop() || 'package.whl'
    const downloadPath = path.join(aipgBaseDir, backend, fileName)

    logger.info(`Downloading .whl file from ${packageSpecifier}`)
    const response = await fetch(packageSpecifier)

    if (!response.ok) {
      throw new Error(`Failed to fetch ${packageSpecifier}: ${response.statusText}`)
    }

    const arrayBuffer = await response.arrayBuffer()
    const buffer = Buffer.from(arrayBuffer)
    await fs.promises.writeFile(downloadPath, buffer)
    pipSpecifier = downloadPath
  }
  const uvCommand = ['add', '--directory', path.join(aipgBaseDir, backend), pipSpecifier]
  logger.info(`Installing package ${packageSpecifier}`)

  await uv(uvCommand, logger, extraEnv)

  // Clean up downloaded .whl file if it was a local download
  if (packageSpecifier.endsWith('.whl') && packageSpecifier.startsWith('http')) {
    try {
      await fs.promises.unlink(pipSpecifier)
    } catch {
      // Ignore cleanup errors
    }
  }
}

/**
 * Install requirements from requirements.txt using uv pip
 */
export const installRequirementsTxt = async (
  backend: string,
  requirementsTxtPath: string,
  extraEnv?: Record<string, string>,
): Promise<void> => {
  const logger = loggerFor(`uv.install-requirements.${backend}`)
  await assertUv(logger)

  // Check if requirements.txt exists
  try {
    await fs.promises.access(requirementsTxtPath, fs.constants.R_OK)
  } catch {
    logger.warn(`Requirements file not found: ${requirementsTxtPath}`)
    return
  }

  const uvCommand = [
    'add',
    '--directory',
    path.join(aipgBaseDir, backend),
    '-r',
    requirementsTxtPath,
  ]
  logger.info(`Installing requirements from ${requirementsTxtPath}`)

  await uv(uvCommand, logger, extraEnv)
}

/**
 * Prune the UV cache to reclaim disk space after all backends are installed.
 * Removes cached wheels that are no longer referenced by any installed environment.
 */
export const pruneCache = async (): Promise<void> => {
  const logger = loggerFor('uv.cache-prune')
  await assertUv(logger)
  const cacheDir = path.join(aipgBaseDir, '.uv-cache')
  try {
    const stat = await fs.promises.stat(cacheDir)
    if (!stat.isDirectory()) return
  } catch {
    return
  }
  logger.info('Pruning UV cache to reclaim disk space')
  await uv(['cache', 'prune'], logger)
}

/**
 * Clean /dev/shm temp files created during installation.
 */
export const cleanupTmpDir = (): void => {
  if (process.platform !== 'linux') return
  const shmTmp = '/dev/shm/aipg-tmp'
  try {
    fs.rmSync(shmTmp, { recursive: true, force: true })
  } catch {
    // Best-effort cleanup
  }
}

/**
 * Returns estimated disk usage (in bytes) of the app data directory.
 */
export const getDataDirSizeEstimate = async (): Promise<{ totalBytes: number; cacheBytes: number; venvsBytes: number }> => {
  const logger = loggerFor('uv.disk-usage')
  let totalBytes = 0
  let cacheBytes = 0
  let venvsBytes = 0

  const dirSize = async (dir: string): Promise<number> => {
    let size = 0
    try {
      const entries = await fs.promises.readdir(dir, { withFileTypes: true })
      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name)
        if (entry.isDirectory()) {
          size += await dirSize(fullPath)
        } else {
          try {
            const stat = await fs.promises.stat(fullPath)
            size += stat.size
          } catch {
            // skip inaccessible files
          }
        }
      }
    } catch {
      // skip inaccessible dirs
    }
    return size
  }

  const cachePath = path.join(aipgBaseDir, '.uv-cache')
  cacheBytes = await dirSize(cachePath)

  for (const backend of ['service', 'OpenVINO', 'ComfyUI', 'comfyui-deps']) {
    const venvPath = path.join(aipgBaseDir, backend, '.venv')
    venvsBytes += await dirSize(venvPath)
  }

  totalBytes = cacheBytes + venvsBytes
  logger.info(`Disk usage estimate: total=${(totalBytes / 1e9).toFixed(1)}GB, cache=${(cacheBytes / 1e9).toFixed(1)}GB, venvs=${(venvsBytes / 1e9).toFixed(1)}GB`)
  return { totalBytes, cacheBytes, venvsBytes }
}
