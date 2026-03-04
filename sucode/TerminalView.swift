import SwiftUI
import WebKit
import UIKit

struct TerminalView: View {
    let device: ClusterDevice
    @StateObject private var viewModel = TerminalViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // 黑色背景
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // WebView 终端
                TerminalWebView(
                    url: device.url,
                    isLoading: $viewModel.isLoading,
                    error: $viewModel.error,
                    viewModel: viewModel
                )
                .opacity(viewModel.isLoading ? 0.01 : 1)  // 使用 0.01 而不是 0 防止闪烁
                .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)

                // 加载指示器
                if viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)

                        Text("正在连接 \(device.name)...")
                            .foregroundColor(.gray)

                        Text(device.subtitle)
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.7))

                        // 如果加载时间过长，显示提示
                        Text("如果一直加载，请检查 Bridge 服务是否正常运行")
                            .font(.caption2)
                            .foregroundColor(.orange.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black) // 防止闪烁
                }

                // 错误提示
                if let error = viewModel.error {
                    TerminalErrorView(
                        error: error,
                        device: device,
                        bridgeStatus: viewModel.bridgeStatus,
                        bridgeStatusMessage: viewModel.bridgeStatusMessage,
                        onRetry: {
                            viewModel.retry()
                        },
                        onCheckStatus: {
                            viewModel.checkBridgeStatus(for: device)
                        }
                    )
                }

                // 命令历史指示器
                if viewModel.showingHistoryIndicator {
                    Text(viewModel.historyIndicatorText)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.vertical, 4)
                        .transition(.opacity)
                }

                // 底部工具栏
                TerminalToolbar(
                    onCtrlC: { viewModel.sendKey("\u{0003}") },
                    onCtrlD: { viewModel.sendKey("\u{0004}") },
                    onCtrlL: { viewModel.sendKey("\u{000C}") },
                    onCtrlZ: { viewModel.sendKey("\u{001A}") },
                    onTab: { viewModel.sendKey("\t") },
                    onUp: { viewModel.navigateHistory(direction: -1) },
                    onDown: { viewModel.navigateHistory(direction: 1) },
                    onClear: { viewModel.clear() },
                    onKeyboard: { viewModel.showKeyboard() },
                    onPaste: { viewModel.pasteFromClipboard() }
                )
            }
        }
        .navigationTitle(device.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: { viewModel.reload() }) {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }

                    Button(action: { viewModel.zoomIn() }) {
                        Label("放大", systemImage: "plus.magnifyingglass")
                    }

                    Button(action: { viewModel.zoomOut() }) {
                        Label("缩小", systemImage: "minus.magnifyingglass")
                    }

                    Button(action: { viewModel.resetZoom() }) {
                        Label("重置缩放", systemImage: "arrow.counterclockwise")
                    }

                    Divider()

                    Button(action: { viewModel.toggleCursorBlink() }) {
                        Label(
                            viewModel.cursorBlinkEnabled ? "关闭光标闪烁" : "开启光标闪烁",
                            systemImage: viewModel.cursorBlinkEnabled ? "eye.slash" : "eye"
                        )
                    }

                    Divider()

                    Button(action: {
                        UIPasteboard.general.string = device.url.absoluteString
                    }) {
                        Label("复制 URL", systemImage: "doc.on.doc")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.white)
                }
            }
        }
        .onAppear {
            viewModel.connect(to: device)
        }
    }
}

