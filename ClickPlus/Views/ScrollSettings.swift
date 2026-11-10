import SwiftUI

struct ScrollSettings: View {
    @EnvironmentObject var state: AppState
    @State private var advanced = false
    @State private var modifiers = false
    var body: some View {
        Form {
            Section {
                Toggle("Personalizar rolagem", isOn: $state.preferences.scrollEnabled)
                Text("Aplicado apenas ao mouse identificado. O trackpad mantém seu comportamento.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Rolagem vertical") {
                CurveView(prefs: state.preferences)
                NumberControl(title: "Velocidade", value: $state.preferences.scrollSpeed, range: 0.1...10, help: "Multiplica a distância percorrida pela página. 1 mantém a distância básica; 1,5 percorre uma distância 50% maior.")
                DisclosureGroup("Ajustar a curva", isExpanded: $advanced) {
                NumberControl(title: "Duração (segundos)", value: $state.preferences.duration, range: 0.02...1, step: 0.01, help: "Tempo usado para distribuir cada movimento da roda quando a rolagem suave está ligada. Maior duração deixa a transição mais longa.")
                NumberControl(title: "Ponto de frenagem", value: $state.preferences.brake, range: 0.05...0.95, help: "Define em qual parte da curva a rolagem começa a desacelerar. Valores menores iniciam a frenagem mais cedo. Só muda a sensação com rolagem suave.")
                NumberControl(title: "Aceleração", value: $state.preferences.scrollAcceleration, range: 0...5, help: "Dá um ganho extra aos movimentos maiores da roda. Em zero, o ganho não varia com a intensidade do movimento.")
                NumberControl(title: "Suavização extra", value: $state.preferences.extraSmooth, range: 0...5, help: "Muda o formato da curva de rolagem suave, concentrando o movimento no centro da transição. Não aumenta a distância total.")
                }
                Toggle("Rolagem suave", isOn: $state.preferences.smooth)
                    .controlHelp("Rolagem suave", "Distribui cada movimento da roda ao longo do tempo. Duração, frenagem e suavização extra moldam essa transição.")
                Toggle("Inverter direção vertical", isOn: $state.preferences.invertVertical)
                    .controlHelp("Inverter direção vertical", "Troca o sentido de subir e descer da roda, apenas no mouse identificado.")
                Toggle("Trazer janela à frente ao rolar", isOn: $state.preferences.raiseOnScroll)
                    .controlHelp("Trazer janela à frente ao rolar", "Ativa a janela sob o ponteiro antes de rolar seu conteúdo. Desligado, rolar não tenta mudar a janela em foco.")
                Toggle("Ajustar controles deslizantes com rolagem vertical", isOn: $state.preferences.verticalSliders)
                    .controlHelp("Ajustar controles deslizantes com rolagem vertical", "Com o ponteiro sobre um controle de volume ou outra barra ajustável, a roda altera seu valor. Só funciona quando o controle oferece suporte à acessibilidade; caso contrário, mantém a rolagem normal.")
                    .help("Ajusta controles deslizantes reconhecidos pela acessibilidade sob o cursor.")
            }.disabled(!state.preferences.scrollEnabled)
            Section("Rolagem horizontal") {
                NumberControl(title: "Velocidade horizontal", value: $state.preferences.horizontalSpeed, range: 0.1...10, help: "Multiplica a distância da rolagem para os lados, tanto pela roda horizontal quanto pela combinação de tecla e roda.")
                Toggle("Inverter direção horizontal", isOn: $state.preferences.invertHorizontal)
                    .controlHelp("Inverter direção horizontal", "Troca os sentidos esquerdo e direito da rolagem.")
                Toggle("Ajustar controles deslizantes com rolagem horizontal", isOn: $state.preferences.horizontalSliders)
                    .controlHelp("Ajustar controles deslizantes com rolagem horizontal", "Usa a rolagem lateral, inclusive tecla mais roda, para ajustar o controle deslizante sob o ponteiro. Se ele não permitir ajuste acessível, mantém a rolagem normal.")
            }.disabled(!state.preferences.scrollEnabled)
            Section {
                DisclosureGroup("Atalhos com a roda", isExpanded: $modifiers) {
                ModifierControl(title: "Rolar horizontalmente", value: $state.preferences.horizontalModifier, help: "Segure a tecla escolhida e gire a roda para rolar para os lados. Isso permite rolagem horizontal mesmo em mouses sem uma segunda roda.")
                Toggle("Inverter horizontal com modificador", isOn: $state.preferences.invertModifiedHorizontal)
                    .controlHelp("Inverter horizontal com modificador", "Inverte somente a rolagem horizontal produzida pela combinação de tecla e roda.")
                ModifierControl(title: "Ampliar ou reduzir", value: $state.preferences.zoomModifier, help: "Segure a tecla escolhida e gire a roda para ampliar ou reduzir. Usa os atalhos Comando + e Comando −, conforme o suporte do aplicativo.")
                Text("A ampliação envia Comando + ou Comando − ao aplicativo em foco.").font(.caption).foregroundStyle(.secondary)
                Toggle("Inverter ampliação", isOn: $state.preferences.invertZoom)
                    .controlHelp("Inverter ampliação", "Troca qual sentido da roda amplia ou reduz o conteúdo ao segurar a tecla escolhida.")
                ModifierControl(title: "Alterar velocidade", value: $state.preferences.speedModifier, help: "Segure a tecla escolhida ao rolar para aplicar o multiplicador abaixo. Ao soltar, a rolagem volta à velocidade normal.")
                NumberControl(title: "Multiplicador de velocidade", value: $state.preferences.modifierGain, range: 0.1...10, help: "Ganho aplicado enquanto você segura a tecla de alterar velocidade. 2 dobra a rolagem; 0,5 reduz pela metade.")
            }
            }
            Section("Experimente aqui") {
                ScrollView { VStack(alignment: .leading, spacing: 16) { ForEach(1...20, id: \.self) { i in Text("\(i.formatted(.number.precision(.integerLength(2))))   Uma rolagem do seu jeito.").frame(maxWidth: .infinity, alignment: .leading) } }.padding() }.frame(height: 145).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }
        }.formStyle(.grouped)
    }
}
