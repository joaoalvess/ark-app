import SwiftUI

struct ChatMessageView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .suggestion {
                    Label("Sugestao", systemImage: "lightbulb.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }

                Text(message.text.isEmpty && message.isStreaming ? "..." : message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(backgroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .opacity(message.isStreaming ? 0.9 : 1.0)
            }

            if message.role != .user { Spacer(minLength: 40) }
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user: .accentColor
        case .assistant: Color(.controlBackgroundColor)
        case .suggestion: .yellow.opacity(0.15)
        }
    }
}