// MARK: - Terminal WebView
struct TerminalWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var error: Error?
    let viewModel: TerminalViewModel

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.preferences.javaScriptEnabled = true

        // 启用 WebSocket 支持
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        // 配置 WebSocket 和缓存策略 - 允许所有网络请求
        config.websiteDataStore = WKWebsiteDataStore.default()

        // 关键：允许非安全的HTTP内容
        if #available(iOS 14.0, *) {
            let prefs = WKWebpagePreferences()
            prefs.allowsContentJavaScript = true
            config.defaultWebpagePreferences = prefs
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.backgroundColor = .black
        webView.isOpaque = false

        // 清除缓存以确保重新加载
        clearWebViewCache()

        // 优化滚动体验
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = true
        webView.scrollView.bouncesZoom = true
        webView.scrollView.minimumZoomScale = 0.8
        webView.scrollView.maximumZoomScale = 2.0
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.keyboardDismissMode = .interactive

        // 添加长按手势识别
        let longPressGesture = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPressGesture.minimumPressDuration = 0.4
        webView.addGestureRecognizer(longPressGesture)

        // 添加捏合手势识别
        let pinchGesture = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        webView.addGestureRecognizer(pinchGesture)

        // 添加滑动手势识别（用于命令历史）
        let swipeLeftGesture = UISwipeGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSwipeLeft(_:))
        )
        swipeLeftGesture.direction = .left
        webView.addGestureRecognizer(swipeLeftGesture)

        let swipeRightGesture = UISwipeGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSwipeRight(_:))
        )
        swipeRightGesture.direction = .right
        webView.addGestureRecognizer(swipeRightGesture)

        // 添加点击手势聚焦输入
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tapGesture.numberOfTapsRequired = 1
        webView.addGestureRecognizer(tapGesture)

        // 创建 Coordinator
        let coordinator = context.coordinator

        // 注入 JavaScript 处理终端控制序列
        injectTerminalScripts(into: webView, coordinator: coordinator)

        // 设置 ViewModel 的 WebView 引用
        viewModel.setWebView(webView)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let currentURL = webView.url?.absoluteString ?? ""
        let targetURL = url.absoluteString

        // 只在 URL 改变且不是当前正在加载的 URL 时才加载
        if currentURL != targetURL && !targetURL.isEmpty {
            // 避免重复加载相同的 URL
            if !context.coordinator.hasLoadedURL(targetURL) {
                print("🔄 Loading terminal URL: \(targetURL)")
                let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
                webView.load(request)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self, viewModel: viewModel)
    }

    private func clearWebViewCache() {
        let websiteDataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let date = Date(timeIntervalSince1970: 0)
        WKWebsiteDataStore.default().removeData(ofTypes: websiteDataTypes, modifiedSince: date) { }
    }

    private func injectTerminalScripts(into webView: WKWebView, coordinator: Coordinator) {
        // 键盘事件处理脚本
        let keyboardScript = """
            document.addEventListener('keydown', function(e) {
                var keyData = {
                    key: e.key,
                    code: e.code,
                    ctrlKey: e.ctrlKey,
                    altKey: e.altKey,
                    shiftKey: e.shiftKey,
                    metaKey: e.metaKey
                };

                if (e.ctrlKey) {
                    if (e.key === 'c') {
                        window.webkit.messageHandlers.keyHandler.postMessage({type: 'ctrl+c', data: keyData});
                    } else if (e.key === 'l') {
                        window.webkit.messageHandlers.keyHandler.postMessage({type: 'ctrl+l', data: keyData});
                    } else if (e.key === 'z') {
                        window.webkit.messageHandlers.keyHandler.postMessage({type: 'ctrl+z', data: keyData});
                    } else if (e.key === 'd') {
                        window.webkit.messageHandlers.keyHandler.postMessage({type: 'ctrl+d', data: keyData});
                    }
                }

                if (e.key === 'ArrowUp') {
                    window.webkit.messageHandlers.keyHandler.postMessage({type: 'arrowup', data: keyData});
                    e.preventDefault();
                } else if (e.key === 'ArrowDown') {
                    window.webkit.messageHandlers.keyHandler.postMessage({type: 'arrowdown', data: keyData});
                    e.preventDefault();
                } else if (e.key === 'Tab') {
                    window.webkit.messageHandlers.keyHandler.postMessage({type: 'tab', data: keyData});
                }
            });
        """

        // 移动端优化样式脚本 - 修复字间距问题
        let mobileStyleScript = """
            (function() {
                var style = document.createElement('style');
                style.textContent = `
                    /* 移动端优化 - 修复字间距 */
                    * {
                        -webkit-text-size-adjust: none !important;
                        text-size-adjust: none !important;
                    }

                    body {
                        margin: 0 !important;
                        padding: 8px !important;
                        background: #0d0d0d !important;
                        overflow: hidden !important;
                        font-family: -apple-system, BlinkMacSystemFont, 'SF Mono', Monaco, monospace !important;
                    }

                    .xterm {
                        padding: 0 !important;
                        border-radius: 12px !important;
                        box-shadow: 0 4px 20px rgba(0, 0, 0, 0.5) !important;
                    }

                    .xterm-viewport {
                        border-radius: 12px !important;
                        background-color: #0d0d0d !important;
                        border: 1px solid #2a2a2a !important;
                    }

                    .xterm-screen {
                        padding: 12px !important;
                    }

                    /* 修复字间距 - 关键 */
                    .xterm-rows {
                        font-family: 'SF Mono', 'Menlo', 'Monaco', 'Courier New', monospace !important;
                        font-feature-settings: 'liga' 0 !important;
                        letter-spacing: 0 !important;
                        word-spacing: 0 !important;
                    }

                    .xterm-rows > div {
                        line-height: 1.5 !important;
                        letter-spacing: 0 !important;
                        word-spacing: 0 !important;
                    }

                    .xterm-rows > div > span {
                        letter-spacing: 0 !important;
                        word-spacing: 0 !important;
                    }

                    /* 优化滚动条 */
                    .xterm-viewport::-webkit-scrollbar {
                        width: 4px;
                    }
                    .xterm-viewport::-webkit-scrollbar-track {
                        background: transparent;
                    }
                    .xterm-viewport::-webkit-scrollbar-thumb {
                        background: #444;
                        border-radius: 2px;
                    }

                    /* 增强文字可读性 */
                    .xterm-dom-renderer-owner-1 {
                        font-family: 'SF Mono', -apple-system, BlinkMacSystemFont, monospace !important;
                        -webkit-font-smoothing: antialiased !important;
                        -moz-osx-font-smoothing: grayscale !important;
                        text-rendering: optimizeLegibility !important;
                    }

                    /* 光标样式优化 */
                    .xterm-cursor {
                        background-color: #f97316 !important;
                        border-color: #f97316 !important;
                    }

                    .xterm-cursor-block {
                        background-color: #f97316 !important;
                    }

                    /* 选中样式 */
                    .xterm-selection {
                        background: rgba(249, 115, 22, 0.3) !important;
                    }

                    /* 隐藏输入框 */
                    .xterm-helper-textarea {
                        opacity: 0 !important;
                        position: fixed !important;
                        bottom: 0 !important;
                        left: 0 !important;
                        height: 1px !important;
                        width: 1px !important;
                    }
                `;
                document.head.appendChild(style);

                // 强制更新 xterm 字体设置
                setTimeout(function() {
                    if (typeof term !== 'undefined' && term.options) {
                        term.options.fontFamily = 'SF Mono, Menlo, Monaco, Courier New, monospace';
                        term.options.fontSize = 14;
                        term.options.letterSpacing = 0;
                        term.options.lineHeight = 1.5;
                    }
                }, 100);
            })();
        """

        // 光标闪烁效果脚本
        let cursorScript = """
            (function() {
                var style = document.createElement('style');
                style.textContent = `
                    .xterm-cursor {
                        animation: blink 1s step-end infinite;
                    }
                    @keyframes blink {
                        0%, 50% { opacity: 1; }
                        51%, 100% { opacity: 0; }
                    }
                    .xterm-cursor-block {
                        background-color: currentColor !important;
                        color: #000 !important;
                    }
                `;
                document.head.appendChild(style);
            })();
        """

        // 粘贴板访问脚本
        let pasteScript = """
            document.addEventListener('paste', function(e) {
                var pastedText = e.clipboardData.getData('text');
                window.webkit.messageHandlers.clipboardHandler.postMessage({type: 'paste', data: pastedText});
            });
        """

        // 终端内容变化监听
        let contentScript = """
            (function() {
                var observer = new MutationObserver(function(mutations) {
                    var terminalContent = document.querySelector('.xterm-screen')?.textContent || '';
                    window.webkit.messageHandlers.contentHandler.postMessage({type: 'content', data: terminalContent});
                });

                var terminalElement = document.querySelector('.xterm');
                if (terminalElement) {
                    observer.observe(terminalElement, { childList: true, subtree: true });
                }
            })();
        """

        let scripts = [
            (keyboardScript, "keyboardHandler"),
            (cursorScript, "cursorHandler"),
            (pasteScript, "clipboardHandler"),
            (contentScript, "contentHandler")
        ]

        for (script, handler) in scripts {
            let userScript = WKUserScript(
                source: script,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            webView.configuration.userContentController.addUserScript(userScript)
        }

        // 添加消息处理器
        webView.configuration.userContentController.add(coordinator, name: "keyHandler")
        webView.configuration.userContentController.add(coordinator, name: "clipboardHandler")
        webView.configuration.userContentController.add(coordinator, name: "contentHandler")
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, URLSessionDelegate {
        let parent: TerminalWebView
        let viewModel: TerminalViewModel
        private var lastPinchScale: CGFloat = 1.0
        var isLoading = false
        private var loadedURLs: Set<String> = []

        // 超时检测
        private var loadingTimer: Timer?
        private let loadingTimeout: TimeInterval = 10.0

        init(_ parent: TerminalWebView, viewModel: TerminalViewModel) {
            self.parent = parent
            self.viewModel = viewModel
        }

        func hasLoadedURL(_ url: String) -> Bool {
            if loadedURLs.contains(url) {
                return true
            }
            loadedURLs.insert(url)
            return false
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
            parent.isLoading = true
            parent.error = nil

            // 启动超时检测
            startLoadingTimeout(webView: webView)
        }

        private func startLoadingTimeout(webView: WKWebView) {
            // 取消之前的定时器
            loadingTimer?.invalidate()

            loadingTimer = Timer.scheduledTimer(withTimeInterval: loadingTimeout, repeats: false) { [weak self] _ in
                guard let self = self, self.isLoading else { return }

                // 超时处理
                self.isLoading = false
                self.parent.isLoading = false

                let timeoutError = NSError(
                    domain: NSURLErrorDomain,
                    code: NSURLErrorTimedOut,
                    userInfo: [
                        NSLocalizedDescriptionKey: "连接超时，Bridge 服务器未响应",
                        NSURLErrorFailingURLErrorKey: webView.url ?? URL(string: "")!
                    ]
                )
                self.parent.error = timeoutError

                print("⏱️ Terminal loading timeout after \(self.loadingTimeout)s")
            }
        }

        private func stopLoadingTimeout() {
            loadingTimer?.invalidate()
            loadingTimer = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("✅ Terminal loaded successfully: \(webView.url?.absoluteString ?? "unknown")")

            // 停止超时检测
            stopLoadingTimeout()

            // 延迟一点再隐藏加载指示器，确保页面内容已渲染
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.isLoading = false
                self.parent.isLoading = false
                self.parent.viewModel.isLoading = false

                // 注入光标闪烁样式
                self.viewModel.applyCursorBlinkStyle()

                // 应用终端字体设置
                self.viewModel.applyTerminalFontSettings()
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            print("📄 Terminal did commit navigation")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            stopLoadingTimeout()
            isLoading = false
            parent.isLoading = false
            parent.error = error
            print("❌ Terminal navigation failed: \(error.localizedDescription)")
            print("   URL: \(webView.url?.absoluteString ?? "unknown")")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            stopLoadingTimeout()
            isLoading = false

            // 忽略 -999 (取消) 错误
            let nsError = error as NSError
            if nsError.code == -999 {
                print("⚠️ Navigation cancelled (expected when switching views)")
                return
            }

            parent.isLoading = false
            parent.error = error

            print("❌ Terminal provisional navigation failed")
            print("   Error: \(error.localizedDescription)")
            print("   Code: \(nsError.code)")
            print("   Domain: \(nsError.domain)")
            print("   URL: \(webView.url?.absoluteString ?? "unknown")")

            // 详细的错误信息
            if let failingURL = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
                print("   Failing URL: \(failingURL)")
            }

            // 显示用户可理解的错误
            DispatchQueue.main.async {
                self.showErrorAlert(error: error)
            }
        }

        private func showErrorAlert(error: Error) {
            let nsError = error as NSError
            var message = error.localizedDescription

            // 根据错误代码提供更详细的说明
            switch nsError.code {
            case -1009:
                message += "\n\n请检查：\n1. iPhone 是否连接到 WiFi\n2. 是否允许 sucode 访问本地网络\n3. 设置 → 隐私 → 本地网络 → sucode"
            case -1001:
                message += "\n\n连接超时，请检查：\n1. VPS 服务是否运行\n2. 防火墙是否允许 8767 端口"
            case -1004:
                message += "\n\n无法连接服务器，请检查：\n1. IP 地址和端口是否正确\n2. VPS 安全组是否开放 8767 端口"
            default:
                message += "\n\n请尝试在 Safari 中打开相同 URL 测试"
            }

            // 可以通过通知或其他方式显示给用户
            print("📋 用户提示: \(message)")
        }

        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            // 允许所有证书（包括自签名）
            if let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }

        // MARK: - Gesture Handlers

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }

            // 显示复制菜单
            let menuController = UIMenuController.shared
            let copyItem = UIMenuItem(title: "复制", action: #selector(copyTerminalContent))
            let pasteItem = UIMenuItem(title: "粘贴", action: #selector(pasteToTerminal))
            menuController.menuItems = [copyItem, pasteItem]

            if let webView = gesture.view as? WKWebView {
                let location = gesture.location(in: webView)
                let rect = CGRect(x: location.x, y: location.y, width: 1, height: 1)
                menuController.showMenu(from: webView, rect: rect)
            }
        }

        @objc func copyTerminalContent() {
            viewModel.copyTerminalContent()
        }

        @objc func pasteToTerminal() {
            viewModel.pasteFromClipboard()
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let webView = gesture.view as? WKWebView else { return }

            switch gesture.state {
            case .changed:
                let scale = gesture.scale
                if scale > 1.0 {
                    viewModel.zoomIn()
                } else if scale < 1.0 {
                    viewModel.zoomOut()
                }
                gesture.scale = 1.0
            default:
                break
            }
        }

        @objc func handleSwipeLeft(_ gesture: UISwipeGestureRecognizer) {
            // 切换到下一个保存的命令
            viewModel.navigateHistory(direction: 1)
        }

        @objc func handleSwipeRight(_ gesture: UISwipeGestureRecognizer) {
            // 切换到上一个保存的命令
            viewModel.navigateHistory(direction: -1)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            // 点击时聚焦终端输入
            viewModel.focusTerminal()
        }

        // MARK: - WKScriptMessageHandler

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            DispatchQueue.main.async {
                switch type {
                case "ctrl+c":
                    self.viewModel.sendKey("\u{0003}")
                case "ctrl+l":
                    self.viewModel.sendKey("\u{000C}")
                case "ctrl+z":
                    self.viewModel.sendKey("\u{001A}")
                case "ctrl+d":
                    self.viewModel.sendKey("\u{0004}")
                case "arrowup":
                    self.viewModel.navigateHistory(direction: -1)
                case "arrowdown":
                    self.viewModel.navigateHistory(direction: 1)
                case "tab":
                    self.viewModel.sendKey("\t")
                case "paste":
                    if let data = body["data"] as? String {
                        self.viewModel.sendText(data)
                    }
                case "content":
                    if let data = body["data"] as? String {
                        self.viewModel.updateTerminalContent(data)
                    }
                default:
                    break
                }
            }
        }
    }
}

