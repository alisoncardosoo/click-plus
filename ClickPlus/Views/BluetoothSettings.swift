import SwiftUI

struct BluetoothSettings: View {
    @EnvironmentObject var bluetooth: BluetoothBatteryService
    var body: some View {
        Form {
            Section("Periféricos conectados") {
                if let error = bluetooth.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
                } else if bluetooth.devices.isEmpty {
                    Text(bluetooth.refreshing ? "Consultando Bluetooth…" : "Nenhum outro periférico Bluetooth conectado.").foregroundStyle(.secondary)
                }
                ForEach(bluetooth.devices) { device in
                    LabeledContent {
                        Text(device.summary).monospacedDigit().foregroundStyle(.secondary)
                    } label: { Label(device.name, systemImage: device.icon) }
                    ForEach(device.levels.filter { $0.lastKnownAt != nil }) { level in
                        if let note = level.readingNote {
                            Text("Estojo · \(note)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if device.caseBatteryUnavailable {
                        LabeledContent("Estojo", value: "Bateria não informada")
                        Text("Abra o estojo com pelo menos um fone dentro e toque em Atualizar agora.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button(bluetooth.refreshing ? "Atualizando…" : "Atualizar agora") { bluetooth.refresh() }
                    .disabled(bluetooth.refreshing)
            }
            Section("Leitura de bateria") {
                Text("Conecte seu fone ou outro acessório nos ajustes Bluetooth do macOS. A lista é atualizada a cada 30 segundos e ao abrir o menu. Os níveis do Galaxy Buds2 são recebidos em tempo real enquanto ele está conectado.")
                Text("Galaxy Buds2: leitura direta da bateria esquerda e direita pelo Bluetooth. Ao fechar a tampa, a última leitura válida do estojo é mantida com data e hora enquanto o app estiver aberto. Para outros modelos, os níveis dependem das informações fornecidas pelo macOS.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).onAppear { bluetooth.refresh() }
    }
}
