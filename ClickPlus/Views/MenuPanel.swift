import SwiftUI

struct MenuPanel: View {
    @EnvironmentObject var state: AppState
    let openSettings: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image("BrandIcon").resizable().scaledToFit().frame(width: 40,height: 40)
                VStack(alignment: .leading,spacing: 3) {
                    Text("Click +").font(.system(size: 18,weight: .semibold,design: .rounded))
                    HStack(spacing: 5) {
                        Circle().fill(state.trusted && state.inputAccess ? Color.clickAccent : Color.secondary).frame(width: 5,height: 5)
                        Text(state.trusted && state.inputAccess ? "Personalização ativa" : "Permissão pendente").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
            }
            VStack(alignment: .leading,spacing: 9) {
                Text("BATERIAS").font(.system(size: 10,weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                MenuBatteryRow(name: state.device.name, category: "Mouse", icon: "computermouse.fill", percent: state.device.battery)
                if state.keyboardBatteries.isEmpty {
                    MenuBatteryRow(name: "Teclado Logitech",category: "Não conectado",icon: "keyboard",percent: nil)
                } else {
                    ForEach(state.keyboardBatteries) { keyboard in
                        MenuBatteryRow(name: keyboard.name,category: "Teclado",icon: "keyboard",percent: keyboard.percent)
                    }
                }
            }
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 9))
                Text("Atualização automática · 30 s").font(.system(size: 10))
            }.foregroundStyle(.secondary)
            Divider()
            HStack {
                Button(action: openSettings) { Label("Configurações",systemImage: "slider.horizontal.3").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.regular)
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power").frame(width: 22,height: 20) }
                    .buttonStyle(.bordered).help("Sair do Click +").accessibilityLabel("Sair do Click +")
            }
        }
        .padding(20).frame(width: 330)
        .tint(Color.clickAccent)
        .onAppear { state.hardware.refresh() }
    }
}

private struct MenuBatteryRow: View {
    let name: String
    let category: String
    let icon: String
    let percent: Int?
    private var color: Color { (percent ?? 100) <= 20 ? .orange : .clickAccent }
    var body: some View {
        VStack(spacing: 13) {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 21,weight: .light))
                    .foregroundStyle(color).frame(width: 35,height: 35)
                    .background(color.opacity(0.09),in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading,spacing: 3) {
                    Text(String(name.prefix(30))).font(.system(size: 12,weight: .medium)).lineLimit(1).help(name)
                    Text(category).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if let percent {
                    HStack(alignment: .firstTextBaseline,spacing: 1) {
                        Text("\(percent)").font(.system(size: 24,weight: .semibold,design: .rounded)).monospacedDigit()
                        Text("%").font(.system(size: 11,weight: .medium))
                    }.foregroundStyle(color)
                } else {
                    Text("—").font(.system(size: 23,weight: .light)).foregroundStyle(.tertiary)
                }
            }
            if let percent {
                GeometryReader { geometry in
                    Capsule().fill(color.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Capsule().fill(LinearGradient(colors: [color.opacity(0.55),color],startPoint: .leading,endPoint: .trailing))
                                .frame(width: geometry.size.width * Double(min(100,max(0,percent))) / 100)
                        }
                }.frame(height: 5)
            } else {
                Text(category == "Não conectado" ? "Conecte para consultar a bateria" : "Bateria não informada nesta consulta")
                    .font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity,alignment: .leading)
            }
        }
        .padding(13)
        .background(Color.primary.opacity(0.035),in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(color.opacity(0.12),lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(percent.map { "\($0) por cento" } ?? category + ", bateria não informada")")
    }
}