// MARK: - Terminal Toolbar
struct TerminalToolbar: View {
    let onCtrlC: () -> Void
    let onCtrlD: () -> Void
    let onCtrlL: () -> Void
    let onCtrlZ: () -> Void
    let onTab: () -> Void
    let onUp: () -> Void
    let onDown: () -> Void
    let onClear: () -> Void
    let onKeyboard: () -> Void
    let onPaste: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 主工具栏
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ToolbarButton(
                        title: "Ctrl+C",
                        icon: "stop.fill",
                        color: .red
                    ) {
                        onCtrlC()
                    }

                    ToolbarButton(
                        title: "Ctrl+D",
                        icon: "escape",
                        color: .orange
                    ) {
                        onCtrlD()
                    }

                    ToolbarButton(
                        title: "Ctrl+L",
                        icon: "clear.fill",
                        color: .blue
                    ) {
                        onCtrlL()
                    }

                    ToolbarButton(
                        title: "Ctrl+Z",
                        icon: "pause.fill",
                        color: .purple
                    ) {
                        onCtrlZ()
                    }

                    ToolbarButton(
                        title: "Tab",
                        icon: "arrow.right.to.line",
                        color: .cyan
                    ) {
                        onTab()
                    }

                    // 分隔点
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 4, height: 4)

                    ToolbarButton(
                        title: "↑",
                        icon: "arrow.up",
                        color: .green
                    ) {
                        onUp()
                    }

                    ToolbarButton(
                        title: "↓",
                        icon: "arrow.down",
                        color: .green
                    ) {
                        onDown()
                    }

                    // 分隔点
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 4, height: 4)

                    ToolbarButton(
                        title: "粘贴",
                        icon: "doc.on.clipboard",
                        color: .yellow
                    ) {
                        onPaste()
                    }

                    ToolbarButton(
                        title: "键盘",
                        icon: "keyboard",
                        color: .green
                    ) {
                        onKeyboard()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(
                ZStack {
                    // 渐变背景
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.15, green: 0.15, blue: 0.17),
                            Color(red: 0.10, green: 0.10, blue: 0.12)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // 顶部发光线条
                    VStack {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.orange.opacity(0.5),
                                        Color.orange.opacity(0.2),
                                        Color.clear
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 2)
                            .blur(radius: 2)

                        Spacer()
                    }

                    // 边框
                    Rectangle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
            )
            .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: -4)
        }
    }
}

