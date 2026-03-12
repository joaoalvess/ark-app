import AppKit
import SwiftUI

private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class FloatingPanelController {
    private var panel: NSPanel?

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func createPanel<Content: View>(contentView: Content) {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: Constants.UI.barWidth, height: Constants.UI.barHeight),
            styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = panel.contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hostingView)

        // Position at top-center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - Constants.UI.barWidth / 2
            let y = screenFrame.maxY - Constants.UI.barHeight - 20
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.panel = panel
    }

    func show() {
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func resize(width: CGFloat, height: CGFloat, animate: Bool = true) {
        guard let panel else { return }
        let currentFrame = panel.frame
        let newFrame = NSRect(
            x: currentFrame.origin.x - (width - currentFrame.width) / 2,
            y: currentFrame.origin.y + currentFrame.height - height,
            width: width,
            height: height
        )
        panel.setFrame(newFrame, display: true, animate: animate)
    }

    func makeKey() {
        panel?.makeKey()
    }

    func resignKey() {
        panel?.resignKey()
    }

    func showAsk(responseHeight: CGFloat) {
        let width = Constants.UI.chatPanelWidth
        let height = Constants.UI.barHeight + 8 + Constants.UI.inputBarHeight + responseHeight
        resize(width: width, height: height)
        makeKey()
    }

    func showVoice(responseHeight: CGFloat) {
        let width = Constants.UI.chatPanelWidth
        let height = Constants.UI.barHeight + 8 + Constants.UI.voiceButtonsHeight + responseHeight
        resize(width: width, height: height)
        makeKey()
    }

    func showChat() {
        let width = Constants.UI.chatPanelWidth
        let height = Constants.UI.barHeight + 8 + Constants.UI.chatPanelHeight
        resize(width: width, height: height)
        makeKey()
    }

    func hideChat(barWidth: CGFloat = Constants.UI.barWidth) {
        resize(width: barWidth, height: Constants.UI.barHeight)
        resignKey()
    }
}
