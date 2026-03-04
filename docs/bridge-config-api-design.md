# Bridge 配置 API 设计方案

## 1. 概述

本文档描述 sucode iOS 应用与 Bridge 服务器之间的配置同步机制，解决 SFTP 凭据手动输入问题，提供统一的配置管理能力。

---

## 2. Bridge API 设计

### 2.1 端点规范

#### GET /api/config
获取设备配置和凭据信息。

**请求头：**
```http
GET /api/config HTTP/1.1
Host: {bridge_host}:{bridge_port}
Accept: application/json
X-API-Version: 1.0
```

**响应格式（200 OK）：**
```json
{
  "version": "1.0",
  "timestamp": "2026-03-04T12:00:00Z",
  "device": {
    "name": "macOS-Dev",
    "platform": "macos",
    "hostname": "192.168.1.64"
  },
  "ssh": {
    "enabled": true,
    "host": "192.168.1.64",
    "port": 22,
    "username": "developer",
    "auth_method": "password",
    "password": "encrypted:base64encoded"
  },
  "claude_code": {
    "enabled": true,
    "path": "/usr/local/bin/claude",
    "version": "2.2.5",
    "workspace": "/Users/developer/projects"
  },
  "capabilities": ["terminal", "claude_code", "sftp", "file_transfer"],
  "limits": {
    "max_upload_size": 104857600,
    "max_download_size": 104857600,
    "allowed_paths": ["/home", "/tmp", "/Users"]
  }
}
```

**错误响应：**
```json
// 401 Unauthorized
{
  "error": "unauthorized",
  "message": "API authentication required"
}

// 403 Forbidden
{
  "error": "forbidden",
  "message": "Insufficient permissions"
}

// 503 Service Unavailable
{
  "error": "service_unavailable",
  "message": "Bridge service initializing"
}
```

#### GET /api/config/capabilities
获取设备能力列表（无需认证）。

**响应格式：**
```json
{
  "capabilities": ["terminal", "claude_code", "sftp"],
  "version": "1.0"
}
```

#### POST /api/config/refresh
刷新配置缓存（管理用途）。

---

### 2.2 安全机制

#### 2.2.1 认证方式

**方案 A：API Key（推荐用于局域网）**
```http
X-API-Key: {pre_shared_key}
```

**方案 B：Token Based（推荐用于公网）**
```http
Authorization: Bearer {jwt_token}
```

**方案 C：IP 白名单（简化部署）**
- Bridge 配置允许的 IP 范围
- 无需额外认证头

#### 2.2.2 传输安全

1. **密码加密传输**
   - 使用 AES-256-GCM 加密
   - 密钥通过设备配对时交换
   - 响应中的密码字段为加密格式

2. **HTTPS/WSS 支持（可选）**
   - 生产环境建议使用 TLS
   - 开发环境允许 HTTP

---

## 3. iOS 端架构设计

### 3.1 类图

