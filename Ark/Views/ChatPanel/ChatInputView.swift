import SwiftUI

struct ChatInputView: View {
    @Binding var text: String
    let isProcessing: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Pergunte sobre sua conversa...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit { onSend() }

            Button(action: onSend) {
                Image(systemName: isProcessing ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(text.isEmpty && !isProcessing ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(text.isEmpty && !isProcessing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
