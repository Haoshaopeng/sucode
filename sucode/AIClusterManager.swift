import SwiftUI
import Combine

// MARK: - 集群设备状态
enum ClusterDeviceStatus: String, Codable, CaseIterable {
    case online = "在线"
    case offline = "离线"
    case checking = "检查中"
    case error = "错误"

    var color: Color {
        switch self {
        case .online: return .green
        case .offline: return .gray
        case .checking: return .orange
        case .error: return .red
        }
    }

    var icon: String {
        switch self {
        case .online: return "checkmark.circle.fill"
        case .offline: return "xmark.circle.fill"
        case .checking: return "arrow.clockwise"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - 集群设备模型
struct ClusterHost: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var description: String?
    var capabilities: [DeviceCapability]

    var status: ClusterDeviceStatus = .offline
    var latency: TimeInterval?
    var lastChecked: Date?
    var errorMessage: String?

    var fullAddress: String { "\(host):\(port)" }

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int,
        description: String? = nil,
        capabilities: [DeviceCapability] = [.claudeCode, .terminal]
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.description = description
        self.capabilities = capabilities
    }

    // MARK: - CodingKeys
    enum CodingKeys: String, CodingKey {
        case id, name, host, port, description, capabilities
        case status, latency, lastChecked, errorMessage
    }

    // MARK: - Codable
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        capabilities = try container.decode([DeviceCapability].self, forKey: .capabilities)
        status = try container.decodeIfPresent(ClusterDeviceStatus.self, forKey: .status) ?? .offline
        latency = try container.decodeIfPresent(TimeInterval.self, forKey: .latency)
        lastChecked = try container.decodeIfPresent(Date.self, forKey: .lastChecked)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(latency, forKey: .latency)
        try container.encodeIfPresent(lastChecked, forKey: .lastChecked)
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
    }

    static let defaults: [ClusterHost] = [
        ClusterHost(
            name: "Windows",
            host: "192.168.1.2",
            port: 8767,
            description: "Windows 开发环境",
            capabilities: [.claudeCode, .terminal]
        ),
        ClusterHost(
            name: "macOS",
            host: "192.168.1.64",
            port: 8765,
            description: "macOS 虚拟机",
            capabilities: [.claudeCode, .terminal]
        ),
        ClusterHost(
            name: "VPS",
            host: "123.207.187.104",
            port: 8766,
            description: "云端 VPS",
            capabilities: [.claudeCode, .terminal]
        )
    ]
}

// MARK: - AI 集群管理器
@MainActor
class AIClusterManager: ObservableObject {
    @Published var hosts: [ClusterHost] = []
    @Published var isChecking = false
    @Published var lastCheckTime: Date?

    // 状态检查器
    private let statusMonitor = DeviceStatusMonitor()
    private var cancellables = Set<AnyCancellable>()

    // 配置
    var autoCheckInterval: TimeInterval = 30.0
    private var autoCheckTimer: Timer?

    init() {
        self.hosts = ClusterHost.defaults
        setupBindings()
        startAutoCheck()
    }

    deinit {
        autoCheckTimer?.invalidate()
        autoCheckTimer = nil
    }

    // MARK: - 设置绑定
    private func setupBindings() {
        statusMonitor.$deviceStatuses
            .receive(on: DispatchQueue.main)
            .sink { [weak self] statuses in
                self?.updateHostStatuses(from: statuses)
            }
            .store(in: &cancellables)

        statusMonitor.$isChecking
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isChecking in
                self?.isChecking = isChecking
            }
            .store(in: &cancellables)
    }

    // MARK: - 状态更新
    private func updateHostStatuses(from statuses: [UUID: DeviceStatusCheckResult]) {
        for (index, host) in hosts.enumerated() {
            if let result = statuses[host.id] {
                hosts[index].status = result.isOnline ? .online : .offline
                hosts[index].latency = result.latency
                hosts[index].lastChecked = result.timestamp
                hosts[index].errorMessage = result.error?.errorDescription
            }
        }
        lastCheckTime = Date()
    }

    // MARK: - 自动检查
    func startAutoCheck() {
        stopAutoCheck()

        // 立即检查一次
        checkAllHosts()

        // 设置定时器
        autoCheckTimer = Timer.scheduledTimer(withTimeInterval: autoCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkAllHostsAsync()
            }
        }
    }

    func stopAutoCheck() {
        autoCheckTimer?.invalidate()
        autoCheckTimer = nil
    }

    // MARK: - 手动检查
    func checkAllHosts() {
        Task {
            await checkAllHostsAsync()
        }
    }

    func checkAllHostsAsync() async {
        let clusterDevices = hosts.map { host in
            ClusterDevice(
                id: host.id,
                name: host.name,
                host: host.host,
                port: host.port,
                status: .offline,
                mode: .shared,
                capabilities: host.capabilities
            )
        }

        await statusMonitor.checkDevices(clusterDevices)
    }

    func checkHost(_ host: ClusterHost) async {
        let device = ClusterDevice(
            id: host.id,
            name: host.name,
            host: host.host,
            port: host.port,
            status: .offline,
            mode: .shared,
            capabilities: host.capabilities
        )

        _ = await statusMonitor.checkDevice(device)
    }

    // MARK: - 主机管理
    func addHost(_ host: ClusterHost) {
        hosts.append(host)
        // 开始监控新主机
        let device = ClusterDevice(
            id: host.id,
            name: host.name,
            host: host.host,
            port: host.port,
            status: .offline,
            mode: .shared,
            capabilities: host.capabilities
        )
        statusMonitor.startMonitoring(device: device)
    }

    func removeHost(id: UUID) {
        hosts.removeAll { $0.id == id }
        statusMonitor.stopMonitoring(deviceId: id)
    }

    func updateHost(_ host: ClusterHost) {
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index] = host
        }
    }

    // MARK: - 辅助方法
    func getHost(byId id: UUID) -> ClusterHost? {
        return hosts.first { $0.id == id }
    }

    func formattedLatency(for hostId: UUID) -> String {
        guard let host = getHost(byId: hostId),
              let latency = host.latency else {
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

    var onlineHostsCount: Int {
        hosts.filter { $0.status == .online }.count
    }

    var totalHostsCount: Int {
        hosts.count
    }

    var averageLatency: TimeInterval? {
        let latencies = hosts.compactMap { $0.latency }
        guard !latencies.isEmpty else { return nil }
        return latencies.reduce(0, +) / Double(latencies.count)
    }

    func formattedAverageLatency() -> String {
        guard let avg = averageLatency else { return "--" }
        return String(format: "%.0fms", avg * 1000)
    }
}

// MARK: - 集群仪表盘视图
struct AIClusterDashboard: View {
    @StateObject private var manager = AIClusterManager()

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("集群概览")) {
                    ClusterOverviewCard(manager: manager)
                }

                Section(header: Text("设备状态")) {
                    ForEach(manager.hosts) { host in
                        ClusterHostRow(host: host, manager: manager)
                    }
                }

                Section {
                    Button(action: { manager.checkAllHosts() }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("刷新状态")
                            Spacer()
                            if manager.isChecking {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(manager.isChecking)
                }
            }
            .navigationTitle("AI Cluster")
            .onAppear {
                manager.startAutoCheck()
            }
            .onDisappear {
                manager.stopAutoCheck()
            }
        }
    }
}