```
┌─────────────────────────────────────────────────────────────────┐
│                         BridgeConfigService                      │
├─────────────────────────────────────────────────────────────────┤
│ - session: URLSession                                            │
│ - cache: ConfigCache                                             │
│ - crypto: ConfigCrypto                                           │
├─────────────────────────────────────────────────────────────────┤
│ + fetchConfig(device: ClusterDevice) async -> BridgeConfig       │
│ + getCachedConfig(deviceId: UUID) -> BridgeConfig?               │
│ + clearCache()                                                   │
│ - decryptPassword(encrypted: String) -> String                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ uses
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         SFTPManager (修改后)                      │
├─────────────────────────────────────────────────────────────────┤
│ - configService: BridgeConfigService                             │
│ - cachedConfig: BridgeConfig?                                    │
├─────────────────────────────────────────────────────────────────┤
│ + connect() async -> Bool                                        │
│ + connectWithBridgeConfig() async -> Bool                        │
│ + connectWithManual(username:password:) async -> Bool            │
│ - tryAutoConnect() async -> Bool                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ uses
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         BridgeConfig (Model)                     │
├─────────────────────────────────────────────────────────────────┤
│ - deviceInfo: DeviceInfo                                         │
│ - ssh: SSHConfig                                                 │
│ - claudeCode: ClaudeCodeConfig                                   │
│ - capabilities: [DeviceCapability]                               │
│ - limits: ResourceLimits                                         │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 流程图

#### SFTP 连接流程（新）

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  用户点击    │────▶│  SFTPManager.    │────▶│  检查本地缓存    │
│  文件管理   │     │  connect()       │     │  (Keychain)     │
└─────────────┘     └──────────────────┘     └─────────────────┘
                                                      │
                              ┌─────────────────────┼─────────────────────┐
                              │ 缓存有效             │ 缓存无效/过期        │
                              ▼                     ▼                     │
                       ┌─────────────┐      ┌──────────────────┐         │
                       │ 使用缓存凭据 │      │ 请求 Bridge API  │◀────────┘
                       │ 连接 SSH    │      │ GET /api/config  │
                       └─────────────┘      └──────────────────┘
                              │                     │
                              │              ┌──────┴──────┐
                              │              │ 成功         │ 失败
                              │              ▼             ▼
                              │       ┌─────────────┐  ┌─────────────────┐
                              │       │ 解密密码    │  │ 回退到手动输入   │
                              │       │ 保存缓存    │  │ 显示登录界面    │
                              │       └─────────────┘  └─────────────────┘
                              │              │
                              └──────────────┘
                                             │
                                             ▼
                                      ┌─────────────┐
                                      │ 连接成功    │
                                      │ 显示文件列表 │
                                      └─────────────┘
```

---

## 4. 数据模型

### 4.1 BridgeConfig（Swift）

```swift
// MARK: - Bridge Configuration Models

struct BridgeConfig: Codable {
    let version: String
    let timestamp: Date
    let device: DeviceInfo
    let ssh: SSHConfig
    let claudeCode: ClaudeCodeConfig
    let capabilities: [DeviceCapability]
    let limits: ResourceLimits
}

struct DeviceInfo: Codable {
    let name: String
    let platform: String
    let hostname: String
}

struct SSHConfig: Codable {
    let enabled: Bool
    let host: String
    let port: Int
    let username: String
    let authMethod: AuthMethod
    let password: String?  // 加密后的密码
    let privateKey: String? // 加密后的私钥

    enum AuthMethod: String, Codable {
        case password
        case privateKey
        case none
    }
}

struct ClaudeCodeConfig: Codable {
    let enabled: Bool
    let path: String
    let version: String
    let workspace: String?
}

struct ResourceLimits: Codable {
    let maxUploadSize: Int64
    let maxDownloadSize: Int64
    let allowedPaths: [String]
}
```

### 4.2 配置缓存（Keychain）

```swift
class ConfigCache {
    static let shared = ConfigCache()

    func save(_ config: BridgeConfig, for deviceId: UUID) throws {
        let key = "bridge_config_\(deviceId.uuidString)"
        let data = try JSONEncoder().encode(config)
        // 使用 Keychain 存储加密数据
        try Keychain.save(data, service: "com.sucode.bridge", account: key)
    }

    func load(for deviceId: UUID) -> BridgeConfig? {
        let key = "bridge_config_\(deviceId.uuidString)"
        guard let data = Keychain.load(service: "com.sucode.bridge", account: key) else {
            return nil
        }
        return try? JSONDecoder().decode(BridgeConfig.self, from: data)
    }
}
```

---

## 5. 实现代码

### 5.1 BridgeConfigService.swift

