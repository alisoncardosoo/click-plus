import SwiftUI
import UserNotifications

struct BatteryAlertSettings: View {
    @ObservedObject var alerts: BatteryAlertService
    @Environment(\.scenePhase) private var scenePhase

    private func binding<Value>(_ path: WritableKeyPath<BatteryAlertPreferences, Value>) -> Binding<Value> {
        Binding(get: { alerts.preferences[keyPath: path] }, set: { value in
            var preferences = alerts.preferences
            preferences[keyPath: path] = value
            alerts.update(preferences)
        })
    }

    var body: some View {
        Section("Avisos de bateria") {
            Toggle("Notificar quando a bateria estiver baixa", isOn: binding(\.enabled))
            Group {
                Stepper("Bateria baixa: \(alerts.preferences.low)%", value: binding(\.low), in: (alerts.preferences.critical + 1)...100)
                Stepper("Bateria crítica: \(alerts.preferences.critical)%", value: binding(\.critical), in: 1...(alerts.preferences.low - 1))
                Toggle("Reproduzir som", isOn: binding(\.sound))
            }.disabled(!alerts.preferences.enabled)
            if alerts.preferences.enabled {
                if alerts.authorization == .denied {
                    Text("As notificações estão bloqueadas pelo macOS. Permita os avisos do Click + nos Ajustes do Sistema.").foregroundStyle(.orange)
                    Button("Abrir ajustes de notificações") { alerts.openSystemSettings() }
                } else if alerts.authorization == .notDetermined {
                    Button("Permitir notificações") { alerts.requestPermission() }.disabled(alerts.requestingPermission)
                } else {
                    Text("Notificações autorizadas no macOS.").foregroundStyle(.secondary)
                }
            }
            if let error = alerts.error { Text(error).foregroundStyle(.orange) }
            Text("Os limites valem para o mouse selecionado, teclados e acessórios com bateria informada pelo macOS. Cada nível avisa uma vez; novos avisos são liberados após uma recarga acima do limite de bateria baixa, com margem de 3 pontos. O Click + precisa estar em execução, inclusive na barra de menus.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { alerts.refreshAuthorization() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { alerts.refreshAuthorization() } }
    }
}