// MARK: - 集群概览卡片
struct ClusterOverviewCard: View {
    @ObservedObject var manager: AIClusterManager

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                StatView(
                    title: "在线设备",
                    value: "\(manager.onlineHostsCount)/\(manager.totalHostsCount)",
                    color: .green
                )

                Divider()
                    .frame(height: 40)

                StatView(
                    title: "平均延迟",
                    value: manager.formattedAverageLatency(),
                    color: .blue
                )
            }

            if let lastCheck = manager.lastCheckTime {
                Text("上次检查: \(formattedTime(lastCheck))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - 统计视图
struct StatView: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 集群主机行
struct ClusterHostRow: View {
    let host: ClusterHost
    @ObservedObject var manager: AIClusterManager

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(host.name)
                    .font(.headline)
                Text(host.fullAddress)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let description = host.description {
                    Text(description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: statusIcon)
                        .foregroundColor(host.status.color)
                    Text(host.status.rawValue)
                        .font(.caption)
                        .foregroundColor(host.status.color)
                }

                if host.status == .online {
                    Text(manager.formattedLatency(for: host.id))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if let error = host.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusIcon: String {
        switch host.status {
        case .online:
            return "checkmark.circle.fill"
        case .offline:
            return "xmark.circle.fill"
        case .checking:
            return "arrow.clockwise"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - 预览
struct AIClusterDashboard_Previews: PreviewProvider {
    static var previews: some View {
        AIClusterDashboard()
            .preferredColorScheme(.dark)
    }
}
import Foundation
import NaturalLanguage

// Task models are available from AgentTaskModels.swift in the same module

// MARK: - Task Parser Error

enum TaskParserError: Error, LocalizedError {
    case emptyInput
    case unsupportedIntent
    case lowConfidence
    case parsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "输入不能为空"
        case .unsupportedIntent:
            return "暂不支持此类型的任务"
        case .lowConfidence:
            return "无法准确理解任务意图"
        case .parsingFailed(let reason):
            return "解析失败: \(reason)"
        }
    }
}

// MARK: - Task Parser

@MainActor
class TaskParser {

    // 关键词映射表
    private let actionKeywords: [String: [String]] = [
        "analyze": ["分析", "查看", "检查", "统计", "汇总", "总结", "review", "analyze", "check", "inspect"],
        "execute": ["执行", "运行", "启动", "调用", "run", "execute", "start", "launch"],
        "monitor": ["监控", "监视", "追踪", "观察", "monitor", "watch", "track", "observe"],
        "deploy": ["部署", "发布", "上线", "deploy", "release", "publish"],
        "sync": ["同步", "复制", "备份", "sync", "copy", "backup", "mirror"],
        "configure": ["配置", "设置", "修改", "configure", "setup", "set", "modify"]
    ]

    private let targetKeywords: [String: [String]] = [
        "logs": ["日志", "log", "logs", "记录"],
        "files": ["文件", "file", "files", "文档"],
        "processes": ["进程", "process", "processes", "任务"],
        "services": ["服务", "service", "services", "daemon"],
        "network": ["网络", "network", "连接", "端口", "connection"],
        "system": ["系统", "system", "性能", "资源", "performance", "resources"],
        "security": ["安全", "security", "漏洞", "vulnerability", "权限"],
        "database": ["数据库", "database", "db", "sql", "数据"]
    ]

    // MARK: - Parse Natural Language

    func parse(_ input: String) async throws -> TaskIntent {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TaskParserError.emptyInput
        }

        // 1. 使用 NLTagger 进行词性标注和实体识别
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
        tagger.string = input

        // 2. 识别动作
        let action = recognizeAction(input)

        // 3. 识别目标
        let targets = recognizeTargets(input)

        // 4. 提取约束条件
        let constraints = extractConstraints(input)

        // 5. 提取参数
        let parameters = extractParameters(input)

        // 6. 计算置信度
        let confidence = calculateConfidence(action: action, targets: targets, input: input)

        guard confidence > 0.3 else {
            throw TaskParserError.lowConfidence
        }

        return TaskIntent(
            action: action,
            targets: targets,
            constraints: constraints,
            parameters: parameters,
            confidence: confidence
        )
    }

    // MARK: - Action Recognition

    private func recognizeAction(_ input: String) -> String {
        let lowercased = input.lowercased()

        for (action, keywords) in actionKeywords {
            for keyword in keywords {
                if lowercased.contains(keyword.lowercased()) {
                    return action
                }
            }
        }

        // 默认动作
        return "analyze"
    }

    // MARK: - Target Recognition

    private func recognizeTargets(_ input: String) -> [String] {
        let lowercased = input.lowercased()
        var foundTargets: [String] = []

        for (target, keywords) in targetKeywords {
            for keyword in keywords {
                if lowercased.contains(keyword.lowercased()) {
                    foundTargets.append(target)
                    break
                }
            }
        }

        // 如果没有识别到目标，检查是否提到特定文件路径或进程名
        if foundTargets.isEmpty {
            if input.contains("/") || input.contains("\\") {
                foundTargets.append("files")
            }
        }

        return foundTargets.isEmpty ? ["system"] : foundTargets
    }

    // MARK: - Constraint Extraction

    private func extractConstraints(_ input: String) -> [String] {
        var constraints: [String] = []
        let lowercased = input.lowercased()

        // 时间约束
        if lowercased.contains("最近") || lowercased.contains("latest") ||
           lowercased.contains("最近") || lowercased.contains("recent") {
            constraints.append("time:recent")
        }
        if lowercased.contains("今天") || lowercased.contains("today") {
            constraints.append("time:today")
        }
        if lowercased.contains("本周") || lowercased.contains("this week") {
            constraints.append("time:this_week")
        }

        // 数量约束
        let numberPattern = "([0-9]+)"
        if let regex = try? NSRegularExpression(pattern: numberPattern, options: []),
           let match = regex.firstMatch(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count)) {
            if let range = Range(match.range, in: input) {
                let number = String(input[range])
                constraints.append("limit:\(number)")
            }
        }

        // 排序约束
        if lowercased.contains("最大") || lowercased.contains("最高") ||
           lowercased.contains("most") || lowercased.contains("top") {
            constraints.append("order:desc")
        }
        if lowercased.contains("最小") || lowercased.contains("最低") ||
           lowercased.contains("least") {
            constraints.append("order:asc")
        }

        return constraints
    }

    // MARK: - Parameter Extraction

    private func extractParameters(_ input: String) -> [String: String] {
        var parameters: [String: String] = [:]
        let lowercased = input.lowercased()

        // 提取时间范围
        if lowercased.contains("小时") || lowercased.contains("hours") {
            parameters["time_range"] = "hours"
        } else if lowercased.contains("天") || lowercased.contains("days") {
            parameters["time_range"] = "days"
        }

        // 提取设备数量
        if lowercased.contains("所有") || lowercased.contains("全部") ||
           lowercased.contains("all") {
            parameters["device_scope"] = "all"
        } else if lowercased.contains("每个") || lowercased.contains("every") {
            parameters["device_scope"] = "each"
        }

        // 提取输出格式
        if lowercased.contains("json") {
            parameters["output_format"] = "json"
        } else if lowercased.contains("表格") || lowercased.contains("table") {
            parameters["output_format"] = "table"
        }

        // 提取文件路径
        let pathPattern = "(/[a-zA-Z0-9_/\\.~-]+)|([a-zA-Z]:\\\\[a-zA-Z0-9_\\\\.~-]+)"
        if let regex = try? NSRegularExpression(pattern: pathPattern, options: []),
           let match = regex.firstMatch(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count)) {
            if let range = Range(match.range, in: input) {
                parameters["path"] = String(input[range])
            }
        }

        return parameters
    }

    // MARK: - Confidence Calculation

    private func calculateConfidence(action: String, targets: [String], input: String) -> Double {
        var score: Double = 0.5

        // 动作识别置信度
        if action != "analyze" {
            score += 0.2
        }

        // 目标识别置信度
        if !targets.isEmpty && targets != ["system"] {
            score += 0.15
        }

        // 输入长度检查（太短的输入通常不够明确）
        if input.count >= 10 {
            score += 0.1
        }

        // 关键词密度检查
        let meaningfulWords = input.components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.count >= 2 }
        if meaningfulWords.count >= 3 {
            score += 0.05
        }

        return min(score, 1.0)
    }

    // MARK: - Generate Task Type

    func generateTaskType(from intent: TaskIntent) -> TaskType {
        switch intent.action {
        case "analyze":
            return .analysis
        case "monitor":
            return .monitoring
        case "execute", "deploy", "sync", "configure":
            return .execution
        default:
            if intent.targets.contains("files") {
                return .fileOperation
            } else if intent.targets.contains("system") {
                return .systemInfo
            }
            return .custom
        }
    }
}
import Foundation

