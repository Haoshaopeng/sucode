import SwiftUI

// MARK: - sucode App Icon 设计
// 使用 SwiftUI Canvas 绘制矢量图标
// 支持导出为各种尺寸

struct AppIconView: View {
    var size: CGFloat = 1024

    var body: some View {
        ZStack {
            // 背景渐变
            backgroundGradient

            // 主图标内容
            iconContent
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    // MARK: - 背景渐变
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.03, blue: 0.18),
                Color(red: 0.15, green: 0.08, blue: 0.28),
                Color(red: 0.25, green: 0.15, blue: 0.45)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - 图标主内容
    private var iconContent: some View {
        ZStack {
            // 装饰性网格背景
            gridPattern
                .opacity(0.15)

            // 外圈光环
            outerRing

            // 服务器/终端主体
            terminalBody

            // AI 神经网络装饰
            neuralNetwork

            // 代码符号
            codeSymbol
        }
    }

    // MARK: - 网格背景
    private var gridPattern: some View {
        Canvas { context, size in
            let gridSize: CGFloat = size.width / 16
            let lineWidth: CGFloat = 1

            // 垂直线
            for i in 0..<17 {
                let x = CGFloat(i) * gridSize
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.white.opacity(0.3)), lineWidth: lineWidth)
            }

            // 水平线
            for i in 0..<17 {
                let y = CGFloat(i) * gridSize
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.white.opacity(0.3)), lineWidth: lineWidth)
            }
        }
    }

    // MARK: - 外圈光环
    private var outerRing: some View {
        ZStack {
            // 外圈光晕
            Circle()
                .stroke(
                    Color(red: 0.4, green: 0.3, blue: 0.8).opacity(0.3),
                    lineWidth: size * 0.015
                )
                .frame(width: size * 0.78, height: size * 0.78)

            // 内圈
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.5, green: 0.4, blue: 0.9).opacity(0.6),
                            Color.blue.opacity(0.4)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: size * 0.008
                )
                .frame(width: size * 0.72, height: size * 0.72)
        }
    }

    // MARK: - 终端主体
    private var terminalBody: some View {
        ZStack {
            // 终端外框
            RoundedRectangle(cornerRadius: size * 0.06, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.12, blue: 0.18),
                            Color(red: 0.08, green: 0.08, blue: 0.12)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.55, height: size * 0.42)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.06, style: .continuous)
                        .stroke(
                            Color(red: 0.4, green: 0.35, blue: 0.7).opacity(0.5),
                            lineWidth: size * 0.004
                        )
                )
                .shadow(
                    color: Color(red: 0.3, green: 0.2, blue: 0.6).opacity(0.4),
                    radius: size * 0.03,
                    x: 0,
                    y: size * 0.015
                )

            // 终端标题栏
            VStack(spacing: 0) {
                HStack(spacing: size * 0.02) {
                    Circle()
                        .fill(Color.red.opacity(0.8))
                        .frame(width: size * 0.025, height: size * 0.025)
                    Circle()
                        .fill(Color.yellow.opacity(0.8))
                        .frame(width: size * 0.025, height: size * 0.025)
                    Circle()
                        .fill(Color.green.opacity(0.8))
                        .frame(width: size * 0.025, height: size * 0.025)

                    Spacer()
                }
                .padding(.horizontal, size * 0.03)
                .padding(.vertical, size * 0.02)

                // 终端内容区域
                HStack(spacing: size * 0.015) {
                    Text(">_")
                        .font(.system(size: size * 0.08, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.4, green: 0.9, blue: 0.4))

                    // 光标
                    Rectangle()
                        .fill(Color(red: 0.4, green: 0.9, blue: 0.4))
                        .frame(width: size * 0.04, height: size * 0.06)
                        .opacity(0.8)

                    Spacer()
                }
                .padding(.horizontal, size * 0.04)

                Spacer()
            }
            .frame(width: size * 0.55, height: size * 0.42)
        }
    }

    // MARK: - 神经网络装饰
    private var neuralNetwork: some View {
        Canvas { context, size in
            let centerX = size.width / 2
            let centerY = size.height / 2
            let radius = size.width * 0.35

            // 节点位置
            let nodes: [CGPoint] = [
                CGPoint(x: centerX - radius * 0.5, y: centerY - radius * 0.3),
                CGPoint(x: centerX + radius * 0.5, y: centerY - radius * 0.3),
                CGPoint(x: centerX, y: centerY + radius * 0.4),
                CGPoint(x: centerX - radius * 0.3, y: centerY),
                CGPoint(x: centerX + radius * 0.3, y: centerY),
            ]

            // 绘制连接线
            let connections = [
                (0, 3), (0, 4), (1, 3), (1, 4), (3, 4), (3, 2), (4, 2)
            ]

            for (i, j) in connections {
                var path = Path()
                path.move(to: nodes[i])
                path.addLine(to: nodes[j])
                context.stroke(
                    path,
                    with: .color(Color(red: 0.5, green: 0.4, blue: 0.9).opacity(0.3)),
                    lineWidth: size.width * 0.003
                )
            }

            // 绘制节点
            for (index, node) in nodes.enumerated() {
                let nodeSize = index < 3 ? size.width * 0.025 : size.width * 0.02
                let circle = Path(ellipseIn: CGRect(
                    x: node.x - nodeSize / 2,
                    y: node.y - nodeSize / 2,
                    width: nodeSize,
                    height: nodeSize
                ))

                if index < 3 {
                    context.fill(circle, with: .color(Color(red: 0.6, green: 0.5, blue: 1.0).opacity(0.6)))
                } else {
                    context.fill(circle, with: .color(Color.blue.opacity(0.5)))
                }
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - 代码符号
    private var codeSymbol: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                // 右下角装饰符号
                ZStack {
                    // 大括号 {
                    Text("{")
                        .font(.system(size: size * 0.12, weight: .light, design: .monospaced))
                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.9).opacity(0.4))
                        .offset(x: -size * 0.03, y: 0)

                    // 大括号 }
                    Text("}")
                        .font(.system(size: size * 0.12, weight: .light, design: .monospaced))
                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.9).opacity(0.4))
                        .offset(x: size * 0.03, y: 0)

                    // 斜杠 /
                    Text("/")
                        .font(.system(size: size * 0.1, weight: .light, design: .monospaced))
                        .foregroundColor(Color.blue.opacity(0.3))
                        .offset(x: 0, y: -size * 0.02)
                }
                .offset(x: -size * 0.08, y: -size * 0.08)
            }
        }
    }
}