// MARK: - Toolbar Button
struct ToolbarButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            HapticFeedback.light()
            action()
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(height: 18)

                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.white)
            .frame(minWidth: 56, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                color.opacity(0.8),
                                color.opacity(0.5)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(color.opacity(0.5), lineWidth: 1)
                    )
            )
            .shadow(color: color.opacity(0.3), radius: 4, x: 0, y: 2)
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Terminal ViewModel
@MainActor
class TerminalViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: Error?
    @Published var zoomLevel: CGFloat = 1.0
    @Published var cursorBlinkEnabled = true
    @Published var showingHistoryIndicator = false
    @Published var historyIndicatorText = ""

    // Bridge 服务状态检查
    @Published var bridgeStatus: BridgeStatus = .unknown
    @Published var bridgeStatusMessage = ""

    private var device: ClusterDevice?
    private var webView: WKWebView?
    private let persistence = DataPersistenceManager.shared
    private var statusCheckTask: Task<Void, Never>?

    // 命令历史
    private var commandHistory: [String] = []
    private var historyIndex: Int = -1
    private var currentCommand: String = ""
    private let maxHistoryCount = 100

    // 终端内容
    private var terminalContent: String = ""

    init() {
        loadCommandHistory()
    }

    func connect(to device: ClusterDevice) {
        self.device = device
        self.isLoading = true
        self.error = nil
        self.bridgeStatus = .unknown
        self.bridgeStatusMessage = ""

        // 启动时检查 Bridge 状态
        checkBridgeStatus(for: device)
    }

    // MARK: - Bridge Status Check

    enum BridgeStatus: String {
        case unknown = "未知"
        case checking = "检查中"
        case online = "在线"
        case offline = "离线"
        case timeout = "超时"
        case error = "错误"

        var color: Color {
            switch self {
            case .unknown: return .gray
            case .checking: return .yellow
            case .online: return .green
            case .offline: return .red
            case .timeout: return .orange
            case .error: return .red
            }
        }

        var icon: String {
            switch self {
            case .unknown: return "questionmark.circle"
            case .checking: return "arrow.clockwise"
            case .online: return "checkmark.circle.fill"
            case .offline: return "xmark.circle.fill"
            case .timeout: return "exclamationmark.triangle"
            case .error: return "exclamationmark.octagon"
            }
        }
    }

    func checkBridgeStatus(for device: ClusterDevice) {
        bridgeStatus = .checking
        bridgeStatusMessage = "正在检查 Bridge 服务..."

        statusCheckTask?.cancel()
        statusCheckTask = Task {
            let result = await performBridgeStatusCheck(device: device)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.bridgeStatus = result.status
                self.bridgeStatusMessage = result.message
            }
        }
    }

    private func performBridgeStatusCheck(device: ClusterDevice) async -> (status: BridgeStatus, message: String) {
        guard let url = URL(string: "http://\(device.host):\(device.port)/health") else {
            return (.error, "无效的 URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return (.error, "无效的响应")
            }

            switch httpResponse.statusCode {
            case 200:
                return (.online, "Bridge 服务正常运行")
            default:
                return (.error, "HTTP \(httpResponse.statusCode)")
            }
        } catch let error as NSError {
            if error.code == NSURLErrorTimedOut {
                return (.timeout, "连接超时，请检查网络")
            } else if error.code == NSURLErrorCannotConnectToHost {
                return (.offline, "无法连接到 Bridge 服务")
            } else if error.code == NSURLErrorNotConnectedToInternet {
                return (.offline, "无网络连接")
            } else {
                return (.error, error.localizedDescription)
            }
        } catch {
            return (.error, error.localizedDescription)
        }
    }

    func retry() {
        guard let device = device else { return }
        connect(to: device)
    }

    func reload() {
        webView?.reload()
    }

    // MARK: - Zoom Control

    func zoomIn() {
        zoomLevel = min(zoomLevel + 0.1, 2.0)
        applyZoom()
    }

    func zoomOut() {
        zoomLevel = max(zoomLevel - 0.1, 0.5)
        applyZoom()
    }

    func resetZoom() {
        zoomLevel = 1.0
        applyZoom()
    }

    private func applyZoom() {
        let script = """
            document.body.style.zoom = '\(zoomLevel)';
            if (typeof term !== 'undefined' && term.options) {
                var fontSize = Math.round(14 * \(zoomLevel));
                term.options.fontSize = fontSize;
            }
        """
        webView?.evaluateJavaScript(script)
    }

    // MARK: - Cursor Blink

    func toggleCursorBlink() {
        cursorBlinkEnabled.toggle()
        applyCursorBlinkStyle()
    }

    func applyCursorBlinkStyle() {
        let script = cursorBlinkEnabled ? """
            var style = document.getElementById('cursor-blink-style');
            if (!style) {
                style = document.createElement('style');
                style.id = 'cursor-blink-style';
                style.textContent = `
                    .xterm-cursor {
                        animation: blink 1s step-end infinite !important;
                    }
                    @keyframes blink {
                        0%, 50% { opacity: 1; }
                        51%, 100% { opacity: 0; }
                    }
                `;
                document.head.appendChild(style);
            }
        """ : """
            var style = document.getElementById('cursor-blink-style');
            if (style) {
                style.remove();
            }
        """
        webView?.evaluateJavaScript(script)
    }

    // MARK: - Terminal Font Settings

    func applyTerminalFontSettings() {
        let fontSize = persistence.terminalFontSize
        let fontFamily = persistence.terminalFontFamily

        let script = """
            (function() {
                if (typeof term !== 'undefined' && term.options) {
                    term.options.fontSize = \(Int(fontSize));
                    term.options.fontFamily = '\(fontFamily)';
                }
                // 同时更新 body 字体
                document.body.style.fontFamily = '\(fontFamily), monospace';
            })();
        """
        webView?.evaluateJavaScript(script)
    }

    // MARK: - Key Handling

    func sendKey(_ key: String) {
        let escapedKey = key.replacingOccurrences(of: "\\", with: "\\\\")
                           .replacingOccurrences(of: "'", with: "\\'")
                           .replacingOccurrences(of: "\n", with: "\\n")
                           .replacingOccurrences(of: "\t", with: "\\t")

        let script = """
            (function() {
                var event = new KeyboardEvent('keydown', {
                    key: '\(escapedKey)',
                    code: 'Key',
                    bubbles: true,
                    cancelable: true
                });
                document.dispatchEvent(event);

                // 如果终端有输入处理函数，也调用它
                if (typeof term !== 'undefined' && term.input) {
                    term.input('\(escapedKey)');
                }
            })();
        """
        webView?.evaluateJavaScript(script)
    }

    func sendText(_ text: String) {
        let escapedText = text.replacingOccurrences(of: "\\", with: "\\\\")
                              .replacingOccurrences(of: "'", with: "\\'")
                              .replacingOccurrences(of: "\n", with: "\\n")
                              .replacingOccurrences(of: "\t", with: "\\t")

        let script = """
            (function() {
                if (typeof term !== 'undefined' && term.paste) {
                    term.paste('\(escapedText)');
                } else {
                    var chars = '\(escapedText)';
                    for (var i = 0; i < chars.length; i++) {
                        var event = new KeyboardEvent('keydown', {
                            key: chars[i],
                            bubbles: true,
                            cancelable: true
                        });
                        document.dispatchEvent(event);
                    }
                }
            })();
        """
        webView?.evaluateJavaScript(script)

        // 记录到命令历史
        if text.contains("\n") || text.contains("\r") {
            addToHistory(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: - Command History

    func navigateHistory(direction: Int) {
        guard !commandHistory.isEmpty else { return }

        if historyIndex == -1 {
            currentCommand = getCurrentTerminalInput()
        }

        let newIndex = historyIndex + direction

        if newIndex >= -1 && newIndex < commandHistory.count {
            historyIndex = newIndex

            if historyIndex == -1 {
                // 恢复到当前输入
                setTerminalInput(currentCommand)
                showHistoryIndicator("当前输入")
            } else {
                // 显示历史命令
                let command = commandHistory[commandHistory.count - 1 - historyIndex]
                setTerminalInput(command)
                showHistoryIndicator("[\(historyIndex + 1)/\(commandHistory.count)] \(command.prefix(20))...")
            }
        }
    }

    private func getCurrentTerminalInput() -> String {
        // 尝试从终端获取当前输入
        var result = ""
        let script = """
            (function() {
                if (typeof term !== 'undefined' && term.buffer) {
                    var buffer = term.buffer.active;
                    var line = buffer.getLine(buffer.cursorY);
                    return line ? line.translateToString() : '';
                }
                return '';
            })();
        """
        webView?.evaluateJavaScript(script) { value, _ in
            if let text = value as? String {
                result = text
            }
        }
        return result
    }

    private func setTerminalInput(_ text: String) {
        let escapedText = text.replacingOccurrences(of: "\\", with: "\\\\")
                              .replacingOccurrences(of: "'", with: "\\'")
                              .replacingOccurrences(of: "\n", with: "\\n")

        let script = """
            (function() {
                if (typeof term !== 'undefined') {
                    // 清除当前行并输入新文本
                    term.input('\(escapedText)', true);
                }
            })();
        """
        webView?.evaluateJavaScript(script)
    }

    private func showHistoryIndicator(_ text: String) {
        historyIndicatorText = text
        showingHistoryIndicator = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.showingHistoryIndicator = false
        }
    }

    func addToHistory(_ command: String) {
        guard !command.isEmpty else { return }

        // 避免重复添加相同的连续命令
        if let last = commandHistory.last, last == command {
            return
        }

        commandHistory.append(command)

        // 限制历史记录数量
        if commandHistory.count > maxHistoryCount {
            commandHistory.removeFirst(commandHistory.count - maxHistoryCount)
        }

        saveCommandHistory()
        historyIndex = -1
    }

    private func saveCommandHistory() {
        // 转换为 ClusterCommand 保存到 DataPersistenceManager
        let commands = commandHistory.map { cmd in
            ClusterCommand(
                command: cmd,
                targetDevices: device != nil ? [device!.id] : [],
                results: [:]
            )
        }
        persistence.saveCommandHistory(commands)
    }

    private func loadCommandHistory() {
        // 从 DataPersistenceManager 加载
        let commands = persistence.loadCommandHistory()
        commandHistory = commands.map { $0.command }
    }

    func clearCommandHistory() {
        commandHistory.removeAll()
        historyIndex = -1
        persistence.clearCommandHistory()
    }

    // MARK: - Clipboard

    func copyTerminalContent() {
        UIPasteboard.general.string = terminalContent
    }

    func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string else { return }
        sendText(text)
    }

    // MARK: - Terminal Content

    func updateTerminalContent(_ content: String) {
        terminalContent = content

        // 检测命令执行并记录
        detectAndRecordCommand(from: content)
    }

    private func detectAndRecordCommand(from content: String) {
        // 简单的命令检测逻辑：查找提示符后的内容
        let lines = content.components(separatedBy: .newlines)
        if let lastLine = lines.last,
           let promptRange = lastLine.range(of: "$") ?? lastLine.range(of: "#") ?? lastLine.range(of: ">") {
            let command = String(lastLine[promptRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !command.isEmpty && command != currentCommand {
                currentCommand = command
            }
        }
    }

    func clear() {
        let script = """
            (function() {
                if (typeof term !== 'undefined' && term.clear) {
                    term.clear();
                } else if (typeof clear === 'function') {
                    clear();
                } else {
                    console.clear();
                }
            })();
        """
        webView?.evaluateJavaScript(script)
    }

    func showKeyboard() {
        focusTerminal()
    }

    func focusTerminal() {
        // 优化后的终端聚焦脚本
        let script = """
            (function() {
                // 尝试聚焦 xterm 终端
                if (typeof term !== 'undefined' && term.textarea) {
                    term.textarea.focus();
                    return;
                }
                // 回退方案：查找任何输入元素
                var input = document.querySelector('input, textarea');
                if (input) {
                    input.focus();
                } else {
                    // 创建临时输入元素
                    var tempInput = document.createElement('input');
                    tempInput.style.position = 'fixed';
                    tempInput.style.bottom = '0';
                    tempInput.style.left = '0';
                    tempInput.style.opacity = '0';
                    tempInput.style.height = '1px';
                    document.body.appendChild(tempInput);
                    tempInput.focus();
                    // 保持焦点
                    tempInput.addEventListener('blur', function() {
                        setTimeout(function() { tempInput.focus(); }, 10);
                    });
                }
            })();
        """
        webView?.evaluateJavaScript(script)
    }

    func setWebView(_ webView: WKWebView) {
        self.webView = webView
    }
}

// MARK: - Terminal Error View
struct TerminalErrorView: View {
    let error: Error
    let device: ClusterDevice
    let bridgeStatus: TerminalViewModel.BridgeStatus
    let bridgeStatusMessage: String
    let onRetry: () -> Void
    let onCheckStatus: () -> Void

    private var nsError: NSError {
        error as NSError
    }

    private var errorCodeDescription: String {
        switch nsError.code {
        case NSURLErrorTimedOut:
            return "连接超时 (-1001)"
        case NSURLErrorCannotConnectToHost:
            return "无法连接到主机 (-1004)"
        case NSURLErrorNotConnectedToInternet:
            return "无网络连接 (-1009)"
        case NSURLErrorBadServerResponse:
            return "服务器响应错误 (-1011)"
        case NSURLErrorNetworkConnectionLost:
            return "网络连接丢失 (-1005)"
        case NSURLErrorDNSLookupFailed:
            return "DNS 解析失败 (-1006)"
        default:
            return "错误代码: \(nsError.code)"
        }
    }

    private var suggestedSolution: String {
        switch nsError.code {
        case NSURLErrorTimedOut:
            return """
            建议解决方案:
            1. 检查 Bridge 服务是否已启动
            2. 确认设备与服务器在同一网络
            3. 检查防火墙是否允许端口 \(device.port)
            4. 尝试在 Safari 中访问 http://\(device.host):\(device.port)
            """
        case NSURLErrorCannotConnectToHost:
            return """
            建议解决方案:
            1. 确认 IP 地址 \(device.host) 是否正确
            2. 检查 Bridge 服务是否正在运行
            3. 确认防火墙未阻止端口 \(device.port)
            4. 检查路由器端口转发设置
            """
        case NSURLErrorNotConnectedToInternet:
            return """
            建议解决方案:
            1. 检查 iPhone WiFi 连接
            2. 确认 sucode 有本地网络访问权限
            3. 设置 → 隐私 → 本地网络 → sucode → 开启
            """
        default:
            return """
            建议解决方案:
            1. 检查 Bridge 服务状态
            2. 确认网络连接正常
            3. 尝试重启 Bridge 服务
            4. 在 Safari 中测试: http://\(device.host):\(device.port)
            """
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 错误图标
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.red)
                    .padding(.top, 40)

                // 错误标题
                Text("终端连接失败")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                // 错误描述
                Text(error.localizedDescription)
                    .font(.body)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Bridge 状态检查
                BridgeStatusCard(
                    status: bridgeStatus,
                    message: bridgeStatusMessage,
                    onCheck: onCheckStatus
                )

                // 错误详情
                VStack(alignment: .leading, spacing: 12) {
                    DetailRow(label: "URL", value: device.url.absoluteString, isURL: true)
                    DetailRow(label: "错误类型", value: errorCodeDescription)
                    DetailRow(label: "错误域", value: nsError.domain)

                    if let failingURL = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
                        DetailRow(label: "失败地址", value: failingURL.absoluteString, isURL: true)
                    }
                }
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal)

                // 建议解决方案
                VStack(alignment: .leading, spacing: 8) {
                    Text(suggestedSolution)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .lineSpacing(4)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)

                // 操作按钮
                HStack(spacing: 16) {
                    Button(action: onRetry) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("重试连接")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [.orange, .red]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(10)
                    }

                    Button(action: {
                        UIPasteboard.general.string = device.url.absoluteString
                    }) {
                        HStack {
                            Image(systemName: "doc.on.doc")
                            Text("复制 URL")
                        }
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(Color.gray.opacity(0.6))
                        .cornerRadius(10)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .padding()
        }
        .background(Color.black)
    }
}

