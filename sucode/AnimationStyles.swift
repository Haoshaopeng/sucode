import SwiftUI
import UIKit

// MARK: - 动画常量
enum AnimationDuration {
    static let fast: Double = 0.15
    static let normal: Double = 0.3
    static let slow: Double = 0.5
    static let spring: Double = 0.4
}

enum AnimationDelay {
    static let stagger: Double = 0.05
    static let card: Double = 0.08
}

// MARK: - 缓动函数
extension Animation {
    static var smooth: Animation {
        .timingCurve(0.4, 0.0, 0.2, 1.0, duration: AnimationDuration.normal)
    }

    static var bouncy: Animation {
        .spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.2)
    }

    static var snappy: Animation {
        .spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0.1)
    }

    static var gentle: Animation {
        .easeInOut(duration: AnimationDuration.slow)
    }

    static var spin: Animation {
        .linear(duration: 1).repeatForever(autoreverses: false)
    }
}

// MARK: - Haptic 反馈
enum HapticFeedback {
    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    static func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    static func heavy() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }

    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    static func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }

    static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}

// MARK: - View 扩展
extension View {
    // 淡入动画
    func fadeIn(delay: Double = 0) -> some View {
        self.modifier(FadeInModifier(delay: delay))
    }

    // 从底部滑入
    func slideUp(delay: Double = 0, offset: CGFloat = 30) -> some View {
        self.modifier(SlideUpModifier(delay: delay, offset: offset))
    }

    // 缩放动画
    func scaleIn(delay: Double = 0) -> some View {
        self.modifier(ScaleInModifier(delay: delay))
    }

    // 脉冲效果（用于在线状态）
    func pulseEffect(active: Bool, color: Color = .green) -> some View {
        self.modifier(PulseModifier(active: active, color: color))
    }

    // 玻璃拟态效果
    func glassmorphism(cornerRadius: CGFloat = 16) -> some View {
        self.modifier(GlassmorphismModifier(cornerRadius: cornerRadius))
    }

    // 按压效果
    func pressable(scale: CGFloat = 0.96) -> some View {
        self.modifier(PressableModifier(scale: scale))
    }

    // Skeleton 加载效果
    func skeleton(isLoading: Bool) -> some View {
        self.modifier(SkeletonModifier(isLoading: isLoading))
    }

    // 页面切换过渡
    func pageTransition(_ direction: PageTransitionDirection) -> some View {
        self.modifier(PageTransitionModifier(direction: direction))
    }
}

// MARK: - 动画修饰符
struct FadeInModifier: ViewModifier {
    let delay: Double
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.smooth.delay(delay)) {
                    isVisible = true
                }
            }
    }
}

struct SlideUpModifier: ViewModifier {
    let delay: Double
    let offset: CGFloat
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .offset(y: isVisible ? 0 : offset)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.bouncy.delay(delay)) {
                    isVisible = true
                }
            }
    }
}

struct ScaleInModifier: ViewModifier {
    let delay: Double
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isVisible ? 1 : 0.8)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.bouncy.delay(delay)) {
                    isVisible = true
                }
            }
    }
}

struct PulseModifier: ViewModifier {
    let active: Bool
    let color: Color
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .overlay(
                Circle()
                    .stroke(color, lineWidth: 2)
                    .scaleEffect(isPulsing ? 1.5 : 1)
                    .opacity(isPulsing ? 0 : 0.6)
                    .animation(active ? .easeOut(duration: 1.2).repeatForever(autoreverses: false) : .default, value: isPulsing)
            )
            .onAppear {
                if active {
                    isPulsing = true
                }
            }
            .onChange(of: active) { newValue in
                isPulsing = newValue
            }
    }
}

struct GlassmorphismModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
    }
}

struct PressableModifier: ViewModifier {
    let scale: CGFloat
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? scale : 1)
            .animation(.snappy, value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            HapticFeedback.light()
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                    }
            )
    }
}

struct SkeletonModifier: ViewModifier {
    let isLoading: Bool
    @State private var isAnimating = false

    func body(content: Content) -> some View {
        content
            .redacted(reason: isLoading ? .placeholder : [])
            .overlay(
                GeometryReader { geometry in
                    if isLoading {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.15),
                                Color.white.opacity(0)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 2)
                        .offset(x: isAnimating ? geometry.size.width : -geometry.size.width)
                        .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: isAnimating)
                    }
                }
            )
            .onAppear {
                if isLoading {
                    isAnimating = true
                }
            }
    }
}

enum PageTransitionDirection {
    case left, right, up, down
}

struct PageTransitionModifier: ViewModifier {
    let direction: PageTransitionDirection
    @State private var isVisible = false

    private var offset: CGSize {
        switch direction {
        case .left: return CGSize(width: 50, height: 0)
        case .right: return CGSize(width: -50, height: 0)
        case .up: return CGSize(width: 0, height: 30)
        case .down: return CGSize(width: 0, height: -30)
        }
    }

    func body(content: Content) -> some View {
        content
            .offset(x: isVisible ? 0 : offset.width, y: isVisible ? 0 : offset.height)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.smooth) {
                    isVisible = true
                }
            }
    }
}

// MARK: - 页面切换动画
struct TabTransitionView<Content: View>: View {
    let content: Content
    let direction: PageTransitionDirection
    @State private var trigger = false

    init(direction: PageTransitionDirection, @ViewBuilder content: () -> Content) {
        self.direction = direction
        self.content = content()
    }

    var body: some View {
        content
            .pageTransition(direction)
            .id(trigger)
            .onAppear {
                trigger.toggle()
            }
    }
}

// MARK: - 交错动画容器
struct StaggeredContainer<Content: View>: View {
    let content: Content
    let delay: Double

    init(delay: Double = 0, @ViewBuilder content: () -> Content) {
        self.delay = delay
        self.content = content()
    }

    var body: some View {
        content
            .opacity(0)
            .onAppear {
                withAnimation(.smooth.delay(delay)) {
                    // 触发子视图动画
                }
            }
    }
}

// MARK: - 设备卡片 Skeleton
struct DeviceCardSkeleton: View {
    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 120, height: 16)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 80, height: 12)
            }

            Spacer()

            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.1))
                .frame(width: 60, height: 24)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
        .skeleton(isLoading: true)
    }
}

// MARK: - 统计卡片 Skeleton
struct StatCardSkeleton: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 24, height: 24)
                Spacer()
            }

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.1))
                .frame(height: 28)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.08))
                .frame(width: 40, height: 12)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
        .skeleton(isLoading: true)
    }
}