// MARK: - 预览
struct AppIconView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // 主图标 1024x1024
            AppIconView(size: 1024)
                .previewLayout(.fixed(width: 1024, height: 1024))
                .previewDisplayName("1024x1024")

            // App Store 预览
            AppIconView(size: 1024)
                .previewLayout(.fixed(width: 1200, height: 1200))
                .padding(100)
                .background(Color.gray)
                .previewDisplayName("App Store Preview")

            // 小尺寸测试
            AppIconView(size: 120)
                .previewLayout(.fixed(width: 200, height: 200))
                .previewDisplayName("120x120")

            // 列表尺寸测试
            AppIconView(size: 60)
                .previewLayout(.fixed(width: 100, height: 100))
                .previewDisplayName("60x60")
        }
    }
}

// MARK: - 图标导出辅助视图
struct AppIconExporter: View {
    let sizes: [CGFloat] = [1024, 180, 120, 87, 80, 60, 58, 40, 29, 20]

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                Text("sucode App Icon 导出")
                    .font(.largeTitle)
                    .padding()

                ForEach(sizes, id: \.self) { size in
                    VStack {
                        AppIconView(size: size)
                            .frame(width: size, height: size)
                            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))

                        Text("\(Int(size))x\(Int(size))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
        }
    }
}

// MARK: - 导出预览
struct AppIconExporter_Previews: PreviewProvider {
    static var previews: some View {
        AppIconExporter()
    }
}
