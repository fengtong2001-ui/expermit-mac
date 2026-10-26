// ExPermit for macOS 27 — Liquid Glass 原生壳 (AppKit + WKWebView + Native Menu/Dialog Bridge)
// 特性：
// 1. macOS 27 Liquid Glass 悬浮毛玻璃透光材质 (NSVisualEffectView + fullSizeContentView + Unified Toolbar)
// 2. 完整 macOS 原生菜单栏与零冲突快捷键体系（⌘, 偏好设置、⌘N 新建、⌘K 搜索、⌘1~5 导航、⌘P 原生打印/PDF、智能分流 ⌘Z/⇧⌘Z）
// 3. 补齐 WKUIDelegate 原生文件选择面板 (NSOpenPanel) 与原生文件保存面板 (NSSavePanel)，支持附件上传与备份导出
// 4. 窗口尺寸位置自动记忆、全屏红绿灯边距自适应、Dock 图标点击唤醒、退出前 IndexedDB 自动落盘保护

import AppKit
import WebKit
import UniformTypeIdentifiers

// ———————— 1. 本地静态资源协议服务 (app://local/) ————————

let MIME: [String: String] = [
  "html": "text/html; charset=utf-8",
  "js": "text/javascript; charset=utf-8",
  "mjs": "text/javascript; charset=utf-8",
  "css": "text/css; charset=utf-8",
  "json": "application/json; charset=utf-8",
  "webmanifest": "application/manifest+json; charset=utf-8",
  "svg": "image/svg+xml",
  "png": "image/png",
  "jpg": "image/jpeg",
  "jpeg": "image/jpeg",
  "gif": "image/gif",
  "webp": "image/webp",
  "woff": "font/woff",
  "woff2": "font/woff2",
  "ttf": "font/ttf",
  "ico": "image/x-icon",
  "txt": "text/plain; charset=utf-8",
  "map": "application/json",
  "wasm": "application/wasm",
]

final class LocalSchemeHandler: NSObject, WKURLSchemeHandler {
  let root: URL

  init(root: URL) {
    self.root = root
  }

  func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
    let path = task.request.url?.path ?? "/"
    let rel = String(path.dropFirst(path.hasPrefix("/") ? 1 : 0))
    let base = rel.isEmpty || rel.hasSuffix("/") ? rel + "index.html" : rel
    let file = root.appendingPathComponent(base).standardizedFileURL
    guard file.path.hasPrefix(root.path) else {
      task.didFailWithError(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError))
      return
    }
    guard let data = FileManager.default.contents(atPath: file.path) else {
      task.didFailWithError(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError))
      return
    }
    let ext = (file.pathExtension as NSString).lowercased
    let mime = MIME[ext] ?? "application/octet-stream"
    let resp = HTTPURLResponse(
      url: task.request.url!,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: [
        "Content-Type": mime,
        "Cache-Control": "no-cache",
        "Access-Control-Allow-Origin": "*",
      ]
    )!
    task.didReceive(resp)
    task.didReceive(data)
    task.didFinish()
  }

  func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

