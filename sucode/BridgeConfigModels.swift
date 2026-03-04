import Foundation
import SwiftUI

// MARK: - Bridge Configuration Models

/// Bridge 服务器返回的完整配置
struct BridgeConfig: Codable {
    let version: String
    let timestamp: Date?
    let device: DeviceInfo
    let ssh: SSHConfig
    let claudeCode: ClaudeCodeConfig
    let capabilities: [String]
    let limits: ResourceLimits?

    enum CodingKeys: String, CodingKey {
        case version, timestamp, device, ssh, capabilities, limits
        case claudeCode = "claude_code"
    }
}

/// 设备信息
struct DeviceInfo: Codable {
    let name: String
    let platform: String
    let hostname: String
}

/// SSH 配置
struct SSHConfig: Codable {
    let enabled: Bool
    let host: String
    let port: Int
    let username: String
    let authMethod: AuthMethod
    let password: String?  // 加密后的密码
    let privateKey: String? // 加密后的私钥

    enum CodingKeys: String, CodingKey {
        case enabled, host, port, username, password
        case authMethod = "auth_method"
        case privateKey = "private_key"
    }

    enum AuthMethod: String, Codable {
        case password
        case privateKey = "private_key"
        case none
    }
}

/// Claude Code 配置
struct ClaudeCodeConfig: Codable {
    let enabled: Bool
    let path: String
    let version: String
    let workspace: String?
}

/// 资源限制
struct ResourceLimits: Codable {
    let maxUploadSize: Int64
    let maxDownloadSize: Int64
    let allowedPaths: [String]

    enum CodingKeys: String, CodingKey {
        case maxUploadSize = "max_upload_size"
        case maxDownloadSize = "max_download_size"
        case allowedPaths = "allowed_paths"
    }
}

// MARK: - Bridge Config Error

enum BridgeConfigError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case unauthorized
    case forbidden
    case serviceUnavailable
    case noCredentials
    case decryptionFailed
    case sshDisabled
    case cacheExpired

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 Bridge URL"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .decodingError:
            return "配置数据解析失败"
        case .unauthorized:
            return "API 认证失败，请检查 API Key"
        case .forbidden:
            return "权限不足"
        case .serviceUnavailable:
            return "Bridge 服务不可用"
        case .noCredentials:
            return "未找到 SSH 凭据"
        case .decryptionFailed:
            return "密码解密失败"
        case .sshDisabled:
            return "SSH 未在 Bridge 配置中启用"
        case .cacheExpired:
            return "配置缓存已过期"
        }
    }
}

// MARK: - Config Cache

/// 配置缓存管理
class ConfigCache {
    static let shared = ConfigCache()

    private let userDefaults = UserDefaults.standard
    private let cachePrefix = "bridge_config_"
    private let cacheTimestampPrefix = "bridge_config_timestamp_"
    private let cacheValidityDuration: TimeInterval = 3600 // 1小时

    /// 保存配置到缓存
    func save(_ config: BridgeConfig, for deviceId: UUID) throws {
        let key = cacheKey(for: deviceId)
        let timestampKey = cacheTimestampKey(for: deviceId)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(config)

        // 使用 UserDefaults 存储（生产环境应使用 Keychain）
        userDefaults.set(data, forKey: key)
        userDefaults.set(Date(), forKey: timestampKey)
    }

    /// 从缓存加载配置
    func load(for deviceId: UUID) -> BridgeConfig? {
        let key = cacheKey(for: deviceId)
        let timestampKey = cacheTimestampKey(for: deviceId)

        guard let data = userDefaults.data(forKey: key),
              let timestamp = userDefaults.object(forKey: timestampKey) as? Date else {
            return nil
        }

        // 检查缓存是否过期
        if Date().timeIntervalSince(timestamp) > cacheValidityDuration {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try? decoder.decode(BridgeConfig.self, from: data)
    }

    /// 检查缓存是否有效
    func isValid(for deviceId: UUID) -> Bool {
        let timestampKey = cacheTimestampKey(for: deviceId)
        guard let timestamp = userDefaults.object(forKey: timestampKey) as? Date else {
            return false
        }
        return Date().timeIntervalSince(timestamp) <= cacheValidityDuration
    }

    /// 清除指定设备的缓存
    func clear(for deviceId: UUID) {
        userDefaults.removeObject(forKey: cacheKey(for: deviceId))
        userDefaults.removeObject(forKey: cacheTimestampKey(for: deviceId))
    }

    /// 清除所有缓存
    func clearAll() {
        let keys = userDefaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix(cachePrefix) || $0.hasPrefix(cacheTimestampPrefix)
        }
        keys.forEach { userDefaults.removeObject(forKey: $0) }
    }

    private func cacheKey(for deviceId: UUID) -> String {
        return "\(cachePrefix)\(deviceId.uuidString)"
    }

    private func cacheTimestampKey(for deviceId: UUID) -> String {
        return "\(cacheTimestampPrefix)\(deviceId.uuidString)"
    }
}
