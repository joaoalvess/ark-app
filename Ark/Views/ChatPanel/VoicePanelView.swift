import SwiftUI

private struct VoiceTextHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct VoicePanelView: View {
    @Bindable var appState: AppState

    @State private var hoveredAction: VoiceAction?

    private var engine: SuggestionEngine { appState.suggestionEngine }

    var body: some View {
        GlassPanel {
            VStack(spacing: 0) {
                // Inline action row
                HStack(spacing: 0) {
                    actionButton(icon: "sparkles", label: "Assistir", action: .assist)
                    dot
                    actionButton(icon: "ellipsis", label: "Continuar", action: .whatToSay)
                    dot
                    actionButton(icon: "text.append", label: "Follow-up", action: .followUp)
                    dot
                    actionButton(icon: "arrow.counterclockwise", label: "Recapitular", action: .recap)
                }
                .opacity(engine.isStreaming ? 0.4 : 1.0)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                // Response area
                if engine.isStreaming || !engine.displayedText.isEmpty {
                    Divider()
                        .padding(.horizontal, 12)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if engine.displayedText.isEmpty {
                                thinkingView
                                    .transition(.blurReplace)
                            } else {
                                Text(markdownAttributed(engine.displayedText))
                                    .font(.system(size: 14))
                                    .lineSpacing(3)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .transition(.blurReplace)
                                    .onTapGesture {
                                        if !engine.isStreaming {
                                            engine.clearDisplay()
                                        }
                                    }

                                if engine.isStreaming {
                                    cursorView
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .animation(.easeOut(duration: 0.25), value: engine.displayedText.isEmpty)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: VoiceTextHeightKey.self, value: geo.size.height)
                            }
                        )
                    }
                    .frame(height: min(engine.contentHeight, Constants.UI.voiceResponseMaxHeight))
                    .onPreferenceChange(VoiceTextHeightKey.self) { height in
                        engine.contentHeight = height
                    }
                }
            }
        }
    }

    private var dot: some View {
        Text("•")
            .font(.system(size: 12))
            .foregroundStyle(.quaternary)
            .padding(.horizontal, 4)
    }

    private func actionButton(icon: String, label: String, action: VoiceAction) -> some View {
        let isHovered = hoveredAction == action
        return Button {
            engine.handleUserCommand(
                action: action,
                transcript: appState.transcriptManager.formattedTranscript
            )
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isHovered ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(.white.opacity(isHovered ? 0.08 : 0))
            )
        }
        .buttonStyle(.plain)
        .disabled(engine.isStreaming)
        .onHover { hovering in
            hoveredAction = hovering ? action : nil
        }
        .animation(.easeOut(duration: 0.15), value: hoveredAction)
    }

    private var thinkingView: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                ThinkingDot(delay: Double(index) * 0.15)
            }
            Text("Pensando")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var cursorView: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.accentColor)
            .frame(width: 2, height: 14)
            .opacity(0.8)
    }

    private func markdownAttributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

private struct ThinkingDot: View {
    let delay: Double
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.7))
            .frame(width: 6, height: 6)
            .scaleEffect(isAnimating ? 1.0 : 0.4)
            .opacity(isAnimating ? 1.0 : 0.3)
            .animation(
                .easeInOut(duration: 0.5)
                .repeatForever(autoreverses: true)
                .delay(delay),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}
