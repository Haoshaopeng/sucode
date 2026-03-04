import SwiftUI

struct SettingsView: View {
    @StateObject private var persistence = DataPersistenceManager.shared
    let providers = ["Claude", "Kimi", "GLM", "Custom"]
    let fontFamilies = ["SF Mono", "Menlo", "Courier", "Monaco"]
    let themes = ["dark", "light", "system"]
    let themeDisplayNames = ["dark": "深色", "light": "浅色", "system": "跟随系统"]
    let terminalThemes = ["dark", "light", "solarized", "monokai"]
    let terminalThemeDisplayNames = ["dark": "深色", "light": "浅色", "solarized": "Solarized", "monokai": "Monokai"]
    let cursorStyles = ["block", "line", "bar"]
    let cursorStyleDisplayNames = ["block": "块状", "line": "竖线", "bar": "下划线"]

    @State private var showingResetConfirmation = false
    @State private var showingClearHistoryConfirmation = false
    @State private var showingExportSheet = false
    @State private var exportData: Data?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                Spacer().frame(height: 50)

                HStack {
                    Text("设置")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal)

                // MARK: - Appearance Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("外观")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal)

                    VStack(spacing: 0) {
                        SettingPickerRow(
                            title: "主题",
                            value: $persistence.themeRawValue,
                            options: themes,
                            displayNames: themeDisplayNames
                        )
                        Divider().background(Color.white.opacity(0.1)).padding(.leading)
                        SettingPickerRow(title: "字体", value: $persistence.terminalFontFamily, options: fontFamilies)
                        Divider().background(Color.white.opacity(0.1)).padding(.leading)
                        SettingStepperRow(
                            title: "字体大小",
                            value: $persistence.terminalFontSize,
                            range: 10...20,
                            step: 1
                        )
                        Divider().background(Color.white.opacity(0.1)).padding(.leading)
                        SettingPickerRow(
                            title: "终端主题",
                            value: $persistence.terminalTheme,
                            options: terminalThemes,
                            displayNames: terminalThemeDisplayNames
                        )
                        Divider().background(Color.white.opacity(0.1)).padding(.leading)
                        SettingToggleRow(title: "自动换行", isOn: $persistence.wordWrap)
                        Divider().background(Color.white.opacity(0.1)).padding(.leading)
                        SettingPickerRow(
                            title: "光标样式",
                            value: $persistence.cursorStyle,
                            options: cursorStyles,
                            displayNames: cursorStyleDisplayNames
                        )
                        Divider().background(Color.white.opacity(0.1)).padding(.leading)
                        SettingToggleRow(title: "显示行号", isOn: $persistence.showLineNumbers)
                        Divider().background(Color.white.opacity(0.1)).padding(.leading)
                        SettingToggleRow(title: "终端声音", isOn: $persistence.terminalSound)
                    }
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                // MARK: - Connection Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("连接")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal)

                    VStack(spacing: 0) {
                        SettingStepperRow(
                            title: "连接超时",
                            value: Binding(
                                get: { CGFloat(persistence.connectionTimeout) },
                                set: { persistence.connectionTimeout = Double($0) }
                            ),
                            range: 3...60,
                            step: 1,
                            suffix: "秒"
                        )
                        Divider().background(Color.white.opacity(0.1)).padding(.leading)
                        SettingStepperRow(
                            title: "心跳间隔",
                            value: Binding(
                                get: { CGFloat(persistence.heartbeatInterval) },
                                set: { persistence.heartbeatInterval = Double($0) }
                            ),
                            range: 10...120,
                            step: 5,
                            suffix: "秒"
                        )
                        Divider().background(Color.white.opacity(0.1)).padding(.leading)
                        SettingToggleRow(title: "启动时自动连接", isOn: $persistence.autoConnect)
                    }
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                // MARK: - Cluster Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("集群")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal)

                    VStack(spacing: 0) {
                        SettingToggleRow(title: "自动刷新状态", isOn: $persistence.clusterAutoRefresh)
                        if persistence.clusterAutoRefresh {
                            Divider().background(Color.white.opacity(0.1)).padding(.leading)
                            SettingStepperRow(
                                title: "刷新间隔",
                                value: Binding(
                                    get: { CGFloat(persistence.clusterRefreshInterval) },
                                    set: { persistence.clusterRefreshInterval = Int($0) }
                                ),
                                range: 5...300,
                                step: 5,
                                suffix: "秒"
                            )
                        }
                    }
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                // MARK: - AI Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("AI 服务")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal)

