import SwiftUI
import AppKit

struct ButtonSettings: View {
    @EnvironmentObject var state: AppState
    @State private var recording: Int?
    @State private var monitor: Any?
    private func binding(_ button: Int) -> Binding<ButtonAction> {
        Binding(get: { state.preferences.buttons[button] ?? .init() }, set: { state.assignButton(button, action: $0) })
    }
    var body: some View {
        Form {
            Section {
                if state.capturingButton {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Pressione e solte a roda ou um botão lateral do mouse selecionado.")
                        Spacer()
                        Button("Cancelar") { state.cancelButtonCapture() }
                    }
                    Text("O clique de identificação não executa nenhuma função. Esc cancela.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button { state.beginButtonCapture() } label: { Label("Adicionar botão", systemImage: "plus.circle.fill") }
                    Text("Pressione o botão do mouse e depois escolha o que ele faz. Botões já adicionados serão editados, sem duplicação.").font(.caption).foregroundStyle(.secondary)
                }
                Button("Restaurar cliques nativos do mouse") { state.recoverNativeButtons() }
                    .disabled(state.capturingButton)
                    .controlHelp("Restaurar cliques", "Use se os laterais pararam após usar outro controlador. Restaura o envio de cliques pelo mouse, preservando as atribuições deste app.")
                if let hint = state.captureHint { Text(hint).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Último acionamento") {
                Text(state.diagnostics.lastButtonAction).foregroundStyle(.secondary)
            }
            Section("Atribuições") {
                ForEach(state.preferences.buttons.keys.sorted(), id: \.self) { button in
                    let action = binding(button)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Picker(DetectedButton.name(button), selection: action.kind) { ForEach(ActionKind.allCases) { Text($0.displayName).tag($0) } }
                            ControlHelp(title: action.wrappedValue.kind.displayName, text: action.wrappedValue.kind.explanation)
                            Button { state.preferences.buttons.removeValue(forKey: button) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).help("Remover atribuição")
                        }
                        if action.wrappedValue.kind == .shortcut {
                            Button(recording == button ? "Pressione o atalho… Esc cancela" : action.wrappedValue.label) { beginRecording(button) }
                        }
                        if action.wrappedValue.kind == .application {
                            HStack {
                                Text(action.wrappedValue.applicationPath.isEmpty ? "Nenhum aplicativo escolhido" : URL(fileURLWithPath: action.wrappedValue.applicationPath).deletingPathExtension().lastPathComponent).foregroundStyle(.secondary)
                                Spacer(); Button("Escolher…") { chooseApplication(button) }
                            }
                            EmptyView()
                        }
                        if button == 3 && !state.preferences.captureBack || button == 4 && !state.preferences.captureForward {
                            Text("Habilite a captura deste botão na seção Mouse.").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }
            }
            Section("Arrastar para rolar") {
                Text("Segure o botão escolhido e mova o mouse para rolar a página, sem girar a rodinha. Um clique curto continua executando a função cadastrada.").font(.callout)
                Picker("Botão usado para arrastar", selection: $state.preferences.panButton) {
                    Text("Desativado").tag(-1); Text("Esquerdo").tag(0); Text("Direito").tag(1); Text("Clique da roda").tag(2); Text("Lateral traseiro").tag(3); Text("Lateral dianteiro").tag(4)
                }
                Toggle("Inverter direção do arrasto", isOn: $state.preferences.panInvert)
                    .controlHelp("Direção do arrasto", "Troca o sentido em que a página se move quando você arrasta o mouse.")
                Toggle("Continuar com inércia", isOn: $state.preferences.panMomentum)
                    .controlHelp("Inércia", "Ao soltar o botão depois de arrastar, a rolagem continua por um instante e desacelera. Desligue para parar ao soltar.")
                Toggle("Rolar em janela inativa ao arrastar", isOn: $state.preferences.panClickThrough)
                    .controlHelp("Janela inativa", "Permite começar a rolar uma janela que está ao fundo: o primeiro arrasto traz a janela à frente e já rola seu conteúdo, sem um clique adicional.")
            }
            Section("Clicar em janela inativa") {
                Toggle("Clique esquerdo em janela inativa", isOn: $state.preferences.leftClickThrough)
                    .controlHelp("Primeiro clique esquerdo", "Traz a janela sob o ponteiro para a frente e encaminha o mesmo clique. Não cria um clique extra. Alguns aplicativos podem tratar esse primeiro clique de outra forma.")
                Toggle("Clique direito em janela inativa", isOn: $state.preferences.rightClickThrough)
                    .controlHelp("Primeiro clique direito", "Traz a janela sob o ponteiro para a frente e encaminha o clique direito, por exemplo para abrir seu menu de opções.")
                Text("Ativa a janela e encaminha a primeira interação, sem gerar clique extra. O comportamento também depende do aplicativo de destino.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
        .sheet(item: $state.capturedButton) { detected in
            ButtonActionEditor(button: detected.id, initial: state.preferences.buttons[detected.id] ?? .init()) { action in
                state.assignButton(detected.id, action: action)
                state.capturedButton = nil
            }
        }
        .onExitCommand { state.cancelButtonCapture() }
        .onDisappear { endRecording(); state.cancelButtonCapture() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if state.capturingButton { state.cancelButtonCapture() }
        }
    }
    private func chooseApplication(_ button: Int) {
        let panel = NSOpenPanel(); panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.allowedContentTypes = [.applicationBundle]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { var action = state.preferences.buttons[button] ?? .init(); action.applicationPath = url.path; state.preferences.buttons[button] = action }
    }
    private func beginRecording(_ button: Int) {
        endRecording(); recording = button
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode != 53 {
                var action = state.preferences.buttons[button] ?? .init()
                action.keyCode = event.keyCode
                let flags = event.modifierFlags.intersection([.command,.shift,.control,.option])
                action.flags = UInt64(flags.rawValue)
                action.label = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "") + (event.charactersIgnoringModifiers?.uppercased() ?? "Tecla \(event.keyCode)")
                state.preferences.buttons[button] = action
            }
            endRecording(); return nil
        }
    }
    private func endRecording() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; recording = nil }
}
