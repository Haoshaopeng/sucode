import Foundation
import SwiftData
import SwiftUI

// MARK: - SwiftData Models (iOS 17+)
// 这些模型使用 SwiftData 进行持久化，提供更强大的查询和数据管理功能

/// 持久化设备模型
@Model
class PersistedDevice {
    @Attribute(.unique) var id: UUID
    var name: String
    var host: String
    var port: Int
    var status: String
    var mode: String
    var lastConnected: Date?
    var capabilities: [String]
    var deviceDescription: String?
    var groupId: UUID?
    var iconName: String
    var colorHex: String
    var sortOrder: Int
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 8765,
        status: String = "disconnected",
        mode: String = "shared",
        lastConnected: Date? = nil,
        capabilities: [String] = ["terminal"],
        deviceDescription: String? = nil,
        groupId: UUID? = nil,
        iconName: String = "server.rack",
        colorHex: String = "007AFF",
        sortOrder: Int = 0,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.status = status
        self.mode = mode
        self.lastConnected = lastConnected
        self.capabilities = capabilities
        self.deviceDescription = deviceDescription
        self.groupId = groupId
        self.iconName = iconName
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.isFavorite = isFavorite
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// 转换为 ClusterDevice
    func toClusterDevice() -> ClusterDevice {
        return ClusterDevice(
            id: id,
            name: name,
            host: host,
            port: port,
            status: DeviceStatus(rawValue: status) ?? .offline,
            mode: ConnectionMode(rawValue: mode) ?? .shared,
            lastSeen: lastConnected,
            capabilities: capabilities.compactMap { DeviceCapability(rawValue: $0) },
            description: deviceDescription
        )
    }

    /// 从 ClusterDevice 更新
    func update(from device: ClusterDevice) {
        self.name = device.name
        self.host = device.host
        self.port = device.port
        self.status = device.status.rawValue
        self.mode = device.mode.rawValue
        self.lastConnected = device.lastSeen
        self.updatedAt = Date()
    }
}

/// 设备分组模型
@Model
class DeviceGroup {
    @Attribute(.unique) var id: UUID
    var name: String
    var iconName: String
    var colorHex: String
    var sortOrder: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        iconName: String = "folder",
        colorHex: String = "007AFF",
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
}

/// 命令历史模型
@Model
class CommandHistory {
    @Attribute(.unique) var id: UUID
    var deviceId: UUID?
    var command: String
    var timestamp: Date
    var isFavorite: Bool
    var executionTime: TimeInterval?
    var exitCode: Int?
    var outputPreview: String?
    var useCount: Int
    var lastUsed: Date

    init(
        id: UUID = UUID(),
        deviceId: UUID? = nil,
        command: String,
        timestamp: Date = Date(),
        isFavorite: Bool = false,
        executionTime: TimeInterval? = nil,
        exitCode: Int? = nil,
        outputPreview: String? = nil
    ) {
        self.id = id
        self.deviceId = deviceId
        self.command = command
        self.timestamp = timestamp
        self.isFavorite = isFavorite
        self.executionTime = executionTime
        self.exitCode = exitCode
        self.outputPreview = outputPreview
        self.useCount = 1
        self.lastUsed = Date()
    }

    /// 标记为已使用
    func markUsed() {
        self.useCount += 1
        self.lastUsed = Date()
    }
}

/// 批量命令会话模型
@Model
class BatchCommandSession {
    @Attribute(.unique) var id: UUID
    var name: String
    var command: String
    var targetDeviceIds: [UUID]
    var createdAt: Date
    var isCompleted: Bool
    var completedDeviceIds: [UUID]
    var results: [BatchCommandResult]

    init(
        id: UUID = UUID(),
        name: String,
        command: String,
        targetDeviceIds: [UUID],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.targetDeviceIds = targetDeviceIds
        self.createdAt = createdAt
        self.isCompleted = false
        self.completedDeviceIds = []
        self.results = []
    }
}

/// 批量命令结果嵌入模型
struct BatchCommandResult: Codable {
    let deviceId: UUID
    let success: Bool
    let output: String
    let error: String?
    let executionTime: TimeInterval
    let timestamp: Date
}