// Models from AgentTaskModels.swift are available in the same module

// MARK: - Scheduler Error

enum SchedulerError: Error, LocalizedError {
    case noAvailableDevices
    case deviceNotCapable(UUID)
    case circularDependency
    case taskTimeout
    case insufficientResources

    var errorDescription: String? {
        switch self {
        case .noAvailableDevices:
            return "没有可用的设备"
        case .deviceNotCapable(let id):
            return "设备 \(id) 不具备执行此任务的能力"
        case .circularDependency:
            return "任务存在循环依赖"
        case .taskTimeout:
            return "任务调度超时"
        case .insufficientResources:
            return "资源不足"
        }
    }
}

// MARK: - Device Load Info

struct DeviceLoadInfo {
    let deviceId: UUID
    var currentTasks: Int
    var averageResponseTime: TimeInterval
    var lastUsed: Date
    var cpuUsage: Double
    var memoryUsage: Double
}

// MARK: - Task Scheduler

@MainActor
class TaskScheduler {

    // 设备负载信息
    private var deviceLoads: [UUID: DeviceLoadInfo] = [:]

    // 调度配置
    var config: SchedulerConfiguration

    init(config: SchedulerConfiguration = SchedulerConfiguration()) {
        self.config = config
    }

    // MARK: - Create Execution Plan

    func createPlan(
        from intent: TaskIntent,
        availableDevices: [ClusterDevice]
    ) async throws -> TaskPlan {

        // 1. 分析设备能力匹配
        let matches = analyzeDeviceCapabilities(
            intent: intent,
            devices: availableDevices
        )

        // 2. 根据任务类型确定执行策略
        let strategy = determineExecutionStrategy(intent: intent, deviceCount: availableDevices.count)

        // 3. 生成子任务
        let subtasks = try await generateSubtasks(
            intent: intent,
            matches: matches,
            strategy: strategy
        )

        // 4. 计算预估总时长
        let estimatedDuration = estimateTotalDuration(subtasks: subtasks, strategy: strategy)

        return TaskPlan(
            subtasks: subtasks,
            executionStrategy: strategy,
            estimatedTotalDuration: estimatedDuration
        )
    }

    // MARK: - Device Capability Analysis

