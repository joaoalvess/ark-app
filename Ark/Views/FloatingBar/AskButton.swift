import SwiftUI

struct AskButton: View {
    let isChatVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isChatVisible {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                    Text("Hide")
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10, weight: .bold))
                    Text("Ask")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(isChatVisible ? Color.gray.opacity(0.6) : Color.accentColor)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
