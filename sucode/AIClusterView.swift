import SwiftUI

struct AIClusterView: View {
    @StateObject private var viewModel = ClusterViewModel()
    @State private var showingBatchCommand = false
    @State private var showSettings = false
    @State private var isLoaded = false
    @State private var showingAddDevice = false
    @State private var selectedDeviceForDetail: ClusterDevice? = nil
    @State private var showingMasterAgent = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // 顶部导航栏
                topBar
                    .slideUp(delay: 0)

                // 标题区域
                headerView
                    .slideUp(delay: AnimationDelay.stagger)

                // 统计卡片 - 带 Skeleton 效果
                statsView
                    .slideUp(delay: AnimationDelay.stagger * 2)

                // 批量操作按钮
                batchActionView
                    .slideUp(delay: AnimationDelay.stagger * 3)

                // 设备列表
                deviceListView
                    .slideUp(delay: AnimationDelay.stagger * 4)

                Spacer(minLength: 50)
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $showingBatchCommand) {
            BatchCommandView(devices: viewModel.selectedDevicesList)
        }
        .sheet(isPresented: $showSettings) {
            ClusterSettingsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingAddDevice) {
            AddClusterDeviceView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingMasterAgent) {
            MasterAgentView()
                .environmentObject(viewModel)
        }
        .sheet(item: $selectedDeviceForDetail) { device in
            ClusterDeviceDetailView(device: device, viewModel: viewModel)
        }
        .task {
            // 先立即显示（使用缓存状态）
            isLoaded = true

            // 后台刷新状态
            Task {
                await viewModel.refreshStatus()
            }
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            Text("AI Cluster")
                .font(.headline)
                .foregroundColor(.white)

            Spacer()

            HStack(spacing: 16) {
                // Master Agent 按钮
                Button(action: {
                    HapticFeedback.light()
                    showingMasterAgent = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .foregroundColor(.orange)
                            .font(.system(size: 16))
                        Text("Agent")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(8)
                }
                .pressable(scale: 0.9)

                // 添加设备按钮
                Button(action: {
                    HapticFeedback.light()
                    showingAddDevice = true
                }) {
                    Image(systemName: "plus")
                        .foregroundColor(.white)
                        .font(.system(size: 18))
                }
                .pressable(scale: 0.9)

                Button(action: {
                    HapticFeedback.light()
                    showSettings = true
                }) {
                    Image(systemName: "gear")
                        .foregroundColor(.white)
                        .font(.system(size: 18))
                }
                .pressable(scale: 0.9)

                Button(action: {
                    HapticFeedback.light()
                    Task {
                        await viewModel.refreshStatus()
                        // 打印调试信息
                        print("=== 设备状态调试 ===")
                        for device in viewModel.devices {
                            print("📱 \(device.name): \(device.status.rawValue) - \(device.host):\(device.port)")
                        }
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.white)
                        .font(.system(size: 18))
                        .rotationEffect(.degrees(viewModel.isRefreshing ? 360 : 0))
                        .animation(viewModel.isRefreshing ? .spin : .default, value: viewModel.isRefreshing)
                }
                .disabled(viewModel.isRefreshing)
                .pressable(scale: 0.9)
            }
        }
        .padding(.top, 50)
        .padding(.bottom, 10)
    }

    // MARK: - Header
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Cluster")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.white)

            Text("管理和控制你的 AI 计算集群")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Stats
    @State private var debugInfo: String = ""

    private var statsView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if !isLoaded || viewModel.isRefreshing {
                    // Skeleton 加载状态
                    StatCardSkeleton()
                    StatCardSkeleton()
                    StatCardSkeleton()
                } else {
                    StatCard(
                        title: "设备",
                        value: "\(viewModel.devices.count)",
                        icon: "cpu",
                        color: .blue
                    )

                    StatCard(
                        title: "在线",
                        value: "\(viewModel.devices.filter { $0.isOnline }.count)",
                        icon: "checkmark.circle",
                        color: .green
                    )

                    StatCard(
                        title: "选中",
                        value: "\(viewModel.selectedDevices.count)",
                        icon: "checkmark.square",
                        color: .orange
                    )
                }
            }

            // 调试信息按钮
            Button(action: {
                testConnection()
            }) {
                HStack {
                    Image(systemName: "network.badge.shield.half.filled")
                    Text("测试连接并请求权限")
                }
                .font(.caption)
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }

            if !debugInfo.isEmpty {
                Text(debugInfo)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
            }
        }
    }

    private func testConnection() {
        debugInfo = "正在测试连接...\n请检查是否弹出权限请求"

        // 使用 Bonjour/NetService 触发本地网络权限
        let service = NetService(domain: "local.", type: "_http._tcp.", name: "test", port: 80)
        service.resolve(withTimeout: 5)

        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 等待1秒

            for device in viewModel.devices {
                let url = "http://\(device.host):\(device.port)/"
                if let testUrl = URL(string: url) {
                    do {
                        let config = URLSessionConfiguration.default
                        config.timeoutIntervalForRequest = 5
                        let session = URLSession(configuration: config)
                        let (_, response) = try await session.data(from: testUrl)
                        if let httpResponse = response as? HTTPURLResponse {
                            await MainActor.run {
                                debugInfo += "\n\(device.name): HTTP \(httpResponse.statusCode) ✅"
                            }
                        }
                    } catch {
                        await MainActor.run {
                            let errorDesc = error.localizedDescription
                            if errorDesc.contains("The Internet connection appears to be offline") {
                                debugInfo += "\n\(device.name): ❌ 无网络权限或未连接WiFi"
                            } else if errorDesc.contains("Could not connect to the server") {
                                debugInfo += "\n\(device.name): ❌ 无法连接服务器\n   请检查: 1. WiFi连接 2. IP地址正确 3. 服务是否运行"
                            } else {
                                debugInfo += "\n\(device.name): ❌ \(errorDesc)"
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Batch Actions
    private var batchActionView: some View {
        HStack(spacing: 12) {
            ActionButton(
                title: "全选",
                icon: "checkmark.square.fill",
                action: {
                    HapticFeedback.light()
                    viewModel.selectAll()
                }
            )

            ActionButton(
                title: "取消",
                icon: "xmark.square",
                action: {
                    HapticFeedback.light()
                    viewModel.deselectAll()
                }
            )

            Spacer()

            if !viewModel.selectedDevices.isEmpty {
                Button(action: {
                    HapticFeedback.medium()
                    showingBatchCommand = true
                }) {
                    Label("批量命令", systemImage: "terminal.fill")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue.opacity(0.7), Color.blue.opacity(0.5)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(10)
                        .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .transition(.scale.combined(with: .opacity))
                .pressable(scale: 0.95)
            }
        }
    }

    // MARK: - Device List
    private var deviceListView: some View {
        VStack(spacing: 12) {
            if !isLoaded {
                // Skeleton 加载状态
                deviceSkeletonList
            } else {
                deviceActualList
            }
        }
    }

    private var deviceSkeletonList: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { index in
                DeviceCardSkeleton()
                    .slideUp(delay: Double(index) * AnimationDelay.card)
            }
        }
    }

    private var deviceActualList: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.devices) { device in
                DeviceCard(
                    device: device,
                    isSelected: viewModel.selectedDevices.contains(device.id),
                    onSelect: {
                        HapticFeedback.selection()
                        viewModel.toggleSelection(device.id)
                    },
                    onTap: {
                        HapticFeedback.light()
                        selectedDeviceForDetail = device
                    }
                )
            }
        }
    }
}

// MARK: - Action Button
struct ActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.1))
                )
                .scaleEffect(isPressed ? 0.95 : 1)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.snappy) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.snappy) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let delay: Double = 0

    @State private var animatedValue = "0"
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Spacer()
            }

            Text(animatedValue)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1)
        .onTapGesture {
            withAnimation(.snappy) {
                isHovered = true
                HapticFeedback.light()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.snappy) {
                    isHovered = false
                }
            }
        }
        .onAppear {
            // 数字滚动动画
            withAnimation(.smooth.delay(delay)) {
                animatedValue = value
            }
        }
        .onChange(of: value) { newValue in
            withAnimation(.smooth) {
                animatedValue = newValue
            }
        }
    }
}

// MARK: - Device Card
struct DeviceCard: View {
    let device: ClusterDevice
    let isSelected: Bool
    let onSelect: () -> Void
    let onTap: () -> Void

    @State private var isPressed = false
    @State private var offset: CGFloat = 0

    var body: some View {
        HStack(spacing: 16) {
            // 选择圆圈 - 点击切换选择状态
            Button(action: {
                onSelect()
            }) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray.opacity(0.5))
                    .font(.title3)
                    .scaleEffect(isSelected ? 1.1 : 1)
                    .animation(.bouncy, value: isSelected)
            }
            .buttonStyle(PlainButtonStyle())

