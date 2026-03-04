import SwiftUI
import Combine

// MARK: - 设备模型
struct Device: Identifiable, Codable {
    let id = UUID()
    var name: String
    var host: String
    var port: Int
    var username: String
    var password: String
}

// MARK: - 设备管理器
@MainActor
class DeviceManager: ObservableObject {
    @Published var devices: [Device] = []
    @Published var deviceStatuses: [UUID: DeviceStatusCheckResult] = [:]
    @Published var isRefreshing = false

    private let statusMonitor = DeviceStatusMonitor()
    private var cancellables = Set<AnyCancellable>()

    init() {
        loadDevices()
        setupBindings()
    }

    private func setupBindings() {
        statusMonitor.$deviceStatuses
            .receive(on: DispatchQueue.main)
            .sink { [weak self] statuses in
                self?.deviceStatuses = statuses
            }
            .store(in: &cancellables)
    }

    // MARK: - 数据持久化
    func loadDevices() {
        if let data = UserDefaults.standard.data(forKey: "devices"),
           let decoded = try? JSONDecoder().decode([Device].self, from: data) {
            devices = decoded
        }
    }

    func saveDevices() {
        if let encoded = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(encoded, forKey: "devices")
        }
    }

    // MARK: - 设备管理
    func addDevice(_ device: Device) {
        devices.append(device)
        saveDevices()

        // 开始监控新设备
        let clusterDevice = ClusterDevice(
            id: device.id,
            name: device.name,
            host: device.host,
            port: device.port,
            status: .offline,
            mode: .shared,
            capabilities: [.terminal]
        )
        statusMonitor.startMonitoring(device: clusterDevice)
    }

    func removeDevice(at offsets: IndexSet) {
        for index in offsets {
            let device = devices[index]
            statusMonitor.stopMonitoring(deviceId: device.id)
            deviceStatuses.removeValue(forKey: device.id)
        }
        devices.remove(atOffsets: offsets)
        saveDevices()
    }

    func updateDevice(_ device: Device) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
            saveDevices()
        }
    }

    // MARK: - 状态检查
    func checkAllDevices() async {
        isRefreshing = true
        defer { isRefreshing = false }

        let clusterDevices = devices.map { device in
            ClusterDevice(
                id: device.id,
                name: device.name,
                host: device.host,
                port: device.port,
                status: .offline,
                mode: .shared,
                capabilities: [.terminal]
            )
        }

        await statusMonitor.checkDevices(clusterDevices)
    }

    func checkDevice(_ device: Device) async {
        let clusterDevice = ClusterDevice(
            id: device.id,
            name: device.name,
            host: device.host,
            port: device.port,
            status: .offline,
            mode: .shared,
            capabilities: [.terminal]
        )

        _ = await statusMonitor.checkDevice(clusterDevice)
    }

    // MARK: - 状态查询
    func status(for deviceId: UUID) -> DeviceStatus {
        guard let result = deviceStatuses[deviceId] else {
            return .offline
        }
        return result.isOnline ? .online : .offline
    }

    func latency(for deviceId: UUID) -> String {
        guard let result = deviceStatuses[deviceId],
              let latency = result.latency else {
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

    func lastChecked(for deviceId: UUID) -> Date? {
        return deviceStatuses[deviceId]?.timestamp
    }

    // MARK: - 启动监控
    func startMonitoringAllDevices() {
        for device in devices {
            let clusterDevice = ClusterDevice(
                id: device.id,
                name: device.name,
                host: device.host,
                port: device.port,
                status: .offline,
                mode: .shared,
                capabilities: [.terminal]
            )
            statusMonitor.startMonitoring(device: clusterDevice)
        }
    }

    func stopMonitoringAllDevices() {
        for device in devices {
            statusMonitor.stopMonitoring(deviceId: device.id)
        }
    }
}

// MARK: - 设备列表视图
struct DeviceListView: View {
    @StateObject private var deviceManager = DeviceManager()
    @State private var showingAddDevice = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                Spacer().frame(height: 50)

                // 标题栏
                HStack {
                    Text("设备管理")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Spacer()

                    // 刷新按钮
                    Button(action: {
                        HapticFeedback.light()
                        Task {
                            await deviceManager.checkAllDevices()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                            .rotationEffect(.degrees(deviceManager.isRefreshing ? 360 : 0))
                            .animation(deviceManager.isRefreshing ? .spin : .default, value: deviceManager.isRefreshing)
                    }
                    .disabled(deviceManager.isRefreshing)
                    .pressable(scale: 0.9)

                    // 添加按钮
                    Button(action: {
                        HapticFeedback.medium()
                        showingAddDevice = true
                    }) {
                        Image(systemName: "plus")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue.opacity(0.7), Color.blue.opacity(0.5)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Circle())
                            .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .pressable(scale: 0.9)
                }
                .padding(.horizontal)
                .slideUp(delay: 0)

                // 设备列表
                if deviceManager.devices.isEmpty {
                    EmptyDeviceView()
                        .scaleIn(delay: AnimationDelay.stagger)
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(deviceManager.devices.enumerated()), id: \.element.id) { index, device in
                            DeviceRow(
                                device: device,
                                status: deviceManager.status(for: device.id),
                                latency: deviceManager.latency(for: device.id),
                                lastChecked: deviceManager.lastChecked(for: device.id)
                            )
                            .slideUp(delay: Double(index) * AnimationDelay.card)
                        }
                        .onDelete { offsets in
                            withAnimation(.bouncy) {
                                HapticFeedback.warning()
                                deviceManager.removeDevice(at: offsets)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer(minLength: 50)
            }
        }
        .sheet(isPresented: $showingAddDevice) {
            Text("Add Device View")
        }
        .onAppear {
            deviceManager.startMonitoringAllDevices()
            // 立即检查一次
            Task {
                await deviceManager.checkAllDevices()
            }
        }
        .onDisappear {
            deviceManager.stopMonitoringAllDevices()
        }
    }
}

// MARK: - 空设备视图
struct EmptyDeviceView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 20) {
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 100, height: 100)
                .overlay(
                    Image(systemName: "server.rack")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                )
                .scaleEffect(isAnimating ? 1.05 : 1)
                .animation(.gentle.repeatForever(autoreverses: true), value: isAnimating)

            Text("暂无设备")
                .font(.title3)
                .foregroundColor(.white)

            Text("点击右上角 + 添加服务器")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .padding(.top, 100)
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - 设备行
struct DeviceRow: View {
    let device: Device
    let status: DeviceStatus
    let latency: String
    let lastChecked: Date?

    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 16) {
            // 设备图标
            ZStack {
                Circle()
                    .fill(status.color.opacity(0.2))
                    .frame(width: 50, height: 50)

                Image(systemName: "server.rack")
                    .font(.title2)
                    .foregroundColor(status.color)

                // 在线脉冲效果
                if status == .online {
                    Circle()
                        .stroke(status.color, lineWidth: 2)
                        .frame(width: 50, height: 50)
                        .scaleEffect(1.3)
                        .opacity(0)
                        .pulseEffect(active: true, color: status.color)
                }
            }

            // 设备信息
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                    .foregroundColor(.white)

                Text("\(device.host):\(device.port)")
                    .font(.caption)
                    .foregroundColor(.gray)

                if let lastChecked = lastChecked {
                    Text("检查于: \(formattedTime(lastChecked))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // 状态指示器
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 8, height: 8)

                    Text(status.rawValue)
                        .font(.caption)
                        .foregroundColor(status.color)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(status.color.opacity(0.15))
                )

                if status == .online {
                    Text(latency)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .scaleEffect(isPressed ? 0.98 : 1)
        .onTapGesture {
            withAnimation(.snappy) {
                isPressed = true
            }
            HapticFeedback.light()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.snappy) {
                    isPressed = false
                }
            }
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - 预览
struct DeviceListView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceListView()
            .preferredColorScheme(.dark)
    }
}
