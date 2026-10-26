# ExPermit · macOS 版

ExPermit 实验记录本的 **macOS 打包仓**。应用源码（网页层 + 数据模型 + 同步）在
[expermit-eln](https://github.com/fengtong2001-ui/expermit-eln)，本仓只负责任何 macOS 壳与打包。

两种壳，功能一致、体验不同：

| 壳 | 位置 | 特点 |
|---|---|---|
| Electron（与 Windows 同源） | `app/shell` + `electron-builder.yml` | 与 Windows 功能完全对齐：应用内热更新、检查更新、数据位置迁移 |
| Swift 原生 | `native/mac/main.swift` | 系统 WebKit、Liquid Glass、原生文件面板，体积 1–2 MB；无桌面更新功能 |

## 本地构建

```bash
npm install
node scripts/fetch-core.mjs --ver 0.1.4        # 或 --core ../expermit-eln
npx electron-builder --mac                     # → release/*.dmg
./native/mac/build.sh                          # → release-native/ExPermit.app
node scripts/selftest.mjs                      # 两个壳都跑 SELFTEST
```

## 发版

GitHub → Actions → **Build macOS** → Run workflow，填核心版本号。产出 dmg（arm64/x64）
与原生壳 zip 到本仓 Release。未签名：首次打开需右键 →「打开」。

## 约定

- 网页层与 Electron 壳的源码都在核心仓，本仓不改它们；Swift 原生壳只属于本仓。
- 热更新走核心仓制品；完整安装包/下载页指向本仓（`resources/update-config.json`）。
