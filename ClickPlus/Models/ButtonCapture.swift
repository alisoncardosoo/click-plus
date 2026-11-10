import Foundation
import CoreGraphics

/// Tracks a complete physical click. No action is emitted until its release;
/// cancellation preserves the pending release so it cannot leak to another app.
struct ButtonCapture {
    enum Result: Equatable { case pass, consume, detected(Int) }
    private(set) var waiting = false
    private(set) var heldButton: Int?
    private var discardedRelease: Int?
    mutating func begin() { cancel(); waiting = true }
    mutating func cancel() {
        if let heldButton { discardedRelease = heldButton }
        heldButton = nil; waiting = false
    }
    mutating func process(type: CGEventType, button: Int, isTarget: Bool) -> Result {
        guard isTarget else { return .pass }
        let down = type == .otherMouseDown
        let up = type == .otherMouseUp
        if up, button == discardedRelease { discardedRelease = nil; return .consume }
        if down, button == discardedRelease { discardedRelease = nil }
        guard waiting, button >= 2 else { return .pass }
        if down, heldButton == nil { heldButton = button; return .consume }
        if button == heldButton {
            if up { heldButton = nil; waiting = false; return .detected(button) }
            if type == .otherMouseDragged || down { return .consume }
        }
        return .pass
    }
}

struct DetectedButton: Identifiable {
    let id: Int
    static func name(_ id: Int) -> String {
        switch id {
        case 2: return "Clique da roda"
        case 3: return "Botão lateral 1"
        case 4: return "Botão lateral 2"
        default: return "Botão \(id + 1)"
        }
    }
}

struct InputDiagnostics {
    var mouseEvents = 0
    var trackpadPassed = 0
    var scrollTransforms = 0
    var cursorTransforms = 0
    var mappedActions = 0
    var lastAction = "Nenhuma"
    var lastButtonAction = "Nenhum botão acionado nesta execução"
    var lastSource = "Aguardando entrada física"
    var pointerStatus = "Não solicitado"
}