    private func analyzeDeviceCapabilities(
        intent: TaskIntent,
        devices: [ClusterDevice]
    ) -> [DeviceCapabilityMatch] {

        return devices.map { device in
            var score: Double = 0.0
            var matchedCapabilities: [String] = []

            // 基础在线状态检查
            guard device.status == .online else {
                return DeviceCapabilityMatch(
                    deviceId: device.id,
                    score: 0,
                    matchedCapabilities: [],
                    estimatedLoad: 1.0
                )
            }

            // 检查设备能力
            for capability in device.capabilities {
                switch capability {
                case .claudeCode:
                    if intent.action == "analyze" || intent.action == "execute" {
                        score += 0.4
                        matchedCapabilities.append("claude_code")
                    }
                case .terminal:
                    score += 0.3
                    matchedCapabilities.append("terminal")
                case .fileTransfer:
                    if intent.targets.contains("files") {
                        score += 0.3
                        matchedCapabilities.append("file_transfer")
                    }
                }
            }

            // 历史性能加权
            if let loadInfo = deviceLoads[device.id] {
                let loadFactor = 1.0 - min(Double(loadInfo.currentTasks) / 5.0, 0.5)
                score *= loadFactor

                let responseFactor = max(0.5, 1.0 - (loadInfo.averageResponseTime / 10.0))
                score *= responseFactor
            }

            return DeviceCapabilityMatch(
                deviceId: device.id,
                score: score,
                matchedCapabilities: matchedCapabilities,
                estimatedLoad: 0.5
            )
        }.sorted { $0.score > $1.score }
    }

    // MARK: - Determine Strategy

    private func determineExecutionStrategy(
        intent: TaskIntent,
        deviceCount: Int
    ) -> ExecutionStrategy {

        // 单设备时只能顺序执行
        guard deviceCount > 1 else {
            return .sequential
        }

        // 分析任务类型
        switch intent.action {
        case "analyze", "monitor":
            // 分析和监控任务可以并行
            return .parallel
        case "sync", "deploy":
            // 同步和部署可能需要顺序
            return deviceCount > 2 ? .mixed : .sequential
        case "configure":
            // 配置通常是顺序的
            return .sequential
        default:
            return .mixed
        }
    }

    // MARK: - Generate Subtasks

    private func generateSubtasks(
        intent: TaskIntent,
        matches: [DeviceCapabilityMatch],
        strategy: ExecutionStrategy
    ) async throws -> [SubTask] {

        var subtasks: [SubTask] = []
        let availableMatches = matches.filter { $0.score > 0.3 }

        guard !availableMatches.isEmpty else {
            throw SchedulerError.noAvailableDevices
        }

        switch intent.action {
        case "analyze":
            subtasks = generateAnalysisSubtasks(intent: intent, matches: availableMatches)

        case "monitor":
            subtasks = generateMonitoringSubtasks(intent: intent, matches: availableMatches)

        case "execute":
            subtasks = generateExecutionSubtasks(intent: intent, matches: availableMatches, strategy: strategy)

        case "sync":
            subtasks = generateSyncSubtasks(intent: intent, matches: availableMatches)

        default:
            subtasks = generateGenericSubtasks(intent: intent, matches: availableMatches)
        }

        // 验证依赖关系
        try validateDependencies(subtasks: subtasks)

        return subtasks
    }

    // MARK: - Subtask Generators

    private func generateAnalysisSubtasks(
        intent: TaskIntent,
        matches: [DeviceCapabilityMatch]
    ) -> [SubTask] {

        return matches.map { match in
            let command = generateAnalysisCommand(intent: intent, deviceId: match.deviceId)

            return SubTask(
                description: "在设备上执行 \(intent.targets.joined(separator: ", ")) 分析",
                targetDeviceId: match.deviceId,
                command: command,
                dependencies: [],
                status: .pending,
                estimatedDuration: 30.0
            )
        }
    }

    private func generateMonitoringSubtasks(
        intent: TaskIntent,
        matches: [DeviceCapabilityMatch]
    ) -> [SubTask] {

        return matches.map { match in
            SubTask(
                description: "监控 \(intent.targets.joined(separator: ", "))",
                targetDeviceId: match.deviceId,
                command: "monitor \(intent.targets.joined(separator: " "))",
                dependencies: [],
                status: .pending,
                estimatedDuration: 60.0
            )
        }
    }

    private func generateExecutionSubtasks(
        intent: TaskIntent,
        matches: [DeviceCapabilityMatch],
        strategy: ExecutionStrategy
    ) -> [SubTask] {

        var subtasks: [SubTask] = []
        var previousTaskId: UUID? = nil

        for (index, match) in matches.enumerated() {
            var dependencies: [UUID] = []

            // 顺序执行时添加依赖
            if strategy == .sequential, let prevId = previousTaskId {
                dependencies.append(prevId)
            }

            let subtask = SubTask(
                description: "执行步骤 \(index + 1)",
                targetDeviceId: match.deviceId,
                command: intent.parameters["command"],
                dependencies: dependencies,
                status: .pending,
                estimatedDuration: 10.0
            )

            subtasks.append(subtask)
            previousTaskId = subtask.id
        }

        return subtasks
    }

    private func generateSyncSubtasks(
        intent: TaskIntent,
        matches: [DeviceCapabilityMatch]
    ) -> [SubTask] {

        guard let sourcePath = intent.parameters["path"] else {
            return []
        }

        // 第一个设备作为源
        let sourceDevice = matches.first!

        var subtasks: [SubTask] = []

        // 源设备读取任务
        let sourceTask = SubTask(
            description: "从源设备读取 \(sourcePath)",
            targetDeviceId: sourceDevice.deviceId,
            command: "read \(sourcePath)",
            dependencies: [],
            status: .pending,
            estimatedDuration: 5.0
        )
        subtasks.append(sourceTask)

        // 其他设备同步任务
        for match in matches.dropFirst() {
            let syncTask = SubTask(
                description: "同步到设备",
                targetDeviceId: match.deviceId,
                command: "sync \(sourcePath)",
                dependencies: [sourceTask.id],
                status: .pending,
                estimatedDuration: 10.0
            )
            subtasks.append(syncTask)
        }

        return subtasks
    }

    private func generateGenericSubtasks(
        intent: TaskIntent,
        matches: [DeviceCapabilityMatch]
    ) -> [SubTask] {

        return matches.prefix(1).map { match in
            SubTask(
                description: "执行: \(intent.action)",
                targetDeviceId: match.deviceId,
                command: nil,
                dependencies: [],
                status: .pending,
                estimatedDuration: 15.0
            )
        }
    }

    // MARK: - Command Generation

    private func generateAnalysisCommand(intent: TaskIntent, deviceId: UUID) -> String {
        var components: [String] = ["analyze"]

        // 添加目标
        components.append(contentsOf: intent.targets)

        // 添加约束
        for constraint in intent.constraints {
            components.append("--\(constraint)")
        }

        // 添加参数
        for (key, value) in intent.parameters {
            components.append("--\(key)=\(value)")
        }

        return components.joined(separator: " ")
    }

