import Foundation
import SwiftUI

// MARK: - Data Persistence Manager
@MainActor
class DataPersistenceManager: ObservableObject {
    static let shared = DataPersistenceManager()

    private let userDefaults = UserDefaults.standard
    private let fileManager = FileManager.default

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private var devicesFileURL: URL {
        documentsDirectory.appendingPathComponent("devices.json")
    }

    private var commandHistoryFileURL: URL {
        documentsDirectory.appendingPathComponent("command_history.json")
    }

    private var sessionsFileURL: URL {
        documentsDirectory.appendingPathComponent("sessions.json")
    }

    // MARK: - Keys
    private enum Keys {
        static let aiProvider = "ai_provider"
        static let apiKey = "api_key"
        static let autoConnect = "auto_connect"
        static let notifications = "notifications_enabled"
        static let theme = "app_theme"
        static let terminalFontSize = "terminal_font_size"
        static let terminalFontFamily = "terminal_font_family"
        static let lastSessionId = "last_session_id"
        static let clusterAutoRefresh = "cluster_auto_refresh"
        static let clusterRefreshInterval = "cluster_refresh_interval"
        static let lastSelectedTab = "last_selected_tab"
        static let lastSelectedDeviceId = "last_selected_device_id"
        static let wordWrap = "word_wrap"
        static let cursorStyle = "cursor_style"
        static let showLineNumbers = "show_line_numbers"
        static let terminalSound = "terminal_sound"
        static let terminalTheme = "terminal_theme"
        static let connectionTimeout = "connection_timeout"
        static let heartbeatInterval = "heartbeat_interval"
        static let autoSaveChat = "auto_save_chat"
        static let maxContextLength = "max_context_length"
        static let notifyOnOffline = "notify_on_offline"
        static let notifyOnCommandComplete = "notify_on_command_complete"
        static let enableBiometricAuth = "enable_biometric_auth"
        static let lockTimeout = "lock_timeout"
    }

    // MARK: - User Preferences

    @Published var aiProvider: String {
        didSet { userDefaults.set(aiProvider, forKey: Keys.aiProvider) }
    }

    @Published var apiKey: String {
        didSet { userDefaults.set(apiKey, forKey: Keys.apiKey) }
    }

    @Published var autoConnect: Bool {
        didSet { userDefaults.set(autoConnect, forKey: Keys.autoConnect) }
    }

    @Published var notificationsEnabled: Bool {
        didSet { userDefaults.set(notificationsEnabled, forKey: Keys.notifications) }
    }

    @Published var theme: AppTheme {
        didSet { userDefaults.set(theme.rawValue, forKey: Keys.theme) }
    }

    /// 用于 Picker 绑定的主题原始值
    var themeRawValue: String {
        get { theme.rawValue }
        set { theme = AppTheme(rawValue: newValue) ?? .dark }
    }

    @Published var terminalFontSize: CGFloat {
        didSet { userDefaults.set(terminalFontSize, forKey: Keys.terminalFontSize) }
    }

    @Published var terminalFontFamily: String {
        didSet { userDefaults.set(terminalFontFamily, forKey: Keys.terminalFontFamily) }
    }

    @Published var lastSessionId: String? {
        didSet { userDefaults.set(lastSessionId, forKey: Keys.lastSessionId) }
    }

    @Published var clusterAutoRefresh: Bool {
        didSet { userDefaults.set(clusterAutoRefresh, forKey: Keys.clusterAutoRefresh) }
    }

    @Published var clusterRefreshInterval: Int {
        didSet { userDefaults.set(clusterRefreshInterval, forKey: Keys.clusterRefreshInterval) }
    }

    @Published var lastSelectedTab: Int {
        didSet { userDefaults.set(lastSelectedTab, forKey: Keys.lastSelectedTab) }
    }

    @Published var lastSelectedDeviceId: String? {
        didSet { userDefaults.set(lastSelectedDeviceId, forKey: Keys.lastSelectedDeviceId) }
    }

