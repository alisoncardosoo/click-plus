import SwiftUI

struct MenuPanel: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var bluetooth: BluetoothBatteryService
    let openSettings: () -> Void
    // MenuBarExtra asks for an ideal content size. A ScrollView with only a
    // maximum height can report zero and hide all rows in the status popover.
    private var batteryListHeight: CGFloat {
        let rows = (state.device.id == nil ? 0 : 1) + state.keyboardBatteries.count
            + bluetooth.devices.reduce(0) { $0 + max(1, $1.levels.count) + ($1.caseBatteryUnavailable ? 1 : 0) }
        return min(440, 25 + CGFloat(max(1, rows)) * (rows == 0 ? 35 : 105) + (bluetooth.error == nil ? 0 : 25))
    }
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
            ScrollView {
                VStack(alignment: .leading,spacing: 9) {
                    Text("BATERIAS").font(.system(size: 10,weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                    if state.device.id != nil {
                        MenuBatteryRow(name: state.device.name, category: "Mouse", icon: "computermouse.fill", percent: state.device.battery)
                    }
                    if !state.keyboardBatteries.isEmpty {
                        ForEach(state.keyboardBatteries) { keyboard in
                            MenuBatteryRow(name: keyboard.name,category: "Teclado",icon: "keyboard",percent: keyboard.percent)
                        }
                    }
                    ForEach(bluetooth.devices) { device in
                        if device.levels.isEmpty {
                            MenuBatteryRow(name: device.name, category: "Bluetooth", icon: device.icon, percent: nil)
                        } else {
                            ForEach(device.levels) { level in
                                MenuBatteryRow(name: device.name, category: level.label.isEmpty ? "Bluetooth" : level.label, icon: device.icon, percent: level.percent,
                                               readingNote: level.readingNote)
                            }
                        }
                        if device.caseBatteryUnavailable {
                            MenuBatteryRow(name: device.name, category: "Estojo", icon: "earbuds.case", percent: nil,
                                           unavailableMessage: "Abra o estojo com um fone dentro para consultar")
                        }
                    }
                    if state.device.id == nil && state.keyboardBatteries.isEmpty && bluetooth.devices.isEmpty {
                        Text("Nenhum dispositivo conectado").font(.caption).foregroundStyle(.secondary)
                    }
                    if bluetooth.error != nil {
                        Text("Consulta Bluetooth indisponível").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.frame(height: batteryListHeight)
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
        .onAppear { state.hardware.refresh(); bluetooth.refresh() }
    }
}

private struct MenuBatteryRow: View {
    let name: String
    let category: String
    let icon: String
    let percent: Int?
    var readingNote: String? = nil
    var unavailableMessage = "Bateria não informada nesta consulta"
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
            if let readingNote {
                Text(readingNote).font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                Text(unavailableMessage)
                    .font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity,alignment: .leading)
            }
        }
        .padding(13)
        .background(Color.primary.opacity(0.035),in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(color.opacity(0.12),lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(category), \(percent.map { "\($0) por cento" } ?? unavailableMessage)\(readingNote.map { ", " + $0 } ?? "")")
    }
}