    // MARK: - Dependency Validation

    private func validateDependencies(subtasks: [SubTask]) throws {
        var visited: Set<UUID> = []
        var recStack: Set<UUID> = []

        func hasCycle(_ id: UUID, _ adjacencyList: [UUID: [UUID]]) -> Bool {
            visited.insert(id)
            recStack.insert(id)

            for neighbor in adjacencyList[id] ?? [] {
                if !visited.contains(neighbor) {
                    if hasCycle(neighbor, adjacencyList) {
                        return true
                    }
                } else if recStack.contains(neighbor) {
                    return true
                }
            }

            recStack.remove(id)
            return false
        }

        // 构建邻接表
        var adjacencyList: [UUID: [UUID]] = [:]
        for subtask in subtasks {
            adjacencyList[subtask.id] = subtask.dependencies
        }

        // 检查每个节点
        for subtask in subtasks {
            if !visited.contains(subtask.id) {
                if hasCycle(subtask.id, adjacencyList) {
                    throw SchedulerError.circularDependency
                }
            }
        }
    }

    // MARK: - Duration Estimation

    private func estimateTotalDuration(subtasks: [SubTask], strategy: ExecutionStrategy) -> TimeInterval {
        switch strategy {
        case .sequential:
            return subtasks.reduce(0) { $0 + ($1.estimatedDuration ?? 0) }

        case .parallel:
            return subtasks.map { $0.estimatedDuration ?? 0 }.max() ?? 0

        case .mixed:
            // 简化的混合估计：先找出关键路径
            let maxPath = findCriticalPath(subtasks: subtasks)
            return maxPath.reduce(0) { $0 + ($1.estimatedDuration ?? 0) }
        }
    }

    private func findCriticalPath(subtasks: [SubTask]) -> [SubTask] {
        // 简化的关键路径计算
        let sorted = topologicalSort(subtasks: subtasks)
        return sorted
    }

    private func topologicalSort(subtasks: [SubTask]) -> [SubTask] {
        var result: [SubTask] = []
        var visited: Set<UUID> = []
        var subtaskMap: [UUID: SubTask] = [:]

        for subtask in subtasks {
            subtaskMap[subtask.id] = subtask
        }

        func visit(_ id: UUID) {
            guard !visited.contains(id), let subtask = subtaskMap[id] else { return }

            visited.insert(id)
            for depId in subtask.dependencies {
                visit(depId)
            }
            result.append(subtask)
        }

        for subtask in subtasks {
            visit(subtask.id)
        }

        return result
    }

    // MARK: - Update Device Load

    func updateDeviceLoad(deviceId: UUID, taskCompleted: Bool, responseTime: TimeInterval) {
        if var info = deviceLoads[deviceId] {
            if taskCompleted {
                info.currentTasks = max(0, info.currentTasks - 1)
            } else {
                info.currentTasks += 1
            }

            // 更新平均响应时间（指数移动平均）
            let alpha = 0.3
            info.averageResponseTime = info.averageResponseTime * (1 - alpha) + responseTime * alpha
            info.lastUsed = Date()

            deviceLoads[deviceId] = info
        } else {
            deviceLoads[deviceId] = DeviceLoadInfo(
                deviceId: deviceId,
                currentTasks: taskCompleted ? 0 : 1,
                averageResponseTime: responseTime,
                lastUsed: Date(),
                cpuUsage: 0,
                memoryUsage: 0
            )
        }
    }
}

// MARK: - Scheduler Configuration

struct SchedulerConfiguration {
    var maxConcurrentTasksPerDevice: Int = 3
    var defaultTimeout: TimeInterval = 60.0
    var enableLoadBalancing: Bool = true
    var enableFailover: Bool = true
    var retryAttempts: Int = 2

    init(
        maxConcurrentTasksPerDevice: Int = 3,
        defaultTimeout: TimeInterval = 60.0,
        enableLoadBalancing: Bool = true,
        enableFailover: Bool = true,
        retryAttempts: Int = 2
    ) {
        self.maxConcurrentTasksPerDevice = maxConcurrentTasksPerDevice
        self.defaultTimeout = defaultTimeout
        self.enableLoadBalancing = enableLoadBalancing
        self.enableFailover = enableFailover
        self.retryAttempts = retryAttempts
    }
}
import Foundation

// MARK: - Executor Error

enum ExecutorError: Error, LocalizedError {
    case deviceOffline(UUID)
    case executionFailed(UUID, String)
    case timeout(UUID)
    case invalidCommand
    case apiError(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .deviceOffline(let id):
            return "设备 \(id) 离线"
        case .executionFailed(let id, let reason):
            return "设备 \(id) 执行失败: \(reason)"
        case .timeout(let id):
            return "设备 \(id) 执行超时"
        case .invalidCommand:
            return "无效的命令"
        case .apiError(let message):
            return "API 错误: \(message)"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        }
    }
}

// MARK: - API Configuration

struct APIConfiguration {
    var provider: AIProvider
    var apiKey: String
    var baseURL: String?
    var model: String
    var timeout: TimeInterval

    enum AIProvider: String, CaseIterable {
        case openAI = "OpenAI"
        case anthropic = "Anthropic"
        case deepSeek = "DeepSeek"
        case local = "Local"

        var displayName: String {
            switch self {
            case .openAI: return "OpenAI"
            case .anthropic: return "Anthropic"
            case .deepSeek: return "DeepSeek"
            case .local: return "本地模型"
            }
        }

        var defaultModel: String {
            switch self {
            case .openAI:
                return "gpt-4"
            case .anthropic:
                return "claude-3-opus-20240229"
            case .deepSeek:
                return "deepseek-chat"
            case .local:
                return "local-model"
            }
        }

        var defaultBaseURL: String? {
            switch self {
            case .openAI:
                return "https://api.openai.com/v1"
            case .anthropic:
                return "https://api.anthropic.com/v1"
            case .deepSeek:
                return "https://api.deepseek.com/v1"
            case .local:
                return nil
            }
        }