// MARK: - Bridge Status Card
struct BridgeStatusCard: View {
    let status: TerminalViewModel.BridgeStatus
    let message: String
    let onCheck: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: status.icon)
                    .font(.title2)
                    .foregroundColor(status.color)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Bridge 服务状态: \(status.rawValue)")
                        .font(.headline)
                        .foregroundColor(status.color)

                    if !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }

                Spacer()

                Button(action: onCheck) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                        .padding(8)
                        .background(Color.blue.opacity(0.2))
                        .clipShape(Circle())
                }
            }
            .padding()
            .background(status.color.opacity(0.1))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(status.color.opacity(0.3), lineWidth: 1)
            )
        }
        .padding(.horizontal)
    }
}

// MARK: - Detail Row
struct DetailRow: View {
    let label: String
    let value: String
    var isURL: Bool = false

    var body: some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(.gray)
                .frame(width: 70, alignment: .leading)

            Text(value)
                .font(.caption)
                .foregroundColor(isURL ? .blue : .white.opacity(0.8))
                .lineLimit(2)

            Spacer()
        }
    }
}

// MARK: - Error Extension
extension Error {
    var localizedDescription: String {
        let nsError = self as NSError
        return nsError.localizedDescription
    }
}
import SwiftUI
import WebKit
import UIKit

