import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var section = "Mouse"
    @State private var reset = false
    private let items = [("Mouse","computermouse"),("Teclado","keyboard"),("Trackpad","rectangle.and.hand.point.up.left"),("Ajustes","gearshape")]
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image("BrandIcon").resizable().scaledToFit()
                        .frame(width: 48, height: 48)
                        .accessibilityLabel("Ícone Click +")
                    VStack(alignment: .leading) { Text("Click +").font(.system(size: 16, weight: .semibold)); Text("Seu mouse. Seu ritmo.").font(.system(size: 11)).foregroundStyle(.secondary) }
                }.padding(20)
                List(selection: $section) { ForEach(items, id: \.0) { item in Label(item.0, systemImage: item.1).tag(item.0) } }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Circle().fill(state.trusted && state.inputAccess ? Color.clickAccent : Color.secondary).frame(width: 6, height: 6)
                        Text(state.trusted && state.inputAccess ? "Personalização ativa" : "Permissão pendente").font(.caption).foregroundStyle(.secondary)
                    }
                    Divider().padding(.vertical, 6)
                    sidebarBattery(state.device.name, percent: state.device.battery, icon: "computermouse")
                    ForEach(state.keyboardBatteries) { keyboard in sidebarBattery(keyboard.name, percent: keyboard.percent, icon: "keyboard") }
                }.padding(16)
            }.navigationSplitViewColumnWidth(min: 235, ideal: 245, max: 275)
        } detail: {
            VStack(spacing: 0) {
                pageHeader
                Divider()
                if !state.trusted {
                    HStack { Image(systemName: "hand.raised"); Text("Permita Acessibilidade para personalizar o mouse.").font(.callout); Spacer(); Button("Permitir") { state.requestAccess() } }.padding().background(.orange.opacity(0.1))
                }
                switch section {
                case "Mouse": MouseWorkspace()
                case "Teclado": KeyboardSettings()
                case "Trackpad": TrackpadSettings()
                case "Ajustes": settings
                default: ScrollSettings()
                }
            }.navigationTitle(section)
        }.frame(minWidth: 850, minHeight: 650)
        .alert("Aviso", isPresented: Binding(get: { state.message != nil }, set: { if !$0 { state.message = nil } })) { Button("OK") { state.message = nil } } message: { Text(state.message ?? "") }
    }
    private var pageHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: items.first { $0.0 == section }?.1 ?? "gearshape")
                .font(.system(size: 24, weight: .light)).foregroundStyle(Color.clickAccent)
                .frame(width: 48, height: 48).background(Color.clickAccent.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(section).font(.system(size: 25, weight: .semibold, design: .rounded))
                Text(sectionDescription).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 28).padding(.vertical, 22)
    }
    private var sectionDescription: String {
        switch section {
        case "Mouse": return "Precisão no movimento. Controle na sua mão."
        case "Teclado": return "Seu teclado e suas informações de bateria."
        case "Trackpad": return "Um gesto em cada borda. O centro continua livre."
        case "Ajustes": return "Tudo pronto para funcionar do seu jeito."
        default: return "Encontre o ritmo ideal para cada página."
        }
    }
    private func sidebarBattery(_ name: String, percent: Int?, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 17).foregroundStyle(.secondary)
            Text(name.replacingOccurrences(of: "Logi ", with: "")).lineLimit(1)
            Spacer(minLength: 4)
            Text(percent.map { "\($0)%" } ?? "—").monospacedDigit().foregroundStyle(.secondary)
        }.font(.system(size: 11)).padding(.vertical, 3)
    }
    private var settings: some View {
        Form {
            Section("Permissões") {
                LabeledContent("Acessibilidade", value: state.trusted ? "Permitida" : "Pendente")
                LabeledContent("Monitoramento de Entrada", value: state.inputAccess ? "Permitido" : "Pendente")
                Button("Abrir Acessibilidade") { state.requestAccess() }
                Button("Abrir Monitoramento de Entrada") { state.requestInputAccess() }
                Button("Localizar aplicativo no Finder") { state.revealApplication() }
                Text("Nos Ajustes do Sistema, habilite Click +. Se ele não aparecer, use o botão + para adicionar esta versão. O botão Localizar aplicativo abre sua pasta no Finder. A leitura HID permite consultar DPI e bateria.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Aplicativo") {
                Toggle("Iniciar com o macOS", isOn: Binding(get: { state.launchAtLogin }, set: { state.login($0) }))
                Button("Restaurar configurações…", role: .destructive) { reset = true }
                Text("Preferências armazenadas apenas neste Mac. Nenhuma conta ou conexão com servidor.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Verificação de entrada") {
                LabeledContent("Última origem", value: state.diagnostics.lastSource)
                LabeledContent("Eventos do mouse", value: String(state.diagnostics.mouseEvents))
                LabeledContent("Eventos do trackpad preservados", value: String(state.diagnostics.trackpadPassed))
                LabeledContent("Rolagens transformadas", value: String(state.diagnostics.scrollTransforms))
                LabeledContent("Movimentos com velocidade ajustada", value: String(state.diagnostics.cursorTransforms))
                LabeledContent("Funções executadas", value: String(state.diagnostics.mappedActions))
                LabeledContent("Última função", value: state.diagnostics.lastAction)
                LabeledContent("Controle de aceleração", value: state.diagnostics.pointerStatus)
                Text("Contadores desta execução. Eventos sintéticos são ignorados; estes números ajudam a conferir entradas físicas, sem registrar teclas ou conteúdo.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Compatibilidade") {
                Text("Desative BetterMouse e Logi Options+ enquanto testar o Click +, para evitar que dois aplicativos transformem o mesmo evento.")
                Text("Eventos não identificados passam intactos. Recursos de hardware só aparecem quando confirmados pelo dispositivo. A identificação usa um adaptador de APIs não públicas do macOS.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
        .confirmationDialog("Restaurar as configurações originais?", isPresented: $reset) {
            Button("Restaurar", role: .destructive) { state.preferences = Preferences(); state.hardware.restoreDPI() }
        }
    }
}
