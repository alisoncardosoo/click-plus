import Foundation
import CoreGraphics

enum Modifier: String, Codable, CaseIterable, Identifiable {
    case none = "Nenhuma", shift = "Shift", control = "Control", command = "Command", option = "Option"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none: return "Nenhuma"
        case .shift: return "Maiúsculas (Shift ⇧)"
        case .control: return "Controle (⌃)"
        case .command: return "Comando (⌘)"
        case .option: return "Opção (⌥)"
        }
    }
    var flag: CGEventFlags {
        switch self { case .none: return []; case .shift: return .maskShift; case .control: return .maskControl; case .command: return .maskCommand; case .option: return .maskAlternate }
    }
    func matches(_ flags: CGEventFlags) -> Bool { self != .none && flags.contains(flag) }
}
enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case original = "Original", missionControl = "Mission Control", back = "Voltar", forward = "Avançar", copy = "Copiar", paste = "Colar", shortcut = "Atalho", application = "Abrir aplicativo"
    var id: String { rawValue }
    var displayName: String { self == .missionControl ? "Visão de janelas" : rawValue }
    var explanation: String {
        switch self {
        case .original: return "Mantém a função original deste botão, sem executar uma ação personalizada."
        case .missionControl: return "Abre a visão geral das janelas do macOS, chamada Mission Control. Pressione novamente para sair."
        case .back: return "Volta à página ou etapa anterior em aplicativos que aceitam o atalho Comando + [."
        case .forward: return "Avança à próxima página em aplicativos que aceitam o atalho Comando + ]."
        case .copy: return "Copia a seleção atual usando Comando + C."
        case .paste: return "Cola o conteúdo copiado usando Comando + V."
        case .shortcut: return "Grave uma combinação de teclas. O botão enviará esse atalho ao aplicativo em foco."
        case .application: return "Abre o aplicativo escolhido. Se ele já estiver em foco, o próximo clique oculta sua interface e retorna ao aplicativo anterior, sem encerrá-lo."
        }
    }
}
struct ButtonAction: Codable, Equatable {
    var kind: ActionKind = .original
    var keyCode: UInt16 = 0
    var flags: UInt64 = 0
    var label = "Gravar atalho"
    var applicationPath = ""
}
struct Preferences: Codable, Equatable {
    var version = 1
    var enabled = true
    var scrollEnabled = false
    var smooth = false
    var duration = 0.16
    var brake = 0.35
    var scrollSpeed = 1.0
    var scrollAcceleration = 0.0
    var extraSmooth = 0.0
    var invertVertical = false
    var horizontalSpeed = 1.0
    var invertHorizontal = false
    var raiseOnScroll = false
    var verticalSliders = false
    var horizontalSliders = false
    var horizontalModifier = Modifier.shift
    var zoomModifier = Modifier.control
    var speedModifier = Modifier.command
    var modifierGain = 2.0
    var invertZoom = false
    var invertModifiedHorizontal = false
    var cursorEnabled = false
    var cursorSpeed = 1.0
    var cursorAcceleration = 0.0
    var precisionModifier = Modifier.none
    var precisionGain = 0.3
    var holdCursor = false
    var captureBack = false
    var captureForward = false
    var buttons: [Int: ButtonAction] = [2: .init(), 3: .init(), 4: .init()]
    var panButton = -1
    var panInvert = false
    var panMomentum = false
    var panClickThrough = false
    var leftClickThrough = false
    var rightClickThrough = false
    func captures(_ button: Int) -> Bool {
        guard button >= 2 else { return false }
        if button == 3 { return captureBack }
        if button == 4 { return captureForward }
        return buttons[button] != nil
    }
    func needsHardwareButton(_ button: Int) -> Bool {
        enabled && button >= 2 && (panButton == button || hardwareAction(button) != nil)
    }
    func hardwareAction(_ button: Int) -> ButtonAction? {
        guard enabled, captures(button), panButton != button,
              let action = buttons[button], action.kind != .original else { return nil }
        return action
    }
    mutating func assign(_ action: ButtonAction, to button: Int) {
        guard button >= 2 else { return }
        buttons[button] = action
        if button == 3 { captureBack = true }
        if button == 4 { captureForward = true }
    }
}

/// A normalized impulse: controls change its shape, never its total distance.
enum ScrollMath {
    static func weights(duration: Double, brake: Double, extra: Double, rate: Double = 120) -> [Double] {
        let count = max(2, Int(min(1, max(0.02, duration)) * rate))
        let peak = max(0.05, min(0.95, brake))
        let values = (0..<count).map { i -> Double in
            let t = (Double(i) + 0.5) / Double(count)
            let triangle = t < peak ? t / peak : (1-t)/(1-peak)
            return pow(max(0, triangle), 1 + min(5, max(0, extra)) * 0.3)
        }
        let total = values.reduce(0,+)
        return values.map { $0 / total }
    }
    static func distance(_ delta: Double, speed: Double, acceleration: Double) -> Double {
        delta * max(0.1, min(10, speed)) * (1 + min(5, max(0, acceleration)) * min(abs(delta), 40) / 40)
    }
}
