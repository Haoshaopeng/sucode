import Foundation

// MARK: - WebSocket Connection State
enum WebSocketState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var description: String {
        switch self {
        case .disconnected: return "已断开"
        case .connecting: return "连接中"
        case .connected: return "已连接"
        case .error(let msg): return "错误: \(msg)"
        }
    }
}

// MARK: - WebSocket Message Types
enum WebSocketMessage {
    case text(String)
    case data(Data)
    case error(Error)
}

// MARK: - WebSocket Client
@MainActor
open class WebSocketClient: NSObject, ObservableObject {
    @Published var state: WebSocketState = .disconnected
    @Published var lastMessage: String?

    private var webSocketTask: URLSessionWebSocketTask?
    private var url: URL?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private let reconnectDelay: TimeInterval = 3.0
    private var reconnectTimer: Timer?
    private var isIntentionallyDisconnected = false

    var isConnected: Bool {
        state == .connected
    }

    // MARK: - Connection Management

    func connect(to host: String, port: Int, path: String = "/terminal") {
        guard let url = URL(string: "ws://\(host):\(port)\(path)") else {
            state = .error("无效的WebSocket URL")
            return
        }

        self.url = url
        isIntentionallyDisconnected = false
        connect()
    }

    func connect(to url: URL) {
        self.url = url
        isIntentionallyDisconnected = false
        connect()
    }

    open func connect() {
        guard let url = url else { return }

        state = .connecting

        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0

        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.delegate = self

        setupMessageHandler()
        webSocketTask?.resume()
    }

    func disconnect() {
        isIntentionallyDisconnected = true
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        reconnectAttempts = 0

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        state = .disconnected
    }

    // MARK: - Reconnection

    private func scheduleReconnect() {
        guard !isIntentionallyDisconnected,
              reconnectAttempts < maxReconnectAttempts else {
            state = .error("重连失败，已达到最大尝试次数")
            return
        }

        reconnectAttempts += 1

        DispatchQueue.main.async { [weak self] in
            self?.reconnectTimer = Timer.scheduledTimer(withTimeInterval: self?.reconnectDelay ?? 3.0, repeats: false) { _ in
                Task { @MainActor in
                    self?.connect()
                }
            }
        }
    }

    // MARK: - Message Handling

    private func setupMessageHandler() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self?.reconnectAttempts = 0

                    switch message {
                    case .string(let text):
                        self?.lastMessage = text
                        self?.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self?.lastMessage = text
                            self?.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }

                    // Continue receiving messages
                    self?.setupMessageHandler()

                case .failure(let error):
                    self?.handleError(error)
                }
            }
        }
    }

    open func handleMessage(_ message: String) {
        // Subclass can override this to handle specific message types
        // Default implementation just updates lastMessage
    }

    private func handleError(_ error: Error) {
        state = .error(error.localizedDescription)

        if !isIntentionallyDisconnected {
            scheduleReconnect()
        }
    }

    // MARK: - Send Messages

    func send(_ message: String) async throws {
        guard state == .connected else {
            throw WebSocketError.notConnected
        }

        try await webSocketTask?.send(.string(message))
    }

    func send(_ data: Data) async throws {
        guard state == .connected else {
            throw WebSocketError.notConnected
        }

        try await webSocketTask?.send(.data(data))
    }

    func sendPing() async throws {
        guard state == .connected else {
            throw WebSocketError.notConnected
        }

        try await webSocketTask?.sendPing { _ in }
    }
}

// MARK: - URLSessionWebSocketDelegate
extension WebSocketClient: URLSessionWebSocketDelegate {
    public nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor in
            self.state = .connected
            self.reconnectAttempts = 0
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor in
            let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "未知原因"

            switch closeCode {
            case .normalClosure:
                self.state = .disconnected
            case .goingAway:
                self.state = .error("服务器关闭")
                self.scheduleReconnect()
            default:
                self.state = .error("连接关闭: \(reasonString)")
                self.scheduleReconnect()
            }
        }
    }
}

// MARK: - WebSocket Error
enum WebSocketError: LocalizedError {
    case notConnected
    case invalidURL
    case encodingFailed
    case sendFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "WebSocket未连接"
        case .invalidURL:
            return "无效的URL"
        case .encodingFailed:
            return "消息编码失败"
        case .sendFailed(let error):
            return "发送失败: \(error.localizedDescription)"
        }
    }
}