struct WebSocketTerminalView: View {
    let device: ClusterDevice
    @StateObject private var viewModel = WebSocketTerminalViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // WebSocket 终端 WebView
                WebSocketTerminalWebView(
                    device: device,
                    viewModel: viewModel
                )

                // 连接状态栏
                HStack {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 8, height: 8)

                    Text(viewModel.connectionState.description)
                        .font(.caption)
                        .foregroundColor(.gray)

                    Spacer()

                    if viewModel.isConnecting {
                        ProgressView()
                            .scaleEffect(0.6)
                    }

                    Text("\(device.host):\(device.port)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.8))
            }
        }
        .onAppear {
            // 延迟一点再连接，避免页面切换时卡死
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                viewModel.connect(to: device)
            }
        }
        .onDisappear {
            viewModel.disconnect()
        }
    }

    private var connectionColor: Color {
        switch viewModel.connectionState {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .gray
        case .error:
            return .red
        }
    }
}

// MARK: - WebSocket Terminal View Model
@MainActor
class WebSocketTerminalViewModel: ObservableObject {
    @Published var connectionState: WebSocketState = .disconnected
    @Published var isConnecting = false

    private var webSocketClient: WebSocketClient?
    private var device: ClusterDevice?

    func connect(to device: ClusterDevice) {
        self.device = device
        self.isConnecting = true

        let client = TerminalWebSocketClient()
        client.onMessage = { [weak self] message in
            // 处理接收到的消息，传递给 WebView
            self?.handleMessage(message)
        }
        client.onStateChange = { [weak self] state in
            self?.connectionState = state
            self?.isConnecting = (state == .connecting)
        }

        self.webSocketClient = client
        client.connect(to: device.host, port: device.port, path: "/terminal")
    }

