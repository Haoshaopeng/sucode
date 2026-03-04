import Foundation
import SwiftUI

// MARK: - System Info

struct SystemInfo: Codable, Equatable {
    let hostname: String
    let platform: String
    let version: String
    let cpuCount: Int
    let memoryGB: Double
    let pythonVersion: String
}

// MARK: - Cluster Command

struct ClusterCommand: Identifiable, Codable {
    let id: UUID
    let command: String
    let targetDevices: [UUID]
    let timestamp: Date
    var results: [UUID: CommandResult]

    init(id: UUID = UUID(), command: String, targetDevices: [UUID] = [], timestamp: Date = Date(), results: [UUID: CommandResult] = [:]) {
        self.id = id
        self.command = command
        self.targetDevices = targetDevices
        self.timestamp = timestamp
        self.results = results
    }
}

// MARK: - Command Result

struct CommandResult: Codable {
    let deviceId: UUID
    let success: Bool
    let output: String
    let error: String?
    let executionTime: TimeInterval
    let timestamp: Date

    init(deviceId: UUID, success: Bool, output: String, error: String? = nil, executionTime: TimeInterval = 0, timestamp: Date = Date()) {
        self.deviceId = deviceId
        self.success = success
        self.output = output
        self.error = error
        self.executionTime = executionTime
        self.timestamp = timestamp
    }
}

// MARK: - Cluster Session

struct ClusterSession: Identifiable, Codable {
    let id: UUID
    let name: String
    let createdAt: Date
    var devices: [ClusterDevice]
    var commandHistory: [ClusterCommand]
    var isActive: Bool
}

// MARK: - Device Group Model

struct DeviceGroupInfo: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var iconName: String
    var colorHex: String
    var sortOrder: Int
    var deviceCount: Int

    init(id: UUID = UUID(), name: String, iconName: String = "folder", colorHex: String = "007AFF", sortOrder: Int = 0, deviceCount: Int = 0) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.deviceCount = deviceCount
    }

    var displayColor: Color {
        Color(hex: colorHex)
    }
}

// MARK: - Preset Device Groups

extension DeviceGroupInfo {
    static let presets: [DeviceGroupInfo] = [
        DeviceGroupInfo(name: "工作", iconName: "briefcase", colorHex: "007AFF"),
        DeviceGroupInfo(name: "个人", iconName: "person", colorHex: "34C759"),
        DeviceGroupInfo(name: "云端", iconName: "cloud", colorHex: "FF9500"),
        DeviceGroupInfo(name: "测试", iconName: "hammer", colorHex: "AF52DE")
    ]
}

// MARK: - Device Icon Presets

struct DeviceIconPreset {
    let name: String
    let icon: String
    let color: String

    static let presets: [DeviceIconPreset] = [
        DeviceIconPreset(name: "服务器", icon: "server.rack", color: "007AFF"),
        DeviceIconPreset(name: "桌面", icon: "desktopcomputer", color: "5856D6"),
        DeviceIconPreset(name: "笔记本", icon: "laptopcomputer", color: "5AC8FA"),
        DeviceIconPreset(name: "云端", icon: "cloud", color: "FF9500"),
        DeviceIconPreset(name: "数据库", icon: "cylinder", color: "34C759"),
        DeviceIconPreset(name: "终端", icon: "terminal", color: "FF3B30"),
        DeviceIconPreset(name: "开发", icon: "hammer", color: "AF52DE"),
        DeviceIconPreset(name: "生产", icon: "bolt", color: "FFCC00"),
        DeviceIconPreset(name: "监控", icon: "eye", color: "64D2FF"),
        DeviceIconPreset(name: "安全", icon: "lock.shield", color: "8E8E93")
    ]
}
import Foundation

// MARK: - 任务类型

enum TaskType: String, Codable, CaseIterable {
    case analysis = "分析"
    case execution = "执行"
    case monitoring = "监控"
    case fileOperation = "文件操作"
    case systemInfo = "系统信息"
    case custom = "自定义"

    var icon: String {
        switch self {
        case .analysis: return "chart.bar"
        case .execution: return "play.circle"
        case .monitoring: return "eye"
        case .fileOperation: return "folder"
        case .systemInfo: return "info.circle"
        case .custom: return "command"
        }
    }
}

// MARK: - 任务状态