            // 设备信息区域 - 点击进入详情
            Button(action: {
                onTap()
            }) {
                HStack(spacing: 16) {
                    // 设备图标
                    ZStack {
                        Circle()
                            .fill(device.status.color.opacity(0.2))
                            .frame(width: 50, height: 50)

                        Image(systemName: deviceIcon)
                            .font(.system(size: 24))
                            .foregroundColor(device.status.color)

                        // 在线脉冲效果
                        if device.isOnline {
                            Circle()
                                .stroke(device.status.color, lineWidth: 2)
                                .frame(width: 50, height: 50)
                                .scaleEffect(1.3)
                                .opacity(0)
                                .pulseEffect(active: true, color: device.status.color)
                        }
                    }

                    // 设备信息
                    VStack(alignment: .leading, spacing: 6) {
                        Text(device.displayName)
                            .font(.headline)
                            .foregroundColor(.white)

                        Text(device.subtitle)
                            .font(.caption)
                            .foregroundColor(.gray)

                        if let description = device.description {
                            Text(description)
                                .font(.caption2)
                                .foregroundColor(.gray.opacity(0.7))
                        }

                        HStack(spacing: 6) {
                            ForEach(device.capabilities, id: \.self) { capability in
                                Image(systemName: capability.icon)
                                    .font(.caption2)
                                    .foregroundColor(.blue.opacity(0.8))
                            }

                            Text(device.mode.description)
                                .font(.caption2)
                                .foregroundColor(.purple.opacity(0.8))
                        }
                    }

                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())

            // 状态标签
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: device.status.icon)
                        .font(.caption)
                    Text(device.status.rawValue)
                        .font(.caption)
                }
                .foregroundColor(device.status.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(device.status.color.opacity(0.15))
                )

                if device.isOnline {
                    Text(device.formattedLastSeen)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }

            Image(systemName: "chevron.right")
                .foregroundColor(.gray.opacity(0.5))
                .font(.caption)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? Color.blue.opacity(0.5) : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
                )
        )
        .scaleEffect(isPressed ? 0.98 : 1)
        .animation(.snappy, value: isPressed)
    }

    private var deviceIcon: String {
        switch device.name.lowercased() {
        case let name where name.contains("win"):
            return "desktopcomputer"
        case let name where name.contains("mac"):
            return "laptopcomputer"
        case let name where name.contains("vps"), let name where name.contains("server"):
            return "server.rack"
        default:
            return "cpu"
        }
    }
}

// MARK: - Batch Command View
struct BatchCommandView: View {
    let devices: [ClusterDevice]
    @State private var command = ""
    @State private var results: [UUID: String] = [:]
    @State private var isExecuting = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 16) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(devices) { device in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(device.status.color)
                                        .frame(width: 6, height: 6)
                                    Text(device.name)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("命令")
                            .font(.subheadline)
                            .foregroundColor(.gray)

                        TextEditor(text: $command)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(8)
                            .frame(height: 80)
                    }
                    .padding(.horizontal)

                    Button(action: {
                        HapticFeedback.medium()
                        executeCommand()
                    }) {
                        HStack {
                            Image(systemName: isExecuting ? "arrow.clockwise" : "play.fill")
                                .rotationEffect(.degrees(isExecuting ? 360 : 0))
                                .animation(isExecuting ? .spin : .default, value: isExecuting)
                            Text(isExecuting ? "执行中..." : "执行")
                        }
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: command.isEmpty || isExecuting ?
                                    [Color.gray.opacity(0.5), Color.gray.opacity(0.3)] :
                                    [Color.blue.opacity(0.7), Color.blue.opacity(0.5)]
                                ),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                        .shadow(color: command.isEmpty || isExecuting ? Color.clear : Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .padding(.horizontal)
                    .disabled(command.isEmpty || isExecuting)
                    .pressable(scale: 0.97)

                    if !results.isEmpty {
                        Text("执行结果")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .slideUp()

                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                                    if let result = results[device.id] {
                                        BatchResultCard(device: device, result: result)
                                            .slideUp(delay: Double(index) * AnimationDelay.card)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    Spacer()
                }
                .padding(.top)
            }
            .navigationTitle("批量命令")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }

    private func executeCommand() {
        isExecuting = true
        results = [:]

        let commandToExecute = command
        let targetDevices = devices.filter { $0.isOnline }.map { $0.id }

        Task {
            var commandResults: [UUID: CommandResult] = [:]

            await withTaskGroup(of: (UUID, String, TimeInterval).self) { group in
                for device in devices where device.isOnline {
                    group.addTask {
                        let startTime = Date()
                        let result = await self.executeCommandOnDevice(commandToExecute, device: device)
                        let executionTime = Date().timeIntervalSince(startTime)
                        return (device.id, result, executionTime)
                    }
                }

                for await (deviceId, result, executionTime) in group {
                    await MainActor.run {
                        withAnimation(.smooth) {
                            results[deviceId] = result
                        }
                        commandResults[deviceId] = CommandResult(
                            deviceId: deviceId,
                            success: !result.hasPrefix("错误"),
                            output: result,
                            error: result.hasPrefix("错误") ? result : nil,
                            executionTime: executionTime,
                            timestamp: Date()
                        )
                    }
                }
            }

            // 标记离线设备
            for device in devices where !device.isOnline {
                results[device.id] = "设备离线，无法执行命令"
                commandResults[device.id] = CommandResult(
                    deviceId: device.id,
                    success: false,
                    output: "",
                    error: "设备离线",
                    executionTime: 0,
                    timestamp: Date()
                )
            }

            // Save command to history
            let clusterCommand = ClusterCommand(
                id: UUID(),
                command: commandToExecute,
                targetDevices: targetDevices,
                timestamp: Date(),
                results: commandResults
            )
            DataPersistenceManager.shared.addCommandToHistory(clusterCommand)

            await MainActor.run {
                isExecuting = false
                HapticFeedback.success()
            }
        }
    }

    private func executeCommandOnDevice(_ command: String, device: ClusterDevice) async -> String {
        guard let url = URL(string: "http://\(device.host):\(device.port)/execute") else {
            return "错误: 无效的URL"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0

        let body: [String: String] = ["command": command]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return "错误: 无效的响应"
            }

            if httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let output = json["output"] as? String {
                    return output
                } else if let text = String(data: data, encoding: .utf8) {
                    return text
                } else {
                    return "执行成功 (无法解析输出)"
                }
            } else {
                let errorText = String(data: data, encoding: .utf8) ?? "未知错误"
                return "错误 (HTTP \(httpResponse.statusCode)): \(errorText)"
            }
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                return "错误: 请求超时"
            case .cannotConnectToHost:
                return "错误: 无法连接到设备"
            case .notConnectedToInternet:
                return "错误: 无网络连接"
            default:
                return "错误: \(error.localizedDescription)"
            }
        } catch {
            return "错误: \(error.localizedDescription)"
        }
    }
}

// MARK: - Batch Result Card
struct BatchResultCard: View {
    let device: ClusterDevice
    let result: String

    private var isError: Bool {
        result.hasPrefix("错误") || result.hasPrefix("设备离线")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(device.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Spacer()

                Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundColor(isError ? .red : .green)
            }

            Text(result)
                .font(.caption)
                .foregroundColor(isError ? .red.opacity(0.8) : .gray)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(8)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isError ? Color.red.opacity(0.3) : Color.green.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Cluster Settings View
struct ClusterSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ClusterViewModel
    @AppStorage("clusterAutoRefresh") private var autoRefresh = true
    @AppStorage("clusterRefreshInterval") private var refreshInterval = 30
    @State private var showingResetConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("连接设置") {
                    Toggle("自动刷新状态", isOn: $autoRefresh)
                        .onChange(of: autoRefresh) { _ in
                            HapticFeedback.selection()
                        }

                    if autoRefresh {
                        Picker("刷新间隔", selection: $refreshInterval) {
                            Text("10 秒").tag(10)
                            Text("30 秒").tag(30)
                            Text("1 分钟").tag(60)
                            Text("5 分钟").tag(300)
                        }
                        .onChange(of: refreshInterval) { _ in
                            HapticFeedback.selection()
                        }
                    }
                }

                Section("数据管理") {
                    Button(role: .destructive, action: {
                        HapticFeedback.warning()
                        showingResetConfirmation = true
                    }) {
                        Label("重置为默认设备", systemImage: "arrow.counterclockwise")
                    }
                }

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }

                    HStack {
                        Text("Bridge 协议")
                        Spacer()
                        Text("WebSocket + HTTP")
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .alert("重置设备", isPresented: $showingResetConfirmation) {
                Button("取消", role: .cancel) {}
                Button("重置", role: .destructive) {
                    viewModel.resetToDefaults()
                }
            } message: {
                Text("这将删除所有现有设备并恢复为默认设备配置。此操作不可撤销。")
            }
        }
    }
}

