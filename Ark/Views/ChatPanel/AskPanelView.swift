import SwiftUI

private struct TextHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct AskPanelView: View {
    @Bindable var appState: AppState

    var body: some View {
        GlassPanel {
            VStack(spacing: 0) {
                // Input
                ChatInputView(
                    text: $appState.currentInput,
                    isProcessing: appState.isProcessing
                ) {
                    Task { await appState.sendAskMessage() }
                }

                // Response area
                if appState.isAskStreaming || !appState.askDisplayedText.isEmpty {
                    Divider()
                        .padding(.horizontal, 12)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if appState.askDisplayedText.isEmpty {
                                thinkingView
                                    .transition(.blurReplace)
                            } else {
                                Text(markdownAttributed(appState.askDisplayedText))
                                    .font(.system(size: 14))
                                    .lineSpacing(3)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .transition(.blurReplace)

                                if appState.isAskStreaming {
                                    cursorView
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 14)
                        .animation(.easeOut(duration: 0.25), value: appState.askDisplayedText.isEmpty)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: TextHeightKey.self, value: geo.size.height)
                            }
                        )
                    }
                    .frame(height: min(appState.askContentHeight, Constants.UI.askResponseMaxHeight))
                    .onPreferenceChange(TextHeightKey.self) { height in
                        appState.askContentHeight = height
                    }
                }
            }
        }
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