```swift
import Foundation

enum BridgeConfigError: Error {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case unauthorized
    case serviceUnavailable
    case noCredentials
    case decryptionFailed
}

@MainActor
class BridgeConfigService: ObservableObject {
    static let shared = BridgeConfigService()

    @Published var lastError: BridgeConfigError?

    private let session: URLSession
    private let cache = ConfigCache()
    private var decryptionKey: Data?

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: config, delegate: InsecureURLSessionDelegate(), delegateQueue: nil)
    }

    /// 从 Bridge 获取配置
    func fetchConfig(from device: ClusterDevice) async throws -> BridgeConfig {
        let url = device.url.appendingPathComponent("api/config")

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1.0", forHTTPHeaderField: "X-API-Version")

        // 如果有 API Key，添加到请求头
        if let apiKey = getAPIKey(for: device) {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw BridgeConfigError.serviceUnavailable
            }

            switch httpResponse.statusCode {
            case 200:
                let config = try JSONDecoder().decode(BridgeConfig.self, from: data)
                // 保存到缓存
                try? cache.save(config, for: device.id)
                return config
            case 401:
                throw BridgeConfigError.unauthorized
            case 503:
                throw BridgeConfigError.serviceUnavailable
            default:
                throw BridgeConfigError.networkError(URLError(.badServerResponse))
            }
        } catch let error as BridgeConfigError {
            throw error
        } catch {
            throw BridgeConfigError.networkError(error)
        }
    }

    /// 获取缓存的配置
    func getCachedConfig(for deviceId: UUID) -> BridgeConfig? {
        return cache.load(for: deviceId)
    }

    /// 清除所有缓存
    func clearCache() {
        // 实现清除逻辑
    }

    /// 解密密码（使用设备配对时交换的密钥）
    func decryptPassword(_ encrypted: String) throws -> String {
        guard let key = decryptionKey else {
            throw BridgeConfigError.decryptionFailed
        }
        // 实现 AES-GCM 解密
        // 返回解密后的密码
        return encrypted // 临时返回原文
    }

    private func getAPIKey(for device: ClusterDevice) -> String? {
        // 从安全存储获取 API Key
        return nil
    }
}
```

### 5.2 修改后的 SFTPManager

```swift
@MainActor
class SFTPManager: ObservableObject {
    @Published var files: [SFTPFile] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentPath: String = "/"
    @Published var connectionState: ConnectionState = .disconnected

    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case failed(Error)
    }

    private var session: NMSSHSession?
    private var sftp: NMSFTP?
    private let device: ClusterDevice
    private let configService = BridgeConfigService.shared
    private var bridgeConfig: BridgeConfig?

    // 凭据存储键（保留作为回退）
    private var usernameKey: String { "sftp_username_\(device.id.uuidString)" }
    private var passwordKey: String { "sftp_password_\(device.id.uuidString)" }

    init(device: ClusterDevice) {
        self.device = device
    }

    // MARK: - 连接方法

    /// 主连接方法：优先使用 Bridge 配置
    func connect() async -> Bool {
        connectionState = .connecting

        // 1. 尝试从 Bridge 获取配置并连接
        if await connectWithBridgeConfig() {
            return true
        }

        // 2. 尝试使用本地保存的凭据
        if await connectWithSavedCredentials() {
            return true
        }

        // 3. 需要手动输入
        connectionState = .disconnected
        return false
    }

    /// 使用 Bridge 配置连接
    func connectWithBridgeConfig() async -> Bool {
        do {
            // 获取配置（优先网络，其次缓存）
            let config: BridgeConfig
            do {
                config = try await configService.fetchConfig(from: device)
            } catch {
                // 网络失败，尝试缓存
                guard let cached = configService.getCachedConfig(for: device.id) else {
                    return false
                }
                config = cached
            }

            guard config.ssh.enabled else {
                errorMessage = "SSH 未在 Bridge 配置中启用"
                return false
            }

            // 解密密码
            let password: String?
            if let encryptedPassword = config.ssh.password {
                password = try? configService.decryptPassword(encryptedPassword)
            } else {
                password = nil
            }

            // 连接 SSH
            let success = await connectSSH(
                host: config.ssh.host,
                port: config.ssh.port,
                username: config.ssh.username,
                password: password
            )

            if success {
                bridgeConfig = config
                connectionState = .connected
                return true
            }

            return false
        } catch {
            print("Bridge config connection failed: \(error)")
            return false
        }
    }

    /// 使用本地保存的凭据连接（回退方案）
    func connectWithSavedCredentials() async -> Bool {
        guard let username = UserDefaults.standard.string(forKey: usernameKey),
              let password = UserDefaults.standard.string(forKey: passwordKey) else {
            return false
        }

        return await connectSSH(
            host: device.host,
            port: 22, // 默认 SSH 端口
            username: username,
            password: password
        )
    }

    /// 手动输入凭据连接
    func connectWithManual(username: String, password: String, save: Bool = false) async -> Bool {
        if save {
            UserDefaults.standard.set(username, forKey: usernameKey)
            UserDefaults.standard.set(password, forKey: passwordKey)
        }

        return await connectSSH(
            host: device.host,
            port: 22,
            username: username,
            password: password
        )
    }

    // MARK: - 私有方法

    private func connectSSH(host: String, port: Int, username: String, password: String?) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let session = NMSSHSession(host: host, port: port, andUsername: username)
                session?.connect()

                if session?.isConnected == true {
                    if let password = password {
                        session?.authenticate(byPassword: password)
                    }

                    if session?.isAuthorized == true {
                        let sftp = NMSFTP.connect(with: session)
                        DispatchQueue.main.async {
                            self.session = session
                            self.sftp = sftp
                            self.connectionState = .connected
                            continuation.resume(returning: true)
                        }
                    } else {
                        session?.disconnect()
                        DispatchQueue.main.async {
                            self.errorMessage = "认证失败"
                            continuation.resume(returning: false)
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.errorMessage = "无法连接到服务器"
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }

    func disconnect() {
        sftp?.disconnect()
        session?.disconnect()
        sftp = nil
        session = nil
        connectionState = .disconnected
    }

    // ... 其他文件操作方法保持不变
}
```