enum TaskStatus: String, Codable {
    case pending = "待处理"
    case parsing = "解析中"
    case planning = "规划中"
    case dispatching = "分发中"
    case executing = "执行中"
    case completed = "已完成"
    case failed = "失败"
    case cancelled = "已取消"

    var color: String {
        switch self {
        case .pending: return "gray"
        case .parsing, .planning, .dispatching: return "orange"
        case .executing: return "blue"
        case .completed: return "green"
        case .failed: return "red"
        case .cancelled: return "gray"
        }
    }
}

// MARK: - 执行模式

enum ExecutionMode: String, Codable, CaseIterable {
    case api = "API模式"
    case claudeCode = "Claude Code模式"
    case hybrid = "混合模式"

    var displayName: String {
        switch self {
        case .api:
            return "API 模式"
        case .claudeCode:
            return "Claude Code"
        case .hybrid:
            return "混合模式"
        }
    }

    var description: String {
        switch self {
        case .api:
            return "使用 OpenAI/Claude/DeepSeek API 直接处理"
        case .claudeCode:
            return "通过本地 Claude Code Bridge 执行"
        case .hybrid:
            return "自动选择最优执行方式"
        }
    }

    var icon: String {
        switch self {
        case .api:
            return "cloud.fill"
        case .claudeCode:
            return "terminal.fill"
        case .hybrid:
            return "arrow.triangle.branch"
        }
    }
}

// MARK: - 子任务

struct SubTask: Identifiable, Codable {
    let id: UUID
    let description: String
    let targetDeviceId: UUID?
    let command: String?
    let dependencies: [UUID]
    var status: TaskStatus
    var result: SubTaskResult?
    let estimatedDuration: TimeInterval?
    var startedAt: Date?
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        description: String,
        targetDeviceId: UUID? = nil,
        command: String? = nil,
        dependencies: [UUID] = [],
        status: TaskStatus = .pending,
        estimatedDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.description = description
        self.targetDeviceId = targetDeviceId
        self.command = command
        self.dependencies = dependencies
        self.status = status
        self.estimatedDuration = estimatedDuration
    }
}

// MARK: - 子任务结果

struct SubTaskResult: Codable {
    let success: Bool
    let output: String
    let error: String?
    let executionTime: TimeInterval
    let metadata: [String: String]?
}

// MARK: - 主任务

struct AgentTask: Identifiable, Codable {
    let id: UUID
    let naturalLanguageInput: String
    var type: TaskType
    var status: TaskStatus
    let createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    let executionMode: ExecutionMode

    // 解析结果
    var parsedIntent: TaskIntent?
    var executionPlan: TaskPlan?

    // 执行结果
    var results: [UUID: SubTaskResult]
    var finalOutput: String?
    var error: String?

    init(
        id: UUID = UUID(),
        naturalLanguageInput: String,
        type: TaskType = .custom,
        executionMode: ExecutionMode = .hybrid
    ) {
        self.id = id
        self.naturalLanguageInput = naturalLanguageInput
        self.type = type
        self.status = .pending
        self.createdAt = Date()
        self.executionMode = executionMode
        self.results = [:]
    }
}

// MARK: - 任务意图

struct TaskIntent: Codable {
    let action: String
    let targets: [String]
    let constraints: [String]
    let parameters: [String: String]
    let confidence: Double
}

// MARK: - 执行计划

struct TaskPlan: Codable {
    let subtasks: [SubTask]
    let executionStrategy: ExecutionStrategy
    let estimatedTotalDuration: TimeInterval
}

// MARK: - 执行策略

enum ExecutionStrategy: String, Codable {
    case sequential = "顺序执行"
    case parallel = "并行执行"
    case mixed = "混合执行"
}

// MARK: - 设备能力匹配

struct DeviceCapabilityMatch: Codable {
    let deviceId: UUID
    let score: Double
    let matchedCapabilities: [String]
    let estimatedLoad: Double
}

// MARK: - Agent 执行结果

struct AgentExecutionResult: Codable {
    let taskId: UUID
    let success: Bool
    let output: String
    let subtaskResults: [UUID: SubTaskResult]
    let executionTime: TimeInterval
    let tokensUsed: Int?
    let cost: Double?
}

// MARK: - 任务历史记录

struct TaskHistoryEntry: Identifiable, Codable {
    let id: UUID
    let taskId: UUID
    let input: String
    let type: TaskType
    let status: TaskStatus
    let createdAt: Date
    let completedAt: Date?
    let deviceCount: Int
    let summary: String?
}
