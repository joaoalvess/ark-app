import SwiftUI

struct ChatInputView: View {
    @Binding var text: String
    let isProcessing: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Pergunte sobre a tela ou conversa, ou ⌘↵ para Assistir", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit { onSend() }

            Button(action: onSend) {
                ZStack {
                    Circle()
                        .fill(text.isEmpty && !isProcessing ? Color.secondary.opacity(0.3) : Color.accentColor)
                        .frame(width: 28, height: 28)
                    Image(systemName: isProcessing ? "stop.fill" : "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(text.isEmpty && !isProcessing)
        }
        .padding(.horizontal, 12)
        .frame(height: Constants.UI.inputBarHeight)
    }
}