        var apiKeyPlaceholder: String {
            switch self {
            case .openAI:
                return "sk-..."
            case .anthropic:
                return "sk-ant-..."
            case .deepSeek:
                return "sk-..."
            case .local:
                return "无需 API Key"
            }
        }
    }

    init(
        provider: AIProvider = .anthropic,
        apiKey: String = "",
        model: String? = nil,
        timeout: TimeInterval = 60.0
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.baseURL = provider.defaultBaseURL
        self.model = model ?? provider.defaultModel
        self.timeout = timeout
    }
}

// MARK: - Task Executor

@MainActor
class TaskExecutor {

    private let urlSession: URLSession
    private let apiConfig: APIConfiguration

    // 执行中的任务
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    init(apiConfig: APIConfiguration = APIConfiguration()) {
        self.apiConfig = apiConfig

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = apiConfig.timeout
        config.timeoutIntervalForResource = apiConfig.timeout * 2
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Execute Subtask

    func execute(
        subtask: SubTask,
        on device: ClusterDevice,
        mode: ExecutionMode
    ) async -> SubTaskResult {
        let startTime = Date()

        do {
            let result: SubTaskResult

            switch mode {
            case .api:
                result = try await executeViaAPI(subtask: subtask, device: device)
            case .claudeCode:
                result = try await executeViaClaudeCode(subtask: subtask, device: device)
            case .hybrid:
                // 智能选择：如果有 Claude Code 能力就用它，否则用 API
                if device.capabilities.contains(.claudeCode) {
                    result = try await executeViaClaudeCode(subtask: subtask, device: device)
                } else {
                    result = try await executeViaAPI(subtask: subtask, device: device)
                }
            }

            return result

        } catch {
            let executionTime = Date().timeIntervalSince(startTime)
            return SubTaskResult(
                success: false,
                output: "",
                error: error.localizedDescription,
                executionTime: executionTime,
                metadata: ["device": device.name]
            )
        }
    }

    // MARK: - API Mode Execution

    private func executeViaAPI(
        subtask: SubTask,
        device: ClusterDevice
    ) async throws -> SubTaskResult {
        let startTime = Date()

        // 构建提示词
        let prompt = buildPrompt(for: subtask, device: device)

        // 根据 provider 调用不同的 API
        let response: String
        switch apiConfig.provider {
        case .openAI:
            response = try await callOpenAI(prompt: prompt)
        case .anthropic:
            response = try await callAnthropic(prompt: prompt)
        case .deepSeek:
            response = try await callDeepSeek(prompt: prompt)
        case .local:
            response = try await callLocalAPI(prompt: prompt)
        }

        let executionTime = Date().timeIntervalSince(startTime)

        return SubTaskResult(
            success: true,
            output: response,
            error: nil,
            executionTime: executionTime,
            metadata: [
                "provider": apiConfig.provider.rawValue,
                "model": apiConfig.model,
                "device": device.name
            ]
        )
    }

    // MARK: - Claude Code Mode Execution

    private func executeViaClaudeCode(
        subtask: SubTask,
        device: ClusterDevice
    ) async throws -> SubTaskResult {
        let startTime = Date()

        // 构建 Bridge API URL
        let bridgeURL = URL(string: "http://\(device.host):\(device.port)/api/execute")!

        // 构建请求体
        let requestBody: [String: Any] = [
            "command": subtask.command ?? subtask.description,
            "context": [
                "task_id": subtask.id.uuidString,
                "device_name": device.name
            ]
        ]

        var request = URLRequest(url: bridgeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ExecutorError.executionFailed(
                device.id,
                "HTTP \(statusCode)"
            )
        }

        // 解析响应
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let output = json?["output"] as? String ?? ""
        let error = json?["error"] as? String

        let executionTime = Date().timeIntervalSince(startTime)

        return SubTaskResult(
            success: error == nil,
            output: output,
            error: error,
            executionTime: executionTime,
            metadata: [
                "mode": "claude_code",
                "device": device.name
            ]
        )
    }

    // MARK: - API Calls

    private func callOpenAI(prompt: String) async throws -> String {
        guard !apiConfig.apiKey.isEmpty else {
            throw ExecutorError.apiError("OpenAI API key not configured")
        }

        let url = URL(string: "\(apiConfig.baseURL ?? "")/chat/completions")!

        let requestBody: [String: Any] = [
            "model": apiConfig.model,
            "messages": [
                ["role": "system", "content": "You are a helpful assistant for server management."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 2000
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ExecutorError.apiError("OpenAI API error: \(errorText)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        return message?["content"] as? String ?? ""
    }

    private func callAnthropic(prompt: String) async throws -> String {
        guard !apiConfig.apiKey.isEmpty else {
            // 如果没有 API key，返回模拟响应
            return simulateAnthropicResponse(prompt: prompt)
        }

        let url = URL(string: "\(apiConfig.baseURL ?? "")/messages")!

        let requestBody: [String: Any] = [
            "model": apiConfig.model,
            "max_tokens": 2000,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiConfig.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ExecutorError.apiError("Anthropic API error: \(errorText)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? [[String: Any]]
        return content?.first?["text"] as? String ?? ""
    }

    private func callDeepSeek(prompt: String) async throws -> String {
        guard !apiConfig.apiKey.isEmpty else {
            throw ExecutorError.apiError("DeepSeek API key not configured")
        }

        // 使用正确的 baseURL，确保包含 /v1 路径
        let baseURL = apiConfig.baseURL ?? "https://api.deepseek.com/v1"
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw ExecutorError.apiError("Invalid DeepSeek API URL: \(baseURL)")
        }

        // 调试日志
        #if DEBUG
        print("[DeepSeek API] Request URL: \(url.absoluteString)")
        print("[DeepSeek API] Model: \(apiConfig.model)")
        #endif

        let requestBody: [String: Any] = [
            "model": apiConfig.model,
            "messages": [
                ["role": "system", "content": "You are a helpful assistant for server management and system administration."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 2000,
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExecutorError.apiError("DeepSeek API: Invalid response")
        }

        // 调试日志
        #if DEBUG
        print("[DeepSeek API] Response status: \(httpResponse.statusCode)")
        #endif

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ExecutorError.apiError("DeepSeek API error (HTTP \(httpResponse.statusCode)): \(errorText)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = message?["content"] as? String

        guard let result = content, !result.isEmpty else {
            throw ExecutorError.apiError("DeepSeek API: Empty response content")
        }

        return result
    }

    private func callLocalAPI(prompt: String) async throws -> String {
        // 本地 API 调用（例如通过 Ollama 等本地模型）
        let url = URL(string: "http://localhost:11434/api/generate")!

        let requestBody: [String: Any] = [
            "model": apiConfig.model,
            "prompt": prompt,
            "stream": false
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ExecutorError.apiError("Local API error")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["response"] as? String ?? ""
    }

    // MARK: - Simulation (for demo)

    private func simulateAnthropicResponse(prompt: String) -> String {
        // 模拟响应，用于演示
        return """
        我已收到您的请求。基于设备信息，执行结果如下：

        **执行摘要**
        - 任务类型：\(prompt.prefix(50))...
        - 状态：成功
        - 发现：系统运行正常，未发现异常

        **详细信息**
        由于这是模拟模式，实际执行需要通过配置真实的 API Key 来启用。
        请在设置中配置您的 Anthropic API Key。
        """
    }

    // MARK: - Prompt Building

    private func buildPrompt(for subtask: SubTask, device: ClusterDevice) -> String {
        return """
        请协助执行以下服务器管理任务：

        **设备信息**
        - 名称：\(device.name)
        - 地址：\(device.host):\(device.port)
        - 能力：\(device.capabilities.map { $0.rawValue }.joined(separator: ", "))

        **任务描述**
        \(subtask.description)

        **命令**
        \(subtask.command ?? "无具体命令")

        请提供详细的执行步骤和预期结果。
        """
    }

    // MARK: - Cancel Task

    func cancelTask(_ taskId: UUID) {
        activeTasks[taskId]?.cancel()
        activeTasks.removeValue(forKey: taskId)
    }

    func cancelAllTasks() {
        activeTasks.values.forEach { $0.cancel() }
        activeTasks.removeAll()
    }
}

// MARK: - Batch Execution Result

struct BatchExecutionResult {
    let taskId: UUID
    let subtaskResults: [UUID: SubTaskResult]
    let completedAt: Date
    let successCount: Int
    let failureCount: Int

    var isSuccessful: Bool {
        failureCount == 0
    }

    var summary: String {
        return "成功: \(successCount), 失败: \(failureCount)"
    }
}
import Foundation
import Combine

// MARK: - Master Agent Controller

@MainActor
class MasterAgentController: ObservableObject {

    // MARK: - Published Properties

    @Published var currentTask: AgentTask?
    @Published var isProcessing = false
    @Published var taskHistory: [TaskHistoryEntry] = []
    @Published var errorMessage: String?

    // MARK: - Components

    let parser = TaskParser()
    let scheduler = TaskScheduler()
    var executor: TaskExecutor

    // MARK: - State

    private var cancellables = Set<AnyCancellable>()
    private let persistence = DataPersistenceManager.shared

    // MARK: - Initialization

    init() {
        // 从 UserDefaults 加载 API 配置
        let providerString = UserDefaults.standard.string(forKey: "aiProvider") ?? "deepSeek"
        let apiKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
        let customBaseURL = UserDefaults.standard.string(forKey: "customBaseURL")

        let provider: APIConfiguration.AIProvider
        switch providerString {
        case "openAI":
            provider = .openAI
        case "anthropic":
            provider = .anthropic
        case "deepSeek":
            provider = .deepSeek
        default:
            provider = .local
        }

        let apiConfig = APIConfiguration(
            provider: provider,
            apiKey: apiKey,
            model: nil,
            timeout: 60.0
        )

        // 使用自定义 base URL（如果设置了）
        var finalConfig = apiConfig
        if let customURL = customBaseURL, !customURL.isEmpty {
            finalConfig.baseURL = customURL
        }

        self.executor = TaskExecutor(apiConfig: finalConfig)
        loadHistory()
    }

    // 重新加载 API 配置（当设置改变时调用）
    func reloadAPIConfig() {
        let providerString = UserDefaults.standard.string(forKey: "aiProvider") ?? "deepSeek"
        let apiKey = UserDefaults.standard.string(forKey: "apiKey") ?? ""
        let customBaseURL = UserDefaults.standard.string(forKey: "customBaseURL")

        let provider: APIConfiguration.AIProvider
        switch providerString {
        case "openAI":
            provider = .openAI
        case "anthropic":
            provider = .anthropic
        case "deepSeek":
            provider = .deepSeek
        default:
            provider = .local
        }

        let apiConfig = APIConfiguration(
            provider: provider,
            apiKey: apiKey,
            model: nil,
            timeout: 60.0
        )

        // 更新 executor 的 API 配置
        var finalConfig = apiConfig
        if let customURL = customBaseURL, !customURL.isEmpty {
            finalConfig.baseURL = customURL
        }
        self.executor = TaskExecutor(apiConfig: finalConfig)

        #if DEBUG
        print("[MasterAgent] API config reloaded: provider=\(provider), baseURL=\(finalConfig.baseURL ?? "default")")
        #endif
    }

    // MARK: - Main Entry Point

    /// 处理自然语言输入
    func process(
        _ naturalLanguageInput: String,
        on devices: [ClusterDevice],
        mode: ExecutionMode = .hybrid
    ) async {
        guard !isProcessing else {
            errorMessage = "已有任务正在执行"
            return
        }

        isProcessing = true
        errorMessage = nil

        // 1. 创建任务
        var task = AgentTask(
            naturalLanguageInput: naturalLanguageInput,
            executionMode: mode
        )
        currentTask = task

        do {
            // 2. 解析意图
            task.status = .parsing
            currentTask = task

            let intent = try await parser.parse(naturalLanguageInput)
            task.parsedIntent = intent
            task.type = parser.generateTaskType(from: intent)

            // 3. 创建执行计划
            task.status = .planning
            currentTask = task

            let plan = try await scheduler.createPlan(
                from: intent,
                availableDevices: devices.filter { $0.status == .online }
            )
            task.executionPlan = plan

            // 4. 执行计划
            task.status = .executing
            task.startedAt = Date()
            currentTask = task

            let results = try await executePlan(plan, on: devices, mode: mode)

            // 5. 汇总结果
            task.results = results
            task.finalOutput = synthesizeResults(results, for: task)
            task.status = .completed
            task.completedAt = Date()

            // 6. 保存历史
            saveToHistory(task)

        } catch let error as TaskParserError {
            task.status = .failed
            task.error = error.localizedDescription
            errorMessage = error.localizedDescription
        } catch let error as SchedulerError {
            task.status = .failed
            task.error = error.localizedDescription
            errorMessage = error.localizedDescription
        } catch {
            task.status = .failed
            task.error = error.localizedDescription
            errorMessage = "执行失败: \(error.localizedDescription)"
        }

        currentTask = task
        isProcessing = false
    }

    // MARK: - Execute Plan

    private func executePlan(
        _ plan: TaskPlan,
        on devices: [ClusterDevice],
        mode: ExecutionMode
    ) async throws -> [UUID: SubTaskResult] {

        var results: [UUID: SubTaskResult] = [:]
        let deviceMap = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })

        // 根据策略执行
        switch plan.executionStrategy {
        case .sequential:
            // 顺序执行
            for subtask in plan.subtasks {
                guard let deviceId = subtask.targetDeviceId,
                      let device = deviceMap[deviceId] else {
                    continue
                }

                let result = await executor.execute(subtask: subtask, on: device, mode: mode)
                results[subtask.id] = result
            }

        case .parallel:
            // 并行执行
            await withTaskGroup(of: (UUID, SubTaskResult).self) { group in
                for subtask in plan.subtasks {
                    guard let deviceId = subtask.targetDeviceId,
                          let device = deviceMap[deviceId] else {
                        continue
                    }

                    group.addTask {
                        let result = await self.executor.execute(
                            subtask: subtask,
                            on: device,
                            mode: mode
                        )
                        return (subtask.id, result)
                    }
                }

                for await (subtaskId, result) in group {
                    results[subtaskId] = result
                }
            }

        case .mixed:
            // 混合策略：先处理有依赖的，再并行执行独立的
            results = try await executeMixedStrategy(
                plan: plan,
                deviceMap: deviceMap,
                mode: mode
            )
        }

        return results
    }

    private func executeMixedStrategy(
        plan: TaskPlan,
        deviceMap: [UUID: ClusterDevice],
        mode: ExecutionMode
    ) async throws -> [UUID: SubTaskResult] {

        var results: [UUID: SubTaskResult] = [:]
        var completedSubtasks: Set<UUID> = []
        var remainingSubtasks = plan.subtasks

        while !remainingSubtasks.isEmpty {
            // 找出可以执行的子任务（依赖已满足）
            let readySubtasks = remainingSubtasks.filter { subtask in
                subtask.dependencies.allSatisfy { completedSubtasks.contains($0) }
            }

            guard !readySubtasks.isEmpty else {
                throw SchedulerError.circularDependency
            }

            // 并行执行就绪的子任务
            await withTaskGroup(of: (UUID, SubTaskResult).self) { group in
                for subtask in readySubtasks {
                    guard let deviceId = subtask.targetDeviceId,
                          let device = deviceMap[deviceId] else {
                        continue
                    }

                    group.addTask {
                        let result = await self.executor.execute(
                            subtask: subtask,
                            on: device,
                            mode: mode
                        )
                        return (subtask.id, result)
                    }
                }

                for await (subtaskId, result) in group {
                    results[subtaskId] = result
                    completedSubtasks.insert(subtaskId)
                }
            }

            // 移除已完成的子任务
            remainingSubtasks.removeAll { completedSubtasks.contains($0.id) }
        }

        return results
    }

    // MARK: - Result Synthesis

    private func synthesizeResults(
        _ results: [UUID: SubTaskResult],
        for task: AgentTask
    ) -> String {
        var output = "## 任务执行结果\n\n"

        output += "**任务**: \(task.naturalLanguageInput)\n"
        output += "**类型**: \(task.type.rawValue)\n"
        output += "**时间**: \(formatDate(task.completedAt ?? Date()))\n\n"

        output += "---\n\n"

        // 统计
        let successCount = results.values.filter { $0.success }.count
        let totalCount = results.count
        output += "**完成度**: \(successCount)/\(totalCount) 成功\n\n"

        // 详细结果
        for (subtaskId, result) in results {
            output += "### 子任务 \(subtaskId.uuidString.prefix(8))\n"
            output += "- 状态: \(result.success ? "✅ 成功" : "❌ 失败")\n"
            output += "- 耗时: \(String(format: "%.2f", result.executionTime))s\n"

            if !result.output.isEmpty {
                output += "\n**输出**:\n```\n\(result.output)\n```\n"
            }

            if let error = result.error {
                output += "\n**错误**: \(error)\n"
            }

            output += "\n"
        }

        return output
    }

    // MARK: - History Management

    private func saveToHistory(_ task: AgentTask) {
        let entry = TaskHistoryEntry(
            id: UUID(),
            taskId: task.id,
            input: task.naturalLanguageInput,
            type: task.type,
            status: task.status,
            createdAt: task.createdAt,
            completedAt: task.completedAt,
            deviceCount: task.executionPlan?.subtasks.count ?? 0,
            summary: task.finalOutput?.prefix(200).description
        )

        taskHistory.insert(entry, at: 0)

        // 限制历史记录数量
        if taskHistory.count > 100 {
            taskHistory = Array(taskHistory.prefix(100))
        }

        // 持久化
        persistence.saveTaskHistory(taskHistory)
    }

    private func loadHistory() {
        taskHistory = persistence.loadTaskHistory()
    }

    func clearHistory() {
        taskHistory.removeAll()
        persistence.clearTaskHistory()
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Cancel

    func cancelCurrentTask() {
        executor.cancelAllTasks()
        if var task = currentTask {
            task.status = .cancelled
            currentTask = task
        }
        isProcessing = false
    }
}

// MARK: - Data Persistence Extension

extension DataPersistenceManager {

    func saveTaskHistory(_ history: [TaskHistoryEntry]) {
        do {
            let data = try JSONEncoder().encode(history)
            UserDefaults.standard.set(data, forKey: "task_history")
        } catch {
            print("Failed to save task history: \(error)")
        }
    }

    func loadTaskHistory() -> [TaskHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: "task_history") else {
            return []
        }

        do {
            return try JSONDecoder().decode([TaskHistoryEntry].self, from: data)
        } catch {
            print("Failed to load task history: \(error)")
            return []
        }
    }

    func clearTaskHistory() {
        UserDefaults.standard.removeObject(forKey: "task_history")
    }
}