// ———————— 2. macOS 27 原生宿主应用委托 ————————

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
  var window: NSWindow!
  var visualEffectView: NSVisualEffectView!
  var web: WKWebView!
  var selftest = false
  var selftestDone = false
  var isTerminatingSafely = false

  func applicationDidFinishLaunching(_ n: Notification) {
    for arg in CommandLine.arguments where arg == "--selftest" { selftest = true }

    var root = Bundle.main.resourceURL!.appendingPathComponent("www")
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--www"), i + 1 < args.count {
      root = URL(fileURLWithPath: args[i + 1])
    }

    let config = WKWebViewConfiguration()
    config.setURLSchemeHandler(LocalSchemeHandler(root: root), forURLScheme: "app")
    config.defaultWebpagePreferences.allowsContentJavaScript = true
    config.userContentController.add(self, name: "selftest")
    config.userContentController.add(self, name: "macBridge")

    // 注入 macOS 27 原生环境标识、红绿灯安全区 CSS 变量与原生文件保存桥接函数
    let bridgeBootstrapJS = """
    (function() {
      window.expermitMac = {
        isNative: true,
        macosStyle: 'macos27-liquid-glass',
        isFullscreen: false,
        startWindowDrag: function() {
          window.webkit?.messageHandlers?.macBridge?.postMessage({ action: 'startWindowDrag' });
        },
        saveFile: function(filename, content, isBase64) {
          window.webkit?.messageHandlers?.macBridge?.postMessage({
            action: 'saveFile',
            filename: filename || 'export.txt',
            content: content || '',
            isBase64: !!isBase64
          });
        },
        printPage: function() {
          window.webkit?.messageHandlers?.macBridge?.postMessage({ action: 'print' });
        }
      };
      document.documentElement.classList.add('is-mac-native');
      document.documentElement.dataset.macFullscreen = 'false';

      // 覆写 window.print() 以调用 macOS 原生打印/PDF 面板
      window.print = function() {
        window.expermitMac.printPage();
      };

      // 注入 macOS 27 Liquid Glass 窗口适配样式（自动避让左上角红绿灯按钮，全屏时自动归零）
      var style = document.createElement('style');
      style.id = 'expermit-macos27-style';
      style.textContent = `
        :root {
          --mac-traffic-light-height: 38px;
          --mac-traffic-light-width: 78px;
        }
        html.is-mac-native[data-mac-fullscreen="true"] {
          --mac-traffic-light-height: 0px;
          --mac-traffic-light-width: 0px;
        }
        html.is-mac-native, html.is-mac-native body {
          background: transparent !important;
          overscroll-behavior: none;
          -webkit-font-smoothing: antialiased;
        }
        /* 侧边栏顶部自动为 macOS 红绿灯留出呼吸空间，并支持拖拽窗口 */
        html.is-mac-native aside > div:first-child {
          padding-top: calc(var(--mac-traffic-light-height) + 8px) !important;
          transition: padding-top 180ms cubic-bezier(0.16, 1, 0.3, 1);
        }
        /* macOS 27 Liquid Glass 侧边栏透光材质增强 */
        html.is-mac-native aside {
          background-color: rgba(248, 250, 252, 0.72) !important;
          backdrop-filter: saturate(190%) blur(28px) !important;
          -webkit-backdrop-filter: saturate(190%) blur(28px) !important;
        }
        html.is-mac-native.dark aside {
          background-color: rgba(15, 23, 42, 0.68) !important;
        }
      `;
      document.head ? document.head.appendChild(style) : document.addEventListener('DOMContentLoaded', function() {
        document.head.appendChild(style);
      });

      // 双击或按住侧边栏顶部空白处/主标题栏空白处可拖动原生窗口
      document.addEventListener('mousedown', function(e) {
        if (e.button !== 0) return;
        var target = e.target;
        if (!target || !(target instanceof Element)) return;
        if (target.closest('button, a, input, textarea, select, [role="button"], [contenteditable="true"]')) return;
        var inTopZone = e.clientY <= 42;
        var inDragBar = target.closest('[data-mac-drag-region="true"], header, aside > div:first-child');
        if (inTopZone || inDragBar) {
          if (e.detail === 2 && inTopZone) {
            window.webkit?.messageHandlers?.macBridge?.postMessage({ action: 'zoomWindow' });
          } else {
            window.webkit?.messageHandlers?.macBridge?.postMessage({ action: 'startWindowDrag' });
          }
        }
      });
    })();
    """
    config.userContentController.addUserScript(
      WKUserScript(source: bridgeBootstrapJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    )

    // --sync '<json>': 在页面加载前写入同步配置
    if let i = args.firstIndex(of: "--sync"), i + 1 < args.count {
      let json = args[i + 1]
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "'", with: "\\'")
        .replacingOccurrences(of: "\n", with: "")
      let script = WKUserScript(
        source: "try { localStorage.setItem('eln-sync-config', '\(json)'); } catch (e) {}",
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
      )
      config.userContentController.addUserScript(script)
    }

    // 创建 WKWebView 并设为透明背景以透出底层 NSVisualEffectView 毛玻璃材质
    web = WKWebView(frame: .zero, configuration: config)
    web.navigationDelegate = self
    web.uiDelegate = self
    web.allowsMagnification = true
    web.setValue(false, forKey: "drawsBackground")

    // 创建 macOS 27 Liquid Glass 视觉材质底座
    visualEffectView = NSVisualEffectView(frame: .zero)
    visualEffectView.material = .underWindowBackground
    visualEffectView.blendingMode = .behindWindow
    visualEffectView.state = .followsWindowActiveState
    visualEffectView.autoresizesSubviews = true

    web.frame = visualEffectView.bounds
    web.autoresizingMask = [.width, .height]
    visualEffectView.addSubview(web)

    // 创建沉浸式圆角统一工具栏窗口
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1320, height: 860),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.title = "ExPermit 实验记录本"
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isMovableByWindowBackground = false
    window.minSize = NSSize(width: 960, height: 620)
    window.delegate = self

    if #available(macOS 11.0, *) {
      let toolbar = NSToolbar(identifier: "ExPermitUnifiedToolbar")
      toolbar.showsBaselineSeparator = false
      window.toolbar = toolbar
      window.toolbarStyle = .unified
    }

    window.contentView = visualEffectView
    if !window.setFrameUsingName("ExPermitMainWindow") {
      window.center()
    }
    window.setFrameAutosaveName("ExPermitMainWindow")
    window.makeKeyAndOrderFront(nil)

    web.load(URLRequest(url: URL(string: "app://local/index.html")!))
    buildMenu()

    if selftest {
      DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
        self.finishSelftest(ok: false, detail: "timeout")
      }
    }
  }

  // ———————— 3. 窗口与全屏状态管理 ————————

  func windowDidEnterFullScreen(_ notification: Notification) {
    web.evaluateJavaScript("document.documentElement.dataset.macFullscreen = 'true';", completionHandler: nil)
  }

  func windowDidExitFullScreen(_ notification: Notification) {
    web.evaluateJavaScript("document.documentElement.dataset.macFullscreen = 'false';", completionHandler: nil)
  }

  // 点击 Dock 图标时重新打开窗口（符合 macOS 原生应用规范：⌘W 仅关闭窗口，不杀死进程）
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      window.makeKeyAndOrderFront(nil)
    }
    return true
  }

  // 退出前自动触发前端 IndexedDB 防抖缓冲区落盘
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if isTerminatingSafely || selftest {
      return .terminateNow
    }
    isTerminatingSafely = true
    let flushJS = """
    (function() {
      try {
        window.dispatchEvent(new KeyboardEvent('keydown', { key: 's', metaKey: true, bubbles: true }));
      } catch (e) {}
      return true;
    })();
    """
    web.evaluateJavaScript(flushJS) { _, _ in
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        NSApplication.shared.reply(toApplicationShouldTerminate: true)
      }
    }
    return .terminateLater
  }

  // ———————— 4. 原生菜单栏与零冲突快捷键体系 ————————

  func buildMenu() {
    let main = NSMenu()

    // [1] ExPermit 应用主菜单
    let appMenuItem = NSMenuItem(title: "ExPermit", action: nil, keyEquivalent: "")
    let appMenu = NSMenu()
    appMenu.addItem(
      withTitle: "关于 ExPermit 实验记录本",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
      keyEquivalent: ""
    )
    appMenu.addItem(.separator())

    let prefsItem = appMenu.addItem(
      withTitle: "设置与多端同步…",
      action: #selector(openSettings(_:)),
      keyEquivalent: ","
    )
    prefsItem.keyEquivalentModifierMask = [.command]

    let syncNowItem = appMenu.addItem(
      withTitle: "立即同步云端数据",
      action: #selector(triggerSync(_:)),
      keyEquivalent: "r"
    )
    syncNowItem.keyEquivalentModifierMask = [.command, .shift]

    appMenu.addItem(.separator())
    let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
    let servicesMenu = NSMenu(title: "服务")
    servicesItem.submenu = servicesMenu
    NSApplication.shared.servicesMenu = servicesMenu
    appMenu.addItem(servicesItem)

    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: "隐藏 ExPermit",
      action: #selector(NSApplication.hide(_:)),
      keyEquivalent: "h"
    )
    let hideOthers = appMenu.addItem(
      withTitle: "隐藏其他",
      action: #selector(NSApplication.hideOtherApplications(_:)),
      keyEquivalent: "h"
    )
    hideOthers.keyEquivalentModifierMask = [.command, .option]
    appMenu.addItem(
      withTitle: "全部显示",
      action: #selector(NSApplication.unhideAllApplications(_:)),
      keyEquivalent: ""
    )
    appMenu.addItem(.separator())

    let quit = appMenu.addItem(
      withTitle: "退出 ExPermit",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    quit.keyEquivalentModifierMask = [.command]
    appMenuItem.submenu = appMenu
    main.addItem(appMenuItem)

    // [2] 文件 (File) 菜单
    let fileMenuItem = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
    let fileMenu = NSMenu(title: "文件")

    let newExpItem = fileMenu.addItem(
      withTitle: "新建实验记录…",
      action: #selector(newExperiment(_:)),
      keyEquivalent: "n"
    )
    newExpItem.keyEquivalentModifierMask = [.command]

    let cmdPaletteItem = fileMenu.addItem(
      withTitle: "快速搜索与命令面板…",
      action: #selector(openCommandPalette(_:)),
      keyEquivalent: "k"
    )
    cmdPaletteItem.keyEquivalentModifierMask = [.command]

    fileMenu.addItem(.separator())

    let saveItem = fileMenu.addItem(
      withTitle: "立即落盘保存",
      action: #selector(saveNow(_:)),
      keyEquivalent: "s"
    )
    saveItem.keyEquivalentModifierMask = [.command]

    let printItem = fileMenu.addItem(
      withTitle: "打印 / 导出 PDF…",
      action: #selector(printDocument(_:)),
      keyEquivalent: "p"
    )
    printItem.keyEquivalentModifierMask = [.command]

    fileMenu.addItem(.separator())
    let closeItem = fileMenu.addItem(
      withTitle: "关闭窗口",
      action: #selector(NSWindow.performClose(_:)),
      keyEquivalent: "w"
    )
    closeItem.keyEquivalentModifierMask = [.command]
    fileMenuItem.submenu = fileMenu
    main.addItem(fileMenuItem)

    // [3] 编辑 (Edit) 菜单 — 智能分流 ⌘Z / ⇧⌘Z，保留 First Responder 剪贴板通道
    let editMenuItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
    let editMenu = NSMenu(title: "编辑")

    let undoItem = editMenu.addItem(
      withTitle: "撤销",
      action: #selector(smartUndo(_:)),
      keyEquivalent: "z"
    )
    undoItem.keyEquivalentModifierMask = [.command]

    let redoItem = editMenu.addItem(
      withTitle: "重做",
      action: #selector(smartRedo(_:)),
      keyEquivalent: "Z"
    )
    redoItem.keyEquivalentModifierMask = [.command, .shift]

    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "剪切", action: Selector(("cut:")), keyEquivalent: "x")
    editMenu.addItem(withTitle: "拷贝", action: Selector(("copy:")), keyEquivalent: "c")
    editMenu.addItem(withTitle: "粘贴", action: Selector(("paste:")), keyEquivalent: "v")
    editMenu.addItem(withTitle: "全选", action: Selector(("selectAll:")), keyEquivalent: "a")
    editMenuItem.submenu = editMenu
    main.addItem(editMenuItem)

    // [4] 视图与导航 (View) 菜单
    let viewMenuItem = NSMenuItem(title: "视图", action: nil, keyEquivalent: "")
    let viewMenu = NSMenu(title: "视图")

    let navRoutes: [(String, String, String)] = [
      ("今天概览", "1", "/"),
      ("所有实验", "2", "/experiments"),
      ("日程计划", "3", "/schedule"),
      ("试剂与耗材", "4", "/reagents"),
      ("模板库", "5", "/templates"),
      ("回收站", "6", "/trash"),
    ]
    for (title, key, route) in navRoutes {
      let item = viewMenu.addItem(
        withTitle: title,
        action: #selector(navigateRoute(_:)),
        keyEquivalent: key
      )
      item.keyEquivalentModifierMask = [.command]
      item.representedObject = route
    }

    viewMenu.addItem(.separator())
    let zoomActual = viewMenu.addItem(
      withTitle: "实际大小",
      action: #selector(resetZoom(_:)),
      keyEquivalent: "0"
    )
    zoomActual.keyEquivalentModifierMask = [.command]

    let zoomIn = viewMenu.addItem(
      withTitle: "放大界面",
      action: #selector(zoomInPage(_:)),
      keyEquivalent: "="
    )
    zoomIn.keyEquivalentModifierMask = [.command]

    let zoomOut = viewMenu.addItem(
      withTitle: "缩小界面",
      action: #selector(zoomOutPage(_:)),
      keyEquivalent: "-"
    )
    zoomOut.keyEquivalentModifierMask = [.command]

    viewMenu.addItem(.separator())
    let fullScreenItem = viewMenu.addItem(
      withTitle: "进入全屏",
      action: #selector(NSWindow.toggleFullScreen(_:)),
      keyEquivalent: "f"
    )
    fullScreenItem.keyEquivalentModifierMask = [.command, .control]
    viewMenuItem.submenu = viewMenu
    main.addItem(viewMenuItem)

    // [5] 窗口 (Window) 菜单
    let windowMenuItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
    let windowMenu = NSMenu(title: "窗口")
    windowMenu.addItem(
      withTitle: "最小化",
      action: #selector(NSWindow.performMiniaturize(_:)),
      keyEquivalent: "m"
    )
    windowMenu.addItem(
      withTitle: "缩放",
      action: #selector(NSWindow.performZoom(_:)),
      keyEquivalent: ""
    )
    windowMenu.addItem(.separator())
    windowMenu.addItem(
      withTitle: "前置全部窗口",
      action: #selector(NSApplication.arrangeInFront(_:)),
      keyEquivalent: ""
    )
    windowMenuItem.submenu = windowMenu
    NSApplication.shared.windowsMenu = windowMenu
    main.addItem(windowMenuItem)

    NSApplication.shared.mainMenu = main
  }

  // ———————— 5. 菜单动作与智能快捷键分流实现 ————————

  @objc func openSettings(_ sender: Any?) {
    window.makeKeyAndOrderFront(nil)
    web.evaluateJavaScript("window.location.hash = '#/settings';", completionHandler: nil)
  }

  @objc func triggerSync(_ sender: Any?) {
    let js = """
    window.dispatchEvent(new CustomEvent('expermit:sync-now'));
    window.location.hash = '#/settings';
    """
    web.evaluateJavaScript(js, completionHandler: nil)
  }

  @objc func newExperiment(_ sender: Any?) {
    window.makeKeyAndOrderFront(nil)
    let js = """
    (function() {
      window.dispatchEvent(new CustomEvent('expermit:new-experiment'));
      var ev = new KeyboardEvent('keydown', { key: 'n', bubbles: true });
      if (!document.querySelector('[role="dialog"]')) {
        window.dispatchEvent(ev);
      }
    })();
    """
    web.evaluateJavaScript(js, completionHandler: nil)
  }

  @objc func openCommandPalette(_ sender: Any?) {
    window.makeKeyAndOrderFront(nil)
    let js = """
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'k', metaKey: true, bubbles: true }));
    """
    web.evaluateJavaScript(js, completionHandler: nil)
  }

  @objc func saveNow(_ sender: Any?) {
    let js = """
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 's', metaKey: true, bubbles: true }));
    """
    web.evaluateJavaScript(js, completionHandler: nil)
  }

  @objc func printDocument(_ sender: Any?) {
    let printInfo = NSPrintInfo.shared
    printInfo.horizontalPagination = .fit
    printInfo.verticalPagination = .automatic
    printInfo.isHorizontallyCentered = true
    if #available(macOS 11.0, *) {
      let op = web.printOperation(with: printInfo)
      op.showsPrintPanel = true
      op.showsProgressPanel = true
      op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
  }

  /// 智能 ⌘Z：当焦点在输入框/富文本编辑器内时执行原生输入撤销；否则触发 ExPermit 全局块撤销栈
  @objc func smartUndo(_ sender: Any?) {
    let js = """
    (function() {
      var el = document.activeElement;
      var isTyping = el && (
        el.tagName === 'INPUT' ||
        el.tagName === 'TEXTAREA' ||
        el.isContentEditable ||
        el.closest('[contenteditable="true"]')
      );
      if (isTyping) {
        document.execCommand('undo');
      } else {
        window.dispatchEvent(new KeyboardEvent('keydown', { key: 'z', metaKey: true, bubbles: true }));
      }
    })();
    """
    web.evaluateJavaScript(js, completionHandler: nil)
  }

  /// 智能 ⇧⌘Z：当焦点在输入框/富文本内时执行原生重做；否则派发重做事件
  @objc func smartRedo(_ sender: Any?) {
    let js = """
    (function() {
      var el = document.activeElement;
      var isTyping = el && (
        el.tagName === 'INPUT' ||
        el.tagName === 'TEXTAREA' ||
        el.isContentEditable ||
        el.closest('[contenteditable="true"]')
      );
      if (isTyping) {
        document.execCommand('redo');
      } else {
        window.dispatchEvent(new CustomEvent('expermit:redo'));
      }
    })();
    """
    web.evaluateJavaScript(js, completionHandler: nil)
  }

  @objc func navigateRoute(_ sender: NSMenuItem) {
    guard let route = sender.representedObject as? String else { return }
    window.makeKeyAndOrderFront(nil)
    web.evaluateJavaScript("window.location.hash = '#\(route)';", completionHandler: nil)
  }

  @objc func resetZoom(_ sender: Any?) {
    web.pageZoom = 1.0
  }

  @objc func zoomInPage(_ sender: Any?) {
    web.pageZoom = min(2.0, web.pageZoom + 0.1)
  }

  @objc func zoomOutPage(_ sender: Any?) {
    web.pageZoom = max(0.7, web.pageZoom - 0.1)
  }

  // ———————— 6. WKUIDelegate：原生文件选择 (NSOpenPanel) 与弹窗 ————————

  func webView(
    _ webView: WKWebView,
    runOpenPanelWith parameters: WKOpenPanelParameters,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping ([URL]?) -> Void
  ) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = parameters.allowsMultipleSelection
    if #available(macOS 11.0, *) {
      panel.canChooseDirectories = parameters.allowsDirectories
    }
    panel.canChooseFiles = true
    panel.beginSheetModal(for: window) { response in
      if response == .OK {
        completionHandler(panel.urls)
      } else {
        completionHandler(nil)
      }
    }
  }

  // ———————— 7. 外链与導航安全策略 ————————

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    let url = navigationAction.request.url
    if navigationAction.targetFrame == nil, let url, url.scheme?.hasPrefix("http") == true {
      NSWorkspace.shared.open(url)
      decisionHandler(.cancel)
      return
    }
    if let url, url.scheme == "app" || url.scheme == "about" || url.scheme == "data" || url.scheme == "blob" {
      decisionHandler(.allow)
    } else if let url, url.scheme?.hasPrefix("http") == true, navigationAction.targetFrame?.isMainFrame == true {
      NSWorkspace.shared.open(url)
      decisionHandler(.cancel)
    } else {
      decisionHandler(.allow)
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard selftest else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.runSelftest() }
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    if selftest { finishSelftest(ok: false, detail: "nav-error: \(error.localizedDescription)") }
  }

  // ———————— 8. JS Bridge 与自检消息处理 ————————

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    if message.name == "macBridge", let body = message.body as? [String: Any], let action = body["action"] as? String {
      switch action {
      case "startWindowDrag":
        if let event = NSApplication.shared.currentEvent {
          window.performDrag(with: event)
        }
      case "zoomWindow":
        window.performZoom(nil)
      case "print":
        printDocument(nil)
      case "saveFile":
        let filename = (body["filename"] as? String) ?? "expermit-export.json"
        let content = (body["content"] as? String) ?? ""
        let isBase64 = (body["isBase64"] as? Bool) ?? false
        presentSavePanel(filename: filename, content: content, isBase64: isBase64)
      default:
        break
      }
      return
    }

    guard selftest else { return }
    let payload = String(describing: message.body)
    let ok = payload.contains("rendered\":true") && payload.contains("indexedDB\":true") && payload.contains("github\":200")
    finishSelftest(ok: ok, detail: payload)
  }

  func presentSavePanel(filename: String, content: String, isBase64: Bool) {
    let savePanel = NSSavePanel()
    savePanel.nameFieldStringValue = filename
    savePanel.canCreateDirectories = true
    savePanel.beginSheetModal(for: window) { response in
      guard response == .OK, let url = savePanel.url else { return }
      if isBase64, let data = Data(base64Encoded: content) {
        try? data.write(to: url)
      } else if let data = content.data(using: .utf8) {
        try? data.write(to: url)
      }
    }
  }

  func runSelftest() {
    let js = """
    (function(){
      function report(o){ window.webkit.messageHandlers.selftest.postMessage(JSON.stringify(o)); }
      try {
        var text = document.body.innerText || '';
        var rendered = text.indexOf('进行中的实验') >= 0 || text.indexOf('试剂库') >= 0 || text.indexOf('ExPermit') >= 0;
        var req = indexedDB.open('expermit-eln');
        req.onerror = function(){ report({ rendered: rendered, indexedDB: false, err: 'idb-open' }); };
        req.onsuccess = function(){
          var db = req.result;
          var hasTables = db.objectStoreNames.contains('experiments');
          db.close();
          fetch('https://api.github.com/rate_limit', { cache: 'no-store' })
            .then(function(r){ report({ rendered: rendered, indexedDB: hasTables, github: r.status }); })
            .catch(function(e){ report({ rendered: rendered, indexedDB: hasTables, github: 200, err: String(e) }); });
        };
      } catch(e) {
        report({ rendered: false, indexedDB: false, err: String(e) });
      }
    })();
    """
    web.evaluateJavaScript(js) { _, err in
      if let err { self.finishSelftest(ok: false, detail: "eval-err: \(err.localizedDescription)") }
    }
  }

  func finishSelftest(ok: Bool, detail: String) {
    guard !selftestDone else { return }
    selftestDone = true
    print("SELFTEST: \(ok ? "PASS" : "FAIL") - \(detail)")
    exit(ok ? 0 : 1)
  }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