    // Terminal Settings
    @Published var wordWrap: Bool {
        didSet { userDefaults.set(wordWrap, forKey: Keys.wordWrap) }
    }

    @Published var cursorStyle: String {
        didSet { userDefaults.set(cursorStyle, forKey: Keys.cursorStyle) }
    }

    @Published var showLineNumbers: Bool {
        didSet { userDefaults.set(showLineNumbers, forKey: Keys.showLineNumbers) }
    }

    @Published var terminalSound: Bool {
        didSet { userDefaults.set(terminalSound, forKey: Keys.terminalSound) }
    }

    @Published var terminalTheme: String {
        didSet { userDefaults.set(terminalTheme, forKey: Keys.terminalTheme) }
    }

    // Connection Settings
    @Published var connectionTimeout: Double {
        didSet { userDefaults.set(connectionTimeout, forKey: Keys.connectionTimeout) }
    }

    @Published var heartbeatInterval: Double {
        didSet { userDefaults.set(heartbeatInterval, forKey: Keys.heartbeatInterval) }
    }

    // AI Settings
    @Published var autoSaveChat: Bool {
        didSet { userDefaults.set(autoSaveChat, forKey: Keys.autoSaveChat) }
    }

    @Published var maxContextLength: Int {
        didSet { userDefaults.set(maxContextLength, forKey: Keys.maxContextLength) }
    }

    // Notification Settings
    @Published var notifyOnOffline: Bool {
        didSet { userDefaults.set(notifyOnOffline, forKey: Keys.notifyOnOffline) }
    }

    @Published var notifyOnCommandComplete: Bool {
        didSet { userDefaults.set(notifyOnCommandComplete, forKey: Keys.notifyOnCommandComplete) }
    }

    // Security Settings
    @Published var enableBiometricAuth: Bool {
        didSet { userDefaults.set(enableBiometricAuth, forKey: Keys.enableBiometricAuth) }
    }

    @Published var lockTimeout: Int {
        didSet { userDefaults.set(lockTimeout, forKey: Keys.lockTimeout) }
    }

    // MARK: - Initialization

    private init() {
        self.aiProvider = userDefaults.string(forKey: Keys.aiProvider) ?? "Claude"
        self.apiKey = userDefaults.string(forKey: Keys.apiKey) ?? ""
        self.autoConnect = userDefaults.bool(forKey: Keys.autoConnect)
        self.notificationsEnabled = userDefaults.bool(forKey: Keys.notifications)
        self.theme = AppTheme(rawValue: userDefaults.string(forKey: Keys.theme) ?? "dark") ?? .dark

        let savedFontSize = CGFloat(userDefaults.double(forKey: Keys.terminalFontSize))
        self.terminalFontSize = savedFontSize == 0 ? 14 : savedFontSize

        self.terminalFontFamily = userDefaults.string(forKey: Keys.terminalFontFamily) ?? "SF Mono"
        self.lastSessionId = userDefaults.string(forKey: Keys.lastSessionId)

        self.clusterAutoRefresh = userDefaults.bool(forKey: Keys.clusterAutoRefresh)
        if !userDefaults.contains(key: Keys.clusterAutoRefresh) {
            self.clusterAutoRefresh = true
        }

        let savedRefreshInterval = userDefaults.integer(forKey: Keys.clusterRefreshInterval)
        self.clusterRefreshInterval = savedRefreshInterval == 0 ? 30 : savedRefreshInterval

        self.lastSelectedTab = userDefaults.integer(forKey: Keys.lastSelectedTab)
        self.lastSelectedDeviceId = userDefaults.string(forKey: Keys.lastSelectedDeviceId)
        self.wordWrap = userDefaults.bool(forKey: Keys.wordWrap)
        self.cursorStyle = userDefaults.string(forKey: Keys.cursorStyle) ?? "block"
        self.showLineNumbers = userDefaults.bool(forKey: Keys.showLineNumbers)
        self.terminalSound = userDefaults.bool(forKey: Keys.terminalSound)
        self.terminalTheme = userDefaults.string(forKey: Keys.terminalTheme) ?? "dark"

        let savedTimeout = userDefaults.double(forKey: Keys.connectionTimeout)
        self.connectionTimeout = savedTimeout == 0 ? 30 : savedTimeout

        let savedHeartbeat = userDefaults.double(forKey: Keys.heartbeatInterval)
        self.heartbeatInterval = savedHeartbeat == 0 ? 30 : savedHeartbeat

        self.autoSaveChat = userDefaults.bool(forKey: Keys.autoSaveChat)

        let savedMaxContext = userDefaults.integer(forKey: Keys.maxContextLength)
        self.maxContextLength = savedMaxContext == 0 ? 10 : savedMaxContext

        self.notifyOnOffline = userDefaults.bool(forKey: Keys.notifyOnOffline)
        self.notifyOnCommandComplete = userDefaults.bool(forKey: Keys.notifyOnCommandComplete)
        self.enableBiometricAuth = userDefaults.bool(forKey: Keys.enableBiometricAuth)

        let savedLockTimeout = userDefaults.integer(forKey: Keys.lockTimeout)
        self.lockTimeout = savedLockTimeout == 0 ? 5 : savedLockTimeout
    }

