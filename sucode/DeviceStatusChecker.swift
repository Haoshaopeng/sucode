import Foundation
import Combine

// MARK: - 设备状态检查结果
struct DeviceStatusCheckResult {
    let isOnline: Bool
    let latency: TimeInterval?
    let error: DeviceStatusError?
    let timestamp: Date
    let httpStatusCode: Int?
}

enum DeviceStatusError: Error, LocalizedError {
    case invalidURL
    case timeout
    case networkError(Error)
    case httpError(Int)
    case unreachable
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 URL"
        case .timeout:
            return "连接超时"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .httpError(let code):
            return "HTTP 错误: \(code)"
        case .unreachable:
            return "主机不可达"
        case .unknown:
            return "未知错误"
        }
    }
}

// MARK: - 设备状态监控器
@MainActor
class DeviceStatusMonitor: ObservableObject {
    @Published var deviceStatuses: [UUID: DeviceStatusCheckResult] = [:]
    @Published var isChecking = false

    // 配置
    var checkInterval: TimeInterval = 30.0  // 默认30秒检查一次
    var timeout: TimeInterval = 5.0         // 默认5秒超时
    var maxRetries: Int = 2                 // 最大重试次数
    var retryDelay: TimeInterval = 1.0      // 重试间隔

    private var timers: [UUID: Timer] = [:]
    private var urlSession: URLSession
    private var cancellables = Set<AnyCancellable>()

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        self.urlSession = URLSession(configuration: config)
    }

    deinit {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
    }

    // MARK: - 公共方法

    /// 开始监控设备
    func startMonitoring(device: ClusterDevice) {
        stopMonitoring(deviceId: device.id)

        // 立即检查一次
        Task {
            await checkDevice(device)
        }

        // 设置定时器
        let timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkDevice(device)
            }
        }
        timers[device.id] = timer
    }

    /// 停止监控特定设备
    func stopMonitoring(deviceId: UUID) {
        timers[deviceId]?.invalidate()
        timers.removeValue(forKey: deviceId)
    }

    /// 停止所有监控
    func stopAllMonitoring() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
    }

    /// 立即检查设备状态（带重试机制）
    func checkDevice(_ device: ClusterDevice) async -> DeviceStatusCheckResult {
        isChecking = true
        defer { isChecking = false }

        var lastResult: DeviceStatusCheckResult?

        for attempt in 0...maxRetries {
            let result = await performCheck(device: device)
            lastResult = result

            if result.isOnline {
                deviceStatuses[device.id] = result
                return result
            }

            // 如果不是最后一次尝试，等待后重试
            if attempt < maxRetries {
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }

        // 所有重试都失败了
        if let result = lastResult {
            deviceStatuses[device.id] = result
            return result
        }

        let failedResult = DeviceStatusCheckResult(
            isOnline: false,
            latency: nil,
            error: .unknown,
            timestamp: Date(),
            httpStatusCode: nil
        )
        deviceStatuses[device.id] = failedResult
        return failedResult
    }

    /// 批量检查多个设备
    func checkDevices(_ devices: [ClusterDevice]) async {
        isChecking = true
        defer { isChecking = false }

        await withTaskGroup(of: (UUID, DeviceStatusCheckResult).self) { group in
            for device in devices {
                group.addTask { [weak self] in
                    guard let self = self else {
                        return (device.id, DeviceStatusCheckResult(
                            isOnline: false,
                            latency: nil,
                            error: .unknown,
                            timestamp: Date(),
                            httpStatusCode: nil
                        ))
                    }
                    let result = await self.checkDevice(device)
                    return (device.id, result)
                }
            }

            for await (deviceId, result) in group {
                self.deviceStatuses[deviceId] = result
            }
        }
    }

    /// 获取设备状态
    func status(for deviceId: UUID) -> DeviceStatus {
        guard let result = deviceStatuses[deviceId] else {
            return .offline
        }
        return result.isOnline ? .online : .offline
    }

    /// 获取设备延迟
    func latency(for deviceId: UUID) -> TimeInterval? {
        return deviceStatuses[deviceId]?.latency
    }

    /// 格式化延迟显示
    func formattedLatency(for deviceId: UUID) -> String {
        guard let latency = latency(for: deviceId) else {
            return "--"
        }

        if latency < 0.001 {
            return "<1ms"
        } else if latency < 1.0 {
            return String(format: "%.0fms", latency * 1000)
        } else {
            return String(format: "%.1fs", latency)
        }
    }

    /// 获取最后检查时间
    func lastChecked(for deviceId: UUID) -> Date? {
        return deviceStatuses[deviceId]?.timestamp
    }

    /// 获取错误信息
    func error(for deviceId: UUID) -> DeviceStatusError? {
        return deviceStatuses[deviceId]?.error
    }

    // MARK: - 私有方法

    private func performCheck(device: ClusterDevice) async -> DeviceStatusCheckResult {
        let startTime = Date()
        let timestamp = startTime

        // 构建健康检查 URL
        let healthEndpoints = [
            "http://\(device.host):\(device.port)/health",
            "http://\(device.host):\(device.port)/",
            "http://\(device.host):\(device.port)/api/health"
        ]

        for endpoint in healthEndpoints {
            guard let url = URL(string: endpoint) else {
                continue
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            request.httpMethod = "GET"
            request.setValue("sucode/1.0", forHTTPHeaderField: "User-Agent")

            do {
                let (_, response) = try await urlSession.data(for: request)
                let latency = Date().timeIntervalSince(startTime)

                if let httpResponse = response as? HTTPURLResponse {
                    // 2xx 状态码表示在线
                    if (200...299).contains(httpResponse.statusCode) {
                        return DeviceStatusCheckResult(
                            isOnline: true,
                            latency: latency,
                            error: nil,
                            timestamp: timestamp,
                            httpStatusCode: httpResponse.statusCode
                        )
                    }
                }
            } catch let error as URLError {
                // 根据错误类型处理
                switch error.code {
                case .timedOut:
                    return DeviceStatusCheckResult(
                        isOnline: false,
                        latency: nil,
                        error: .timeout,
                        timestamp: timestamp,
                        httpStatusCode: nil
                    )
                case .cannotConnectToHost, .notConnectedToInternet:
                    // 继续尝试下一个端点
                    continue
                default:
                    // 继续尝试下一个端点
                    continue
                }
            } catch {
                // 继续尝试下一个端点
                continue
            }
        }

        // 所有端点都失败了
        return DeviceStatusCheckResult(
            isOnline: false,
            latency: nil,
            error: .unreachable,
            timestamp: timestamp,
            httpStatusCode: nil
        )
    }
}

// MARK: - 设备状态历史记录
@MainActor
class DeviceStatusHistory: ObservableObject {
    @Published var history: [UUID: [DeviceStatusRecord]] = [:]
    private let maxRecords = 100

    struct DeviceStatusRecord: Codable, Identifiable {
        let id = UUID()
        let timestamp: Date
        let isOnline: Bool
        let latency: TimeInterval?

        var formattedTime: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return formatter.string(from: timestamp)
        }
    }

    func addRecord(deviceId: UUID, result: DeviceStatusCheckResult) {
        let record = DeviceStatusRecord(
            timestamp: result.timestamp,
            isOnline: result.isOnline,
            latency: result.latency
        )

        if history[deviceId] == nil {
            history[deviceId] = []
        }

        history[deviceId]?.append(record)

        // 限制历史记录数量
        if history[deviceId]!.count > maxRecords {
            history[deviceId]?.removeFirst()
        }
    }

    func getHistory(for deviceId: UUID) -> [DeviceStatusRecord] {
        return history[deviceId] ?? []
    }

    func getUptime(for deviceId: UUID, since: Date) -> Double {
        let records = getHistory(for: deviceId).filter { $0.timestamp >= since }
        guard !records.isEmpty else { return 0 }

        let onlineCount = records.filter { $0.isOnline }.count
        return Double(onlineCount) / Double(records.count)
    }

    func clearHistory(for deviceId: UUID) {
        history.removeValue(forKey: deviceId)
    }

    func clearAllHistory() {
        history.removeAll()
    }
}
