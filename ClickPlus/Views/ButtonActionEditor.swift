import SwiftUI
import AppKit

struct ButtonActionEditor: View {
    let button: Int
    let editorTitle: String?
    let save: (ButtonAction) -> Void
    @State private var action: ButtonAction
    @State private var recording = false
    @State private var monitor: Any?
    @Environment(\.dismiss) private var dismiss
    init(button: Int, initial: ButtonAction, editorTitle: String? = nil, save: @escaping (ButtonAction) -> Void) {
        self.button = button; self.editorTitle = editorTitle; self.save = save; _action = State(initialValue: initial)
    }
    private var isValid: Bool {
        if action.kind == .application { return !action.applicationPath.isEmpty }
        if action.kind == .shortcut { return action.label != "Gravar atalho" }
        return true
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(editorTitle == nil ? "Botão identificado" : "Ação da borda", systemImage: "checkmark.circle.fill").foregroundStyle(Color.clickAccent)
            Text(editorTitle ?? DetectedButton.name(button)).font(.title2.bold())
            Picker("Função", selection: $action.kind) {
                ForEach(ActionKind.allCases) { Text($0.displayName).tag($0) }
            }
            Text(action.kind.explanation).font(.callout).foregroundStyle(.secondary)
            if action.kind == .shortcut {
                Button(recording ? "Pressione o atalho… Esc cancela" : action.label) { recordShortcut() }
            }
            if action.kind == .application {
                HStack {
                    Text(action.applicationPath.isEmpty ? "Nenhum aplicativo escolhido" : URL(fileURLWithPath: action.applicationPath).deletingPathExtension().lastPathComponent)
                        .foregroundStyle(.secondary)
                    Spacer(); Button("Escolher…") { chooseApplication() }
                }
            }
            Text(editorTitle == nil ? "Ao salvar, a captura deste botão será habilitada. Os cliques principais e o trackpad continuam com suas funções." : "Essa ação será executada uma vez por deslize. Levante o dedo para repetir. Original significa sem ação personalizada.")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Salvar função") { stopRecording(); save(action) }.keyboardShortcut(.defaultAction).disabled(!isValid || recording)
            }
        }.padding(28).frame(width: 460).onDisappear { stopRecording() }
        .onChange(of: action.kind) { _, _ in stopRecording() }
    }
    private func chooseApplication() {
        let panel = NSOpenPanel(); panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { action.applicationPath = url.path }
    }
    private func recordShortcut() {
        stopRecording(); recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode != 53 {
                let flags = event.modifierFlags.intersection([.command,.shift,.control,.option])
                action.keyCode = event.keyCode; action.flags = UInt64(flags.rawValue)
                action.label = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "") + (event.charactersIgnoringModifiers?.uppercased() ?? "Tecla \(event.keyCode)")
            }
            stopRecording(); return nil
        }
    }
    private func stopRecording() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; recording = false }
}
