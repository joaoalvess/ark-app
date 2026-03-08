import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private let panelController = FloatingPanelController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = FloatingBarView(appState: appState)
        panelController.createPanel(contentView: contentView)
        panelController.show()

        Task {
            await appState.setup()
        }

        observeChatVisibility()

        // Register global shortcut: Cmd+Enter to toggle listening
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command) && event.keyCode == 36 { // 36 = Return
                Task { @MainActor in
                    await self?.appState.toggleListening()
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func observeChatVisibility() {
        withObservationTracking {
            _ = appState.isChatVisible
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.appState.isChatVisible {
                    self.panelController.showChat()
                } else {
                    self.panelController.hideChat()
                }
                self.observeChatVisibility()
            }
        }
    }
}
