import SwiftUI

struct MouseSettings: View {
    @EnvironmentObject var state: AppState
    @State private var selectedDPI = 1200
    var body: some View {
        Form {
            Section("Mouse Logitech") {
                if state.mouseDevices.isEmpty {
                    Text("Conecte um mouse Logitech para identificar o modelo.").foregroundStyle(.secondary)
                } else {
                    Picker("Modelo selecionado",selection: Binding(get: { state.device.id ?? state.mouseDevices.first?.id ?? "" },set: { state.hardware.selectMouse($0) })) {
                        ForEach(state.mouseDevices) { mouse in Text(mouse.name).tag(mouse.id) }
                    }
                    Text("As configurações globais são aplicadas ao mouse selecionado. Bateria, DPI e botões avançados variam conforme o modelo e a conexão.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Cursor") {
                Toggle("Personalizar cursor", isOn: $state.preferences.cursorEnabled)
                NumberControl(title: "Velocidade", value: $state.preferences.cursorSpeed, range: 0.1...5, help: "Multiplica o deslocamento do ponteiro do mouse. 1 é a base; 1,3 aumenta em 30%. O trackpad não recebe esse ajuste.")
                NumberControl(title: "Aceleração", value: $state.preferences.cursorAcceleration, range: 0...3, help: "Quanto maior o valor, maior o ganho quando você move o mouse rapidamente. Zero mantém uma resposta linear.")
                ModifierControl(title: "Velocidade temporária", value: $state.preferences.precisionModifier, help: "Segure a tecla escolhida enquanto move o mouse para usar o multiplicador temporário. Ao soltar, volta à velocidade normal. Nenhuma desativa essa função.")
                NumberControl(title: "Multiplicador temporário", value: $state.preferences.precisionGain, range: 0.1...3, help: "Ganho usado enquanto a tecla de velocidade temporária estiver pressionada. 0,3 reduz para 30%, útil para movimentos precisos.")
                Toggle("Manter ponteiro parado ao arrastar para rolar", isOn: $state.preferences.holdCursor)
                    .controlHelp("Ponteiro parado", "Durante o arrasto para rolar, mantém o ponteiro na posição inicial. O conteúdo se move, mas a seta fica no mesmo lugar.")
                LabeledContent("Frequência estimada", value: state.frequency > 0 ? "\(state.frequency) eventos/s" : "Mova o mouse com o serviço ativo")
                    .controlHelp("Frequência estimada", "Quantidade aproximada de eventos recebidos por segundo durante o uso. Varia com o movimento e a conexão; não é uma medição fixa da frequência do sensor.")
            }
            Section(state.device.name) {
                LabeledContent("Conexão", value: state.device.transport.replacingOccurrences(of: "Bluetooth Low Energy", with: "Bluetooth de baixo consumo"))
                LabeledContent("Bateria", value: state.device.battery.map { "\($0)%" } ?? "Não disponível")
                LabeledContent("Sensibilidade do sensor (DPI)", value: state.device.dpi.map(String.init) ?? "Não confirmado")
                    .controlHelp("Sensibilidade do sensor", "DPI significa pontos por polegada: é a sensibilidade física do sensor do mouse. Valores maiores fazem o ponteiro percorrer mais distância para o mesmo movimento da mão. Só muda ao clicar em Aplicar DPI; Restaurar DPI anterior recupera o valor guardado.")
                if !state.device.dpiValues.isEmpty {
                    Picker("Novo DPI", selection: $selectedDPI) { ForEach(state.device.dpiValues, id: \.self) { Text(String($0)).tag($0) } }
                    HStack {
                        Button("Aplicar DPI") { state.hardware.setDPI(selectedDPI) }
                        Button("Restaurar DPI anterior") { state.hardware.restoreDPI() }.disabled(!state.device.dpiControlled)
                    }
                }
                LabeledContent("Captura avançada de botões",value: state.device.buttonCaptureAvailable ? "Interface disponível" : "Não confirmada nesta conexão")
                Text(state.device.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Button("Consultar dispositivo") { state.hardware.refresh() }
            }
            Section("Botões laterais") {
                Toggle("Capturar botão lateral traseiro", isOn: $state.preferences.captureBack)
                Toggle("Capturar botão lateral dianteiro", isOn: $state.preferences.captureForward)
                Text("A captura habilita as atribuições da seção Botões. Desativada, mantém os eventos originais.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
        .onChange(of: state.device.dpi) { _, value in if let value { selectedDPI = value } }
    }
}
