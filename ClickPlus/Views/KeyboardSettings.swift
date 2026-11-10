import SwiftUI

struct KeyboardSettings: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Form {
            Section("Teclados Logitech") {
                if state.keyboardBatteries.isEmpty {
                    Label("Nenhum teclado conectado",systemImage: "keyboard").foregroundStyle(.secondary)
                    Text("Conecte o teclado e pressione uma tecla para acordá-lo.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(state.keyboardBatteries) { keyboard in
                        LabeledContent { Text(keyboard.description).monospacedDigit().foregroundStyle(Color.clickAccent) } label: { Label(keyboard.name,systemImage: "keyboard") }
                    }
                }
            }
            Section("Atualização automática") {
                Text("A bateria é consultada a cada 30 segundos e ao abrir o menu da barra superior. Um teclado em repouso pode precisar ser acordado para responder.").foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}

struct MouseWorkspace: View {
    @State private var tab = "Ponteiro"
    var body: some View {
        VStack(spacing: 0) {
            Picker("Configurações do mouse",selection: $tab) {
                Text("Ponteiro e sensor").tag("Ponteiro")
                Text("Rolagem").tag("Rolagem")
                Text("Botões").tag("Botões")
            }.pickerStyle(.segmented).padding(.horizontal,28).padding(.vertical,12)
            switch tab {
            case "Rolagem": ScrollSettings()
            case "Botões": ButtonSettings()
            default: MouseSettings()
            }
        }
    }
}
