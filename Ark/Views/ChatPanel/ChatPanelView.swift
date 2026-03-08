import SwiftUI

struct ChatPanelView: View {
    @Bindable var appState: AppState

    var body: some View {
        GlassPanel {
            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(appState.messages) { message in
                                ChatMessageView(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: appState.messages.count) {
                        if let last = appState.messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // Transcript indicator
                if appState.isListening {
                    HStack(spacing: 6) {
                        PulsingIndicator(color: .green)
                        Text("Transcrevendo...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(appState.transcriptManager.entries.count) falas")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }

                Divider()

                // Input
                ChatInputView(
                    text: $appState.currentInput,
                    isProcessing: appState.isProcessing
                ) {
                    Task { await appState.sendMessage() }
                }
            }
        }
    }
}