                    VStack(spacing: 0) {
                        SettingPickerRow(title: "AI 提供商", value: $persistence.aiProvider, options: providers)
                        Divider().background(Color.white.opacity(0.1)).padding(.leading)
                        SettingSecureRow(title: "API Key", text: $persistence.apiKey)
                        Divider().background(Color.white.opacity(0.1)).padding(.leading)
                        SettingToggleRow(title: "自动保存对话", isOn: $persistence.autoSaveChat)
                        Divider().background(Color.white.opacity(0.1)).padding(.leading)
                        SettingStepperRow(
                            title: "最大上下文长度",
                            value: Binding(
                                get: { CGFloat(persistence.maxContextLength) },
                                set: { persistence.maxContextLength = Int($0) }
                            ),
                            range: 1...50,
                            step: 1,
                            suffix: "条"
                        )
                    }
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                // MARK: - Notification Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("通知")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal)

                    VStack(spacing: 0) {
                        SettingToggleRow(title: "启用通知", isOn: $persistence.notificationsEnabled)
                        Divider().background(Color.white.opacity(0.1)).padding(.leading)
                        SettingToggleRow(title: "设备离线通知", isOn: $persistence.notifyOnOffline)
                        Divider().background(Color.white.opacity(0.1)).padding(.leading)
                        SettingToggleRow(title: "命令完成通知", isOn: $persistence.notifyOnCommandComplete)
                    }
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                // MARK: - Security Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("安全")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal)

                    VStack(spacing: 0) {
                        SettingToggleRow(title: "启用 Face ID / Touch ID", isOn: $persistence.enableBiometricAuth)
                        Divider().background(Color.white.opacity(0.1)).padding(.leading)
                        SettingStepperRow(
                            title: "锁屏超时",
                            value: Binding(
                                get: { CGFloat(persistence.lockTimeout) },
                                set: { persistence.lockTimeout = Int($0) }
                            ),
                            range: 1...30,
                            step: 1,
                            suffix: "分钟"
                        )
                    }
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                // MARK: - Data Management Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("数据管理")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal)

                    VStack(spacing: 0) {
                        Button(action: { Task { await exportDataAction() } }) {
                            SettingButtonRow(title: "导出数据", icon: "square.and.arrow.up", color: .blue)
                        }
                        Divider().background(Color.white.opacity(0.1)).padding(.leading)
                        Button(action: { showingClearHistoryConfirmation = true }) {
                            SettingButtonRow(title: "清除命令历史", icon: "clock.arrow.circlepath", color: .orange)
                        }
                        Divider().background(Color.white.opacity(0.1)).padding(.leading)
                        Button(action: { showingResetConfirmation = true }) {
                            SettingButtonRow(title: "重置所有设置", icon: "arrow.counterclockwise", color: .red)
                        }
                    }
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                // MARK: - About Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("关于")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal)

                    HStack {
                        Text("版本")
                            .foregroundColor(.white)
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                Spacer(minLength: 50)
            }
        }
        .alert("重置设置", isPresented: $showingResetConfirmation) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) {
                persistence.resetAllSettings()
            }
        } message: {
            Text("确定要重置所有设置吗？此操作不可撤销。")
        }
        .alert("清除命令历史", isPresented: $showingClearHistoryConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                persistence.clearCommandHistory()
            }
        } message: {
            Text("确定要清除所有命令历史吗？此操作不可撤销。")
        }
        .sheet(isPresented: $showingExportSheet) {
            if let data = exportData {
                ShareSheet(items: [data])
            }
        }
    }

    private func exportDataAction() async {
        do {
            exportData = try await PersistenceManager.shared.exportData()
            showingExportSheet = true
        } catch {
            print("Export failed: \(error)")
        }
    }
}

struct SettingPickerRow: View {
    let title: String
    @Binding var value: String
    let options: [String]
    var displayNames: [String: String]? = nil

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.white)
            Spacer()
            Picker("", selection: $value) {
                ForEach(options, id: \.self) { option in
                    Text(displayNames?[option] ?? option).tag(option)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .accentColor(.white)
        }
        .padding()
    }
}

struct SettingSecureRow: View {
    let title: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.white)
            Spacer()
            SecureField("输入 API Key", text: $text)
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
        }
        .padding()
    }
}

struct SettingToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.white)
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: .blue))
        }
        .padding()
    }
}

struct SettingStepperRow: View {
    let title: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let step: CGFloat
    var suffix: String = ""

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.white)
            Spacer()
            Text("\(Int(value))\(suffix)")
                .foregroundColor(.gray)
                .frame(minWidth: 50)
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
        }
        .padding()
    }
}

struct SettingButtonRow: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(title)
                .foregroundColor(.white)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .font(.caption)
        }
        .padding()
        .contentShape(Rectangle())
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
