import Foundation
import SwiftUI

enum DeviceStatus: String, Codable, Hashable, CaseIterable {
    case online = "在线"
    case offline = "离线"
    case connecting = "连接中"
    case error = "错误"

    var color: Color {
        switch self {
        case .online: return .green
        case .offline: return .gray
        case .connecting: return .yellow
        case .error: return .red
        }
    }

    var icon: String {
        switch self {
        case .online: return "checkmark.circle.fill"
        case .offline: return "xmark.circle.fill"
        case .connecting: return "arrow.clockwise"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

enum ConnectionMode: String, Codable, CaseIterable {
    case shared = "Shared"
    case isolated = "Isolated"

    var description: String {
        switch self {
        case .shared: return "共享会话"
        case .isolated: return "独立会话"
        }
    }
}

enum DeviceCapability: String, Codable, CaseIterable {
    case claudeCode = "claude"
    case terminal = "terminal"
    case fileTransfer = "sftp"

    var icon: String {
        switch self {
        case .claudeCode: return "brain"
        case .terminal: return "terminal"
        case .fileTransfer: return "folder"
        }
    }

    var description: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .terminal: return "终端"
        case .fileTransfer: return "文件传输"
        }
    }
}

struct ClusterDevice: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var status: DeviceStatus
    var mode: ConnectionMode
    var lastSeen: Date?
    var latency: TimeInterval?
    var capabilities: [DeviceCapability]
    var description: String?

    var url: URL { URL(string: "http://\(host):\(port)")! }

    /// WebSocket URL for terminal connection
    var webSocketURL: URL {
        // Use ws:// for WebSocket connection
        URL(string: "ws://\(host):\(port)/terminal")!
    }

    /// WebSocket URL for xterm.js WebSocket connection
    var terminalWebSocketURL: String {
        "ws://\(host):\(port)/terminal"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ClusterDevice, rhs: ClusterDevice) -> Bool {
        lhs.id == rhs.id
    }

    var displayName: String {
        name
    }

    var subtitle: String {
        "\(host):\(port)"
    }

    var isOnline: Bool {
        status == .online
    }

    var formattedLastSeen: String {
        guard let lastSeen = lastSeen else { return "从未连接" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastSeen, relativeTo: Date())
    }

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int,
        status: DeviceStatus = .offline,
        mode: ConnectionMode = .shared,
        lastSeen: Date? = nil,
        capabilities: [DeviceCapability] = [.claudeCode, .terminal],
        description: String? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.status = status
        self.mode = mode
        self.lastSeen = lastSeen
        self.capabilities = capabilities
        self.description = description
    }

    static let defaults = [
        ClusterDevice(
            name: "Windows",
            host: "192.168.1.63",
            port: 8080,
            mode: .isolated,
            capabilities: [.claudeCode, .terminal],
            description: "Windows 开发环境"
        ),
        ClusterDevice(
            name: "macOS",
            host: "192.168.1.64",
            port: 8765,
            mode: .shared,
            capabilities: [.claudeCode, .terminal],
            description: "macOS 开发机"
        ),
        ClusterDevice(
            name: "VPS",
            host: "123.207.187.104",
            port: 8767,
            mode: .shared,
            capabilities: [.claudeCode, .terminal],
            description: "云端 VPS (Bridge)"
        )
    ]
}

// MARK: - Device Status Result
struct DeviceStatusResult {
    let isOnline: Bool
    let latency: TimeInterval?
    let error: Error?
}

// MARK: - URLSession Delegate for insecure HTTP
class InsecureURLSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Allow all connections including HTTP and self-signed certificates
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - ViewModel
@MainActor
class ClusterViewModel: ObservableObject {
    @Published var devices: [ClusterDevice] = []
    @Published var isRefreshing = false
    @Published var selectedDevices: Set<UUID> = []
    @Published var deviceLatencies: [UUID: TimeInterval] = [:]
    @Published var commandHistory: [ClusterCommand] = []

