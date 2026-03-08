import SwiftUI

struct MicButton: View {
    let isListening: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
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
        .frame(width: 36, height: 36)
    }
}