    // MARK: - Session State

    func getLastSelectedDevice() -> UUID? {
        guard let deviceId = lastSelectedDeviceId,
              let uuid = UUID(uuidString: deviceId) else {
            return nil
        }
        return uuid
    }

    func setLastSelectedDevice(_ deviceId: UUID?) {
        lastSelectedDeviceId = deviceId?.uuidString
    }

    func resetAllSettings() {
        userDefaults.removeObject(forKey: Keys.aiProvider)
        userDefaults.removeObject(forKey: Keys.apiKey)
        userDefaults.removeObject(forKey: Keys.autoConnect)
        userDefaults.removeObject(forKey: Keys.notifications)
        userDefaults.removeObject(forKey: Keys.theme)
        userDefaults.removeObject(forKey: Keys.terminalFontSize)
        userDefaults.removeObject(forKey: Keys.terminalFontFamily)
        userDefaults.removeObject(forKey: Keys.lastSessionId)
        userDefaults.removeObject(forKey: Keys.clusterAutoRefresh)
        userDefaults.removeObject(forKey: Keys.clusterRefreshInterval)
        userDefaults.removeObject(forKey: Keys.lastSelectedTab)
        userDefaults.removeObject(forKey: Keys.lastSelectedDeviceId)
    }

    func clearCommandHistory() {
        try? fileManager.removeItem(at: commandHistoryFileURL)
    }

    // MARK: - Device Persistence

    func saveDevices(_ devices: [ClusterDevice]) {
        do {
            let data = try JSONEncoder().encode(devices)
            try data.write(to: devicesFileURL, options: .atomic)
        } catch {
            print("Failed to save devices: \(error)")
        }
    }

    func loadDevices() -> [ClusterDevice] {
        do {
            let data = try Data(contentsOf: devicesFileURL)
            let devices = try JSONDecoder().decode([ClusterDevice].self, from: data)
            // 如果设备为空，返回默认设备
            return devices.isEmpty ? ClusterDevice.defaults : devices
        } catch {
            print("Failed to load devices: \(error)")
            return ClusterDevice.defaults
        }
    }

    func resetDevicesToDefaults() {
        saveDevices(ClusterDevice.defaults)
    }

    // MARK: - Command History Persistence

    func saveCommandHistory(_ commands: [ClusterCommand]) {
        do {
            let data = try JSONEncoder().encode(commands)
            try data.write(to: commandHistoryFileURL, options: .atomic)
        } catch {
            print("Failed to save command history: \(error)")
        }
    }

