import Foundation
import Combine
import SwiftUI

/// Bridge 配置服务
/// 负责从 Bridge 服务器获取配置、缓存管理和密码解密
@MainActor
class BridgeConfigService: ObservableObject {
    static let shared = BridgeConfigService()

    @Published var lastError: BridgeConfigError?
    @Published var isLoading = false

    private let session: URLSession
    private let cache = ConfigCache.shared

    // API Key 存储键前缀
    private let apiKeyPrefix = "bridge_api_key_"

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        // 允许不安全的 HTTP 连接（用于局域网）
        config.httpShouldUsePipelining = true

        self.session = URLSession(
            configuration: config,
            delegate: InsecureURLSessionDelegate(),
            delegateQueue: nil
        )
    }

    // MARK: - Public Methods

    /// 从 Bridge 获取配置
    /// - Parameters:
    ///   - device: 目标设备
    ///   - preferCache: 是否优先使用缓存
    /// - Returns: BridgeConfig
    func fetchConfig(from device: ClusterDevice, preferCache: Bool = true) async throws -> BridgeConfig {
        // 如果优先使用缓存且缓存有效，直接返回
        if preferCache, let cached = cache.load(for: device.id) {
            print("📦 Using cached config for \(device.name)")
            return cached
        }

        isLoading = true
        defer { isLoading = false }

        let url = device.url.appendingPathComponent("api/config")

        guard url.host != nil else {
            throw BridgeConfigError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1.0", forHTTPHeaderField: "X-API-Version")

        // 添加 API Key（如果有）
        if let apiKey = getAPIKey(for: device) {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        print("🔍 Fetching config from: \(url)")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw BridgeConfigError.serviceUnavailable
            }

            print("📡 Config API Response: \(httpResponse.statusCode)")

            switch httpResponse.statusCode {
            case 200:
                return try await parseAndCacheConfig(data: data, for: device)
            case 401:
                throw BridgeConfigError.unauthorized
            case 403:
                throw BridgeConfigError.forbidden
            case 503:
                throw BridgeConfigError.serviceUnavailable
            default:
                throw BridgeConfigError.networkError(
                    NSError(domain: "BridgeConfig", code: httpResponse.statusCode)
                )
            }
        } catch let error as BridgeConfigError {
            self.lastError = error
            throw error
        } catch {
            let configError = BridgeConfigError.networkError(error)
            self.lastError = configError
            throw configError
        }
    }

    /// 获取缓存的配置（不发起网络请求）
    func getCachedConfig(for deviceId: UUID) -> BridgeConfig? {
        return cache.load(for: deviceId)
    }

    /// 检查缓存是否有效
    func isCacheValid(for deviceId: UUID) -> Bool {
        return cache.isValid(for: deviceId)
    }

    /// 清除指定设备的缓存
    func clearCache(for deviceId: UUID) {
        cache.clear(for: deviceId)
    }

    /// 清除所有缓存
    func clearAllCache() {
        cache.clearAll()
    }

    /// 解密密码
    /// - Parameter encrypted: 加密后的密码字符串（格式: encrypted:base64）
    /// - Returns: 解密后的明文密码
    func decryptPassword(_ encrypted: String) throws -> String {
        // 检查是否是加密格式
        guard encrypted.hasPrefix("encrypted:") else {
            // 明文返回（开发环境）
            return encrypted
        }

        let encryptedData = String(encrypted.dropFirst("encrypted:".count))

        // TODO: 实现实际的 AES 解密
        // 当前返回 base64 解码后的字符串（临时实现）
        if let data = Data(base64Encoded: encryptedData),
           let password = String(data: data, encoding: .utf8) {
            return password
        }

        throw BridgeConfigError.decryptionFailed
    }

    /// 获取 SSH 凭据（自动处理解密）
    func getSSHCredentials(for device: ClusterDevice) async throws -> (username: String, password: String?, host: String, port: Int) {
        let config = try await fetchConfig(from: device)

        guard config.ssh.enabled else {
            throw BridgeConfigError.sshDisabled
        }

        let password: String?
        if let encryptedPassword = config.ssh.password {
            password = try decryptPassword(encryptedPassword)
        } else {
            password = nil
        }

        return (
            username: config.ssh.username,
            password: password,
            host: config.ssh.host,
            port: config.ssh.port
        )
    }

    /// 保存设备的 API Key
    func saveAPIKey(_ apiKey: String, for device: ClusterDevice) {
        let key = apiKeyKey(for: device)
        UserDefaults.standard.set(apiKey, forKey: key)
    }

    /// 获取设备的 API Key
    func getAPIKey(for device: ClusterDevice) -> String? {
        let key = apiKeyKey(for: device)
        return UserDefaults.standard.string(forKey: key)
    }

    /// 获取设备能力列表（无需认证）
    func fetchCapabilities(from device: ClusterDevice) async throws -> [DeviceCapability] {
        let url = device.url.appendingPathComponent("api/config/capabilities")

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BridgeConfigError.serviceUnavailable
        }

        struct CapabilitiesResponse: Codable {
            let capabilities: [String]
        }

        let result = try JSONDecoder().decode(CapabilitiesResponse.self, from: data)

        return result.capabilities.compactMap { cap in
            switch cap {
            case "terminal": return .terminal
            case "claude", "claude_code": return .claudeCode
            case "sftp", "file_transfer": return .fileTransfer
            default: return nil
            }
        }
    }

    // MARK: - Private Methods

    private func parseAndCacheConfig(data: Data, for device: ClusterDevice) async throws -> BridgeConfig {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let config = try decoder.decode(BridgeConfig.self, from: data)

            // 保存到缓存
            try? cache.save(config, for: device.id)

            print("✅ Config fetched and cached for \(device.name)")
            print("   - SSH: \(config.ssh.enabled ? "enabled" : "disabled")")
            print("   - Claude Code: \(config.claudeCode.enabled ? "enabled" : "disabled")")
            print("   - Capabilities: \(config.capabilities.joined(separator: ", "))")

            return config
        } catch {
            print("❌ Failed to decode config: \(error)")
            throw BridgeConfigError.decodingError(error)
        }
    }

    private func apiKeyKey(for device: ClusterDevice) -> String {
        return "\(apiKeyPrefix)\(device.id.uuidString)"
    }
}

