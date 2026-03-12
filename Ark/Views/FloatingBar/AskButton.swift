import SwiftUI

struct AskButton: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        PanelToggleButton(
            isSelected: isSelected,
            inactiveIcon: "sparkle",
            inactiveTitle: "Ask",
            minWidth: 76,
            action: action
        )
    }
}
