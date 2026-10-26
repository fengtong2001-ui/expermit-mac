// 从核心仓取发布制品（网页包 + Electron 壳），解到 app/ 下
// 用法：
//   node scripts/fetch-core.mjs --ver 0.1.4                # 从核心仓 Release 下载
//   node scripts/fetch-core.mjs --ver 0.1.4 --core ../expermit-eln   # 本地调试：直接用本地核心仓产物
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { unzipSync } from 'fflate'

const CORE_REPO = 'fengtong2001-ui/expermit-eln'
const root = join(import.meta.dirname, '..')
const arg = (n, d = null) => {
  const i = process.argv.indexOf(n)
  return i > -1 && i + 1 < process.argv.length ? process.argv[i + 1] : d
}
const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'))
const ver = arg('--ver', pkg.version)
const core = arg('--core')
const app = join(root, 'app')

rmSync(app, { recursive: true, force: true })
mkdirSync(join(app, 'www'), { recursive: true })
mkdirSync(join(app, 'shell'), { recursive: true })

function put(dir, map) {
  for (const [path, bytes] of Object.entries(map)) {
    const f = join(dir, path)
    mkdirSync(join(f, '..'), { recursive: true })
    writeFileSync(f, bytes)
  }
}

if (core) {
  const c = resolve(core)
  if (!existsSync(join(c, 'dist', 'index.html'))) throw new Error(`本地核心仓没有 dist/：${c}（先在其目录跑 npm run build）`)
  cpSync(join(c, 'dist'), join(app, 'www'), { recursive: true })
  cpSync(join(c, 'electron', 'main.cjs'), join(app, 'shell', 'main.cjs'))
  cpSync(join(c, 'electron', 'preload.cjs'), join(app, 'shell', 'preload.cjs'))
  cpSync(join(c, 'package.json'), join(root, 'shell-source.json'))
  console.log(`✓ 用本地核心仓：${c}`)
} else {
  async function dl(asset) {
    const url = `https://github.com/${CORE_REPO}/releases/download/v${ver}/${asset}`
    const r = await fetch(url)
    if (!r.ok) throw new Error(`下载失败 ${r.status}：${url}`)
    return new Uint8Array(await r.arrayBuffer())
  }
  put(join(app, 'www'), unzipSync(await dl(`www-${ver}.zip`)))
  put(join(app, 'shell'), unzipSync(await dl(`shell-${ver}.zip`)))
  console.log(`✓ 已从核心仓 v${ver} 取回网页包与壳`)
}

// 版本号跟随核心制品
pkg.version = ver
writeFileSync(join(root, 'package.json'), JSON.stringify(pkg, null, 2) + '\n')
console.log(`✓ app/www 与 app/shell 就绪（版本 ${ver}）`)