// MARK: - ClusterDeviceDetailView
struct ClusterDeviceDetailView: View {
    let device: ClusterDevice
    @ObservedObject var viewModel: ClusterViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditDevice = false
    @State private var showingDeleteConfirmation = false
    @State private var showingTerminal = false
    @State private var showingAIAssistant = false
    @State private var showingFileTransfer = false
    @State private var showingFileBrowser = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // 设备头部信息
                        deviceHeader

                        // 操作按钮
                        actionButtons

                        // 连接信息
                        connectionInfoSection

                        // 状态详情
                        statusDetailsSection

                        Spacer(minLength: 50)
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                }
            }
            .navigationTitle(device.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            HapticFeedback.light()
                            showingEditDevice = true
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            HapticFeedback.warning()
                            showingDeleteConfirmation = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(isPresented: $showingEditDevice) {
                EditClusterDeviceView(device: device, viewModel: viewModel)
            }
            .sheet(isPresented: $showingTerminal) {
                WebSocketTerminalView(device: device)
            }
            .sheet(isPresented: $showingFileTransfer) {
                FileTransferView(device: device)
            }
            .sheet(isPresented: $showingFileBrowser) {
                SFTPFileBrowserView(device: device)
            }
            .alert("删除设备", isPresented: $showingDeleteConfirmation) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    viewModel.removeDevice(device)
                    dismiss()
                }
            } message: {
                Text("确定要删除设备 \"\(device.name)\" 吗？此操作不可撤销。")
            }
        }
    }

    // MARK: - Device Header
    private var deviceHeader: some View {
        VStack(spacing: 16) {
            // 设备图标
            ZStack {
                Circle()
                    .fill(device.status.color.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: deviceIcon)
                    .font(.system(size: 40))
                    .foregroundColor(device.status.color)

                // 在线脉冲效果
                if device.isOnline {
                    Circle()
                        .stroke(device.status.color, lineWidth: 2)
                        .frame(width: 80, height: 80)
                        .scaleEffect(1.3)
                        .opacity(0)
                        .pulseEffect(active: true, color: device.status.color)
                }
            }

            // 设备名称和描述
            VStack(spacing: 8) {
                Text(device.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                if let description = device.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }

                // 状态标签
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: device.status.icon)
                            .font(.caption)
                        Text(device.status.rawValue)
                            .font(.caption)
                    }
                    .foregroundColor(device.status.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(device.status.color.opacity(0.15))
                    )

                    HStack(spacing: 4) {
                        Image(systemName: "network")
                            .font(.caption)
                        Text(device.mode.description)
                            .font(.caption)
                    }
                    .foregroundColor(.purple)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.purple.opacity(0.15))
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(device.status.color.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        HStack(spacing: 16) {
            // 终端按钮
            ActionButtonLarge(
                title: "终端",
                icon: "terminal.fill",
                color: .orange,
                isEnabled: device.isOnline
            ) {
                HapticFeedback.medium()
                showingTerminal = true
            }

            // AI助手按钮
            ActionButtonLarge(
                title: "AI助手",
                icon: "brain",
                color: .blue,
                isEnabled: device.isOnline
            ) {
                HapticFeedback.medium()
                showingAIAssistant = true
            }

            // 文件浏览器按钮
            ActionButtonLarge(
                title: "文件",
                icon: "folder.fill",
                color: .green,
                isEnabled: device.isOnline
            ) {
                HapticFeedback.medium()
                showingFileBrowser = true
            }
        }
    }

    // MARK: - Connection Info Section
    private var connectionInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("连接信息")
                .font(.headline)
                .foregroundColor(.white)

            VStack(spacing: 0) {
                InfoRow(title: "主机", value: device.host, icon: "network")
                Divider().background(Color.white.opacity(0.1))
                InfoRow(title: "端口", value: "\(device.port)", icon: "number")
                Divider().background(Color.white.opacity(0.1))
                InfoRow(title: "URL", value: "http://\(device.host):\(device.port)", icon: "link")
            }
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
    }

    // MARK: - Status Details Section
    private var statusDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("状态详情")
                .font(.headline)
                .foregroundColor(.white)

            HStack(spacing: 12) {
                StatusItem(
                    title: "最后在线",
                    value: device.formattedLastSeen,
                    icon: "clock",
                    color: .blue
                )

                StatusItem(
                    title: "延迟",
                    value: device.latency != nil ? "\(Int(device.latency! * 1000))ms" : "--",
                    icon: "bolt.fill",
                    color: .orange
                )
            }

            HStack(spacing: 12) {
                StatusItem(
                    title: "功能",
                    value: "\(device.capabilities.count) 项",
                    icon: "checkmark.shield.fill",
                    color: .green
                )

                StatusItem(
                    title: "ID",
                    value: String(device.id.uuidString.prefix(8)),
                    icon: "tag.fill",
                    color: .purple
                )
            }
        }
    }

    private var deviceIcon: String {
        switch device.name.lowercased() {
        case let name where name.contains("win"):
            return "desktopcomputer"
        case let name where name.contains("mac"):
            return "laptopcomputer"
        case let name where name.contains("vps"), let name where name.contains("server"):
            return "server.rack"
        default:
            return "cpu"
        }
    }
}

// MARK: - Action Button Large
struct ActionButtonLarge: View {
    let title: String
    let icon: String
    let color: Color
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(isEnabled ? color : .gray)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isEnabled ? color.opacity(0.15) : Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isEnabled ? color.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .disabled(!isEnabled)
        .pressable(scale: 0.95)
    }
}

// MARK: - Status Item
struct StatusItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.15))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)
                .background(Color.blue.opacity(0.15))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                UIPasteboard.general.string = value
                HapticFeedback.light()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
    }
}

// MARK: - Edit Cluster Device View
struct EditClusterDeviceView: View {
    let device: ClusterDevice
    @ObservedObject var viewModel: ClusterViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = ""
    @State private var deviceDescription: String = ""

    init(device: ClusterDevice, viewModel: ClusterViewModel) {
        self.device = device
        self.viewModel = viewModel
        _name = State(initialValue: device.name)
        _host = State(initialValue: device.host)
        _port = State(initialValue: String(device.port))
        _deviceDescription = State(initialValue: device.description ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称", text: $name)
                    TextField("描述", text: $deviceDescription)
                }

                Section("连接信息") {
                    TextField("主机地址", text: $host)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                    TextField("端口", text: $port)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("编辑设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveDevice()
                    }
                    .disabled(name.isEmpty || host.isEmpty || port.isEmpty)
                }
            }
        }
    }

    private func saveDevice() {
        guard let portNumber = Int(port) else { return }

        var updatedDevice = device
        updatedDevice.name = name
        updatedDevice.host = host
        updatedDevice.port = portNumber
        updatedDevice.description = deviceDescription.isEmpty ? nil : deviceDescription

        viewModel.updateDevice(updatedDevice)
        dismiss()
    }
}

// MARK: - File Transfer View
struct FileTransferView: View {
    let device: ClusterDevice
    @Environment(\.dismiss) private var dismiss
    @State private var localPath = ""
    @State private var remotePath = ""
    @State private var isUploading = false
    @State private var transferStatus: TransferStatus = .idle

    enum TransferStatus {
        case idle, uploading, downloading, success, failed

        var description: String {
            switch self {
            case .idle: return "准备就绪"
            case .uploading: return "上传中..."
            case .downloading: return "下载中..."
            case .success: return "传输成功"
            case .failed: return "传输失败"
            }
        }

        var color: Color {
            switch self {
            case .idle: return .gray
            case .uploading, .downloading: return .blue
            case .success: return .green
            case .failed: return .red
            }
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("设备信息")) {
                    HStack {
                        Text("名称")
                        Spacer()
                        Text(device.name)
                            .foregroundColor(.gray)
                    }
                    HStack {
                        Text("地址")
                        Spacer()
                        Text("\(device.host):\(device.port)")
                            .foregroundColor(.gray)
                    }
                }

                Section(header: Text("本地文件路径")) {
                    TextField("例如: /Users/documents/file.txt", text: $localPath)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                Section(header: Text("远程路径")) {
                    TextField("例如: /home/user/file.txt", text: $remotePath)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                Section {
                    // 状态显示
                    HStack {
                        Text("状态")
                        Spacer()
                        Text(transferStatus.description)
                            .foregroundColor(transferStatus.color)
                    }

                    // 上传按钮
                    Button(action: uploadFile) {
                        HStack {
                            Image(systemName: "arrow.up.circle.fill")
                            Text("上传到远程")
                        }
                        .foregroundColor(.blue)
                    }
                    .disabled(localPath.isEmpty || remotePath.isEmpty || isUploading)

                    // 下载按钮
                    Button(action: downloadFile) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("下载到本地")
                        }
                        .foregroundColor(.green)
                    }
                    .disabled(localPath.isEmpty || remotePath.isEmpty || isUploading)
                }

