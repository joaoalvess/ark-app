import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    var text: String
    var isStreaming: Bool

    enum Role: String {
        case user
        case assistant
        case suggestion
    }

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(role: .user, text: text, isStreaming: false)
    }

    static func assistant(_ text: String, streaming: Bool = false) -> ChatMessage {
        ChatMessage(role: .assistant, text: text, isStreaming: streaming)
    }

    static func suggestion(_ text: String) -> ChatMessage {
        ChatMessage(role: .suggestion, text: text, isStreaming: false)
    }
}
