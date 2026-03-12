import SwiftUI

struct FloatingBarView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Pill bar
            HStack(spacing: 8) {
                // Settings button
                SettingsLink {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                        Image(systemName: "safari")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: Constants.UI.iconButtonSize, height: Constants.UI.iconButtonSize)
                }
                .buttonStyle(.plain)

                Spacer()

                // Ask/Suggestions button
                if appState.isListening {
                    SuggestionsButton(isChatVisible: appState.isChatVisible) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            appState.toggleChat()
                        }
                    }
                } else {
                    AskButton(isChatVisible: appState.isChatVisible) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            appState.toggleChat()
                        }
                    }
                }

                Spacer()

                // Mic button
                MicButton(isListening: appState.isListening, isLoading: appState.isMicLoading) {
                    Task { await appState.toggleListening() }
                }
            }
            .padding(.horizontal, 8)
            .frame(height: Constants.UI.barHeight)
            .frame(width: appState.isListening ? Constants.UI.barWidthListening : Constants.UI.barWidth)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: appState.isListening)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())

            // Panel
            if appState.isChatVisible {
                if appState.isListening {
                    VoicePanelView(appState: appState)
                        .frame(width: Constants.UI.chatPanelWidth)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                } else {
                    AskPanelView(appState: appState)
                        .frame(width: Constants.UI.chatPanelWidth)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                }
            }
        }
    }
}