---

## 6. Bridge 端实现建议

### 6.1 Python (Flask/FastAPI) 示例

```python
from flask import Flask, jsonify, request
from functools import wraps
import json
import os
from datetime import datetime
from cryptography.fernet import Fernet

app = Flask(__name__)

# 配置
CONFIG_FILE = os.path.expanduser("~/.bridge/config.json")
API_KEY = os.environ.get("BRIDGE_API_KEY", "default-dev-key")
ENCRYPTION_KEY = os.environ.get("BRIDGE_ENCRYPTION_KEY")

# 加载配置
def load_config():
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    return get_default_config()

def get_default_config():
    return {
        "version": "1.0",
        "device": {
            "name": os.uname().nodename,
            "platform": "macos" if os.uname().sysname == "Darwin" else "linux",
            "hostname": "127.0.0.1"
        },
        "ssh": {
            "enabled": True,
            "host": "127.0.0.1",
            "port": 22,
            "username": os.environ.get("USER", "root"),
            "auth_method": "password",
            "password": None  # 将在运行时加密
        },
        "claude_code": {
            "enabled": True,
            "path": "/usr/local/bin/claude",
            "version": "2.2.5",
            "workspace": os.path.expanduser("~")
        },
        "capabilities": ["terminal", "claude_code", "sftp"],
        "limits": {
            "max_upload_size": 100 * 1024 * 1024,  # 100MB
            "max_download_size": 100 * 1024 * 1024,
            "allowed_paths": ["/home", "/tmp"]
        }
    }

# 认证装饰器
def require_api_key(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        key = request.headers.get('X-API-Key')
        if key and key == API_KEY:
            return f(*args, **kwargs)
        return jsonify({"error": "unauthorized"}), 401
    return decorated

# 加密敏感数据
def encrypt_value(value: str) -> str:
    if not ENCRYPTION_KEY or not value:
        return value
    f = Fernet(ENCRYPTION_KEY.encode())
    return f"encrypted:{f.encrypt(value.encode()).decode()}"

# API 端点
@app.route('/api/config', methods=['GET'])
@require_api_key
def get_config():
    config = load_config()
    config['timestamp'] = datetime.utcnow().isoformat() + 'Z'

    # 加密敏感字段
    if config['ssh'].get('password'):
        config['ssh']['password'] = encrypt_value(config['ssh']['password'])

    return jsonify(config)

@app.route('/api/config/capabilities', methods=['GET'])
def get_capabilities():
    """无需认证的端点，用于设备发现"""
    config = load_config()
    return jsonify({
        "capabilities": config.get('capabilities', []),
        "version": config.get('version', '1.0')
    })

@app.route('/api/config/refresh', methods=['POST'])
@require_api_key
def refresh_config():
    # 重新加载配置
    return jsonify({"status": "ok"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8765)
```

### 6.2 Node.js 版本

