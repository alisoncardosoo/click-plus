import Foundation
import IOBluetooth

/// Status framing for Galaxy Buds2. Only status notifications are consumed;
/// no setting, firmware, pairing or audio commands are sent.
/// Protocol reference: https://github.com/timschneeb/GalaxyBudsClient
struct GalaxyBudsBatteryParser {
    private var buffer: [UInt8] = []

    static func supports(_ name: String) -> Bool {
        let normalized = name.lowercased().filter { !$0.isWhitespace }
        return normalized.contains("galaxybuds2") && !normalized.contains("pro")
    }

    static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 { crc = crc & 0x8000 != 0 ? (crc &<< 1) ^ 0x1021 : crc &<< 1 }
        }
        return crc
    }

    mutating func receive(_ bytes: [UInt8]) -> [BluetoothBattery.Level]? {
        buffer += bytes
        while !buffer.isEmpty {
            guard let start = buffer.firstIndex(of: 0xFD) else { buffer = []; return nil }
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= 3 else { return nil }
            let header = Int(buffer[1]) | Int(buffer[2]) << 8
            let size = header & 0x3FF
            guard size >= 3 else { buffer.removeFirst(); continue }
            let total = size + 4
            guard buffer.count >= total else { return nil }
            guard buffer[total - 1] == 0xDD else { buffer.removeFirst(); continue }
            let packet = Array(buffer.prefix(total))
            buffer.removeFirst(total)
            let body = Array(packet[3..<(total - 3)])
            let crc = UInt16(packet[total - 3]) | UInt16(packet[total - 2]) << 8
            guard header & 0x2000 == 0, Self.checksum(body) == crc,
                  let id = body.first, [0x60, 0x61].contains(id) else { continue }
            let payload = Array(body.dropFirst())
            let extended = id == 0x61
            guard payload.count >= (extended ? 8 : 7) else { continue }
            let offset = extended ? 2 : 1
            var levels: [BluetoothBattery.Level] = []
            for (index, key, label) in [(offset, "device_batteryLevelLeft", "Esquerdo"),
                                         (offset + 1, "device_batteryLevelRight", "Direito")] {
                let value = Int(payload[index])
                if value <= 100 { levels.append(.init(id: key, label: label, percent: value)) }
            }
            // The Buds report 0/255 when the case's level is unavailable.
            let caseLevel = Int(payload[extended ? 7 : 6])
            if (1...100).contains(caseLevel) {
                levels.append(.init(id: "device_batteryLevelCase", label: "Estojo", percent: caseLevel))
            }
            if levels.contains(where: { $0.label == "Esquerdo" || $0.label == "Direito" }) { return levels }
        }
        return nil
    }
}

/// Keeps the status channel open so case updates are not lost between polls.
@MainActor final class GalaxyBudsBatteryReader: NSObject, IOBluetoothRFCOMMChannelDelegate {
    private var channel: IOBluetoothRFCOMMChannel?
    private var parser = GalaxyBudsBatteryParser()
    private var openTimeout: Task<Void, Never>?
    private var onLevels: (([BluetoothBattery.Level]) -> Void)?
    private var onDisconnect: (() -> Void)?
    private(set) var isActive = false

    func start(address: String, onLevels: @escaping ([BluetoothBattery.Level]) -> Void,
               onDisconnect: @escaping () -> Void) {
        guard !isActive else { return }
        guard let device = IOBluetoothDevice(addressString: address), device.isConnected(), device.isPaired() else { return }
        let uuid = UUID(uuidString: "2e73a4ad-332d-41fc-90e2-16bef06523f2")!.uuid
        let data = withUnsafeBytes(of: uuid) { Data($0) }
        guard let record = device.getServiceRecord(for: IOBluetoothSDPUUID(data: data)) else { return }
        var id: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&id) == kIOReturnSuccess, id > 0 else { return }
        parser = GalaxyBudsBatteryParser()
        self.onLevels = onLevels
        self.onDisconnect = onDisconnect
        isActive = true
        openTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            self?.stop()
        }
        let status = device.openRFCOMMChannelAsync(&channel, withChannelID: id, delegate: self)
        if status != kIOReturnSuccess { stop() }
    }

    func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        openTimeout?.cancel(); openTimeout = nil
        if error != kIOReturnSuccess { stop() }
    }
    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard isActive, let dataPointer, dataLength > 0 else { return }
        let bytes = Array(UnsafeBufferPointer(start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength))
        var received = parser.receive(bytes)
        while let levels = received {
            onLevels?(levels)
            received = parser.receive([])
        }
    }
    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        let notify = onDisconnect
        stop()
        notify?()
    }

    func stop() {
        isActive = false
        onLevels = nil; onDisconnect = nil
        openTimeout?.cancel(); openTimeout = nil
        channel?.setDelegate(nil)
        channel?.close(); channel = nil
        parser = GalaxyBudsBatteryParser()
    }
}
