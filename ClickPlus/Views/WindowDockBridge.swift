import SwiftUI
import AppKit

/// Keep the Dock entry while a settings window exists, including when minimized.
/// Closing the last window returns to a menu-bar-only utility without stopping it.
struct WindowDockBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowObserverView { WindowObserverView() }
    func updateNSView(_ nsView: WindowObserverView, context: Context) {}
}

final class WindowObserverView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        DockPresence.shared.track(window)
    }
}

@MainActor final class DockPresence {
    static let shared = DockPresence()
    private var observations: [ObjectIdentifier: NSObjectProtocol] = [:]
    func track(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        guard observations[id] == nil else { return }
        NSApp.setActivationPolicy(.regular)
        observations[id] = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            guard let self else { return }
            if let token = self.observations.removeValue(forKey: id) { NotificationCenter.default.removeObserver(token) }
            if self.observations.isEmpty { NSApp.setActivationPolicy(.accessory) }
        }
    }
}
