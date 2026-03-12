import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private let panelController = FloatingPanelController()
    private var lastPanelHeight: CGFloat = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = FloatingBarView(appState: appState)
        panelController.createPanel(contentView: contentView)
        panelController.show()

        Task {
            await appState.setup()
        }

        observePanelMode()
        observeMeasuredPanelHeights()

        // Register global shortcut: Cmd+Enter to toggle listening
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command) && event.keyCode == 36 { // 36 = Return
                Task { @MainActor in
                    await self?.appState.toggleListening()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.audioManager.aggregateManager.cleanup()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Panel mode (show/hide/switch)

    private func observePanelMode() {
        withObservationTracking {
            _ = appState.panelMode
            _ = appState.isListening
            _ = appState.isTranscriptOverlayVisible
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updatePanelMode()
                self.observePanelMode()
            }
        }
    }

    private func updatePanelMode() {
        let contentHeight = computeVisibleContentHeight()
        guard contentHeight > 0 else {
            lastPanelHeight = 0
            let barWidth = appState.isListening ? Constants.UI.barWidthListening : Constants.UI.barWidth
            panelController.hideChat(barWidth: barWidth)
            return
        }

        lastPanelHeight = contentHeight
        panelController.showContent(
            width: Constants.UI.chatPanelWidth,
            contentHeight: contentHeight
        )
    }

    // MARK: - Measured panel resize

    private func observeMeasuredPanelHeights() {
        withObservationTracking {
            _ = appState.askPanelMeasuredHeight
            _ = appState.voicePanelMeasuredHeight
            _ = appState.transcriptPanelMeasuredHeight
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if self.appState.isChatVisible {
                    let contentHeight = self.computeVisibleContentHeight()
                    if abs(contentHeight - self.lastPanelHeight) > 1 {
                        self.lastPanelHeight = contentHeight
                        self.panelController.showContent(
                            width: Constants.UI.chatPanelWidth,
                            contentHeight: contentHeight
                        )
                    }
                }

                self.observeMeasuredPanelHeights()
            }
        }
    }

    private func computeVisibleContentHeight() -> CGFloat {
        var sections: [CGFloat] = []

        switch appState.panelMode {
        case .hidden:
            break
        case .ask:
            sections.append(resolvedAskPanelHeight())
        case .voiceSuggestions:
            sections.append(resolvedVoicePanelHeight())
        }

        if appState.isTranscriptOverlayVisible {
            sections.append(resolvedTranscriptPanelHeight())
        }

        guard !sections.isEmpty else { return 0 }

        let panelsHeight = sections.reduce(0, +)
        let spacingHeight = Constants.UI.panelStackSpacing * CGFloat(sections.count - 1)
        return panelsHeight + spacingHeight
    }

    private func resolvedAskPanelHeight() -> CGFloat {
        max(appState.askPanelMeasuredHeight, estimatedAskPanelHeight())
    }

    private func resolvedVoicePanelHeight() -> CGFloat {
        max(appState.voicePanelMeasuredHeight, estimatedVoicePanelHeight())
    }

    private func resolvedTranscriptPanelHeight() -> CGFloat {
        max(appState.transcriptPanelMeasuredHeight, estimatedTranscriptPanelHeight())
    }

    private func estimatedAskPanelHeight() -> CGFloat {
        let responseHeight = computeAskResponseHeight(maxHeight: Constants.UI.askResponseMaxHeight)
        return Constants.UI.inputBarHeight + responseHeight + (responseHeight > 0 ? 1 : 0)
    }

    private func estimatedVoicePanelHeight() -> CGFloat {
        let isCompact = appState.isTranscriptOverlayVisible
        let responseHeight = computeVoiceResponseHeight(
            maxHeight: isCompact ? Constants.UI.voiceResponseCompactMaxHeight : Constants.UI.voiceResponseMaxHeight
        )
        let headerHeight: CGFloat = isCompact ? 42 : 46
        return headerHeight + responseHeight + (responseHeight > 0 ? 1 : 0)
    }

    private func estimatedTranscriptPanelHeight() -> CGFloat {
        Constants.UI.transcriptPanelHeight + 120
    }

    private func computeVoiceResponseHeight(maxHeight: CGFloat) -> CGFloat {
        let engine = appState.suggestionEngine
        let hasResponse = engine.isStreaming || !engine.displayedText.isEmpty
        guard hasResponse else { return 0 }
        return min(engine.contentHeight, maxHeight)
    }

    private func computeAskResponseHeight(maxHeight: CGFloat) -> CGFloat {
        let hasResponse = appState.isAskStreaming || !appState.askDisplayedText.isEmpty
        guard hasResponse else { return 0 }
        return min(appState.askContentHeight, maxHeight)
    }
}
