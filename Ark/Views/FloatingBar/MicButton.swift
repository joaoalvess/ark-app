import SwiftUI

struct MicButton: View {
    let isListening: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))

                Image(systemName: isListening ? "mic.fill" : "mic")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isListening ? .red : .primary)

                if isListening {
                    PulsingIndicator(color: .red)
                        .offset(x: 8, y: -8)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: Constants.UI.iconButtonSize, height: Constants.UI.iconButtonSize)
    }
}
