//
//  SSHManager.swift
//  sucode
//

import Foundation
import Combine

// MARK: - SSH 错误类型
enum SSHError: Error, LocalizedError {
    case notConnected
    case authenticationFailed
    case commandFailed(String)
    case connectionFailed(String)
    case invalidHost
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "未连接到服务器"
        case .authenticationFailed:
            return "认证失败，请检查用户名和密码"
        case .commandFailed(let msg):
            return "命令执行失败: \(msg)"
        case .connectionFailed(let msg):
            return "连接失败: \(msg)"
        case .invalidHost:
            return "无效的主机地址"
        case .timeout:
            return "连接超时"
        }
    }
}

// MARK: - SSH 日志条目
struct SSHLogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let type: LogType
    let message: String

    enum LogType: Equatable {
        case info
        case error
        case sent
        case received
        case debug

        var icon: String {
            switch self {
            case .info: return "ℹ️"
            case .error: return "❌"
            case .sent: return "📤"
            case .received: return "📥"
            case .debug: return "🔧"
            }
        }

        var color: String {
            switch self {
            case .info: return "blue"
            case .error: return "red"
            case .sent: return "green"
            case .received: return "purple"
            case .debug: return "gray"
            }
        }
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

// MARK: - SSH 管理器
class SSHManager: ObservableObject {
    @Published var isConnected = false
    @Published var lastError: String?
    @Published var logs: [SSHLogEntry] = []
    @Published var isConnecting = false

    private var session: NMSSHSession?
    private var host: String = ""
    private var username: String = ""
    private var logCancellable: AnyCancellable?

    // MARK: - 日志方法
    private func log(_ message: String, type: SSHLogEntry.LogType = .info) {
        DispatchQueue.main.async {
            let entry = SSHLogEntry(timestamp: Date(), type: type, message: message)
            self.logs.append(entry)
            // 限制日志数量，防止内存溢出
            if self.logs.count > 1000 {
                self.logs.removeFirst(self.logs.count - 1000)
            }
        }
    }

    func clearLogs() {
        logs.removeAll()
    }

    // MARK: - 连接方法
    func connect(host: String, port: Int32 = 22, username: String, password: String) async throws {
        guard !host.isEmpty, !username.isEmpty else {
            throw SSHError.invalidHost
        }

        self.host = host
        self.username = username

        await MainActor.run {
            self.isConnecting = true
            self.lastError = nil
        }

        log("开始连接到 \(host):\(port)", type: .info)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // 创建会话
                    self.log("创建 SSH 会话...", type: .debug)
                    self.session = NMSSHSession.connect(toHost: "\(host):\(port)",
                                                       withUsername: username)

                    guard let session = self.session else {
                        self.log("创建会话失败", type: .error)
                        throw SSHError.connectionFailed("无法创建会话")
                    }

                    self.log("会话创建成功，开始认证...", type: .debug)

                    // 使用密码认证
                    let authSuccess = session.authenticate(byPassword: password)

                    if session.isConnected && authSuccess {
                        self.log("认证成功！已连接到 \(self.host)", type: .info)
                        DispatchQueue.main.async {
                            self.isConnected = true
                            self.isConnecting = false
                            self.lastError = nil
                        }
                        continuation.resume()
                    } else {
                        let errorDesc = session.lastError?.localizedDescription ?? "认证失败"
                        self.log("认证失败: \(errorDesc)", type: .error)
                        throw SSHError.authenticationFailed
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.isConnecting = false
                        self.lastError = error.localizedDescription
                    }
                    self.log("连接错误: \(error.localizedDescription)", type: .error)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - 执行命令
    func executeCommand(_ command: String) async throws -> String {
        guard let session = session, session.isConnected else {
            log("错误: 未连接到服务器", type: .error)
            throw SSHError.notConnected
        }

        log("执行命令: \(command)", type: .sent)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSError?
                let result = session.channel.execute(command, error: &error)

                if let err = error {
                    self.log("命令执行失败: \(err.localizedDescription)", type: .error)
                    continuation.resume(throwing: SSHError.commandFailed(err.localizedDescription))
                } else {
                    let trimmedResult = result.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.log("返回结果 (\(trimmedResult.count) 字符)", type: .received)
                    if !trimmedResult.isEmpty {
                        // 只显示前 200 字符到日志
                        let preview = String(trimmedResult.prefix(200))
                        self.log("预览: \(preview)\(trimmedResult.count > 200 ? "..." : "")", type: .debug)
                    }
                    continuation.resume(returning: trimmedResult)
                }
            }
        }
    }

    // MARK: - 批量执行命令
    func executeCommands(_ commands: [String]) async -> [(command: String, result: String, success: Bool)] {
        var results: [(command: String, result: String, success: Bool)] = []

        for command in commands {
            do {
                let result = try await executeCommand(command)
                results.append((command: command, result: result, success: true))
            } catch {
                results.append((command: command, result: error.localizedDescription, success: false))
            }
        }

        return results
    }

    // MARK: - 断开连接
    func disconnect() {
        log("断开连接", type: .info)
        session?.disconnect()
        session = nil
        isConnected = false
    }

    deinit {
        disconnect()
    }
}
