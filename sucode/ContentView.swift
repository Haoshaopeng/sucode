import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var previousTab = 0
    @State private var isRestoringSession = true

    let tabs = [
        (icon: "square.grid.2x2.fill", title: "首页"),
        (icon: "server.rack", title: "设备"),
        (icon: "cpu", title: "Agent Team"),
        (icon: "bubble.left.and.bubble.right.fill", title: "AI助手"),
        (icon: "gearshape.fill", title: "设置")
    ]

    var body: some View {
        ZStack {
            // 全屏背景渐变 - 忽略所有安全区域
            AnimatedBackground()

            // 内容区域
            VStack(spacing: 0) {
                // 主内容 - 带切换动画
                contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // 自定义底部导航栏
                customTabBar
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .ignoresSafeArea(.all)
        .preferredColorScheme(.dark)
        .statusBar(hidden: false)
        .onAppear {
            restoreSession()
        }
        .onChange(of: selectedTab) { _ in
            saveSessionState()
        }
    }

    /// 恢复上次会话状态
    private func restoreSession() {
        let persistence = DataPersistenceManager.shared

        // 恢复上次选中的 Tab
        let savedTab: Int = persistence.lastSelectedTab
        if savedTab >= 0 && savedTab < tabs.count {
            selectedTab = savedTab
            previousTab = savedTab
        }

        // 恢复上次选中的设备（在设备视图中处理）
        // 恢复未完成的批量命令
        Task {
            await restoreIncompleteBatchCommands()
        }

        isRestoringSession = false
    }

    /// 保存当前会话状态
    private func saveSessionState() {
        let persistence = DataPersistenceManager.shared
        let newTab: Int = selectedTab
        persistence.lastSelectedTab = newTab
    }

    /// 恢复未完成的批量命令
    private func restoreIncompleteBatchCommands() async {
        do {
            let incompleteSessions = try await PersistenceManager.shared.fetchIncompleteBatchSessions()
            if !incompleteSessions.isEmpty {
                print("发现 \(incompleteSessions.count) 个未完成的批量命令会话")
                // 这里可以通知用户或自动恢复
            }
        } catch {
            print("恢复批量命令失败: \(error)")
        }
    }

    @ViewBuilder
    private var contentView: some View {
        let direction: PageTransitionDirection = selectedTab > previousTab ? .right : .left

        switch selectedTab {
        case 0:
            DashboardView()
                .pageTransition(direction)
                .id("dashboard_\(selectedTab)")
        case 1:
            DeviceListView()
                .pageTransition(direction)
                .id("devices_\(selectedTab)")
        case 2:
            AIClusterView()
                .pageTransition(direction)
                .id("cluster_\(selectedTab)")
                .environmentObject(ClusterViewModel())
        case 3:
            AIChatView()
                .pageTransition(direction)
                .id("chat_\(selectedTab)")
        case 4:
            SettingsView()
                .pageTransition(direction)
                .id("settings_\(selectedTab)")
        default:
            DashboardView()
                .pageTransition(direction)
        }
    }

    private var customTabBar: some View {
        HStack(spacing: 0) {
            ForEach(0..<tabs.count, id: \.self) { index in
                TabBarItem(
                    icon: tabs[index].icon,
                    title: tabs[index].title,
                    isSelected: selectedTab == index,
                    index: index
                ) {
                    withAnimation(.snappy) {
                        previousTab = selectedTab
                        selectedTab = index
                        HapticFeedback.selection()
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 30)
        .background(
            // 玻璃拟态背景
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0),
                    Color.black.opacity(0.3)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

// MARK: - TabBar Item
struct TabBarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let index: Int
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            HapticFeedback.light()
            action()
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .symbolVariant(isSelected ? .fill : .none)

                Text(title)
                    .font(.caption2)
            }
            .foregroundColor(isSelected ? .white : .gray.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                // 选中时的背景效果
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
                    .scaleEffect(isSelected ? 1 : 0.8)
                    .opacity(isSelected ? 1 : 0)
            )
        }
        .scaleEffect(isPressed ? 0.9 : 1)
        .animation(.snappy, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    isPressed = true
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
    }
}

// MARK: - 动态背景
struct AnimatedBackground: View {
    @State private var animateGradient = false

    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.1, green: 0.05, blue: 0.2),
                Color(red: 0.05, green: 0.05, blue: 0.15),
                Color(red: 0.02, green: 0.02, blue: 0.08)
            ],
            startPoint: animateGradient ? .topLeading : .bottomLeading,
            endPoint: animateGradient ? .bottomTrailing : .topTrailing
        )
        .ignoresSafeArea(.all)
        .onAppear {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
}

// MARK: - 首页视图
struct DashboardView: View {
    @State private var isLoaded = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // 从状态栏下方开始
                Spacer().frame(height: 50)

                // 标题区域 - 交错动画
                headerView
                    .slideUp(delay: 0)

                // 统计卡片 - 玻璃拟态效果
                statusCard
                    .slideUp(delay: AnimationDelay.stagger)

                // 快捷操作
                quickActionsView
                    .slideUp(delay: AnimationDelay.stagger * 2)

                Spacer(minLength: 50)
            }
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("sucode")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                Text("远程服务器管理")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            Spacer()
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: "person.fill").foregroundColor(.white))
                .pressable(scale: 0.95)
        }
        .padding(.horizontal)
    }

    private var statusCard: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .frame(height: 140)
            .overlay(
                VStack(spacing: 16) {
                    HStack {
                        HStack(spacing: 6) {
                            // 脉冲效果表示在线
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                                .pulseEffect(active: true, color: .green)
                            Text("系统在线")
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.2))
                        )
                        Spacer()
                    }
                    HStack {
                        StatItem(value: "3", label: "设备")
                        StatItem(value: "1", label: "连接")
                        StatItem(value: "28", label: "命令")
                    }
                }
                .padding(20)
            )
            .padding(.horizontal)
            .glassmorphism(cornerRadius: 20)
    }

    private var quickActionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷操作")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal)

            HStack(spacing: 12) {
                ActionItem(icon: "plus.circle.fill", title: "添加", color: .blue)
                ActionItem(icon: "terminal.fill", title: "SSH", color: .green)
                ActionItem(icon: "clock.arrow.circlepath", title: "定时", color: .orange)
                ActionItem(icon: "chart.line.uptrend.xyaxis", title: "监控", color: .purple)
            }
            .padding(.horizontal)
        }
    }
}

struct StatItem: View {
    let value: String, label: String
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .scaleEffect(isHovered ? 1.05 : 1)
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
    }
}

struct ActionItem: View {
    let icon: String, title: String, color: Color
    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(color)
                )
                .scaleEffect(isPressed ? 0.9 : 1)
            Text(title)
                .font(.caption)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .pressable(scale: 0.9)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
