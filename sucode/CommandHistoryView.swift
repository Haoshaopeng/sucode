import SwiftUI

struct CommandHistoryView: View {
    @StateObject private var persistence = DataPersistenceManager.shared
    @State private var commandHistory: [ClusterCommand] = []
    @State private var selectedCommand: ClusterCommand?
    @State private var showingDetail = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    if commandHistory.isEmpty {
                        EmptyHistoryView()
                    } else {
                        List {
                            ForEach(commandHistory.sorted(by: { $0.timestamp > $1.timestamp })) { command in
                                CommandHistoryRow(command: command)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedCommand = command
                                        showingDetail = true
                                    }
                            }
                            .onDelete(perform: deleteCommands)
                        }
                        .listStyle(.plain)
                        .background(Color.black)
                    }
                }
            }
            .navigationTitle("命令历史")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: clearHistory) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .disabled(commandHistory.isEmpty)
                }
            }
            .sheet(isPresented: $showingDetail) {
                if let command = selectedCommand {
                    CommandDetailView(command: command)
                }
            }
            .onAppear {
                loadHistory()
            }
        }
    }

    private func loadHistory() {
        commandHistory = persistence.loadCommandHistory()
    }

    private func deleteCommands(at offsets: IndexSet) {
        commandHistory.remove(atOffsets: offsets)
        persistence.saveCommandHistory(commandHistory)
    }

    private func clearHistory() {
        persistence.clearCommandHistory()
        commandHistory = []
    }
}

// MARK: - Command History Row
struct CommandHistoryRow: View {
    let command: ClusterCommand

    private var successCount: Int {
        command.results.values.filter { $0.success }.count
    }

    private var totalCount: Int {
        command.results.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "terminal")
                    .foregroundColor(.blue)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(command.command)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(formattedDate(command.timestamp))
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: successCount == totalCount ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(successCount == totalCount ? .green : .orange)
                        Text("\(successCount)/\(totalCount)")
                            .font(.caption)
                            .foregroundColor(.white)
                    }

                    Text("\(command.targetDevices.count) 设备")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color.black)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Command Detail View
struct CommandDetailView: View {
    let command: ClusterCommand
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Command info
                        VStack(alignment: .leading, spacing: 8) {
                            Text("命令")
                                .font(.caption)
                                .foregroundColor(.gray)

                            Text(command.command)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(8)
                        }

                        // Timestamp
                        HStack {
                            Text("执行时间")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Spacer()
                            Text(formattedDate(command.timestamp))
                                .font(.caption)
                                .foregroundColor(.white)
                        }

                        Divider()
                            .background(Color.white.opacity(0.1))

                        // Results
                        Text("执行结果")
                            .font(.headline)
                            .foregroundColor(.white)

                        ForEach(Array(command.results.keys.sorted()), id: \.self) { deviceId in
                            if let result = command.results[deviceId] {
                                ResultCard(deviceId: deviceId, result: result)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("命令详情")
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

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Result Card
struct ResultCard: View {
    let deviceId: UUID
    let result: CommandResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(deviceId.uuidString.prefix(8))
                    .font(.caption)
                    .foregroundColor(.gray)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.success ? .green : .red)
                    Text(result.success ? "成功" : "失败")
                        .font(.caption)
                        .foregroundColor(result.success ? .green : .red)
                }
            }

            if !result.output.isEmpty {
                Text(result.output)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.gray)
                    .lineLimit(5)
            }

            if let error = result.error {
                Text(error)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.red)
                    .lineLimit(3)
            }

            Text("耗时: \(String(format: "%.2f", result.executionTime))s")
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.white.opacity(0.08))
        .cornerRadius(8)
    }
}

// MARK: - Empty History View
struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))

            Text("暂无命令历史")
                .font(.title3)
                .foregroundColor(.white)

            Text("执行的批量命令将显示在这里")
                .font(.subheadline)
                .foregroundColor(.gray)

            Spacer()
        }
    }
}

// MARK: - Preview
struct CommandHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        CommandHistoryView()
            .preferredColorScheme(.dark)
    }
}
