// 打包后自检：Electron 版 dmg 无法直接跑，所以自检 native 壳 + Electron 未打包目录
import { spawn } from 'node:child_process'
import { existsSync } from 'node:fs'
import { join } from 'node:path'

const root = join(import.meta.dirname, '..')
const native = join(root, 'release-native', 'ExPermit.app', 'Contents', 'MacOS', 'ExPermit')
const electron = join(root, 'release', 'mac-arm64', 'ExPermit 实验记录本.app', 'Contents', 'MacOS', 'ExPermit 实验记录本')

function run(bin, label) {
  return new Promise((resolve) => {
    if (!existsSync(bin)) {
      console.log(`- 跳过 ${label}（不存在：${bin}）`)
      return resolve(true)
    }
    const out = []
    const p = spawn(bin, ['--selftest'], { stdio: ['ignore', 'pipe', 'pipe'] })
    p.stdout.on('data', (d) => out.push(String(d)))
    p.stderr.on('data', (d) => out.push(String(d)))
    const t = setTimeout(() => {
      p.kill()
      console.log(`✗ ${label} 自检超时`)
      resolve(false)
    }, 90000)
    p.on('exit', (code) => {
      clearTimeout(t)
      const text = out.join('')
      console.log(text.trim())
      const ok = code === 0 && /SELFTEST(: PASS| OK)/.test(text)
      console.log(ok ? `✓ ${label} 自检通过` : `✗ ${label} 自检失败（exit ${code}）`)
      resolve(ok)
    })
  })
}

const results = []
results.push(await run(native, '原生壳'))
results.push(await run(electron, 'Electron 壳'))
process.exit(results.every(Boolean) ? 0 : 1)
