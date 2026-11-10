import Foundation

enum TrackpadEdge: String, Codable, CaseIterable, Identifiable {
    case left, right, bottom, top
    var id: String { rawValue }
    var title: String { switch self { case .left: return "Esquerda"; case .right: return "Direita"; case .bottom: return "Inferior"; case .top: return "Superior" } }
    var vertical: Bool { self == .left || self == .right }
}
enum EdgeMode: String, Codable, CaseIterable, Identifiable {
    case off, brightness, volume, tracks, playback, custom
    var id: String { rawValue }
    var title: String {
        switch self { case .off: return "Desativado"; case .brightness: return "Brilho da tela"; case .volume: return "Volume"; case .tracks: return "Trocar faixas"; case .playback: return "Reproduzir / pausar"; case .custom: return "Ações personalizadas" }
    }
}
struct EdgeConfiguration: Codable, Equatable {
    var mode: EdgeMode = .off
    var positive = ButtonAction()
    var negative = ButtonAction()
    var tapToPlay = false
}
struct TrackpadPreferences: Codable, Equatable {
    var enabled = false
    var hapticFeedback = true
    var width = 0.075
    var distance = 0.045
    var edges: [TrackpadEdge: EdgeConfiguration] = [
        .right: .init(mode: .brightness), .left: .init(mode: .volume),
        .bottom: .init(mode: .tracks), .top: .init(mode: .off)
    ]
    init() {}
    private enum CodingKeys: String, CodingKey { case enabled, hapticFeedback, width, distance, edges }
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decode(Bool.self,forKey: .enabled)
        hapticFeedback = try values.decodeIfPresent(Bool.self,forKey: .hapticFeedback) ?? true
        width = try values.decode(Double.self,forKey: .width)
        distance = try values.decode(Double.self,forKey: .distance)
        edges = try values.decode([TrackpadEdge: EdgeConfiguration].self,forKey: .edges)
    }
}
struct EdgeTouch { let id: Int; let x: Double; let y: Double }
struct EdgeCommand: Equatable { let edge: TrackpadEdge; let direction: Int }

/// One finger must start on an enabled edge. Center starts, palm/multifinger
/// contacts and leaving the edge disarm the entire contact until every finger lifts.
struct EdgeRecognizer {
    private var finger: Int?
    private var edge: TrackpadEdge?
    private var origin = 0.0
    private var previous = 0.0
    private var started = 0.0
    private var fired = false
    private var blocked = false
    private(set) var claimed = false
    mutating func reset() { self = EdgeRecognizer() }
    mutating func process(_ touches: [EdgeTouch], time: Double, preferences p: TrackpadPreferences) -> [EdgeCommand] {
        guard p.enabled else { reset(); return [] }
        if touches.isEmpty {
            let tap = edge.flatMap { e -> EdgeCommand? in
                guard !blocked, !fired, time - started < 0.3, p.edges[e]?.tapToPlay == true, e == .bottom else { return nil }
                return EdgeCommand(edge: e,direction: 0)
            }
            reset(); return tap.map { [$0] } ?? []
        }
        guard touches.count == 1, let touch = touches.first,
              touch.x.isFinite, touch.y.isFinite, (0...1).contains(touch.x), (0...1).contains(touch.y) else {
            blocked = true; claimed = false; return []
        }
        guard !blocked else { return [] }
        let width = min(0.15,max(0.03,p.width))
        let distances: [(TrackpadEdge,Double)] = [(.left,touch.x),(.right,1-touch.x),(.bottom,touch.y),(.top,1-touch.y)]
        if finger == nil {
            finger = touch.id; started = time
            edge = distances.filter { $0.1 <= width && p.edges[$0.0]?.mode != .off && p.edges[$0.0] != nil }.min { $0.1 < $1.1 }?.0
            guard let edge else { blocked = true; return [] }
            origin = edge.vertical ? touch.y : touch.x; previous = origin
            return []
        }
        guard finger == touch.id, let edge,
              (distances.first { $0.0 == edge }?.1 ?? 1) <= width * 1.5 else {
            blocked = true; claimed = false; return []
        }
        let position = edge.vertical ? touch.y : touch.x
        let threshold = min(0.2,max(0.02,p.distance))
        guard abs(position - origin) >= threshold || claimed else { return [] }
        claimed = true
        guard abs(position - previous) >= threshold else { return [] }
        let direction = position > previous ? 1 : -1
        previous = position
        let mode = p.edges[edge]?.mode ?? .off
        if [.tracks,.playback,.custom].contains(mode), fired { return [] }
        fired = true
        return [EdgeCommand(edge: edge,direction: direction)]
    }
}
