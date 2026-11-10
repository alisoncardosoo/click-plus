import AppKit
import ApplicationServices

final class AccessibilityService {
    private let system = AXUIElementCreateSystemWide()
    init() { AXUIElementSetMessagingTimeout(system, 0.03) }
    private func element(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &element) == .success else { return nil }
        return element
    }
    private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value
    }
    func raise(at point: CGPoint) {
        guard let element = element(at: point) else { return }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        if let window = attribute(element, kAXWindowAttribute as CFString) {
            AXUIElementPerformAction(window as! AXUIElement, kAXRaiseAction as CFString)
        }
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
    }
    func adjustSlider(at point: CGPoint, delta: Double) -> Bool {
        guard delta != 0, var node = element(at: point) else { return false }
        for _ in 0..<4 {
            if attribute(node, kAXRoleAttribute as CFString) as? String == kAXSliderRole {
                var writable = DarwinBoolean(false)
                if AXUIElementIsAttributeSettable(node, kAXValueAttribute as CFString, &writable) == .success, writable.boolValue,
                   let current = attribute(node, kAXValueAttribute as CFString) as? NSNumber,
                   let minimum = attribute(node, kAXMinValueAttribute as CFString) as? NSNumber,
                   let maximum = attribute(node, kAXMaxValueAttribute as CFString) as? NSNumber {
                    let step = (maximum.doubleValue - minimum.doubleValue) / 100
                    let next = min(maximum.doubleValue, max(minimum.doubleValue, current.doubleValue + (delta > 0 ? step : -step)))
                    return AXUIElementSetAttributeValue(node, kAXValueAttribute as CFString, NSNumber(value: next)) == .success
                }
                return AXUIElementPerformAction(node, (delta > 0 ? kAXIncrementAction : kAXDecrementAction) as CFString) == .success
            }
            guard let parent = attribute(node, kAXParentAttribute as CFString) else { break }
            node = parent as! AXUIElement
        }
        return false
    }
}