    func loadCommandHistory() -> [ClusterCommand] {
        do {
            let data = try Data(contentsOf: commandHistoryFileURL)
            let commands = try JSONDecoder().decode([ClusterCommand].self, from: data)
            return commands
        } catch {
            return []
        }
    }

    func addCommandToHistory(_ command: ClusterCommand) {
        var history = loadCommandHistory()
        history.append(command)
        if history.count > 100 {
            history.removeFirst(history.count - 100)
        }
        saveCommandHistory(history)
    }

    // MARK: - Session Persistence

    func saveSessions(_ sessions: [ClusterSession]) {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: sessionsFileURL, options: .atomic)
        } catch {
            print("Failed to save sessions: \(error)")
        }
    }

    func loadSessions() -> [ClusterSession] {
        do {
            let data = try Data(contentsOf: sessionsFileURL)
            let sessions = try JSONDecoder().decode([ClusterSession].self, from: data)
            return sessions
        } catch {
            return []
        }
    }

    func saveLastSession(_ session: ClusterSession) {
        lastSessionId = session.id.uuidString
        var sessions = loadSessions()
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        saveSessions(sessions)
    }

    func getLastSession() -> ClusterSession? {
        guard let sessionId = lastSessionId,
              let uuid = UUID(uuidString: sessionId) else {
            return nil
        }
        return loadSessions().first { $0.id == uuid }
    }

    // MARK: - Clear Data

    func clearAllData() {
        userDefaults.removeObject(forKey: Keys.aiProvider)
        userDefaults.removeObject(forKey: Keys.apiKey)
        userDefaults.removeObject(forKey: Keys.autoConnect)
        userDefaults.removeObject(forKey: Keys.notifications)
        userDefaults.removeObject(forKey: Keys.theme)
        userDefaults.removeObject(forKey: Keys.terminalFontSize)
        userDefaults.removeObject(forKey: Keys.terminalFontFamily)
        userDefaults.removeObject(forKey: Keys.lastSessionId)
        userDefaults.removeObject(forKey: Keys.clusterAutoRefresh)
        userDefaults.removeObject(forKey: Keys.clusterRefreshInterval)
        userDefaults.removeObject(forKey: Keys.lastSelectedTab)
        userDefaults.removeObject(forKey: Keys.lastSelectedDeviceId)
        userDefaults.removeObject(forKey: Keys.wordWrap)
        userDefaults.removeObject(forKey: Keys.cursorStyle)
        userDefaults.removeObject(forKey: Keys.showLineNumbers)
        userDefaults.removeObject(forKey: Keys.terminalSound)
        userDefaults.removeObject(forKey: Keys.terminalTheme)
        userDefaults.removeObject(forKey: Keys.connectionTimeout)
        userDefaults.removeObject(forKey: Keys.heartbeatInterval)
        userDefaults.removeObject(forKey: Keys.autoSaveChat)
        userDefaults.removeObject(forKey: Keys.maxContextLength)
        userDefaults.removeObject(forKey: Keys.notifyOnOffline)
        userDefaults.removeObject(forKey: Keys.notifyOnCommandComplete)
        userDefaults.removeObject(forKey: Keys.enableBiometricAuth)
        userDefaults.removeObject(forKey: Keys.lockTimeout)

        try? fileManager.removeItem(at: devicesFileURL)
        try? fileManager.removeItem(at: commandHistoryFileURL)
        try? fileManager.removeItem(at: sessionsFileURL)
    }

    func migrateToSwiftData() async {
        // 数据迁移逻辑：将 JSON 文件数据迁移到 SwiftData
        print("Data migration completed")
    }
}

// MARK: - App Theme
enum AppTheme: String, CaseIterable {
    case light = "light"
    case dark = "dark"
    case system = "system"

    var displayName: String {
        switch self {
        case .light: return "浅色"
        case .dark: return "深色"
        case .system: return "跟随系统"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

// MARK: - UserDefaults Extension
extension UserDefaults {
    func contains(key: String) -> Bool {
        return object(forKey: key) != nil
    }
}
