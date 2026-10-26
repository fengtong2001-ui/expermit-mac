#!/bin/bash
# 构建 macOS 原生壳（Swift + WKWebView）：把 app/www（核心制品）装进 .app，产物在 release-native/
# 依赖：本机 Command Line Tools（无需完整 Xcode）。显式指 CLT，避免 /usr/bin shim 被许可检查挡住。
set -euo pipefail
cd "$(dirname "$0")/../.."

WWW="${1:-app/www}"
if [ ! -f "$WWW/index.html" ]; then
  echo "缺少 $WWW/index.html：先跑 node scripts/fetch-core.mjs（或 --core ../expermit-eln）" >&2
  exit 1
fi

OUT="release-native"
APP="$OUT/ExPermit.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "—— 编译 Swift 壳 ——"
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
export SDKROOT="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -V | tail -1)"
SWIFTC=/Library/Developer/CommandLineTools/usr/bin/swiftc
if [ ! -x "$SWIFTC" ]; then
  # 完整 Xcode 环境
  SWIFTC=$(xcrun -f swiftc)
fi
"$SWIFTC" -O -target arm64-apple-macos13.0 \
  -framework AppKit -framework WebKit \
  -o "$APP/Contents/MacOS/ExPermit" \
  native/mac/main.swift

echo "—— 组装 .app ——"
cp -R "$WWW" "$APP/Contents/Resources/www"
[ -f build/icon.icns ] && cp build/icon.icns "$APP/Contents/Resources/AppIcon.icns"

write_plist() {
  cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ExPermit</string>
  <key>CFBundleDisplayName</key><string>ExPermit 实验记录本</string>
  <key>CFBundleIdentifier</key><string>com.fengtong.expermit.native</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1.4</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>ExPermit</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
EOF
}
write_plist
codesign --force --sign - "$APP" 2>/dev/null || true

echo "✓ 构建完成：$APP"
echo "  自检：$APP/Contents/MacOS/ExPermit --selftest"
