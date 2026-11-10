import SwiftUI

struct TrackpadSettings: View {
    @EnvironmentObject var state: AppState
    @State private var selected: TrackpadEdge = .right
    @State private var editing: EdgeEdit?
    private struct EdgeEdit: Identifiable { let positive: Bool; var id: Bool { positive } }
    private var configuration: Binding<EdgeConfiguration> {
        Binding(get: { state.trackpadPreferences.edges[selected] ?? .init() },set: { state.trackpadPreferences.edges[selected] = $0 })
    }
    var body: some View {
        Form {
            Section {
                Toggle("Ativar gestos nas bordas",isOn: $state.trackpadPreferences.enabled)
                Toggle("Retorno háptico",isOn: $state.trackpadPreferences.hapticFeedback)
                    .controlHelp("Retorno háptico", "Um pulso a cada etapa ou ação reconhecida. Requer trackpad com Force Touch e respeita os ajustes hápticos do macOS.")
                Label(state.trackpadStatus,systemImage: "hand.draw").font(.caption).foregroundStyle(.secondary)
                Text("Comece com um dedo na borda e deslize ao longo dela. O centro e os gestos com vários dedos mantêm o comportamento normal.").font(.callout).foregroundStyle(.secondary)
            }
            Section("Escolha uma borda") {
                VStack(spacing: 10) {
                    edgeButton(.top)
                    HStack {
                        edgeButton(.left)
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "hand.draw").font(.system(size: 24)).foregroundStyle(Color.clickAccent)
                            Text("Centro livre").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        edgeButton(.right)
                    }.frame(minHeight: 80)
                    edgeButton(.bottom)
                }.padding(18).background(Color.clickAccent.opacity(0.035),in: RoundedRectangle(cornerRadius: 16))
                Picker("Borda",selection: $selected) { ForEach(TrackpadEdge.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                Picker("Função da borda \(selected.title.lowercased())",selection: configuration.mode) {
                    ForEach(EdgeMode.allCases) { Text($0.title).tag($0) }
                }
                if configuration.wrappedValue.mode == .custom {
                    customAction(positive: true)
                    customAction(positive: false)
                } else if configuration.wrappedValue.mode == .tracks {
                    Text("Deslize para a direita para a próxima faixa, ou para a esquerda para a anterior. Nas bordas laterais, use cima e baixo.").font(.caption).foregroundStyle(.secondary)
                } else if [.brightness,.volume].contains(configuration.wrappedValue.mode) {
                    Text("Para cima ou para a direita aumenta; para baixo ou para a esquerda diminui. Continue deslizando para ajustar em etapas.").font(.caption).foregroundStyle(.secondary)
                } else if configuration.wrappedValue.mode == .playback {
                    Text("Um deslize alterna reproduzir e pausar. Levante o dedo antes do próximo comando.").font(.caption).foregroundStyle(.secondary)
                }
                if selected == .bottom && configuration.wrappedValue.mode != .off {
                    Toggle("Toque curto para reproduzir / pausar",isOn: configuration.tapToPlay)
                        .controlHelp("Toque na borda inferior", "Toque com um dedo por menos de 0,3 segundo, sem deslizar. Só é reconhecido se você começar dentro da faixa da borda inferior.")
                }
            }
            Section("Sensibilidade") {
                NumberControl(title: "Largura das bordas",value: $state.trackpadPreferences.width,range: 0.03...0.15,step: 0.005,help: "Fração da largura ou altura do trackpad usada para cada borda. 0,075 corresponde a 7,5%. Uma faixa menor reduz acionamentos acidentais.")
                NumberControl(title: "Distância por etapa",value: $state.trackpadPreferences.distance,range: 0.02...0.12,step: 0.005,help: "Distância relativa que o dedo deve percorrer para disparar uma etapa de brilho ou volume. Aumente para reduzir a sensibilidade.")
            }
            Section("Última ação") { Text(state.trackpadLastAction).foregroundStyle(.secondary) }
            Section {
                Text("A reprodução depende do aplicativo de mídia ativo. O brilho controla telas que respondem às teclas de brilho do macOS. Nesta versão, os gestos de borda usam o trackpad integrado.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
        .sheet(item: $editing) { edit in
            ButtonActionEditor(button: 2,initial: edit.positive ? configuration.wrappedValue.positive : configuration.wrappedValue.negative,editorTitle: selected.vertical ? (edit.positive ? "Deslizar para cima" : "Deslizar para baixo") : (edit.positive ? "Deslizar para a direita" : "Deslizar para a esquerda")) { action in
                if edit.positive { configuration.wrappedValue.positive = action } else { configuration.wrappedValue.negative = action }
                editing = nil
            }
        }
    }
    private func edgeButton(_ edge: TrackpadEdge) -> some View {
        Button { selected = edge } label: {
            VStack(spacing: 3) {
                Text(edge.title).font(.system(size: 12,weight: .semibold))
                Text((state.trackpadPreferences.edges[edge]?.mode ?? .off).title).font(.caption2)
            }.foregroundStyle(selected == edge ? Color.clickAccent : Color.secondary)
                .padding(.horizontal,12).padding(.vertical,7)
                .background(selected == edge ? Color.clickAccent.opacity(0.12) : Color.clear,in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }
    private func customAction(positive: Bool) -> some View {
        let action = positive ? configuration.wrappedValue.positive : configuration.wrappedValue.negative
        return HStack {
            Text(selected.vertical ? (positive ? "Para cima" : "Para baixo") : (positive ? "Para a direita" : "Para a esquerda"))
            Spacer()
            Text(action.kind == .original ? "Sem ação" : action.kind.displayName).foregroundStyle(.secondary)
            Button("Escolher…") { editing = .init(positive: positive) }
        }
    }
}