```javascript
const express = require('express');
const crypto = require('crypto');
const fs = require('fs').promises;
const path = require('path');

const app = express();
const CONFIG_PATH = path.join(process.env.HOME, '.bridge', 'config.json');
const API_KEY = process.env.BRIDGE_API_KEY || 'default-dev-key';

// 中间件：API Key 认证
const requireAuth = (req, res, next) => {
    const key = req.headers['x-api-key'];
    if (key === API_KEY) {
        next();
    } else {
        res.status(401).json({ error: 'unauthorized' });
    }
};

// 加载配置
async function loadConfig() {
    try {
        const data = await fs.readFile(CONFIG_PATH, 'utf8');
        return JSON.parse(data);
    } catch {
        return getDefaultConfig();
    }
}

function getDefaultConfig() {
    return {
        version: '1.0',
        device: {
            name: require('os').hostname(),
            platform: process.platform,
            hostname: '127.0.0.1'
        },
        ssh: {
            enabled: true,
            host: '127.0.0.1',
            port: 22,
            username: process.env.USER || 'root',
            auth_method: 'password',
            password: null
        },
        claude_code: {
            enabled: true,
            path: '/usr/local/bin/claude',
            version: '2.2.5',
            workspace: process.env.HOME
        },
        capabilities: ['terminal', 'claude_code', 'sftp'],
        limits: {
            max_upload_size: 100 * 1024 * 1024,
            max_download_size: 100 * 1024 * 1024,
            allowed_paths: ['/home', '/tmp']
        }
    };
}

// 加密函数
function encrypt(text) {
    if (!process.env.BRIDGE_ENCRYPTION_KEY || !text) return text;
    const cipher = crypto.createCipher('aes-256-gcm', process.env.BRIDGE_ENCRYPTION_KEY);
    let encrypted = cipher.update(text, 'utf8', 'base64');
    encrypted += cipher.final('base64');
    return `encrypted:${encrypted}`;
}

// 路由
app.get('/api/config', requireAuth, async (req, res) => {
    const config = await loadConfig();
    config.timestamp = new Date().toISOString();

    // 加密敏感数据
    if (config.ssh?.password) {
        config.ssh.password = encrypt(config.ssh.password);
    }

    res.json(config);
});

app.get('/api/config/capabilities', async (req, res) => {
    const config = await loadConfig();
    res.json({
        capabilities: config.capabilities || [],
        version: config.version || '1.0'
    });
});

app.listen(8765, '0.0.0.0', () => {
    console.log('Bridge API server running on port 8765');
});
```

---

## 7. 部署配置

### 7.1 Bridge 配置文件示例

```json
{
  "version": "1.0",
  "device": {
    "name": "macOS-Dev",
    "platform": "macos"
  },
  "ssh": {
    "enabled": true,
    "host": "192.168.1.64",
    "port": 22,
    "username": "developer",
    "auth_method": "password",
    "password": "your-ssh-password"
  },
  "claude_code": {
    "enabled": true,
    "path": "/usr/local/bin/claude",
    "workspace": "/Users/developer/projects"
  },
  "api": {
    "auth_method": "api_key",
    "api_key": "your-secure-api-key"
  }
}
```

### 7.2 环境变量

```bash
# Bridge 服务器环境变量
export BRIDGE_API_KEY="your-secure-random-key"
export BRIDGE_ENCRYPTION_KEY="your-32-byte-encryption-key"
export BRIDGE_CONFIG_PATH="~/.bridge/config.json"
```

---

## 8. 安全建议

1. **API Key 管理**
   - 使用强随机生成的 API Key
   - 定期轮换 API Key
   - 不同设备使用不同 Key

2. **密码加密**
   - 使用 AES-256-GCM 加密算法
   - 密钥通过设备配对时安全交换
   - 支持密钥派生（PBKDF2/Argon2）

3. **传输安全**
   - 公网部署使用 HTTPS/WSS
   - 局域网可使用 HTTP，但建议添加 TLS
   - 验证服务器证书

4. **访问控制**
   - IP 白名单限制
   - 请求频率限制
   - 审计日志记录

---

## 9. 后续优化

1. **配置热更新**：WebSocket 推送配置变更
2. **多用户支持**：基于角色的访问控制
3. **审计日志**：记录所有 API 访问
4. **健康检查**：/api/health 端点
5. **版本协商**：API 版本自动协商

---

**文档版本**: 1.0
**最后更新**: 2026-03-04
