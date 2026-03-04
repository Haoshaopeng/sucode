import SwiftUI

struct DeviceControlView: View {
    let device: Device
    @StateObject private var sshManager = SSHManager()
    @State private var command = ""
    @State private var output = ""
    @State private var isExecuting = false
    @State private var showConnectionError = false
    @State private var isConnecting = false
    @State private var showingLogs = false

    let quickCommands = [
        ("系统状态", "uname -a"),
        ("磁盘空间", "df -h"),
        ("内存使用", "free -h || vm_stat"),
        ("当前目录", "pwd && ls -la"),
        ("网络信息", "ifconfig || ip addr"),
        ("进程列表", "ps aux | head -20")
    ]

    var body: some View {
        VStack(spacing: 0) {
            connectionStatusBar

            Picker("视图", selection: $showingLogs) {
                Text("终端").tag(false)
                Text("日志").tag(true)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()

            if showingLogs {
                SSHLogView(logs: sshManager.logs, onClear: { sshManager.clearLogs() })
            } else {
                terminalView
            }

            commandInputArea
        }
        .navigationTitle(device.name)
        .alert("连接错误", isPresented: $showConnectionError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(sshManager.lastError ?? "未知错误")
        }
        .onDisappear {
            sshManager.disconnect()
        }
    }

    var connectionStatusBar: some View {
        HStack {
            Circle().fill(statusColor).frame(width: 10, height: 10)
            Text(statusText).font(.subheadline)
            Spacer()
            if sshManager.isConnecting {
                ProgressView().scaleEffect(0.8)
            } else if !sshManager.isConnected {
                Button("连接") { Task { await connect() } }
                    .buttonStyle(.bordered)
            } else {
                Button("断开") { sshManager.disconnect() }
                    .buttonStyle(.bordered).tint(.red)
            }
        }
        .padding().background(Color(.systemGray6))
    }

    var statusColor: Color {
        sshManager.isConnecting ? .yellow : (sshManager.isConnected ? .green : .red)
    }

    var statusText: String {
        sshManager.isConnecting ? "连接中..." : (sshManager.isConnected ? "已连接" : "未连接")
    }

    var terminalView: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(quickCommands, id: \.1) { name, cmd in
                        Button(action: { executeCommand(cmd) }) {
                            Text(name).font(.caption)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(sshManager.isConnected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .tint(.blue)
                        .disabled(!sshManager.isConnected || isExecuting)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)

            ScrollView {
                Text(output.isEmpty ? "点击连接按钮开始..." : output)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(.systemGray6))
        }
    }

    var commandInputArea: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                TextField("输入命令...", text: $command)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(.body, design: .monospaced))
                    .disabled(!sshManager.isConnected || isExecuting)

                if isExecuting {
                    ProgressView().padding(.leading, 8)
                } else {
                    Button(action: { executeCommand(command); command = "" }) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(command.isEmpty || !sshManager.isConnected || isExecuting)
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }

    func connect() async {
        isConnecting = true
        output += "\n[正在连接 \(device.host)...]\n"

        do {
            try await sshManager.connect(
                host: device.host,
                port: Int32(device.port),
                username: device.username,
                password: device.password
            )
            output += "[连接成功!]\n"
            BackgroundTaskManager.shared.notifyDeviceStatusChange(deviceName: device.name, isOnline: true)
        } catch {
            output += "[连接失败: \(error.localizedDescription)]\n"
            sshManager.lastError = error.localizedDescription
            showConnectionError = true
            BackgroundTaskManager.shared.notifyDeviceStatusChange(deviceName: device.name, isOnline: false)
        }
        isConnecting = false
    }

    func executeCommand(_ cmd: String) {
        guard !cmd.isEmpty else { return }
        isExecuting = true
        output += "\n$ \(cmd)\n"

        Task {
            do {
                let result = try await sshManager.executeCommand(cmd)
                await MainActor.run {
                    output += result.isEmpty ? "(无输出)\n" : "\(result)\n"
                    isExecuting = false
                }
                BackgroundTaskManager.shared.notifyCommandComplete(deviceName: device.name, command: cmd, success: true)
            } catch {
                await MainActor.run {
                    output += "错误: \(error.localizedDescription)\n"
                    isExecuting = false
                }
                BackgroundTaskManager.shared.notifyCommandComplete(deviceName: device.name, command: cmd, success: false)
            }
        }
    }
}

struct SSHLogView: View {
    let logs: [SSHLogEntry]
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SSH 连接日志").font(.headline)
                Spacer()
                Button("清空") { onClear() }.font(.caption)
            }
            .padding()
            Divider()
            List(logs.reversed()) { log in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(log.type.icon)
                        Text(log.formattedTime).font(.caption2).foregroundColor(.secondary)
                        Spacer()
                    }
                    Text(log.message)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(logColor(log.type))
                }
            }
            .listStyle(PlainListStyle())
        }
    }

    func logColor(_ type: SSHLogEntry.LogType) -> Color {
        switch type {
        case .error: return .red
        case .sent: return .green
        case .received: return .purple
        case .debug: return .gray
        default: return .primary
        }
    }
}
