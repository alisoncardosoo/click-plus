import SwiftUI

struct NumberControl: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.05
    var help = ""
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Text(title).font(.system(size: 13))
                if !help.isEmpty { ControlHelp(title: title, text: help) }
            }.frame(width: 175, alignment: .leading)
            Slider(value: Binding(get: { value }, set: { newValue in
                let snapped = range.lowerBound + ((newValue - range.lowerBound) / step).rounded() * step
                value = min(range.upperBound, max(range.lowerBound, snapped))
            }), in: range).accessibilityLabel(title)
            Text(value.formatted(.number.precision(.fractionLength(0...3))))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.clickAccent).frame(width: 52, height: 26)
                .background(Color.clickAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }.padding(.vertical, 6)

    }
}
struct ModifierControl: View {
    let title: String
    @Binding var value: Modifier
    var help = "Segure a tecla escolhida enquanto usa a roda ou move o mouse. Nenhuma desativa esse modificador."
    var body: some View {
        Picker(title, selection: $value) { ForEach(Modifier.allCases) { Text($0.displayName).tag($0) } }
            .controlHelp(title, help)
    }
}
struct CurveView: View {
    let prefs: Preferences
    private var durationMS: Int { Int((prefs.duration * 1000).rounded()) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Curva de rolagem").font(.system(size: 12, weight: .semibold))
                    Text("Intensidade relativa ao longo do tempo").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(durationMS) ms").font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color.clickAccent.opacity(0.1), in: Capsule()).foregroundStyle(Color.clickAccent)
            }
            Canvas { context, size in
                let plot = CGRect(x: 32, y: 14, width: max(1,size.width - 42), height: max(1,size.height - 37))
                let weights = ScrollMath.weights(duration: prefs.duration, brake: prefs.brake, extra: prefs.extraSmooth)
                let peak = weights.max() ?? 1
                for fraction in [0.0, 0.5, 1.0] {
                    let y = plot.maxY - plot.height * fraction
                    var line = Path()
                    line.move(to: CGPoint(x: plot.minX,y: y)); line.addLine(to: CGPoint(x: plot.maxX,y: y))
                    context.stroke(line, with: .color(.secondary.opacity(fraction == 0 ? 0.22 : 0.12)), style: StrokeStyle(lineWidth: 1, dash: fraction == 0 ? [] : [3,5]))
                    context.draw(Text("\(Int(fraction * 100))%").font(.system(size: 9,design: .monospaced)).foregroundStyle(.secondary), at: CGPoint(x: plot.minX - 7,y: y), anchor: .trailing)
                }
                for fraction in [0.0,0.5,1.0] {
                    let x = plot.minX + plot.width * fraction
                    context.draw(Text("\(Int(Double(durationMS) * fraction)) ms").font(.system(size: 9,design: .monospaced)).foregroundStyle(.secondary), at: CGPoint(x: x,y: plot.maxY + 14), anchor: fraction == 0 ? .leading : fraction == 1 ? .trailing : .center)
                }
                var curve = Path()
                curve.move(to: CGPoint(x: plot.minX,y: plot.maxY))
                for (index,weight) in weights.enumerated() {
                    curve.addLine(to: CGPoint(x: plot.minX + (Double(index)+0.5)/Double(weights.count)*plot.width, y: plot.maxY - weight/peak*plot.height))
                }
                curve.addLine(to: CGPoint(x: plot.maxX,y: plot.maxY))
                var fill = curve; fill.closeSubpath()
                context.fill(fill, with: .linearGradient(Gradient(colors: [Color.clickAccent.opacity(0.23), Color.clickAccent.opacity(0.01)]),startPoint: CGPoint(x: 0,y: plot.minY),endPoint: CGPoint(x: 0,y: plot.maxY)))
                context.stroke(curve, with: .color(Color.clickAccent), style: StrokeStyle(lineWidth: 2.5,lineCap: .round,lineJoin: .round))
                if let index = weights.firstIndex(of: peak) {
                    let point = CGPoint(x: plot.minX + (Double(index)+0.5)/Double(weights.count)*plot.width,y: plot.minY)
                    var guide = Path(); guide.move(to: point); guide.addLine(to: CGPoint(x: point.x,y: plot.maxY))
                    context.stroke(guide,with: .color(Color.clickAccent.opacity(0.3)),style: StrokeStyle(lineWidth: 1,dash: [3,4]))
                    context.fill(Path(ellipseIn: CGRect(x: point.x-4,y: point.y-4,width: 8,height: 8)),with: .color(Color.clickAccent))
                }
            }.frame(height: 120)
            HStack(spacing: 5) {
                Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(Color.clickAccent)
                Text("Frenagem a partir de \(Int((prefs.brake * prefs.duration * 1000).rounded())) ms")
                Spacer()
                Text("Tempo →")
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.clickAccent.opacity(0.035),in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.clickAccent.opacity(0.1),lineWidth: 1))
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Curva de rolagem: duração \(durationMS) milissegundos, frenagem em \(Int((prefs.brake * prefs.duration * 1000).rounded())) milissegundos")
        .help("Ilustração da rolagem suave. A altura mostra a intensidade relativa ao pico; a área mantém a distância total. O ponto indica a transição para a frenagem.")
    }
}

/// Visible, keyboard-accessible help; unlike a tooltip it also works by clicking.
struct ControlHelp: View {
    let title: String
    let text: String
    @State private var showing = false
    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: "questionmark.circle").font(.system(size: 12)).foregroundStyle(.tertiary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Ajuda: \(title)")
        .help(text)
        .popover(isPresented: $showing) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.headline)
                Text(text).fixedSize(horizontal: false, vertical: true)
                HStack { Spacer(); Button("Entendi") { showing = false }.keyboardShortcut(.cancelAction) }
            }.padding(18).frame(width: 330)
        }
    }
}
extension View {
    func controlHelp(_ title: String, _ text: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            ControlHelp(title: title, text: text)
            self
        }
    }
}

extension Color {
    static var clickAccent: Color { Color("AccentColor") }
}
