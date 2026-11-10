import Foundation
import CoreFoundation
import IOBluetooth

struct BluetoothBattery: Identifiable, Equatable {
    struct Level: Identifiable, Equatable {
        let id: String
        let label: String
        let percent: Int
        var lastKnownAt: Date? = nil
        var readingNote: String? {
            lastKnownAt.map { "Última leitura: \($0.formatted(.dateTime.day().month().hour().minute().locale(Locale(identifier: "pt_BR"))))" }
        }
    }
    let id: String
    let name: String
    let kind: String
    let levels: [Level]
    var icon: String {
        switch kind.lowercased() {
        case "headset", "headphones": return "headphones"
        case "speaker": return "hifispeaker"
        case "keyboard": return "keyboard"
        case "mouse": return "computermouse"
        default: return "wave.3.right"
        }
    }
    var caseBatteryUnavailable: Bool {
        GalaxyBudsBatteryParser.supports(name) && !levels.contains { $0.id == "device_batteryLevelCase" }
    }
    var summary: String {
        levels.isEmpty ? "Bateria não informada" : levels.map {
            $0.label.isEmpty ? "\($0.percent)%" : "\($0.label): \($0.percent)%"
        }.joined(separator: " · ")
    }
}

/// Session-local history, keyed by accessory, so a closed case keeps its last
/// real reading without retaining disconnected devices in the visible list.
struct CaseBatteryHistory {
    private struct Reading { let percent: Int; let date: Date }
    private var readings: [String: Reading] = [:]

    mutating func apply(to device: BluetoothBattery, now: Date = Date()) -> BluetoothBattery {
        guard GalaxyBudsBatteryParser.supports(device.name) else { return device }
        let key = "device_batteryLevelCase"
        if let current = device.levels.first(where: { $0.id == key && $0.lastKnownAt == nil && (1...100).contains($0.percent) }) {
            readings[device.id] = Reading(percent: current.percent, date: now)
            return device
        }
        guard let previous = readings[device.id] else { return device }
        let levels = device.levels.filter { $0.id != key } + [BluetoothBattery.Level(
            id: key, label: "Estojo", percent: previous.percent, lastKnownAt: previous.date)]
        return BluetoothBattery(id: device.id, name: device.name, kind: device.kind, levels: levels)
    }
}

/// Reads the local macOS report and status-only Samsung notifications.
@MainActor final class BluetoothBatteryService: ObservableObject {
    @Published private(set) var devices: [BluetoothBattery] = []
    @Published private(set) var refreshing = false
    @Published private(set) var error: String?
    var onDevicesChanged: (() -> Void)?
    private var timer: Timer?
    private var caseHistory = CaseBatteryHistory()
    private var samsungReaders: [String: GalaxyBudsBatteryReader] = [:]

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task {
            let result = await Task.detached(priority: .utility) { Self.readReport() }.value
            switch result {
            case .success(let values):
                let connected = values.filter { IOBluetoothDevice(addressString: $0.id)?.isConnected() == true }
                let ids = Set(connected.map(\.id))
                for id in Array(samsungReaders.keys) where !ids.contains(id) {
                    samsungReaders.removeValue(forKey: id)?.stop()
                }
                devices = connected.map { device in
                    if samsungReaders[device.id]?.isActive == true,
                       let previous = devices.first(where: { $0.id == device.id }) { return previous }
                    return caseHistory.apply(to: device)
                }
                for device in connected where GalaxyBudsBatteryParser.supports(device.name) {
                    let reader = samsungReaders[device.id] ?? GalaxyBudsBatteryReader()
                    samsungReaders[device.id] = reader
                    reader.start(address: device.id, onLevels: { [weak self] levels in
                        guard let self,
                              IOBluetoothDevice(addressString: device.id)?.isConnected() == true,
                              let index = self.devices.firstIndex(where: { $0.id == device.id }) else { return }
                        self.devices[index] = self.caseHistory.apply(to: BluetoothBattery(id: device.id, name: device.name, kind: device.kind, levels: levels))
                        self.onDevicesChanged?()
                    }, onDisconnect: { [weak self] in
                        guard let self else { return }
                        if IOBluetoothDevice(addressString: device.id)?.isConnected() != true {
                            self.devices.removeAll { $0.id == device.id }
                            self.onDevicesChanged?()
                        }
                    })
                }
                error = nil
            case .failure:
                for reader in samsungReaders.values { reader.stop() }
                samsungReaders = [:]
                devices = [] // Do not present a previous connection or battery as current.
                error = "Não foi possível consultar o Bluetooth. Tente atualizar novamente."
            }
            refreshing = false
            onDevicesChanged?()
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        for reader in samsungReaders.values { reader.stop() }
        samsungReaders = [:]
    }

    private enum ReportError: Error { case unavailable }
    nonisolated private static func readReport() -> Result<[BluetoothBattery], Error> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json", "-timeout", "10"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            // A separate deadline also covers a stuck system_profiler subprocess.
            let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15, execute: deadline)
            defer { deadline.cancel() }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw ReportError.unavailable }
            return .success(try parse(data))
        } catch { return .failure(error) }
    }

    nonisolated static func parse(_ data: Data) throws -> [BluetoothBattery] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else {
            throw ReportError.unavailable
        }
        let fields = [("device_batteryLevelMain", ""), ("device_batteryLevelLeft", "Esquerdo"),
                      ("device_batteryLevelRight", "Direito"), ("device_batteryLevelCase", "Estojo")]
        var devices: [String: BluetoothBattery] = [:]
        for controller in controllers {
            for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let properties = value as? [String: Any],
                          let address = properties["device_address"] as? String, !address.isEmpty else { continue }
                    let kind = properties["device_minorType"] as? String ?? "Bluetooth"
                    // Logitech mice and keyboards already have their own HID++ battery rows.
                    if (properties["device_vendorID"] as? String)?.lowercased() == "0x046d",
                       ["keyboard", "mouse"].contains(kind.lowercased()) { continue }
                    let levels = fields.compactMap { key, label -> BluetoothBattery.Level? in
                        guard let percent = percent(properties[key]) else { return nil }
                        return .init(id: key, label: label, percent: percent)
                    }
                    let id = address.lowercased().replacingOccurrences(of: "-", with: ":")
                    devices[id] = BluetoothBattery(id: id, name: name, kind: kind, levels: levels)
                }
            }
        }
        return devices.values.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
    }

    nonisolated static func percent(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                  (0...100).contains(number.doubleValue), number.doubleValue.rounded() == number.doubleValue else { return nil }
            return number.intValue
        }
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.hasSuffix("%") ? String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces) : trimmed
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let result = Int(digits), (0...100).contains(result) else { return nil }
        return result
    }
}
