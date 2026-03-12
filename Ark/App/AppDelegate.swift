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
        observeAskResize()
        observeVoiceResize()

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
            _ = appState.isChatVisible
            _ = appState.isListening
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updatePanelMode()
                self.observePanelMode()
            }
        }
    }

    private func updatePanelMode() {
        if appState.isChatVisible {
            if appState.isListening {
                let responseHeight = computeVoiceResponseHeight()
                lastPanelHeight = responseHeight
                panelController.showVoice(responseHeight: responseHeight)
            } else {
                let responseHeight = computeAskResponseHeight()
                lastPanelHeight = responseHeight
                panelController.showAsk(responseHeight: responseHeight)
            }
        } else {
            lastPanelHeight = 0
            let barWidth = appState.isListening ? Constants.UI.barWidthListening : Constants.UI.barWidth
            panelController.hideChat(barWidth: barWidth)
        }
    }

    // MARK: - Ask panel dynamic resize (during streaming)

    private func observeAskResize() {
        withObservationTracking {
            _ = appState.askContentHeight
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if self.appState.isChatVisible && !self.appState.isListening {
                    let responseHeight = self.computeAskResponseHeight()
                    // Only resize if height changed meaningfully
                    if abs(responseHeight - self.lastPanelHeight) > 4 {
                        self.lastPanelHeight = responseHeight
                        self.panelController.showAsk(responseHeight: responseHeight)
                    }
                }

                self.observeAskResize()
            }
        }
    }

    // MARK: - Voice panel dynamic resize (during streaming)

    private func observeVoiceResize() {
        withObservationTracking {
            _ = appState.suggestionEngine.contentHeight
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if self.appState.isChatVisible && self.appState.isListening {
                    let responseHeight = self.computeVoiceResponseHeight()
                    if abs(responseHeight - self.lastPanelHeight) > 4 {
                        self.lastPanelHeight = responseHeight
                        self.panelController.showVoice(responseHeight: responseHeight)
                    }
                }

                self.observeVoiceResize()
            }
        }
    }

    private func computeVoiceResponseHeight() -> CGFloat {
        let engine = appState.suggestionEngine
        let hasResponse = engine.isStreaming || !engine.displayedText.isEmpty
        guard hasResponse else { return 0 }
        return min(engine.contentHeight, Constants.UI.voiceResponseMaxHeight)
    }

    private func computeAskResponseHeight() -> CGFloat {
        let hasResponse = appState.isAskStreaming || !appState.askDisplayedText.isEmpty
        guard hasResponse else { return 0 }
        return min(appState.askContentHeight, Constants.UI.askResponseMaxHeight)
    }
}
