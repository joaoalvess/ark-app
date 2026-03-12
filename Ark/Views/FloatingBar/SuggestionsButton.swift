import SwiftUI

struct SuggestionsButton: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        PanelToggleButton(
            isSelected: isSelected,
            inactiveIcon: "sparkles",
            inactiveTitle: "Suggestions",
            minWidth: 122,
            action: action
        )
    }
}

struct PanelToggleButton: View {
    let isSelected: Bool
    let inactiveIcon: String
    let inactiveTitle: String
    let minWidth: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                label(icon: inactiveIcon, title: inactiveTitle)
                    .opacity(isSelected ? 0 : 1)

                label(icon: "chevron.up", title: "Hide")
                    .opacity(isSelected ? 1 : 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(minWidth: minWidth)
            .background(isSelected ? Color.gray.opacity(0.6) : Color.accentColor)
            .clipShape(Capsule())
            .animation(Constants.UI.subtlePanelTransition, value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "Hide" : inactiveTitle)
    }

    private func label(icon: String, title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
    }
}

struct TranscriptIconButton: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
                Image(systemName: "text.quote")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: Constants.UI.iconButtonSize, height: Constants.UI.iconButtonSize)
        }
        .buttonStyle(.plain)
    }
}