/// 应用状态模型（用于会话恢复）
@Model
class AppSessionState {
    @Attribute(.unique) var id: UUID
    var selectedTab: Int
    var selectedDeviceId: UUID?
    var lastActiveBatchSessionId: UUID?
    var lastActiveAt: Date

    init(
        id: UUID = UUID(),
        selectedTab: Int = 0,
        selectedDeviceId: UUID? = nil,
        lastActiveBatchSessionId: UUID? = nil
    ) {
        self.id = id
        self.selectedTab = selectedTab
        self.selectedDeviceId = selectedDeviceId
        self.lastActiveBatchSessionId = lastActiveBatchSessionId
        self.lastActiveAt = Date()
    }
}

// MARK: - Persistence Manager

/// 数据持久化管理器
@MainActor
class PersistenceManager: ObservableObject {
    static let shared = PersistenceManager()

    let container: ModelContainer

    @Published private(set) var isInitialized = false

    private init() {
        let schema = Schema([
            PersistedDevice.self,
            DeviceGroup.self,
            CommandHistory.self,
            BatchCommandSession.self,
            AppSessionState.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            isInitialized = true
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    // MARK: - Context Helper

    private var context: ModelContext {
        container.mainContext
    }

    // MARK: - Device Operations

    /// 保存设备
    func saveDevice(_ device: ClusterDevice, groupId: UUID? = nil, iconName: String = "server.rack", colorHex: String = "007AFF") async throws {
        let descriptor = FetchDescriptor<PersistedDevice>(
            predicate: #Predicate { $0.id == device.id }
        )

        if let existing = try context.fetch(descriptor).first {
            existing.update(from: device)
        } else {
            let persisted = PersistedDevice(
                id: device.id,
                name: device.name,
                host: device.host,
                port: device.port,
                status: device.status.rawValue,
                mode: device.mode.rawValue,
                lastConnected: device.lastSeen,
                groupId: groupId,
                iconName: iconName,
                colorHex: colorHex
            )
            context.insert(persisted)
        }

        try context.save()
    }

    /// 获取所有设备
    func fetchAllDevices() async throws -> [PersistedDevice] {
        let descriptor = FetchDescriptor<PersistedDevice>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    /// 获取设备通过ID
    func fetchDevice(id: UUID) async throws -> PersistedDevice? {
        let descriptor = FetchDescriptor<PersistedDevice>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    /// 删除设备
    func deleteDevice(id: UUID) async throws {
        let descriptor = FetchDescriptor<PersistedDevice>(
            predicate: #Predicate { $0.id == id }
        )

        if let device = try context.fetch(descriptor).first {
            context.delete(device)
            try context.save()
        }
    }

    /// 更新设备状态
    func updateDeviceStatus(id: UUID, status: DeviceStatus) async throws {
        let descriptor = FetchDescriptor<PersistedDevice>(
            predicate: #Predicate { $0.id == id }
        )

        if let device = try context.fetch(descriptor).first {
            device.status = status.rawValue
            if status == .online {
                device.lastConnected = Date()
            }
            device.updatedAt = Date()
            try context.save()
        }
    }

    /// 切换设备收藏状态
    func toggleDeviceFavorite(id: UUID) async throws -> Bool {
        let descriptor = FetchDescriptor<PersistedDevice>(
            predicate: #Predicate { $0.id == id }
        )

        if let device = try context.fetch(descriptor).first {
            device.isFavorite.toggle()
            try context.save()
            return device.isFavorite
        }
        return false
    }

    // MARK: - Group Operations

    /// 创建分组
    func createGroup(name: String, iconName: String = "folder", colorHex: String = "007AFF") async throws -> DeviceGroup {
        let group = DeviceGroup(name: name, iconName: iconName, colorHex: colorHex)
        context.insert(group)
        try context.save()
        return group
    }

    /// 获取所有分组
    func fetchAllGroups() async throws -> [DeviceGroup] {
        let descriptor = FetchDescriptor<DeviceGroup>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    /// 删除分组
    func deleteGroup(id: UUID) async throws {
        let descriptor = FetchDescriptor<DeviceGroup>(
            predicate: #Predicate { $0.id == id }
        )

        if let group = try context.fetch(descriptor).first {
            // 将组内设备移到未分组
            let deviceDescriptor = FetchDescriptor<PersistedDevice>(
                predicate: #Predicate { $0.groupId == id }
            )
            let devices = try context.fetch(deviceDescriptor)
            devices.forEach { $0.groupId = nil }

            context.delete(group)
            try context.save()
        }
    }

    /// 获取分组内的设备
    func fetchDevicesInGroup(groupId: UUID) async throws -> [PersistedDevice] {
        let descriptor = FetchDescriptor<PersistedDevice>(
            predicate: #Predicate { $0.groupId == groupId },
            sortBy: [SortDescriptor(\.name)]
        )
        return try context.fetch(descriptor)
    }

    /// 移动设备到分组
    func moveDeviceToGroup(deviceId: UUID, groupId: UUID?) async throws {
        let descriptor = FetchDescriptor<PersistedDevice>(
            predicate: #Predicate { $0.id == deviceId }
        )

        if let device = try context.fetch(descriptor).first {
            device.groupId = groupId
            try context.save()
        }
    }

    // MARK: - Command History Operations

    /// 保存命令历史
    func saveCommandHistory(deviceId: UUID? = nil, command: String, executionTime: TimeInterval? = nil, exitCode: Int? = nil, outputPreview: String? = nil) async throws {
        // 检查是否已存在相同命令
        let descriptor = FetchDescriptor<CommandHistory>(
            predicate: #Predicate { $0.command == command }
        )

        if let existing = try context.fetch(descriptor).first {
            existing.markUsed()
            existing.timestamp = Date()
            if let deviceId = deviceId {
                existing.deviceId = deviceId
            }
        } else {
            let history = CommandHistory(
                deviceId: deviceId,
                command: command,
                executionTime: executionTime,
                exitCode: exitCode,
                outputPreview: outputPreview
            )
            context.insert(history)
        }

        // 限制历史记录数量
        try await trimCommandHistory()
        try context.save()
    }

    /// 获取命令历史
    func fetchCommandHistory(deviceId: UUID? = nil, limit: Int = 100) async throws -> [CommandHistory] {
        var descriptor: FetchDescriptor<CommandHistory>

        if let deviceId = deviceId {
            descriptor = FetchDescriptor<CommandHistory>(
                predicate: #Predicate { $0.deviceId == deviceId },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<CommandHistory>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        }

        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    /// 获取收藏的命令
    func fetchFavoriteCommands() async throws -> [CommandHistory] {
        let descriptor = FetchDescriptor<CommandHistory>(
            predicate: #Predicate { $0.isFavorite == true },
            sortBy: [SortDescriptor(\.lastUsed, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// 切换命令收藏状态
    func toggleCommandFavorite(id: UUID) async throws -> Bool {
        let descriptor = FetchDescriptor<CommandHistory>(
            predicate: #Predicate { $0.id == id }
        )

        if let command = try context.fetch(descriptor).first {
            command.isFavorite.toggle()
            try context.save()
            return command.isFavorite
        }
        return false
    }

    /// 删除命令历史
    func deleteCommandHistory(id: UUID) async throws {
        let descriptor = FetchDescriptor<CommandHistory>(
            predicate: #Predicate { $0.id == id }
        )

        if let command = try context.fetch(descriptor).first {
            context.delete(command)
            try context.save()
        }
    }

    /// 清理命令历史（保留最近100条）
    private func trimCommandHistory() async throws {
        let descriptor = FetchDescriptor<CommandHistory>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        let allCommands = try context.fetch(descriptor)
        if allCommands.count > 100 {
            let toDelete = allCommands.suffix(from: 100)
            toDelete.forEach { command in
                if !command.isFavorite {
                    context.delete(command)
                }
            }
        }
    }

    /// 搜索命令历史
    func searchCommandHistory(query: String) async throws -> [CommandHistory] {
        let descriptor = FetchDescriptor<CommandHistory>(
            predicate: #Predicate { $0.command.contains(query) },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Batch Command Operations

    /// 创建批量命令会话
    func createBatchSession(name: String, command: String, targetDeviceIds: [UUID]) async throws -> BatchCommandSession {
        let session = BatchCommandSession(
            name: name,
            command: command,
            targetDeviceIds: targetDeviceIds
        )
        context.insert(session)
        try context.save()
        return session
    }

    /// 获取未完成的批量命令
    func fetchIncompleteBatchSessions() async throws -> [BatchCommandSession] {
        let descriptor = FetchDescriptor<BatchCommandSession>(
            predicate: #Predicate { $0.isCompleted == false },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// 更新批量命令结果
    func updateBatchSessionResult(sessionId: UUID, deviceId: UUID, success: Bool, output: String, error: String?, executionTime: TimeInterval) async throws {
        let descriptor = FetchDescriptor<BatchCommandSession>(
            predicate: #Predicate { $0.id == sessionId }
        )

        if let session = try context.fetch(descriptor).first {
            let result = BatchCommandResult(
                deviceId: deviceId,
                success: success,
                output: output,
                error: error,
                executionTime: executionTime,
                timestamp: Date()
            )
            session.results.append(result)
            session.completedDeviceIds.append(deviceId)

            if session.completedDeviceIds.count >= session.targetDeviceIds.count {
                session.isCompleted = true
            }

            try context.save()
        }
    }

    /// 删除批量命令会话
    func deleteBatchSession(id: UUID) async throws {
        let descriptor = FetchDescriptor<BatchCommandSession>(
            predicate: #Predicate { $0.id == id }
        )

        if let session = try context.fetch(descriptor).first {
            context.delete(session)
            try context.save()
        }
    }

    // MARK: - Session State Operations

    /// 保存应用会话状态
    func saveSessionState(selectedTab: Int, selectedDeviceId: UUID?, lastActiveBatchSessionId: UUID? = nil) async throws {
        let descriptor = FetchDescriptor<AppSessionState>()

        if let state = try context.fetch(descriptor).first {
            state.selectedTab = selectedTab
            state.selectedDeviceId = selectedDeviceId
            state.lastActiveBatchSessionId = lastActiveBatchSessionId
            state.lastActiveAt = Date()
        } else {
            let state = AppSessionState(
                selectedTab: selectedTab,
                selectedDeviceId: selectedDeviceId,
                lastActiveBatchSessionId: lastActiveBatchSessionId
            )
            context.insert(state)
        }

        try context.save()
    }

    /// 加载应用会话状态
    func loadSessionState() async throws -> AppSessionState? {
        let descriptor = FetchDescriptor<AppSessionState>()
        return try context.fetch(descriptor).first
    }

    // MARK: - Data Migration

    /// 从旧版本迁移数据（从 UserDefaults）
    func migrateFromUserDefaults() async throws {
        let defaults = UserDefaults.standard

        // 迁移默认设备
        if let devicesData = defaults.data(forKey: "savedDevices"),
           let devices = try? JSONDecoder().decode([ClusterDevice].self, from: devicesData) {
            for device in devices {
                try await saveDevice(device)
            }
            defaults.removeObject(forKey: "savedDevices")
        }

        // 迁移命令历史
        if let commandsData = defaults.data(forKey: "commandHistory"),
           let commands = try? JSONDecoder().decode([String].self, from: commandsData) {
            for command in commands {
                try await saveCommandHistory(command: command)
            }
            defaults.removeObject(forKey: "commandHistory")
        }
    }

    /// 导出数据
    func exportData() async throws -> Data {
        let devices = try await fetchAllDevices()
        let groups = try await fetchAllGroups()
        let commands = try await fetchCommandHistory(limit: 1000)

        let export = DataExport(
            devices: devices.map { ExportDevice(from: $0) },
            groups: groups.map { ExportGroup(from: $0) },
            commands: commands.map { ExportCommand(from: $0) },
            exportDate: Date()
        )

        return try JSONEncoder().encode(export)
    }

    /// 导入数据
    func importData(_ data: Data) async throws {
        let export = try JSONDecoder().decode(DataExport.self, from: data)

        // 导入分组
        for groupExport in export.groups {
            let group = DeviceGroup(
                id: groupExport.id,
                name: groupExport.name,
                iconName: groupExport.iconName,
                colorHex: groupExport.colorHex,
                sortOrder: groupExport.sortOrder
            )
            context.insert(group)
        }

        // 导入设备
        for deviceExport in export.devices {
            let device = PersistedDevice(
                id: deviceExport.id,
                name: deviceExport.name,
                host: deviceExport.host,
                port: deviceExport.port,
                status: deviceExport.status,
                mode: deviceExport.mode,
                lastConnected: deviceExport.lastConnected,
                capabilities: deviceExport.capabilities,
                deviceDescription: deviceExport.deviceDescription,
                groupId: deviceExport.groupId,
                iconName: deviceExport.iconName,
                colorHex: deviceExport.colorHex,
                sortOrder: deviceExport.sortOrder,
                isFavorite: deviceExport.isFavorite
            )
            context.insert(device)
        }

        // 导入命令
        for commandExport in export.commands {
            let command = CommandHistory(
                id: commandExport.id,
                deviceId: commandExport.deviceId,
                command: commandExport.command,
                timestamp: commandExport.timestamp,
                isFavorite: commandExport.isFavorite,
                executionTime: commandExport.executionTime,
                exitCode: commandExport.exitCode,
                outputPreview: commandExport.outputPreview
            )
            command.useCount = commandExport.useCount
            command.lastUsed = commandExport.lastUsed
            context.insert(command)
        }

        try context.save()
    }

    /// 清除所有数据
    func clearAllData() async throws {
        try context.delete(model: PersistedDevice.self)
        try context.delete(model: DeviceGroup.self)
        try context.delete(model: CommandHistory.self)
        try context.delete(model: BatchCommandSession.self)
        try context.delete(model: AppSessionState.self)
        try context.save()
    }
}

// MARK: - Export/Import Models

struct DataExport: Codable {
    let devices: [ExportDevice]
    let groups: [ExportGroup]
    let commands: [ExportCommand]
    let exportDate: Date
}

struct ExportDevice: Codable {
    let id: UUID
    let name: String
    let host: String
    let port: Int
    let status: String
    let mode: String
    let lastConnected: Date?
    let capabilities: [String]
    let deviceDescription: String?
    let groupId: UUID?
    let iconName: String
    let colorHex: String
    let sortOrder: Int
    let isFavorite: Bool

    init(from device: PersistedDevice) {
        self.id = device.id
        self.name = device.name
        self.host = device.host
        self.port = device.port
        self.status = device.status
        self.mode = device.mode
        self.lastConnected = device.lastConnected
        self.capabilities = device.capabilities
        self.deviceDescription = device.deviceDescription
        self.groupId = device.groupId
        self.iconName = device.iconName
        self.colorHex = device.colorHex
        self.sortOrder = device.sortOrder
        self.isFavorite = device.isFavorite
    }
}

struct ExportGroup: Codable {
    let id: UUID
    let name: String
    let iconName: String
    let colorHex: String
    let sortOrder: Int

    init(from group: DeviceGroup) {
        self.id = group.id
        self.name = group.name
        self.iconName = group.iconName
        self.colorHex = group.colorHex
        self.sortOrder = group.sortOrder
    }
}

struct ExportCommand: Codable {
    let id: UUID
    let deviceId: UUID?
    let command: String
    let timestamp: Date
    let isFavorite: Bool
    let executionTime: TimeInterval?
    let exitCode: Int?
    let outputPreview: String?
    let useCount: Int
    let lastUsed: Date

    init(from command: CommandHistory) {
        self.id = command.id
        self.deviceId = command.deviceId
        self.command = command.command
        self.timestamp = command.timestamp
        self.isFavorite = command.isFavorite
        self.executionTime = command.executionTime
        self.exitCode = command.exitCode
        self.outputPreview = command.outputPreview
        self.useCount = command.useCount
        self.lastUsed = command.lastUsed
    }
}

// MARK: - Color Helper

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    func toHex() -> String {
        #if canImport(UIKit)
        let uic = UIColor(self)
        #else
        let uic = NSColor(self)
        #endif
        guard let components = uic.cgColor.components, components.count >= 3 else {
            return "007AFF"
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        return String(format: "%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
    }
}
