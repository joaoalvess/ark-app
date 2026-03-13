import SwiftUI

private struct VoiceTextHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct VoicePanelHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TranscriptPanelHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct VoicePanelView: View {
    @Bindable var appState: AppState

    @State private var hoveredAction: VoiceAction?

    private var engine: SuggestionEngine { appState.suggestionEngine }
    private var isCompactLayout: Bool { appState.isTranscriptOverlayVisible }
    private var headerHorizontalPadding: CGFloat { isCompactLayout ? 12 : 14 }
    private var headerVerticalPadding: CGFloat { isCompactLayout ? 8 : 10 }
    private var bodyHorizontalPadding: CGFloat { isCompactLayout ? 12 : 14 }
    private var bodyVerticalPadding: CGFloat { isCompactLayout ? 8 : 10 }
    private var responseMaxHeight: CGFloat {
        isCompactLayout ? Constants.UI.voiceResponseCompactMaxHeight : Constants.UI.voiceResponseMaxHeight
    }

    var body: some View {
        GlassPanel {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(VoiceAction.allCases.enumerated()), id: \.element) { index, action in
                        actionButton(action: action)
                        if index < VoiceAction.allCases.count - 1 {
                            dot
                        }
                    }
                }
                .opacity(engine.isStreaming ? 0.4 : 1.0)
                .padding(.horizontal, headerHorizontalPadding)
                .padding(.vertical, headerVerticalPadding)

                if engine.isStreaming || !engine.displayedText.isEmpty {
                    Divider()
                        .padding(.horizontal, isCompactLayout ? 10 : 12)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if engine.displayedText.isEmpty {
                                thinkingView
                                    .transition(.blurReplace)
                            } else {
                                Text(markdownAttributed(engine.displayedText))
                                    .font(.system(size: isCompactLayout ? 13 : 14))
                                    .lineSpacing(isCompactLayout ? 2 : 3)
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
                        .padding(.horizontal, bodyHorizontalPadding)
                        .padding(.vertical, bodyVerticalPadding)
                        .animation(.easeOut(duration: 0.25), value: engine.displayedText.isEmpty)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: VoiceTextHeightKey.self, value: geo.size.height)
                            }
                        )
                    }
                    .frame(height: min(engine.contentHeight, responseMaxHeight))
                    .onPreferenceChange(VoiceTextHeightKey.self) { height in
                        engine.contentHeight = height
                    }
                }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: VoicePanelHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(VoicePanelHeightKey.self) { height in
            guard abs(appState.voicePanelMeasuredHeight - height) > 1 else { return }
            appState.voicePanelMeasuredHeight = height
        }
        .animation(Constants.UI.subtlePanelTransition, value: isCompactLayout)
    }

    private var dot: some View {
        Text("•")
            .font(.system(size: isCompactLayout ? 11 : 12))
            .foregroundStyle(.quaternary)
            .padding(.horizontal, isCompactLayout ? 3 : 4)
    }

    private func actionButton(action: VoiceAction) -> some View {
        let isHovered = hoveredAction == action
        return Button {
            engine.handleUserCommand(action: action, entries: appState.transcriptManager.entries)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: action.iconName)
                    .font(.system(size: isCompactLayout ? 10 : 11, weight: .medium))
                Text(action.displayLabel)
                    .font(.system(size: isCompactLayout ? 11 : 12, weight: .medium))
            }
            .foregroundStyle(isHovered ? .primary : .secondary)
            .padding(.horizontal, isCompactLayout ? 7 : 8)
            .padding(.vertical, isCompactLayout ? 3 : 4)
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
            Text("Thinking")
                .font(.system(size: isCompactLayout ? 11 : 12, weight: .medium))
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

struct TranscriptPanelView: View {
    @Bindable var appState: AppState

    var body: some View {
        GlassPanel {
            VStack(spacing: 0) {
                header
                Divider()
                    .padding(.horizontal, 12)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(appState.transcriptManager.entries) { entry in
                                transcriptRow(entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .frame(height: Constants.UI.transcriptPanelHeight)
                    .onChange(of: appState.transcriptManager.entries.count) { _, _ in
                        if let lastID = appState.transcriptManager.entries.last?.id {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: TranscriptPanelHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(TranscriptPanelHeightKey.self) { height in
            guard abs(appState.transcriptPanelMeasuredHeight - height) > 1 else { return }
            appState.transcriptPanelMeasuredHeight = height
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transcript")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                statusCard(
                    title: TranscriptEntry.Speaker.me.displayLabel,
                    status: appState.captureStatusText(for: .me),
                    preview: appState.lastTranscriptPreview(for: .me),
                    diagnostics: appState.captureDiagnosticsText(for: .me),
                    color: .green,
                    audioLevel: appState.micCaptureState.audioLevel
                )
                statusCard(
                    title: TranscriptEntry.Speaker.interviewer.displayLabel,
                    status: appState.captureStatusText(for: .interviewer),
                    preview: appState.lastTranscriptPreview(for: .interviewer),
                    diagnostics: appState.captureDiagnosticsText(for: .interviewer),
                    color: .blue,
                    audioLevel: appState.systemCaptureState.audioLevel
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func statusCard(
        title: String,
        status: String,
        preview: String,
        diagnostics: String,
        color: Color,
        audioLevel: Float = 0
    ) -> some View {
        let isActive = audioLevel > 0.005
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color.opacity(isActive ? 1.0 : 0.4))
                    .frame(width: 7, height: 7)
                    .scaleEffect(isActive ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: isActive)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
                Text(status)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(preview)
                .font(.system(size: 11))
                .lineLimit(2)
                .foregroundStyle(.secondary)

            Text(diagnostics)
                .font(.system(size: 10))
                .lineLimit(2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(0.05))
        )
    }

    private func transcriptRow(_ entry: TranscriptEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.speaker.displayLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(entry.speaker == .me ? Color.green : Color.blue)

                Text(entry.shortTimeLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 82, alignment: .leading)

            Text(entry.text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
