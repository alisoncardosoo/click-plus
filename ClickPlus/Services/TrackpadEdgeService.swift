import AppKit
import Darwin

private typealias TouchCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
private let edgeFrameCallback: TouchCallback = { device, contacts, count, timestamp, _ in
    TrackpadEdgeService.shared.receive(device: device,contacts: contacts,count: count,time: timestamp)
    return 0
}

final class TrackpadEdgeService {
    static let shared = TrackpadEdgeService()
    var onStatus: ((String) -> Void)?
    var onAction: ((String) -> Void)?
    private typealias Create = @convention(c) () -> Unmanaged<CFArray>?
    private typealias Register = @convention(c) (UnsafeMutableRawPointer, TouchCallback) -> Void
    private typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32
    private typealias Stop = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias BuiltIn = @convention(c) (UnsafeMutableRawPointer) -> Bool
    private var handle: UnsafeMutableRawPointer?
    private var deviceList: CFArray?
    private var devices: [UnsafeMutableRawPointer] = []
    private let lock = NSLock()
    private var recognizers: [UInt: EdgeRecognizer] = [:]
    private var preferences = TrackpadPreferences()
    private var generation = 0
    private var claimedUntil = 0.0
    init() { handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW) }
    func configure(_ p: TrackpadPreferences, allowed: Bool) {
        lock.lock(); preferences = p; preferences.enabled = p.enabled && allowed
        generation += 1; recognizers.removeAll(); claimedUntil = 0; lock.unlock()
        if !p.enabled || !allowed { stop(); onStatus?(p.enabled ? "Permita Acessibilidade e Monitoramento de Entrada." : "Gestos de borda desativados"); return }
        guard devices.isEmpty else { onStatus?("Trackpad integrado pronto • deslize com um dedo"); return }
        guard let handle, MemoryLayout<RETouch>.stride == 96,
              let createSymbol = dlsym(handle,"MTDeviceCreateList"),
              let registerSymbol = dlsym(handle,"MTRegisterContactFrameCallback"),
              let startSymbol = dlsym(handle,"MTDeviceStart"),
              let builtInSymbol = dlsym(handle,"MTDeviceIsBuiltIn") else {
            onStatus?("Leitura das bordas indisponível neste macOS."); return
        }
        let create = unsafeBitCast(createSymbol,to: Create.self)
        let register = unsafeBitCast(registerSymbol,to: Register.self)
        let start = unsafeBitCast(startSymbol,to: Start.self)
        let builtIn = unsafeBitCast(builtInSymbol,to: BuiltIn.self)
        deviceList = create()?.takeRetainedValue()
        if let list = deviceList {
            for i in 0..<CFArrayGetCount(list) {
                guard let pointer = CFArrayGetValueAtIndex(list,i) else { continue }
                let device = UnsafeMutableRawPointer(mutating: pointer)
                guard builtIn(device) else { continue }
                register(device,edgeFrameCallback)
                if start(device,0) == 0 { devices.append(device) }
                else if let symbol = dlsym(handle,"MTUnregisterContactFrameCallback") { unsafeBitCast(symbol,to: Register.self)(device,edgeFrameCallback) }
            }
        }
        onStatus?(devices.isEmpty ? "Nenhum trackpad integrado disponível." : "Trackpad integrado pronto • deslize com um dedo")
    }
    func stop() {
        lock.lock(); generation += 1; preferences.enabled = false; recognizers.removeAll(); claimedUntil = 0; lock.unlock()
        guard let handle else { return }
        for device in devices {
            if let symbol = dlsym(handle,"MTUnregisterContactFrameCallback") { unsafeBitCast(symbol,to: Register.self)(device,edgeFrameCallback) }
            if let symbol = dlsym(handle,"MTDeviceStop") { _ = unsafeBitCast(symbol,to: Stop.self)(device) }
        }
        devices.removeAll(); deviceList = nil
    }
    func suppressesMotion() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return preferences.enabled && (recognizers.values.contains { $0.claimed } || ProcessInfo.processInfo.systemUptime < claimedUntil)
    }
    fileprivate func receive(device: UnsafeMutableRawPointer?, contacts: UnsafeMutableRawPointer?, count: Int32, time: Double) {
        guard let device, count >= 0, count <= 16 else { return }
        var touches: [EdgeTouch] = []
        if let contacts {
            let buffer = contacts.assumingMemoryBound(to: RETouch.self)
            for i in 0..<Int(count) {
                let t = buffer[i]
                if (3...5).contains(t.state) { touches.append(.init(id: Int(t.identifier),x: Double(t.normalized.position.x),y: Double(t.normalized.position.y))) }
            }
        }
        lock.lock()
        guard preferences.enabled else { lock.unlock(); return }
        let key = UInt(bitPattern: device)
        var recognizer = recognizers[key] ?? EdgeRecognizer()
        let wasClaimed = recognizer.claimed
        let commands = recognizer.process(touches,time: time,preferences: preferences)
        recognizers[key] = recognizer
        if wasClaimed && touches.isEmpty { claimedUntil = ProcessInfo.processInfo.systemUptime + 0.08 }
        let snapshot = preferences, token = generation
        lock.unlock()
        if !commands.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock(); let valid = self.preferences.enabled && self.generation == token; self.lock.unlock()
                guard valid else { return }
                for command in commands {
                    self.execute(command,configuration: snapshot.edges[command.edge] ?? .init())
                    if snapshot.hapticFeedback {
                        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange,performanceTime: .now)
                    }
                }
            }
        }
    }
    private func execute(_ command: EdgeCommand, configuration: EdgeConfiguration) {
        let positive = command.direction > 0
        let key: Int
        if command.direction == 0 { key = 16 }
        else {
            switch configuration.mode {
            case .off: return
            case .brightness: key = positive ? 2 : 3
            case .volume: key = positive ? 0 : 1
            case .tracks: key = positive ? 17 : 18
            case .playback: key = 16
            case .custom:
                ActionService.perform(positive ? configuration.positive : configuration.negative)
                onAction?("\(command.edge.title) • ação personalizada"); return
            }
        }
        for down in [true,false] {
            let flags = down ? 0xA00 : 0xB00
            if let event = NSEvent.otherEvent(with: .systemDefined,location: .zero,modifierFlags: .init(rawValue: UInt(flags)),timestamp: ProcessInfo.processInfo.systemUptime,windowNumber: 0,context: nil,subtype: 8,data1: (key << 16) | flags,data2: -1)?.cgEvent {
                ActionService.post(event)
            }
        }
        onAction?("\(command.edge.title) • \(command.direction == 0 ? "Reproduzir / pausar" : configuration.mode.title)")
    }
}
