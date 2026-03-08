import SwiftUI

struct FloatingBarView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Pill bar
            HStack(spacing: 12) {
                // Settings button
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 36, height: 36)

                Spacer()

                // Ask/Hide button
                AskButton(isChatVisible: appState.isChatVisible) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        appState.toggleChat()
                    }
                }

                Spacer()

                // Mic button
                MicButton(isListening: appState.isListening) {
                    Task { await appState.toggleListening() }
                }
            }
            .padding(.horizontal, 12)
            .frame(width: Constants.UI.barWidth, height: Constants.UI.barHeight)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())

            // Chat panel
            if appState.isChatVisible {
                ChatPanelView(appState: appState)
                    .frame(width: Constants.UI.chatPanelWidth, height: Constants.UI.chatPanelHeight)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
    }
}
