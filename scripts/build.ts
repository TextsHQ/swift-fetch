import os from 'os'
import fs from 'fs/promises'
import { join } from 'path'
import { spawn, SpawnOptions } from 'child_process'
import { build } from 'node-swift'

const isDebug = process.env.NODE_ENV === 'development' || process.argv.includes('--debug')

async function runAndCapture(command: string, args: readonly string[], options: SpawnOptions = {}): Promise<string> {
  return new Promise((res, rej) => {
    let output = ''
    const proc = spawn(command, args, options)
    proc.stdout?.on('data', d => {
      if (d) output += d.toString()
    })
    proc.on('close', code => {
      if (code === 0) res(output)
      else rej(new Error(`command ${command} exited with code: ${code}`))
    })
  })
}

(async () => {
  if (process.argv.includes('--clean')) {
    try {
      await fs.rm(join(__dirname, '..', 'build'), { recursive: true, force: true })
      await fs.unlink(join(__dirname, '..', 'node_modules', 'node-swift', 'NodeSwiftHost', 'Package.resolved'))
    } catch { /* empty */ }
  }

  const swiftFlags = ['-Osize', '-whole-module-optimization']
  const cFlags = ['-Os', '-ffunction-sections', '-fdata-sections']
  const linkerFlags = [] as unknown as [string]

  const osPlatform = os.platform()

  if (osPlatform === 'darwin') {
    const platform = process.env.NODESWIFT_PLATFORM || 'macosx'
    const target = process.env.NODESWIFT_TARGET || 'arm64-apple-macosx10.15'
    const sdkPath = await (await runAndCapture('xcrun', ['-sdk', platform, '-show-sdk-path'])).trimEnd()
    swiftFlags.push('-sdk', sdkPath, '-target', target)
    cFlags.push('-isysroot', sdkPath, '-target', target)
    linkerFlags.push('-dead_strip', '-dead_strip_dylibs')
  } else if (osPlatform === 'linux') {
    linkerFlags.push('--gc-sections')
  }

  if (process.argv.includes('--use-urlsession')) {
    swiftFlags.push('-DUSE_URLSESSION')
    process.env.USE_URLSESSION = '1'
  }

  const binaryPath = await build(isDebug ? 'debug' : 'release', {
    swiftFlags,
    cFlags,
    linkerFlags,
  })

  // we don't want to strip on debug builds
  if (isDebug) return

  const realBinaryPath = await fs.realpath(binaryPath)

  if (osPlatform === 'darwin') {
    await runAndCapture('strip', ['-ur', realBinaryPath])
    await runAndCapture('codesign', ['-fs', '-', realBinaryPath])
  } else if (osPlatform === 'linux') {
    await runAndCapture('strip', [realBinaryPath])
  }
})()
