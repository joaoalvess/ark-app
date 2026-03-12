import SwiftUI

struct FloatingBarView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
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

                if appState.isListening {
                    SuggestionsButton(isSelected: appState.isVoiceSuggestionsPanelVisible) {
                        withAnimation(Constants.UI.subtlePanelTransition) {
                            appState.toggleVoiceSuggestionsPanel()
                        }
                    }
                } else {
                    AskButton(isSelected: appState.isAskPanelVisible) {
                        withAnimation(Constants.UI.subtlePanelTransition) {
                            appState.toggleAskPanel()
                        }
                    }
                }

                Spacer()

                if appState.isListening {
                    TranscriptIconButton(isSelected: appState.isTranscriptOverlayVisible) {
                        withAnimation(Constants.UI.subtlePanelTransition) {
                            appState.toggleTranscriptOverlay()
                        }
                    }
                }

                MicButton(isListening: appState.isListening, isLoading: appState.isMicLoading) {
                    Task { await appState.toggleListening() }
                }
            }
            .padding(.horizontal, 8)
            .frame(height: Constants.UI.barHeight)
            .frame(width: appState.isListening ? Constants.UI.barWidthListening : Constants.UI.barWidth)
            .animation(Constants.UI.subtlePanelTransition, value: appState.isListening)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())

            if appState.isChatVisible {
                VStack(spacing: Constants.UI.panelStackSpacing) {
                    if appState.isAskPanelVisible {
                        AskPanelView(appState: appState)
                            .frame(width: Constants.UI.chatPanelWidth)
                            .transition(.subtlePanelReveal)
                    }

                    if appState.isVoiceSuggestionsPanelVisible {
                        VoicePanelView(appState: appState)
                            .frame(width: Constants.UI.chatPanelWidth)
                            .transition(.subtlePanelReveal)
                    }

                    if appState.isTranscriptOverlayVisible {
                        TranscriptPanelView(appState: appState)
                            .frame(width: Constants.UI.chatPanelWidth)
                            .transition(.subtlePanelReveal)
                    }
                }
                .padding(.top, Constants.UI.panelStackSpacing)
            }
        }
        .animation(Constants.UI.subtlePanelTransition, value: appState.panelMode)
        .animation(Constants.UI.subtlePanelTransition, value: appState.isTranscriptOverlayVisible)
    }
}

private extension AnyTransition {
    static var subtlePanelReveal: AnyTransition {
        .opacity.combined(
            with: .scale(
                scale: Constants.UI.subtlePanelTransitionScale,
                anchor: .top
            )
        )
    }
}