    private let persistence = DataPersistenceManager.shared
    private let defaultTimeout: TimeInterval = 3.0  // 缩短超时时间
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = defaultTimeout
        config.timeoutIntervalForResource = defaultTimeout
        // 允许不安全的HTTP连接
        config.httpShouldUsePipelining = true
        return URLSession(configuration: config, delegate: InsecureURLSessionDelegate(), delegateQueue: nil)
    }()

    init() {
        self.devices = persistence.loadDevices()
        self.commandHistory = persistence.loadCommandHistory()
    }

    func saveDevices() {
        persistence.saveDevices(devices)
    }

    func addDevice(_ device: ClusterDevice) {
        devices.append(device)
        saveDevices()
    }

    func removeDevice(_ device: ClusterDevice) {
        devices.removeAll { $0.id == device.id }
        selectedDevices.remove(device.id)
        saveDevices()
    }

    func updateDevice(_ device: ClusterDevice) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
            saveDevices()
        }
    }

    func refreshStatus() async {
        isRefreshing = true
        defer { isRefreshing = false }

        await withTaskGroup(of: (Int, DeviceStatusResult).self) { group in
            for (index, device) in devices.enumerated() {
                group.addTask {
                    let result = await self.checkDeviceStatus(device)
                    return (index, result)
                }
            }

            for await (index, result) in group {
                devices[index].status = result.isOnline ? .online : .offline
                if result.isOnline {
                    devices[index].lastSeen = Date()
                    if let latency = result.latency {
                        deviceLatencies[devices[index].id] = latency
                    }
                } else {
                    deviceLatencies.removeValue(forKey: devices[index].id)
                    // 打印离线原因
                    if let error = result.error {
                        print("⚠️ \(devices[index].name) 离线: \(error.localizedDescription)")
                    } else {
                        print("⚠️ \(devices[index].name) 离线: Bridge 服务未运行或网络不通")
                    }
                }
            }
        }

        // Save updated device status
        saveDevices()
    }

    private func checkDeviceStatus(_ device: ClusterDevice) async -> DeviceStatusResult {
        // 快速检测：只尝试根路径，超时3秒
        return await checkURL("http://\(device.host):\(device.port)/")
            ?? DeviceStatusResult(isOnline: false, latency: nil, error: nil)
    }

    private func checkURL(_ urlString: String) async -> DeviceStatusResult? {
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL: \(urlString)")
            return nil
        }

        let startTime = Date()
        print("🔍 Checking: \(urlString)")

        do {
            let (data, response) = try await urlSession.data(from: url)
            let latency = Date().timeIntervalSince(startTime)

            if let httpResponse = response as? HTTPURLResponse {
                let responseText = String(data: data, encoding: .utf8)?.prefix(100) ?? "No body"
                print("📡 Response: \(httpResponse.statusCode) - \(responseText)")

                // 200-399 正常 HTTP，426 是 WebSocket 服务运行中
                if (200...399).contains(httpResponse.statusCode) || httpResponse.statusCode == 426 {
                    print("✅ Device online: \(urlString) - \(String(format: "%.0f", latency * 1000))ms (HTTP \(httpResponse.statusCode))")
                    return DeviceStatusResult(isOnline: true, latency: latency, error: nil)
                } else {
                    print("⚠️ Bad status: \(httpResponse.statusCode)")
                }
            } else {
                print("⚠️ Invalid response type")
            }
            return nil
        } catch let urlError as URLError {
            print("❌ URL Error [\(urlError.code)]: \(urlError.localizedDescription)")
            switch urlError.code {
            case .notConnectedToInternet:
                print("   → No internet connection")
            case .timedOut:
                print("   → Connection timed out - Bridge service not responding")
            case .cannotConnectToHost:
                print("   → Cannot connect to host - Bridge service not running on port")
            case .cancelled:
                print("   → Request cancelled")
            default:
                print("   → Error code: \(urlError.code.rawValue)")
            }
            return nil
        } catch {
            print("❌ Unknown error: \(error.localizedDescription)")
            return nil
        }
    }

    func resetToDefaults() {
        DataPersistenceManager.shared.resetDevicesToDefaults()
        self.devices = DataPersistenceManager.shared.loadDevices()
        self.deviceLatencies.removeAll()
        self.selectedDevices.removeAll()
    }

    func getLatency(for deviceId: UUID) -> String {
        guard let latency = deviceLatencies[deviceId] else { return "--" }
        if latency < 0.001 {
            return "<1ms"
        } else if latency < 1.0 {
            return String(format: "%.0fms", latency * 1000)
        } else {
            return String(format: "%.1fs", latency)
        }
    }

    func toggleSelection(_ deviceId: UUID) {
        if selectedDevices.contains(deviceId) {
            selectedDevices.remove(deviceId)
        } else {
            selectedDevices.insert(deviceId)
        }
    }

    func selectAll() {
        selectedDevices = Set(devices.map { $0.id })
    }

    func deselectAll() {
        selectedDevices.removeAll()
    }

    var selectedDevicesList: [ClusterDevice] {
        devices.filter { selectedDevices.contains($0.id) }
    }
}