    func disconnect() {
        webSocketClient?.disconnect()
        webSocketClient = nil
    }

    func send(message: String) {
        Task {
            try? await webSocketClient?.send(message)
        }
    }

    private func handleMessage(_ message: String) {
        // 通过 NotificationCenter 传递给 WebView
        NotificationCenter.default.post(
            name: .terminalWebSocketMessage,
            object: nil,
            userInfo: ["message": message]
        )
    }
}

// MARK: - Terminal WebSocket Client
class TerminalWebSocketClient: WebSocketClient {
    var onMessage: ((String) -> Void)?
    var onStateChange: ((WebSocketState) -> Void)?

    override func handleMessage(_ message: String) {
        super.handleMessage(message)
        onMessage?(message)
    }

    override func connect() {
        super.connect()
        onStateChange?(.connecting)
    }
}

// MARK: - WebSocket Terminal WebView
struct WebSocketTerminalWebView: UIViewRepresentable {
    let device: ClusterDevice
    @ObservedObject var viewModel: WebSocketTerminalViewModel

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.preferences.javaScriptEnabled = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .black
        webView.isOpaque = false

        // 加载本地终端 HTML
        let html = createTerminalHTML(webSocketURL: device.terminalWebSocketURL)
        webView.loadHTMLString(html, baseURL: nil)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    private func createTerminalHTML(webSocketURL: String) -> String {
        // 使用字符串拼接避免 Swift 多行字符串的转义问题
        let html = """
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>Terminal</title>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/xterm@5.3.0/css/xterm.css">
    <script src="https://cdn.jsdelivr.net/npm/xterm@5.3.0/lib/xterm.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/xterm-addon-fit@0.8.0/lib/xterm-addon-fit.min.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        html, body { width: 100%; height: 100%; background: #0d0d0d; overflow: hidden; }
        #terminal { width: 100%; height: 100%; padding: 8px; }
    </style>
</head>
<body>
    <div id="terminal"></div>
    <script>
        const term = new Terminal({
            fontSize: 14,
            fontFamily: 'SF Mono, Monaco, Menlo, monospace',
            cursorBlink: true,
            cursorStyle: 'block',
            scrollback: 10000,
            theme: { background: '#0d0d0d', foreground: '#e0e0e0' }
        });

        const fitAddon = new FitAddon.FitAddon();
        term.loadAddon(fitAddon);
        term.open(document.getElementById('terminal'));
        fitAddon.fit();
        term.focus();

        const wsUrl = '\(webSocketURL)';
        let ws = null;
        let reconnectAttempts = 0;

        function connect() {
            ws = new WebSocket(wsUrl);

            ws.onopen = function() {
                reconnectAttempts = 0;
            };

            ws.onmessage = function(event) {
                let data = event.data;
                // 简单处理：如果是JSON，提取data字段
                if (data.charAt(0) === '{') {
                    try {
                        var msg = JSON.parse(data);
                        if (msg.data) {
                            // 将\\n转换为真实换行
                            data = msg.data.split('\\\\n').join('\n')
                                          .split('\\\\r').join('\r')
                                          .split('\\\\t').join('\t')
                                          .split('\\\\"').join('"');
                        }
                    } catch(e) {}
                }
                term.write(data);
            };

            ws.onclose = function() {
                if (reconnectAttempts < 5) {
                    reconnectAttempts++;
                    setTimeout(connect, 2000);
                }
            };

            ws.onerror = function(e) {
                console.error('WS Error:', e);
            };
        }

        term.onData(function(data) {
            if (ws && ws.readyState === 1) ws.send(data);
        });

        window.addEventListener('resize', function() { fitAddon.fit(); });
        connect();
    </script>
</body>
</html>
"""
        return html
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let terminalWebSocketMessage = Notification.Name("terminalWebSocketMessage")
}

// MARK: - Preview
struct WebSocketTerminalView_Previews: PreviewProvider {
    static var previews: some View {
        WebSocketTerminalView(device: ClusterDevice(
            name: "Test",
            host: "192.168.1.63",
            port: 8080
        ))
    }
}
