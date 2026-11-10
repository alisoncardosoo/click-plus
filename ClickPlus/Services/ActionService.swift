import AppKit
import CoreGraphics

enum ActionService {
    static var onError: ((String) -> Void)?
    private static var previousApplications: [String: NSRunningApplication] = [:]
    private static var opening: Set<String> = []
    static let marker: Int64 = 0x5241544F
    static func post(_ event: CGEvent) { event.setIntegerValueField(.eventSourceUserData, value: marker); event.post(tap: .cghidEventTap) }
    static func key(_ code: UInt16, flags: CGEventFlags) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { continue }
            event.flags = flags; post(event)
        }
    }
    static func perform(_ action: ButtonAction) {
        switch action.kind {
        case .original: break
        case .missionControl: openApplication("/System/Applications/Mission Control.app")
        case .back: key(33, flags: .maskCommand)
        case .forward: key(30, flags: .maskCommand)
        case .copy: key(8, flags: .maskCommand)
        case .paste: key(9, flags: .maskCommand)
        case .shortcut: key(action.keyCode, flags: CGEventFlags(rawValue: action.flags))
        case .application:
            guard !action.applicationPath.isEmpty else { return }
            openApplication(action.applicationPath, toggle: true)
        }
    }
    static func shouldHideApplication(isActive: Bool, isHidden: Bool, toggle: Bool) -> Bool {
        toggle && isActive && !isHidden
    }
    private static func openApplication(_ path: String, toggle: Bool = false) {
        DispatchQueue.main.async {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            let target = NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL == url }
            if let target, shouldHideApplication(isActive: target.isActive, isHidden: target.isHidden, toggle: toggle) {
                if target.bundleIdentifier == "app.remixdesign.LaunchOS" {
                    // LaunchOS is an accessory panel and rejects NSRunningApplication.hide().
                    // Escape dismisses its launcher; target the exact process, not the foreground app.
                    for down in [true, false] {
                        if let event = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down) {
                            event.flags = []
                            event.setIntegerValueField(.eventSourceUserData, value: marker)
                            event.postToPid(target.processIdentifier)
                        }
                    }
                    let previous = previousApplications.removeValue(forKey: path)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        if target.isActive, let previous, !previous.isTerminated { previous.activate(options: []) }
                    }
                    return
                }
                if target.hide() {
                    if let previous = previousApplications.removeValue(forKey: path), !previous.isTerminated {
                        previous.activate(options: [])
                    }
                } else { onError?("O aplicativo não permitiu ocultar sua interface.") }
                return
            }
            guard !opening.contains(path) else { return }
            if toggle, let previous = NSWorkspace.shared.frontmostApplication, previous.processIdentifier != target?.processIdentifier {
                previousApplications[path] = previous
            }
            opening.insert(path)
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                DispatchQueue.main.async {
                    opening.remove(path)
                    if let error {
                        previousApplications.removeValue(forKey: path)
                        onError?("Não foi possível abrir o aplicativo: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
