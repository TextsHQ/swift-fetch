import { spawn, SpawnOptions } from 'child_process'
import os from 'os'
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
  const swiftFlags = [] as unknown as [string]
  const cFlags = [] as unknown as [string]

  if (os.platform() === 'darwin') {
    const platform = process.env.NODESWIFT_PLATFORM || 'macosx'
    const target = process.env.NODESWIFT_TARGET || 'arm64-apple-macosx10.15'
    const sdkPath = await (await runAndCapture('xcrun', ['-sdk', platform, '-show-sdk-path'])).trimEnd()
    swiftFlags.push('-sdk', sdkPath, '-target', target)
    cFlags.push('-isysroot', sdkPath, '-target', target)
  }

  await build(isDebug ? 'debug' : 'release', {
    swiftFlags,
    cFlags,
  })
})()