                Section(header: Text("说明")) {
                    Text("文件传输通过 SFTP 协议进行。请确保设备支持 SFTP 连接，并且路径格式正确。")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("文件传输")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func uploadFile() {
        isUploading = true
        transferStatus = .uploading

        // 模拟上传过程
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isUploading = false
            transferStatus = .success

            // 3秒后重置状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                transferStatus = .idle
            }
        }
    }

    private func downloadFile() {
        isUploading = true
        transferStatus = .downloading

        // 模拟下载过程
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isUploading = false
            transferStatus = .success

            // 3秒后重置状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                transferStatus = .idle
            }
        }
    }
}

// MARK: - Add Cluster Device View
struct AddClusterDeviceView: View {
    @ObservedObject var viewModel: ClusterViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var host = ""
    @State private var port = "8765"
    @State private var deviceDescription = ""
    @State private var selectedMode: ConnectionMode = .shared

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本信息")) {
                    TextField("设备名称", text: $name)
                    TextField("主机地址", text: $host)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                    TextField("端口", text: $port)
                        .keyboardType(.numberPad)
                }

                Section(header: Text("连接模式")) {
                    Picker("模式", selection: $selectedMode) {
                        ForEach(ConnectionMode.allCases, id: \.self) { mode in
                            Text(mode.description).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                Section(header: Text("描述")) {
                    TextEditor(text: $deviceDescription)
                        .frame(height: 80)
                }
            }
            .navigationTitle("添加设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("添加") {
                        addDevice()
                    }
                    .disabled(name.isEmpty || host.isEmpty || port.isEmpty)
                }
            }
        }
    }

    private func addDevice() {
        guard let portNumber = Int(port) else { return }

        let device = ClusterDevice(
            name: name,
            host: host,
            port: portNumber,
            mode: selectedMode,
            description: deviceDescription.isEmpty ? nil : deviceDescription
        )

        viewModel.addDevice(device)
        dismiss()
    }
}
import SwiftUI
import UIKit

// Types from other files in the module
// ExecutionMode, AgentTask, TaskStatus, etc. are defined in AgentTaskModels.swift

struct MasterAgentView: View {
    @StateObject private var controller = MasterAgentController()
    @EnvironmentObject private var viewModel: ClusterViewModel

    @State private var inputText = ""
    @State private var selectedMode: ExecutionMode = .hybrid
    @State private var showingHistory = false
    @State private var showingAPISettings = false
    @Environment(\.dismiss) private var dismiss

    // API 配置
    @AppStorage("aiProvider") private var aiProvider: String = "deepSeek"
    @AppStorage("apiKey") private var apiKey: String = ""
    @AppStorage("customBaseURL") private var customBaseURL: String = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // 顶部导航
                topBar
                    .slideUp(delay: 0)

                // 输入区域
                inputSection
                    .slideUp(delay: AnimationDelay.stagger)

                // 执行模式选择
                modeSelector
                    .slideUp(delay: AnimationDelay.stagger * 2)

                // 当前任务状态
                if controller.isProcessing || controller.currentTask != nil {
                    taskStatusCard
                        .slideUp(delay: AnimationDelay.stagger * 3)
                }

                // 执行结果
                if let result = controller.currentTask?.finalOutput {
                    resultSection(result: result)
                        .slideUp(delay: AnimationDelay.stagger * 4)
                }

                Spacer(minLength: 50)
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $showingHistory) {
            TaskHistoryView(controller: controller)
        }
        .sheet(isPresented: $showingAPISettings, onDismiss: {
            // 当 API 设置关闭时，通知 controller 重新加载配置
            controller.reloadAPIConfig()
        }) {
            APISettingsView(
                provider: $aiProvider,
                apiKey: $apiKey,
                customBaseURL: $customBaseURL
            )
        }
        .onChange(of: apiKey) { _ in
            controller.reloadAPIConfig()
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Agent Team")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)

                Text("智能任务调度与执行")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            Spacer()

            // API 设置按钮
            Button(action: {
                HapticFeedback.light()
                showingAPISettings = true
            }) {
                Image(systemName: "key.fill")
                    .font(.title3)
                    .foregroundColor(apiKey.isEmpty ? .orange : .green)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .pressable(scale: 0.9)

            // 历史记录按钮
            Button(action: {
                HapticFeedback.light()
                showingHistory = true
            }) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .pressable(scale: 0.9)
        }
        .padding(.top, 50)
    }

    // MARK: - Input Section
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("任务描述")
                .font(.headline)
                .foregroundColor(.white)

            TextEditor(text: $inputText)
                .font(.body)
                .foregroundColor(.white)
                .padding(12)
                .frame(height: 120)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .scrollContentBackground(.hidden)

            // 示例提示
            HStack {
                Text("例如：")
                    .font(.caption)
                    .foregroundColor(.gray)

                Button("分析三个服务器的日志") {
                    inputText = "分析三个服务器的日志"
                }
                .font(.caption)
                .foregroundColor(.blue)

                Button("检查系统性能") {
                    inputText = "检查所有设备的系统性能"
                }
                .font(.caption)
                .foregroundColor(.blue)
            }

            // 执行按钮
            Button(action: executeTask) {
                HStack {
                    if controller.isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "play.fill")
                    }

                    Text(controller.isProcessing ? "执行中..." : "开始执行")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.blue.opacity(controller.isProcessing ? 0.5 : 0.8),
                            Color.purple.opacity(controller.isProcessing ? 0.3 : 0.6)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            .disabled(controller.isProcessing || inputText.isEmpty)
            .pressable(scale: 0.98)
        }
    }

    // MARK: - Mode Selector
    private var modeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("执行模式")
                .font(.headline)
                .foregroundColor(.white)

            HStack(spacing: 12) {
                ForEach(ExecutionMode.allCases, id: \.self) { mode in
                    ModeButton(
                        mode: mode,
                        isSelected: selectedMode == mode
                    ) {
                        withAnimation(.snappy) {
                            selectedMode = mode
                            HapticFeedback.selection()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Task Status Card
    private var taskStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                // 状态指示器
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)
                        .pulseEffect(active: controller.isProcessing, color: statusColor)

                    Text(controller.currentTask?.status.rawValue ?? "准备中")
                        .font(.subheadline)
                        .foregroundColor(statusColor)
                }

                Spacer()

                // 取消按钮
                if controller.isProcessing {
                    Button(action: {
                        controller.cancelCurrentTask()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }
            }

            // 进度条
            if let task = controller.currentTask,
               let plan = task.executionPlan {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(plan.subtasks.count) 个子任务")
                            .font(.caption)
                            .foregroundColor(.gray)

                        Spacer()

                        if !task.results.isEmpty {
                            Text("已完成 \(task.results.count)/\(plan.subtasks.count)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }

                    ProgressView(
                        value: Double(task.results.count),
                        total: Double(plan.subtasks.count)
                    )
                    .progressViewStyle(LinearProgressViewStyle(tint: statusColor))
                }
            }

            // 执行计划预览
            if let plan = controller.currentTask?.executionPlan {
                VStack(alignment: .leading, spacing: 8) {
                    Text("执行计划")
                        .font(.caption)
                        .foregroundColor(.gray)

                    HStack(spacing: 12) {
                        PlanBadge(
                            icon: "number",
                            text: "\(plan.subtasks.count) 步骤"
                        )

                        PlanBadge(
                            icon: "clock",
                            text: "~\(Int(plan.estimatedTotalDuration))s"
                        )

                        PlanBadge(
                            icon: "arrow.triangle.branch",
                            text: plan.executionStrategy.rawValue
                        )
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(statusColor.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Result Section
    private func resultSection(result: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("执行结果")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                // 复制按钮
                Button(action: {
                    UIPasteboard.general.string = result
                    HapticFeedback.success()
                }) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.gray)
                }
            }

            ScrollView {
                Text(result)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 400)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.3))
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Status Color
    private var statusColor: Color {
        guard let status = controller.currentTask?.status else {
            return .gray
        }

        switch status {
        case .pending:
            return .gray
        case .parsing, .planning, .dispatching:
            return .orange
        case .executing:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .gray
        }
    }

    // MARK: - Execute
    private func executeTask() {
        guard !inputText.isEmpty else { return }

        HapticFeedback.medium()

        Task {
            await controller.process(
                inputText,
                on: viewModel.devices,
                mode: selectedMode
            )
        }
    }
}

// MARK: - Mode Button
struct ModeButton: View {
    let mode: ExecutionMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.title3)

                Text(mode.displayName)
                    .font(.caption)
            }
            .foregroundColor(isSelected ? .white : .gray)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.blue.opacity(0.3) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.blue : Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
    }

}

