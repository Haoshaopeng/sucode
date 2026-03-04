import SwiftUI

struct ChatMessage: Identifiable, Codable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp: Date
}

class ChatManager: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false

    func sendMessage(_ content: String) {
        let userMessage = ChatMessage(content: content, isUser: true, timestamp: Date())
        messages.append(userMessage)
        isLoading = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let aiMessage = ChatMessage(content: "AI 响应内容", isUser: false, timestamp: Date())
            self.messages.append(aiMessage)
            self.isLoading = false
        }
    }
}

struct AIChatView: View {
    @StateObject private var chatManager = ChatManager()
    @State private var inputMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 50)

            HStack {
                Text("AI 助手")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 16) {
                    if chatManager.messages.isEmpty {
                        VStack(spacing: 20) {
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 80, height: 80)
                                .overlay(Image(systemName: "bubble.left.and.bubble.right.fill").font(.title2).foregroundColor(.gray))
                            Text("AI 助手已就绪")
                                .font(.title3)
                                .foregroundColor(.white)
                            Text("发送消息开始对话")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 100)
                    } else {
                        ForEach(chatManager.messages) { message in
                            MessageBubble(message: message)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 20)
            }

            HStack(spacing: 12) {
                TextField("输入消息...", text: $inputMessage)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(12)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(20)
                    .foregroundColor(.white)

                if chatManager.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(width: 44, height: 44)
                } else {
                    Button(action: {
                        if !inputMessage.isEmpty {
                            chatManager.sendMessage(inputMessage)
                            inputMessage = ""
                        }
                    }) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 44, height: 44)
                            .overlay(Image(systemName: "arrow.up").font(.system(size: 18, weight: .semibold)).foregroundColor(.white))
                    }
                    .disabled(inputMessage.isEmpty)
                }
            }
            .padding()

            Spacer(minLength: 50)
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    var body: some View {
        HStack {
            if message.isUser { Spacer() }
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.isUser ? "您" : "AI 助手")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(message.content)
                    .font(.subheadline)
                    .padding(12)
                    .background(message.isUser ? Color.blue.opacity(0.3) : Color.white.opacity(0.15))
                    .foregroundColor(.white)
                    .cornerRadius(16)
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            if !message.isUser { Spacer() }
        }
    }
}
