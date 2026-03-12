import SwiftUI

struct MicButton: View {
    let isListening: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.secondary)
                } else {
                    Image(systemName: isListening ? "mic.fill" : "mic")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isListening ? .red : .primary)
                }

                if isListening {
                    PulsingIndicator(color: .red)
                        .offset(x: 8, y: -8)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .frame(width: Constants.UI.iconButtonSize, height: Constants.UI.iconButtonSize)
    }
}