// MARK: - Plan Badge
struct PlanBadge: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .foregroundColor(.white.opacity(0.7))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.1))
        )
    }
}

// MARK: - Task History View
struct TaskHistoryView: View {
    @ObservedObject var controller: MasterAgentController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if controller.taskHistory.isEmpty {
                    Section {
                        Text("暂无历史记录")
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    }
                } else {
                    ForEach(controller.taskHistory) { entry in
                        HistoryRow(entry: entry)
                    }
                }
            }
            .navigationTitle("任务历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空") {
                        controller.clearHistory()
                    }
                    .disabled(controller.taskHistory.isEmpty)
                }
            }
        }
    }
}

// MARK: - History Row
struct HistoryRow: View {
    let entry: TaskHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: entry.type.icon)
                    .foregroundColor(statusColor)

                Text(entry.type.rawValue)
                    .font(.caption)
                    .foregroundColor(.gray)

                Spacer()

                StatusBadge(status: entry.status)
            }

            Text(entry.input)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(2)

            HStack {
                Text(formattedDate(entry.createdAt))
                    .font(.caption2)
                    .foregroundColor(.gray)

                Spacer()

                if entry.deviceCount > 0 {
                    Text("\(entry.deviceCount) 设备")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch entry.status {
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .gray
        default:
            return .orange
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let status: TaskStatus

    var body: some View {
        Text(status.rawValue)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(color.opacity(0.2))
            )
            .foregroundColor(color)
    }

    private var color: Color {
        switch status {
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .gray
        default:
            return .orange
        }
    }
}

// MARK: - API Settings View
struct APISettingsView: View {
    @Binding var provider: String
    @Binding var apiKey: String
    @Binding var customBaseURL: String
    @Environment(\.dismiss) private var dismiss

    private let providers = ["openAI", "anthropic", "deepSeek", "local"]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("AI 提供商")) {
                    Picker("提供商", selection: $provider) {
                        Text("OpenAI").tag("openAI")
                        Text("Anthropic").tag("anthropic")
                        Text("DeepSeek").tag("deepSeek")
                        Text("本地模型").tag("local")
                    }
                    .pickerStyle(SegmentedPickerStyle())

                    if provider == "deepSeek" {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("推荐用于中文任务")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }

                if provider != "local" {
                    Section(header: Text("API Key"), footer: Text("您的 API Key 仅存储在本地设备上")) {
                        SecureField("输入 API Key", text: $apiKey)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()

                        if provider == "deepSeek" {
                            Link("获取 DeepSeek API Key", destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                                .font(.caption)
                        }
                    }

                    Section(header: Text("自定义 Base URL (可选)")) {
                        TextField("默认: \(defaultBaseURL)", text: $customBaseURL)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                }

                Section(header: Text("说明")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DeepSeek")
                            .font(.headline)
                        Text("• 支持中文，性价比高\n• 模型: deepseek-chat / deepseek-coder\n• 官网: platform.deepseek.com")
                            .font(.caption)
                            .foregroundColor(.gray)

                        Divider()

                        Text("OpenAI")
                            .font(.headline)
                        Text("• 功能强大，全球可用\n• 模型: gpt-4 / gpt-3.5-turbo")
                            .font(.caption)
                            .foregroundColor(.gray)

                        Divider()

                        Text("Anthropic")
                            .font(.headline)
                        Text("• 上下文长，推理能力强\n• 模型: claude-3-opus / claude-3-sonnet")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("API 设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var defaultBaseURL: String {
        switch provider {
        case "openAI":
            return "https://api.openai.com/v1"
        case "anthropic":
            return "https://api.anthropic.com/v1"
        case "deepSeek":
            return "https://api.deepseek.com/v1"
        default:
            return ""
        }
    }
}

// MARK: - Preview
struct MasterAgentView_Previews: PreviewProvider {
    static var previews: some View {
        MasterAgentView()
            .environmentObject(ClusterViewModel())
            .environmentObject(ClusterViewModel())
            .preferredColorScheme(.dark)
    }
}
import SwiftUI

struct FileBrowserView: View {
    let device: ClusterDevice
    @StateObject private var viewModel = FileBrowserViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var currentPath = "/"
    @State private var files: [RemoteFile] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pathHistory: [String] = ["/"]
    @State private var historyIndex = 0

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // 路径栏
                    pathBar

                    // 文件列表
                    if isLoading {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.5)
                        Spacer()
                    } else if let error = errorMessage {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 48))
                                .foregroundColor(.orange)
                            Text(error)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                            Button("重试") {
                                loadFiles(path: currentPath)
                            }
                            .foregroundColor(.blue)
                        }
                        Spacer()
                    } else if files.isEmpty {
                        Spacer()
                        Text("空文件夹")
                            .foregroundColor(.gray)
                        Spacer()
                    } else {
                        List {
                            ForEach(files) { file in
                                FileRow(file: file)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        handleFileTap(file)
                                    }
                            }
                        }
                        .listStyle(PlainListStyle())
                        .background(Color.black)
                    }

                    // 底部工具栏
                    bottomToolbar
                }
            }
            .navigationTitle("文件管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            // 新建文件夹
                        } label: {
                            Label("新建文件夹", systemImage: "folder.badge.plus")
                        }

                        Button {
                            // 上传文件
                        } label: {
                            Label("上传文件", systemImage: "arrow.up.doc")
                        }

                        Divider()

                        Button {
                            loadFiles(path: currentPath)
                        } label: {
                            Label("刷新", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear {
            loadFiles(path: currentPath)
        }
    }

    // MARK: - Path Bar
    private var pathBar: some View {
        HStack(spacing: 8) {
            // 后退按钮
            Button {
                goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(historyIndex > 0 ? .white : .gray)
            }
            .disabled(historyIndex <= 0)

            // 前进按钮
            Button {
                goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(historyIndex < pathHistory.count - 1 ? .white : .gray)
            }
            .disabled(historyIndex >= pathHistory.count - 1)

            // 上级目录按钮
            Button {
                goToParent()
            } label: {
                Image(systemName: "arrow.turn.up.left")
                    .foregroundColor(currentPath != "/" ? .white : .gray)
            }
            .disabled(currentPath == "/")

            // 路径显示
            ScrollView(.horizontal, showsIndicators: false) {
                Text(currentPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
    }

    // MARK: - Bottom Toolbar
    private var bottomToolbar: some View {
        HStack {
            Text("\(files.count) 个项目")
                .font(.caption)
                .foregroundColor(.gray)

            Spacer()

            Text(device.name)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
    }

    // MARK: - Actions
    private func loadFiles(path: String) {
        isLoading = true
        errorMessage = nil

        // 模拟文件列表加载
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.files = mockFiles(for: path)
            self.isLoading = false
        }
    }

    private func handleFileTap(_ file: RemoteFile) {
        if file.isDirectory {
            let newPath = currentPath == "/" ? "/\(file.name)" : "\(currentPath)/\(file.name)"

            // 添加到历史
            if historyIndex < pathHistory.count - 1 {
                pathHistory.removeSubrange((historyIndex + 1)...)
            }
            pathHistory.append(newPath)
            historyIndex += 1

            currentPath = newPath
            loadFiles(path: newPath)
        } else {
            // 打开文件
        }
    }

    private func goBack() {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        currentPath = pathHistory[historyIndex]
        loadFiles(path: currentPath)
    }

    private func goForward() {
        guard historyIndex < pathHistory.count - 1 else { return }
        historyIndex += 1
        currentPath = pathHistory[historyIndex]
        loadFiles(path: currentPath)
    }

    private func goToParent() {
        guard currentPath != "/" else { return }

        let parentPath: String
        if let lastSlash = currentPath.dropLast().lastIndex(of: "/") {
            let tempPath = String(currentPath[...lastSlash])
            parentPath = tempPath.isEmpty ? "/" : tempPath
        } else {
            parentPath = "/"
        }

        // 添加到历史
        if historyIndex < pathHistory.count - 1 {
            pathHistory.removeSubrange((historyIndex + 1)...)
        }
        pathHistory.append(parentPath)
        historyIndex += 1

        currentPath = parentPath
        loadFiles(path: parentPath)
    }

    // MARK: - Mock Data
    private func mockFiles(for path: String) -> [RemoteFile] {
        // 模拟文件列表
        var mockFiles: [RemoteFile] = []

        if path == "/" {
            mockFiles = [
                RemoteFile(name: "bin", isDirectory: true, size: 4096, modifiedDate: Date()),
                RemoteFile(name: "etc", isDirectory: true, size: 4096, modifiedDate: Date()),
                RemoteFile(name: "home", isDirectory: true, size: 4096, modifiedDate: Date()),
                RemoteFile(name: "usr", isDirectory: true, size: 4096, modifiedDate: Date()),
                RemoteFile(name: "var", isDirectory: true, size: 4096, modifiedDate: Date()),
                RemoteFile(name: "tmp", isDirectory: true, size: 4096, modifiedDate: Date()),
                RemoteFile(name: "boot", isDirectory: true, size: 4096, modifiedDate: Date()),
                RemoteFile(name: "README.txt", isDirectory: false, size: 1024, modifiedDate: Date())
            ]
        } else if path == "/home" {
            mockFiles = [
                RemoteFile(name: "user", isDirectory: true, size: 4096, modifiedDate: Date()),
                RemoteFile(name: "admin", isDirectory: true, size: 4096, modifiedDate: Date()),
                RemoteFile(name: "logs", isDirectory: true, size: 4096, modifiedDate: Date())
            ]
        } else {
            mockFiles = [
                RemoteFile(name: "documents", isDirectory: true, size: 4096, modifiedDate: Date()),
                RemoteFile(name: "downloads", isDirectory: true, size: 4096, modifiedDate: Date()),
                RemoteFile(name: "config.json", isDirectory: false, size: 2048, modifiedDate: Date()),
                RemoteFile(name: "script.sh", isDirectory: false, size: 512, modifiedDate: Date()),
                RemoteFile(name: "data.csv", isDirectory: false, size: 15360, modifiedDate: Date())
            ]
        }

        return mockFiles.sorted {
            if $0.isDirectory != $1.isDirectory {
                return $0.isDirectory // 文件夹排在前面
            }
            return $0.name < $1.name
        }
    }
}

// MARK: - Remote File Model
struct RemoteFile: Identifiable {
    let id = UUID()
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modifiedDate: Date

    var icon: String {
        if isDirectory {
            return "folder.fill"
        } else if name.hasSuffix(".json") || name.hasSuffix(".xml") {
            return "doc.text.fill"
        } else if name.hasSuffix(".sh") || name.hasSuffix(".py") || name.hasSuffix(".js") {
            return "terminal.fill"
        } else if name.hasSuffix(".jpg") || name.hasSuffix(".png") {
            return "photo.fill"
        } else {
            return "doc.fill"
        }
    }

    var iconColor: Color {
        if isDirectory {
            return .blue
        } else if name.hasSuffix(".sh") || name.hasSuffix(".py") {
            return .green
        } else if name.hasSuffix(".json") || name.hasSuffix(".xml") {
            return .orange
        } else if name.hasSuffix(".txt") || name.hasSuffix(".md") {
            return .white
        } else {
            return .gray
        }
    }

    var formattedSize: String {
        if isDirectory {
            return "--"
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: modifiedDate, relativeTo: Date())
    }
}

// MARK: - File Row
struct FileRow: View {
    let file: RemoteFile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.icon)
                .font(.title2)
                .foregroundColor(file.iconColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(.body)
                    .foregroundColor(.white)

                HStack(spacing: 8) {
                    Text(file.formattedSize)
                        .font(.caption)
                        .foregroundColor(.gray)

                    Text("•")
                        .font(.caption)
                        .foregroundColor(.gray)

                    Text(file.formattedDate)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            if file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 4)
        .background(Color.black)
    }
}

// MARK: - View Model
@MainActor
class FileBrowserViewModel: ObservableObject {
    // 后续可以添加真实的 SFTP/SSH 文件操作
}

// MARK: - Preview
struct FileBrowserView_Previews: PreviewProvider {
    static var previews: some View {
        FileBrowserView(device: ClusterDevice(
            name: "VPS",
            host: "123.207.187.104",
            port: 8766
        ))
    }
}
import SwiftUI
import Foundation

// MARK: - SFTP File Model
struct SFTPFile: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64
    let modificationDate: Date
    let permissions: String

    var icon: String {
        if isDirectory {
            return "folder.fill"
        } else if name.hasSuffix(".json") || name.hasSuffix(".xml") || name.hasSuffix(".plist") {
            return "doc.text.fill"
        } else if name.hasSuffix(".sh") || name.hasSuffix(".py") || name.hasSuffix(".js") || name.hasSuffix(".swift") {
            return "terminal.fill"
        } else if name.hasSuffix(".jpg") || name.hasSuffix(".jpeg") || name.hasSuffix(".png") || name.hasSuffix(".gif") {
            return "photo.fill"
        } else if name.hasSuffix(".mp4") || name.hasSuffix(".mov") || name.hasSuffix(".avi") {
            return "video.fill"
        } else if name.hasSuffix(".mp3") || name.hasSuffix(".wav") || name.hasSuffix(".aac") {
            return "music.note"
        } else if name.hasSuffix(".zip") || name.hasSuffix(".tar") || name.hasSuffix(".gz") || name.hasSuffix(".rar") {
            return "archivebox.fill"
        } else if name.hasSuffix(".pdf") {
            return "doc.text.fill"
        } else if name.hasSuffix(".doc") || name.hasSuffix(".docx") || name.hasSuffix(".txt") || name.hasSuffix(".md") {
            return "doc.fill"
        } else if name.hasSuffix(".xls") || name.hasSuffix(".xlsx") || name.hasSuffix(".csv") {
            return "tablecells.fill"
        } else if name.hasSuffix(".app") || name.hasSuffix(".exe") || name.hasSuffix(".dmg") {
            return "app.fill"
        } else {
            return "doc.fill"
        }
    }

    var iconColor: Color {
        if isDirectory {
            return .blue
        } else if name.hasSuffix(".sh") || name.hasSuffix(".py") || name.hasSuffix(".swift") {
            return .green
        } else if name.hasSuffix(".json") || name.hasSuffix(".xml") {
            return .orange
        } else if name.hasSuffix(".jpg") || name.hasSuffix(".png") {
            return .purple
        } else if name.hasSuffix(".mp4") || name.hasSuffix(".mov") {
            return .red
        } else if name.hasSuffix(".zip") || name.hasSuffix(".tar") || name.hasSuffix(".gz") {
            return .yellow
        } else if name.hasSuffix(".txt") || name.hasSuffix(".md") || name.hasSuffix(".pdf") {
            return .white
        } else {
            return .gray
        }
    }

    var formattedSize: String {
        if isDirectory {
            return "--"
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: modificationDate, relativeTo: Date())
    }

    var isExecutable: Bool {
        return permissions.contains("x")
    }

    var isHidden: Bool {
        return name.hasPrefix(".")
    }
}

// MARK: - SFTP Manager
@MainActor
class SFTPManager: ObservableObject {
    @Published var files: [SFTPFile] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentPath: String = "/"
    @Published var connectionState: ConnectionState = .disconnected

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    private var session: NMSSHSession?
    private var sftp: NMSFTP?
    private let device: ClusterDevice
    private let configService = BridgeConfigService.shared
    private var bridgeConfig: BridgeConfig?

    // 凭据存储键（作为 Bridge 配置的后备）
    private var usernameKey: String { "sftp_username_\(device.id.uuidString)" }
    private var passwordKey: String { "sftp_password_\(device.id.uuidString)" }

    init(device: ClusterDevice) {
        self.device = device
    }

    deinit {
        // 直接断开连接，不要在 deinit 中创建 Task
        sftp?.disconnect()
        session?.disconnect()
    }

    // MARK: - 连接状态

    var isConnected: Bool {
        return connectionState.isConnected
    }

    // MARK: - 连接方法

    /// 主连接方法：优先使用 Bridge 配置，其次本地凭据，最后手动输入
    func connect() async -> Bool {
        connectionState = .connecting

        // 1. 尝试使用 Bridge 配置连接
        if await connectWithBridgeConfig() {
            return true
        }

        // 2. 尝试使用本地保存的凭据连接
        if await connectWithSavedCredentials() {
            return true
        }

        // 3. 需要手动输入
        connectionState = .disconnected
        return false
    }

    /// 使用 Bridge 配置连接
    func connectWithBridgeConfig() async -> Bool {
        print("🔌 Attempting Bridge config connection for \(device.name)...")

        do {
            // 获取配置（优先网络，其次缓存）
            let config: BridgeConfig
            do {
                config = try await configService.fetchConfig(from: device, preferCache: true)
            } catch {
                // 网络失败，尝试缓存
                guard let cached = configService.getCachedConfig(for: device.id) else {
                    print("⚠️ No Bridge config available for \(device.name)")
                    return false
                }
                config = cached
                print("📦 Using cached Bridge config for \(device.name)")
            }

            guard config.ssh.enabled else {
                errorMessage = "SSH 未在 Bridge 配置中启用"
                print("⚠️ SSH disabled in Bridge config")
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
                print("✅ Connected via Bridge config")
                return true
            }

            return false
        } catch {
            print("❌ Bridge config connection failed: \(error.localizedDescription)")
            return false
        }
    }

    /// 使用本地保存的凭据连接（后备方案）
    func connectWithSavedCredentials() async -> Bool {
        guard let username = savedUsername,
              let password = UserDefaults.standard.string(forKey: passwordKey) else {
            return false
        }

        print("🔌 Attempting connection with saved credentials...")

        let success = await connectSSH(
            host: device.host,
            port: 22,
            username: username,
            password: password
        )

        if success {
            print("✅ Connected with saved credentials")
        }

        return success
    }

    /// 手动输入凭据连接
    func connect(username: String, password: String, saveCredentials: Bool = true) async -> Bool {
        if saveCredentials {
            saveCredentialsToStorage(username: username, password: password)
        }

        return await connectSSH(
            host: device.host,
            port: 22,
            username: username,
            password: password
        )
    }

    /// 尝试自动连接（综合策略）
    func autoConnect() async -> Bool {
        return await connect()
    }

    // MARK: - 私有连接方法

    private func connectSSH(host: String, port: Int, username: String, password: String?) async -> Bool {
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let session = NMSSHSession(host: host, port: port, andUsername: username)

                session.connect()

                if session.isConnected {
                    if let password = password {
                        session.authenticate(byPassword: password)
                    }
                }

                if session.isConnected && session.isAuthorized {
                    let sftp = NMSFTP.connect(with: session)

                    DispatchQueue.main.async {
                        self.session = session
                        self.sftp = sftp
                        self.isLoading = false
                        self.connectionState = .connected
                        continuation.resume(returning: sftp != nil)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.errorMessage = "连接失败，请检查用户名和密码"
                        self.connectionState = .failed("认证失败")
                        session.disconnect()
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }

    // MARK: - 凭据管理

    /// 检查是否有保存的凭据（本地或 Bridge）
    var hasSavedCredentials: Bool {
        // 检查 Bridge 缓存
        if configService.isCacheValid(for: device.id) {
            return true
        }
        // 检查本地凭据
        return UserDefaults.standard.string(forKey: usernameKey) != nil
    }

    /// 获取保存的用户名
    var savedUsername: String? {
        // 优先从 Bridge 配置获取
        if let config = configService.getCachedConfig(for: device.id) {
            return config.ssh.username
        }
        // 其次从本地获取
        return UserDefaults.standard.string(forKey: usernameKey)
    }

    /// 保存凭据到本地存储
    func saveCredentialsToStorage(username: String, password: String) {
        UserDefaults.standard.set(username, forKey: usernameKey)
        UserDefaults.standard.set(password, forKey: passwordKey)
    }

    /// 清除所有保存的凭据（本地和 Bridge 缓存）
    func clearSavedCredentials() {
        UserDefaults.standard.removeObject(forKey: usernameKey)
        UserDefaults.standard.removeObject(forKey: passwordKey)
        configService.clearCache(for: device.id)
        bridgeConfig = nil
    }

    func disconnect() {
        sftp?.disconnect()
        session?.disconnect()
        sftp = nil
        session = nil
    }

    func listDirectory(path: String) async {
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }

        guard let sftp = sftp else {
            await MainActor.run {
                self.errorMessage = "未连接到服务器"
                self.isLoading = false
            }
            return
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let contents = sftp.contentsOfDirectory(atPath: path)

                var files: [SFTPFile] = []

                for sftpFile in contents ?? [] {
                    let fullPath = (path as NSString).appendingPathComponent(sftpFile.filename)

                    let file = SFTPFile(
                        name: sftpFile.filename,
                        path: fullPath,
                        isDirectory: sftpFile.isDirectory,
                        size: sftpFile.fileSize?.int64Value ?? 0,
                        modificationDate: sftpFile.modificationDate ?? Date(),
                        permissions: sftpFile.permissions ?? "----------"
                    )
                    files.append(file)
                }

                // 排序：文件夹在前，然后按名称排序
                files.sort {
                    if $0.isDirectory != $1.isDirectory {
                        return $0.isDirectory
                    }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }

                DispatchQueue.main.async {
                    self.files = files
                    self.currentPath = path
                    self.isLoading = false
                    continuation.resume()
                }
            }
        }
    }

    func downloadFile(_ file: SFTPFile, to localPath: URL) async -> Bool {
        // 使用 SFTP 下载文件 - 需要实现
        return false
    }

    func uploadFile(from localPath: URL, to remotePath: String) async -> Bool {
        guard let sftp = sftp else { return false }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let success = sftp.writeFile(atPath: localPath.path, toFileAtPath: remotePath)
                DispatchQueue.main.async {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func deleteFile(_ file: SFTPFile) async -> Bool {
        guard let sftp = sftp else { return false }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let success: Bool
                if file.isDirectory {
                    success = sftp.removeDirectory(atPath: file.path)
                } else {
                    success = sftp.removeFile(atPath: file.path)
                }
                DispatchQueue.main.async {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func createDirectory(name: String, at path: String) async -> Bool {
        guard let sftp = sftp else { return false }

        let fullPath = (path as NSString).appendingPathComponent(name)

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let success = sftp.createDirectory(atPath: fullPath)
                DispatchQueue.main.async {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func readFileContent(_ file: SFTPFile) async -> String? {
        guard let sftp = sftp else { return nil }

        // 文件大小限制：1MB
        let maxFileSize = 1 * 1024 * 1024
        if file.size > maxFileSize {
            await MainActor.run {
                self.errorMessage = "文件过大（>1MB），无法预览"
            }
            return nil
        }

        // 简单实现：直接读取文件内容
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                // 使用 NMSFTP 的 contentsAtPath 方法读取文件
                let data = sftp.contents(atPath: file.path)

                var content: String? = nil
                if let data = data {
                    // 尝试 UTF-8 编码
                    if let utf8String = String(data: data, encoding: .utf8) {
                        content = utf8String
                    } else if let asciiString = String(data: data, encoding: .ascii) {
                        // 回退到 ASCII
                        content = asciiString
                    } else if let latinString = String(data: data, encoding: .isoLatin1) {
                        // 最后尝试 Latin-1
                        content = latinString
                    }
                }

                DispatchQueue.main.async {
                    continuation.resume(returning: content)
                }
            }
        }
    }
}

// MARK: - SFTP File Browser View
struct SFTPFileBrowserView: View {
    let device: ClusterDevice
    @StateObject private var viewModel: SFTPManager
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var isConnected = false
    @State private var showingLogin = true
    @State private var pathHistory: [String] = ["/"]
    @State private var historyIndex = 0
    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var selectedFile: SFTPFile?
    @State private var showingFileDetail = false
    @State private var showingDeleteConfirm = false
    @State private var showingTextViewer = false
    @State private var textContent: String = ""
    @State private var isHandlingTap = false  // 防抖标记

    init(device: ClusterDevice) {
        self.device = device
        _viewModel = StateObject(wrappedValue: SFTPManager(device: device))
    }

    @State private var isAutoConnecting = false
    @State private var autoConnectError: String?
    @State private var showingAutoConnectError = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if isAutoConnecting {
                    autoConnectingView
                } else if showingLogin {
                    loginView
                } else if isConnected {
                    fileBrowserView
                }
            }
            .navigationTitle("文件管理 - \(device.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        viewModel.disconnect()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // 尝试自动连接
            Task {
                await attemptAutoConnect()
            }
        }
        .onDisappear {
            // 重置防抖标记，防止下次打开时卡住
            isHandlingTap = false
        }
        .sheet(isPresented: $showingFileDetail) {
            if let file = selectedFile {
                FileDetailView(file: file, viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showingTextViewer) {
            TextFileViewer(content: textContent, filename: selectedFile?.name ?? "")
        }
        .alert("新建文件夹", isPresented: $showingNewFolder) {
            TextField("文件夹名称", text: $newFolderName)
            Button("取消", role: .cancel) {}
            Button("创建") {
                Task {
                    if await viewModel.createDirectory(name: newFolderName, at: viewModel.currentPath) {
                        await viewModel.listDirectory(path: viewModel.currentPath)
                    }
                    newFolderName = ""
                }
            }
        }
        .alert("连接失败", isPresented: $showingAutoConnectError) {
            Button("确定") {}
        } message: {
            Text(autoConnectError ?? "无法自动连接到服务器")
        }
        .alert("删除确认", isPresented: $showingDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task {
                    if let file = selectedFile {
                        if await viewModel.deleteFile(file) {
                            await viewModel.listDirectory(path: viewModel.currentPath)
                        }
                    }
                }
            }
        } message: {
            Text("确定要删除 \"\(selectedFile?.name ?? "")\" 吗？此操作不可撤销。")
        }
    }

    // MARK: - Auto Connect

    private func attemptAutoConnect() async {
        isAutoConnecting = true
        defer { isAutoConnecting = false }

        // 尝试自动连接（Bridge 配置或本地凭据）
        let success = await viewModel.connect()

        if success {
            isConnected = true
            showingLogin = false
            await viewModel.listDirectory(path: "/")
        } else {
            // 显示登录界面
            showingLogin = true
            // 预填充用户名
            if let savedUsername = viewModel.savedUsername {
                username = savedUsername
            }
        }
    }

    // MARK: - Auto Connecting View

    private var autoConnectingView: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))

            Text("正在连接 \(device.name)...")
                .font(.headline)
                .foregroundColor(.gray)

            if BridgeConfigService.shared.isCacheValid(for: device.id) {
                Text("使用缓存配置")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            Spacer()
        }
    }

    // MARK: - Login View
    @State private var rememberCredentials = true

    private var loginView: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.fill.badge.person.crop")
                .font(.system(size: 64))
                .foregroundColor(.blue)

            Text("连接到 \(device.name)")
                .font(.title2)
                .fontWeight(.bold)

            VStack(spacing: 16) {
                TextField("用户名", text: $username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                SecureField("密码", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Toggle("记住密码", isOn: $rememberCredentials)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal)

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Button {
                Task {
                    let success = await viewModel.connect(username: username, password: password, saveCredentials: rememberCredentials)
                    if success {
                        isConnected = true
                        showingLogin = false
                        await viewModel.listDirectory(path: "/")
                    }
                }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("连接")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(username.isEmpty || password.isEmpty || viewModel.isLoading)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 50)
        .onAppear {
            // 预填充保存的用户名
            if let savedUsername = viewModel.savedUsername {
                username = savedUsername
            }
        }
    }

    // MARK: - File Browser View
    private var fileBrowserView: some View {
        VStack(spacing: 0) {
            // 路径导航栏
            pathNavigationBar

            // 文件列表
            if viewModel.isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.5)
                Spacer()
            } else if let error = viewModel.errorMessage {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        Task {
                            await viewModel.listDirectory(path: viewModel.currentPath)
                        }
                    }
                    .foregroundColor(.blue)
                }
                Spacer()
            } else {
                List {
                    // 上级目录
                    if viewModel.currentPath != "/" {
                        Button {
                            goToParent()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("上级目录")
                                        .font(.body)
                                        .foregroundColor(.white)
                                    Text("..")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }

                    ForEach(viewModel.files) { file in
                        SFTPFileRow(file: file)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                handleFileTap(file)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    selectedFile = file
                                    showingDeleteConfirm = true
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }

                                Button {
                                    selectedFile = file
                                    showingFileDetail = true
                                } label: {
                                    Label("详情", systemImage: "info.circle")
                                }
                                .tint(.blue)
                            }
                    }
                }
                .listStyle(PlainListStyle())
                .background(Color.black)
            }

            // 底部状态栏
            bottomStatusBar
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingNewFolder = true
                    } label: {
                        Label("新建文件夹", systemImage: "folder.badge.plus")
                    }

                    Button {
                        Task {
                            await viewModel.listDirectory(path: viewModel.currentPath)
                        }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }

                    Divider()

                    Button(role: .destructive) {
                        viewModel.disconnect()
                        viewModel.clearSavedCredentials()
                        isConnected = false
                        username = ""
                        password = ""
                        showingLogin = true
                    } label: {
                        Label("断开并清除密码", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - Path Navigation Bar
    private var pathNavigationBar: some View {
        HStack(spacing: 8) {
            Button {
                goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(historyIndex > 0 ? .white : .gray)
            }
            .disabled(historyIndex <= 0)

            Button {
                goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(historyIndex < pathHistory.count - 1 ? .white : .gray)
            }
            .disabled(historyIndex >= pathHistory.count - 1)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(viewModel.currentPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
    }

    // MARK: - Bottom Status Bar
    private var bottomStatusBar: some View {
        HStack {
            Text("\(viewModel.files.count) 个项目")
                .font(.caption)
                .foregroundColor(.gray)

            Spacer()

            Text(device.host)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
    }

    // MARK: - Actions
    private func handleFileTap(_ file: SFTPFile) {
        // 防抖：如果正在处理点击，忽略此次点击
        guard !isHandlingTap else { return }
        isHandlingTap = true

        // 延迟重置防抖标记
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isHandlingTap = false
        }

        if file.isDirectory {
            let newPath = file.path

            // 添加到历史
            if historyIndex < pathHistory.count - 1 {
                pathHistory.removeSubrange((historyIndex + 1)...)
            }
            pathHistory.append(newPath)
            historyIndex += 1

            Task {
                await viewModel.listDirectory(path: newPath)
            }
        } else {
            selectedFile = file

            // 检查是否是文本文件
            let textExtensions = [".txt", ".md", ".json", ".xml", ".plist", ".sh", ".py", ".js", ".swift", ".html", ".css", ".log", ".conf", ".ini", ".yaml", ".yml", ".csv"]
            let isTextFile = textExtensions.contains { file.name.lowercased().hasSuffix($0) }

            if isTextFile {
                Task {
                    if let content = await viewModel.readFileContent(file) {
                        textContent = content
                        showingTextViewer = true
                    } else {
                        showingFileDetail = true
                    }
                }
            } else {
                showingFileDetail = true
            }
        }
    }

    private func goBack() {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        let path = pathHistory[historyIndex]
        Task {
            await viewModel.listDirectory(path: path)
        }
    }

    private func goForward() {
        guard historyIndex < pathHistory.count - 1 else { return }
        historyIndex += 1
        let path = pathHistory[historyIndex]
        Task {
            await viewModel.listDirectory(path: path)
        }
    }

    private func goToParent() {
        guard viewModel.currentPath != "/" else { return }

        let parentPath = (viewModel.currentPath as NSString).deletingLastPathComponent
        let finalPath = parentPath.isEmpty ? "/" : parentPath

        // 添加到历史
        if historyIndex < pathHistory.count - 1 {
            pathHistory.removeSubrange((historyIndex + 1)...)
        }
        pathHistory.append(finalPath)
        historyIndex += 1

        Task {
            await viewModel.listDirectory(path: finalPath)
        }
    }
}

// MARK: - SFTP File Row
struct SFTPFileRow: View {
    let file: SFTPFile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.icon)
                .font(.title2)
                .foregroundColor(file.iconColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(file.name)
                        .font(.body)
                        .foregroundColor(file.isHidden ? .gray : .white)

                    if file.isHidden {
                        Text("隐藏")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.3))
                            .cornerRadius(4)
                            .foregroundColor(.gray)
                    }
                }

                HStack(spacing: 8) {
                    Text(file.formattedSize)
                        .font(.caption)
                        .foregroundColor(.gray)

                    Text("•")
                        .font(.caption)
                        .foregroundColor(.gray)

                    Text(file.formattedDate)
                        .font(.caption)
                        .foregroundColor(.gray)

                    if file.isExecutable && !file.isDirectory {
                        Text("可执行")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.3))
                            .cornerRadius(4)
                            .foregroundColor(.green)
                    }
                }
            }

            Spacer()

            if file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 4)
        .background(Color.black)
    }
}

