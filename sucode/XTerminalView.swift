import SwiftUI
import WebKit

struct XTerminalView: UIViewRepresentable {
    let host: String
    let port: Int = 8765

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()

        // 允许 JavaScript
        config.preferences.javaScriptEnabled = true

        // 允许跨域（重要！）
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        // 注入 JavaScript 处理键盘
        let userScript = WKUserScript(
            source: """
                // 禁用橡皮筋效果（iOS 弹性滚动）
                document.body.style.overscrollBehavior = 'none';

                // 处理 iOS 键盘
                window.addEventListener('focusin', (e) => {
                    if (e.target.tagName === 'TEXTAREA') {
                        window.scrollTo(0, 0);
                    }
                });
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(userScript)

        // 添加消息处理器
        config.userContentController.add(context.coordinator, name: "terminalHandler")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false  // 禁用滚动，由 xterm.js 处理

        // 设置背景色
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.051, green: 0.067, blue: 0.09, alpha: 1.0)

        // 加载终端页面
        loadTerminalPage(webView: webView, coordinator: context.coordinator)

        return webView
    }

    private func loadTerminalPage(webView: WKWebView, coordinator: Coordinator) {
        let url = URL(string: "http://\(host):\(port)")!
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        webView.load(request)
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: XTerminalView
        private var loadingTimer: Timer?
        private let loadingTimeout: TimeInterval = 10.0
        private var isLoading = false

        init(_ parent: XTerminalView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
            startLoadingTimeout(webView: webView)
            print("🔄 XTerminal loading started: http://\(parent.host):\(parent.port)")
        }

        private func startLoadingTimeout(webView: WKWebView) {
            loadingTimer?.invalidate()
            loadingTimer = Timer.scheduledTimer(withTimeInterval: loadingTimeout, repeats: false) { [weak self] _ in
                guard let self = self, self.isLoading else { return }

                self.isLoading = false
                print("⏱️ XTerminal loading timeout after \(self.loadingTimeout)s")

                // 注入超时错误页面
                self.showTimeoutErrorPage(webView: webView)
            }
        }

        private func stopLoadingTimeout() {
            loadingTimer?.invalidate()
            loadingTimer = nil
        }

        private func showTimeoutErrorPage(webView: WKWebView) {
            let errorHTML = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <style>
                    body {
                        background: #0d1117;
                        color: #c9d1d9;
                        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
                        display: flex;
                        flex-direction: column;
                        align-items: center;
                        justify-content: center;
                        min-height: 100vh;
                        margin: 0;
                        padding: 20px;
                        text-align: center;
                    }
                    .error-icon {
                        font-size: 64px;
                        margin-bottom: 20px;
                    }
                    h1 { color: #f85149; margin-bottom: 10px; }
                    .url { color: #58a6ff; font-family: monospace; margin: 10px 0; }
                    .suggestions {
                        text-align: left;
                        background: #161b22;
                        padding: 20px;
                        border-radius: 12px;
                        margin-top: 20px;
                        max-width: 400px;
                    }
                    .suggestions h3 { color: #7ee787; margin-top: 0; }
                    .suggestions ul { padding-left: 20px; }
                    .suggestions li { margin: 8px 0; color: #8b949e; }
                    .retry-btn {
                        background: #238636;
                        color: white;
                        border: none;
                        padding: 12px 24px;
                        border-radius: 6px;
                        font-size: 16px;
                        margin-top: 20px;
                        cursor: pointer;
                    }
                </style>
            </head>
            <body>
                <div class="error-icon">⚠️</div>
                <h1>连接超时</h1>
                <p>无法在 10 秒内连接到 Bridge 服务</p>
                <div class="url">http://\(parent.host):\(parent.port)</div>
                <div class="suggestions">
                    <h3>建议解决方案：</h3>
                    <ul>
                        <li>检查 Bridge 服务是否已启动</li>
                        <li>确认设备与服务器在同一网络</li>
                        <li>检查防火墙是否允许端口 \(parent.port)</li>
                        <li>验证 IP 地址 \(parent.host) 是否正确</li>
                    </ul>
                </div>
                <button class="retry-btn" onclick="window.location.reload()">重新连接</button>
            </body>
            </html>
            """
            webView.loadHTMLString(errorHTML, baseURL: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            stopLoadingTimeout()
            isLoading = false
            print("✅ XTerminal loaded for \(parent.host)")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            stopLoadingTimeout()
            isLoading = false
            print("❌ XTerminal navigation failed: \(error)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            stopLoadingTimeout()
            isLoading = false

            let nsError = error as NSError
            if nsError.code == -999 {
                print("⚠️ XTerminal navigation cancelled")
                return
            }

            print("❌ XTerminal provisional navigation failed: \(error.localizedDescription)")
            showErrorPage(webView: webView, error: error)
        }

        private func showErrorPage(webView: WKWebView, error: Error) {
            let nsError = error as NSError
            var errorTitle = "连接失败"
            var errorDesc = error.localizedDescription

            switch nsError.code {
            case NSURLErrorTimedOut:
                errorTitle = "连接超时"
                errorDesc = "服务器未在指定时间内响应"
            case NSURLErrorCannotConnectToHost:
                errorTitle = "无法连接到主机"
                errorDesc = "请检查 IP 地址和端口是否正确"
            case NSURLErrorNotConnectedToInternet:
                errorTitle = "无网络连接"
                errorDesc = "请检查 iPhone 网络设置"
            default:
                break
            }

            let errorHTML = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <style>
                    body {
                        background: #0d1117;
                        color: #c9d1d9;
                        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
                        display: flex;
                        flex-direction: column;
                        align-items: center;
                        justify-content: center;
                        min-height: 100vh;
                        margin: 0;
                        padding: 20px;
                        text-align: center;
                    }
                    .error-icon { font-size: 64px; margin-bottom: 20px; }
                    h1 { color: #f85149; margin-bottom: 10px; }
                    .error-code { color: #8b949e; font-size: 14px; margin: 10px 0; }
                    .url { color: #58a6ff; font-family: monospace; margin: 10px 0; }
                    .suggestions {
                        text-align: left;
                        background: #161b22;
                        padding: 20px;
                        border-radius: 12px;
                        margin-top: 20px;
                        max-width: 400px;
                    }
                    .suggestions h3 { color: #7ee787; margin-top: 0; }
                    .suggestions ul { padding-left: 20px; }
                    .suggestions li { margin: 8px 0; color: #8b949e; }
                    .retry-btn {
                        background: #238636;
                        color: white;
                        border: none;
                        padding: 12px 24px;
                        border-radius: 6px;
                        font-size: 16px;
                        margin-top: 20px;
                        cursor: pointer;
                    }
                </style>
            </head>
            <body>
                <div class="error-icon">❌</div>
                <h1>\(errorTitle)</h1>
                <p>\(errorDesc)</p>
                <div class="error-code">错误代码: \(nsError.code)</div>
                <div class="url">http://\(parent.host):\(parent.port)</div>
                <div class="suggestions">
                    <h3>建议解决方案：</h3>
                    <ul>
                        <li>检查 Bridge 服务是否已启动</li>
                        <li>确认设备与服务器在同一网络</li>
                        <li>检查防火墙是否允许端口 \(parent.port)</li>
                        <li>在 Safari 中测试此 URL</li>
                    </ul>
                </div>
                <button class="retry-btn" onclick="window.location.reload()">重新连接</button>
            </body>
            </html>
            """
            webView.loadHTMLString(errorHTML, baseURL: nil)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "terminalHandler" {
                print("Terminal message: \(message.body)")
            }
        }
    }
}

// MARK: - 设备选择器
struct DeviceSelectorView: View {
    @Binding var selectedDevice: RemoteDevice

    var body: some View {
        Picker("设备", selection: $selectedDevice) {
            ForEach(RemoteDevice.allCases) { device in
                Text(device.name).tag(device)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
}

enum RemoteDevice: String, CaseIterable, Identifiable {
    case windows = "192.168.1.63"
    case macVM = "192.168.1.64"
    case vps = "123.207.187.104"

    var id: String { self.rawValue }

    var name: String {
        switch self {
        case .windows: return "Windows"
        case .macVM: return "macOS VM"
        case .vps: return "VPS"
        }
    }

    var host: String { self.rawValue }
}

// MARK: - 主界面
struct ClaudeTerminalView: View {
    @State private var selectedDevice: RemoteDevice = .macVM

    var body: some View {
        VStack(spacing: 0) {
            // 设备选择器
            DeviceSelectorView(selectedDevice: $selectedDevice)
                .padding(.vertical, 8)
                .background(Color(red: 0.051, green: 0.067, blue: 0.09))

            // 终端视图
            XTerminalView(host: selectedDevice.host)
                .id(selectedDevice) // 切换设备时刷新
        }
        .ignoresSafeArea(.keyboard) // 键盘弹出时不调整布局
    }
}

// MARK: - 预览
struct XTerminalView_Previews: PreviewProvider {
    static var previews: some View {
        ClaudeTerminalView()
    }
}