// MARK: - File Detail View
struct FileDetailView: View {
    let file: SFTPFile
    let viewModel: SFTPManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("基本信息") {
                    LabeledContent("名称") {
                        Text(file.name)
                            .lineLimit(1)
                    }

                    LabeledContent("路径") {
                        Text(file.path)
                            .font(.caption)
                            .lineLimit(2)
                    }

                    LabeledContent("类型") {
                        Text(file.isDirectory ? "文件夹" : "文件")
                    }

                    LabeledContent("大小") {
                        Text(file.formattedSize)
                    }

                    LabeledContent("修改时间") {
                        Text(file.formattedDate)
                    }

                    LabeledContent("权限") {
                        Text(file.permissions)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                Section("操作") {
                    Button {
                        // 下载文件
                    } label: {
                        Label("下载到本地", systemImage: "arrow.down.circle")
                    }

                    if !file.isDirectory {
                        Button {
                            // 分享文件
                        } label: {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .navigationTitle("文件详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Text File Viewer
struct TextFileViewer: View {
    let content: String
    let filename: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black)
            .navigationTitle(filename)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        UIPasteboard.general.string = content
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
        }
    }
}

// MARK: - Preview
struct SFTPFileBrowserView_Previews: PreviewProvider {
    static var previews: some View {
        SFTPFileBrowserView(device: ClusterDevice(
            name: "VPS",
            host: "123.207.187.104",
            port: 22
        ))
    }
}
