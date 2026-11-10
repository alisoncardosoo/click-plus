import Foundation
import IOKit.hid
import OSLog

struct KeyboardBattery: Identifiable {
    let id: String
    let name: String
    let percent: Int?
    var description: String { percent.map { "\($0)%" } ?? "Bateria não informada" }
}

struct LogitechMouse: Identifiable {
    let id: String
    let name: String
    let transport: String
}
private struct MouseEndpoint {
    let device: IOHIDDevice
    let address: UInt8
    let info: LogitechMouse
    let rootID: UInt64?
    let receiverID: UInt64?
    let canQuery: Bool
}

struct HardwareState {
    var name = "Nenhum mouse Logitech conectado"
    var id: String?
    var mouseDeviceID: UInt64?
    var buttonCaptureAvailable = false
    var transport = "—"
    var battery: Int?
    var dpi: Int?
    var dpiValues: [Int] = []
    var dpiControlled = false
    var receiverUSBID: UInt64?
    var detail = "Conecte o mouse e permita Monitoramento de Entrada para consultar o hardware."
}

enum HIDPP {
    static func packet(device: UInt8, feature: UInt8, function: UInt8, parameters: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = [0x11,device,feature,(function << 4) | 0x0A]
        bytes += parameters.prefix(16)
        bytes += Array(repeating: 0, count: 20-bytes.count)
        return bytes
    }
    static func dpiList(_ payload: [UInt8]) -> [Int] {
        guard payload.count >= 3 else { return [] }
        var values: [Int] = []; var i = 1
        while i+1 < payload.count {
            let value = Int(payload[i]) << 8 | Int(payload[i+1]); i += 2
            if value == 0 { break }
            if value & 0xE000 == 0xE000 {
                let step = value & 0x1FFF
                guard step > 0, let start = values.last, i+1 < payload.count else { return [] }
                let end = Int(payload[i]) << 8 | Int(payload[i+1]); i += 2
                guard end >= start, end <= 30000 else { return [] }
                values += stride(from: start+step, through: end, by: step)
            } else if value <= 30000 { values.append(value) }
        }
        return Array(Set(values)).sorted()
    }
    static func currentDPI(_ payload: [UInt8]) -> Int? {
        guard payload.count >= 5 else { return nil }
        let value = Int(payload[1]) << 8 | Int(payload[2])
        return value == 0 ? Int(payload[3]) << 8 | Int(payload[4]) : value
    }
}

/// Main run loop receives reports; the serial worker waits for matching replies.
/// It never seizes the device and never sends pairing/firmware commands.
final class HardwareService {
    var onMouseDevices: (([LogitechMouse]) -> Void)?
    private var preferredMouse = UserDefaults.standard.string(forKey: "selectedLogitechMouse")
    private var responseDevice: IOHIDDevice?
    var onKeyboardBatteries: (([KeyboardBattery]) -> Void)?
    var onChange: ((HardwareState) -> Void)?
    var onDisconnect: (() -> Void)?
    var onPanButtonState: ((Int, Bool) -> Void)?
    var onPanCancelled: (() -> Void)?
    var onMappedButton: ((Int) -> Void)?
    private var runtimePreferences = Preferences()
    var onCapturedButton: ((Int?, String?) -> Void)?
    private struct CaptureSession {
        let id = UUID()
        let identifying: Bool
        let panButton: Int
        let device: IOHIDDevice
        let address: UInt8
        let feature: UInt8
        var buttons: [UInt16: Int]
        var restore: [[UInt8]]
        var held: Set<UInt16> = []
    }
    // Guarded by condition because reports arrive on the main run loop.
    private var buttonSession: CaptureSession?
    private var captureTimeout: DispatchWorkItem?

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let queue = DispatchQueue(label: "ClickPlus.HIDPP")
    private let condition = NSCondition()
    private var responses: [[UInt8]] = []
    private var registered: [(IOHIDDevice, UnsafeMutablePointer<UInt8>)] = []
    private var selected: IOHIDDevice?
    private var address: UInt8 = 0xFF
    private var dpiFeature: UInt8 = 0
    private var originalDPI: Int?
    private var restoreKey = ""
    private var softwareID: UInt8 = 1
    private var state = HardwareState()
    private var polling: Timer?
    func start() {
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x046d] as CFDictionary)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, removed in
            guard let context else { return }
            let service = Unmanaged<HardwareService>.fromOpaque(context).takeUnretainedValue()
            service.queue.async {
                if service.selected == removed {
                    service.finishButtonCapture(button: nil,reason: "Mouse desconectado.")
                    service.selected = nil
                    DispatchQueue.main.async { service.onDisconnect?() }
                }
            }
            DispatchQueue.main.async { service.refresh() }
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, _ in
            guard let context else { return }
            let service = Unmanaged<HardwareService>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { service.refresh() }
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        refresh()
        polling = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
    }
    func requestAccess() { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent); refresh() }
    func refresh() {
        guard Thread.isMainThread else { DispatchQueue.main.async { self.refresh() }; return }
        IOHIDManagerOpen(manager, 0)
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        let candidates = devices.filter {
            let size = IOHIDDeviceGetProperty($0, kIOHIDMaxOutputReportSizeKey as CFString) as? Int ?? 0
            return size >= 20
        }
        for (device, buffer) in registered where !candidates.contains(device) {
            IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil)
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceClose(device, 0)
            buffer.deallocate()
        }
        registered.removeAll { !candidates.contains($0.0) }
        for device in candidates where !registered.contains(where: { $0.0 == device }) {
            guard IOHIDDeviceOpen(device, 0) == kIOReturnSuccess else { continue }
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
            IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, _, sender, _, reportID, report, length in
                guard let context else { return }
                let service = Unmanaged<HardwareService>.fromOpaque(context).takeUnretainedValue()
                var bytes = Array(UnsafeBufferPointer(start: report, count: length))
                if bytes.first != UInt8(reportID) { bytes.insert(UInt8(reportID), at: 0) }
                guard bytes.count >= 7, [0x10,0x11].contains(bytes[0]) else { return }
                if let sender {
                    let origin = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
                    if service.captureNotification(bytes, device: origin) { return }
                }
                guard let sender else { return }
                let replyOrigin = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
                service.condition.lock()
                guard service.responseDevice == replyOrigin else { service.condition.unlock(); return }
                service.responses.append(bytes)
                if service.responses.count > 64 { service.responses.removeFirst() }
                service.condition.signal(); service.condition.unlock()
            }, Unmanaged.passUnretained(self).toOpaque())
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            registered.append((device,buffer))
        }
        let keyboardProperties = devices.filter { Self.isKeyboard($0) }.map { device in
            KeyboardBattery(id: Self.deviceID(device), name: IOHIDDeviceGetProperty(device,kIOHIDProductKey as CFString) as? String ?? "Teclado Logitech", percent: Self.batteryPercent(IOHIDDeviceGetProperty(device,"BatteryPercent" as CFString)))
        }
        let available = registered.filter { candidates.contains($0.0) }.map(\.0)
        queue.async {
            let endpoints = self.discoverMice(Array(devices), available: available)
            self.onMouseDevices?(endpoints.map(\.info))
            self.inspect(endpoints)
            self.inspectKeyboardBatteries(available, fallback: keyboardProperties)
        }
    }
    func selectMouse(_ id: String) {
        queue.async {
            self.preferredMouse = id
            UserDefaults.standard.set(id,forKey: "selectedLogitechMouse")
            DispatchQueue.main.async { self.refresh() }
        }
    }
    private static func isMouse(_ device: IOHIDDevice) -> Bool {
        let product = IOHIDDeviceGetProperty(device,kIOHIDProductKey as CFString) as? String ?? ""
        let pairs = IOHIDDeviceGetProperty(device,kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Int]] ?? []
        let usages = pairs.compactMap { p -> (Int,Int)? in
            guard let page = p[kIOHIDDeviceUsagePageKey], let usage = p[kIOHIDDeviceUsageKey] else { return nil }; return (page,usage)
        }
        return DeviceIdentity.isLogitechMouse(vendor: 0x046d,product: product,usages: usages,virtual: (IOHIDDeviceGetProperty(device,"HIDVirtualDevice" as CFString) as? Bool) == true)
    }
    private func discoverMice(_ devices: [IOHIDDevice], available: [IOHIDDevice]) -> [MouseEndpoint] {
        var result: [MouseEndpoint] = []
        for device in devices.sorted(by: { Self.deviceID($0) < Self.deviceID($1) }) {
            let product = IOHIDDeviceGetProperty(device,kIOHIDProductKey as CFString) as? String ?? "Logitech"
            let transport = IOHIDDeviceGetProperty(device,kIOHIDTransportKey as CFString) as? String ?? "USB"
            let serial = IOHIDDeviceGetProperty(device,kIOHIDSerialNumberKey as CFString) as? String ?? ""
            let identity = serial.isEmpty ? Self.deviceID(device) : serial
            if Self.isMouse(device) {
                result.append(MouseEndpoint(device: device,address: 0xFF,info: .init(id: identity + ".255",name: product,transport: transport),rootID: UInt64(Self.deviceID(device)),receiverID: nil,canQuery: available.contains(device)))
            } else if available.contains(device), product.localizedCaseInsensitiveContains("Bolt") || product.localizedCaseInsensitiveContains("Receiver") {
                let receiverID = verifiedReceiver(device)
                for address: UInt8 in 1...6 {
                    let index = feature(0x0005,on: device,address: address)
                    guard index != 0,
                          let kind = request(device,address: address,feature: index,function: 2)?.first,
                          [3,5].contains(kind),
                          let length = request(device,address: address,feature: index,function: 0)?.first else { continue }
                    var bytes: [UInt8] = []
                    for offset in stride(from: 0,to: min(Int(length),80),by: 16) {
                        guard let fragment = request(device,address: address,feature: index,function: 1,params: [UInt8(offset)]) else { break }
                        bytes += fragment
                    }
                    guard bytes.count >= Int(length), let name = String(bytes: bytes.prefix(Int(length)),encoding: .utf8), !name.isEmpty else { continue }
                    result.append(MouseEndpoint(device: device,address: address,info: .init(id: identity + "." + String(address),name: name,transport: transport),rootID: nil,receiverID: receiverID,canQuery: true))
                }
                if receiverID != nil && !result.contains(where: { $0.device == device }) {
                    for slot: UInt8 in 1...6 {
                        guard let pairing = receiverRegister(device,sub: 0x50 + slot), pairing.count >= 8, pairing[1] & 15 == 2,
                              let stored = receiverRegister(device,sub: 0x60 + slot,extra: 1), stored.count >= 4 else { continue }
                        let length = min(Int(stored[2]),stored.count-3)
                        guard let name = String(bytes: stored[3..<(3+length)],encoding: .utf8), !name.isEmpty else { continue }
                        result.append(MouseEndpoint(device: device,address: slot,info: .init(id: identity + "." + String(slot),name: name,transport: transport),rootID: nil,receiverID: receiverID,canQuery: false))
                    }
                }
            }
        }
        return result.sorted { $0.info.name < $1.info.name }
    }
    static func batteryPercent(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value >= 0, value <= 100, value.rounded() == value else { return nil }
        return Int(value)
    }
    private static func deviceID(_ device: IOHIDDevice) -> String {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &id)
        return String(id)
    }
    private static func isKeyboard(_ device: IOHIDDevice) -> Bool {
        let pairs = IOHIDDeviceGetProperty(device,kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Int]] ?? []
        return pairs.contains { $0[kIOHIDDeviceUsagePageKey] == 1 && $0[kIOHIDDeviceUsageKey] == 6 }
    }
    private func readBattery(_ device: IOHIDDevice, address: UInt8) -> Int? {
        let unified = feature(0x1004,on: device,address: address)
        if unified != 0, let result = request(device,address: address,feature: unified,function: 1), let level = result.first, level <= 100 { return Int(level) }
        let legacy = feature(0x1000,on: device,address: address)
        if legacy != 0, let result = request(device,address: address,feature: legacy,function: 0), let level = result.first, level <= 100 { return Int(level) }
        return nil
    }
    private func inspectKeyboardBatteries(_ devices: [IOHIDDevice], fallback: [KeyboardBattery]) {
        var keyboards = Dictionary(uniqueKeysWithValues: fallback.map { ($0.id,$0) })
        for device in devices {
            let product = IOHIDDeviceGetProperty(device,kIOHIDProductKey as CFString) as? String ?? "Logitech"
            if Self.isKeyboard(device) {
                let id = Self.deviceID(device)
                let level = readBattery(device,address: 0xFF) ?? keyboards[id]?.percent
                keyboards[id] = KeyboardBattery(id: id,name: product,percent: level)
            } else if product.localizedCaseInsensitiveContains("Bolt") || product.localizedCaseInsensitiveContains("Receiver") {
                for address: UInt8 in 1...6 {
                    let nameFeature = feature(0x0005,on: device,address: address)
                    guard nameFeature != 0,
                          request(device,address: address,feature: nameFeature,function: 2)?.first == 0 else { continue }
                    var name = "Teclado Logitech"
                    if let length = request(device,address: address,feature: nameFeature,function: 0)?.first {
                        var bytes: [UInt8] = []
                        for offset in stride(from: 0,to: min(Int(length),80),by: 16) {
                            guard let fragment = request(device,address: address,feature: nameFeature,function: 1,params: [UInt8(offset)]) else { break }
                            bytes += fragment
                        }
                        name = String(bytes: bytes.prefix(Int(length)),encoding: .utf8) ?? name
                    }
                    let id = Self.deviceID(device) + "." + String(address)
                    keyboards[id] = KeyboardBattery(id: id,name: name,percent: readBattery(device,address: address))
                }
            }
        }
        onKeyboardBatteries?(keyboards.values.sorted { $0.name < $1.name })
    }
    private func request(_ device: IOHIDDevice, address: UInt8, feature: UInt8, function: UInt8, params: [UInt8] = []) -> [UInt8]? {
        var packet = HIDPP.packet(device: address, feature: feature, function: function, parameters: params)
        softwareID = softwareID % 15 + 1
        packet[3] = (function << 4) | softwareID
        condition.lock(); responseDevice = device; responses.removeAll(); condition.unlock()
        let sent = packet.withUnsafeBufferPointer { IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(0x11), $0.baseAddress!, packet.count) }
        guard sent == kIOReturnSuccess else { return nil }
        let deadline = Date().addingTimeInterval(0.35)
        condition.lock(); defer { condition.unlock() }
        while Date() < deadline {
            if let index = responses.firstIndex(where: { $0[1] == address && (($0[2] == feature && $0[3] == packet[3]) || ($0[2] == 0xFF && $0[3] == feature && $0[4] == packet[3])) }) {
                let reply = responses.remove(at: index)
                return reply[2] == 0xFF ? nil : Array(reply.dropFirst(4))
            }
            _ = condition.wait(until: deadline)
        }
        return nil
    }
    private func feature(_ id: UInt16, on device: IOHIDDevice, address: UInt8) -> UInt8 {
        request(device, address: address, feature: 0, function: 0, params: [UInt8(id >> 8), UInt8(id & 255),0])?.first ?? 0
    }
    /// Read-only pairing table: authorize a generic receiver only if it has exactly
    /// one confirmed pointing device. Timeouts and ambiguous receivers fail closed.
    private func verifiedReceiver(_ device: IOHIDDevice) -> UInt64? {
        var mice = 0
        for slot: UInt8 in 1...6 {
            guard let reply = receiverRegister(device, sub: 0x50 + slot) else { return nil }
            if reply.isEmpty { continue }
            guard reply.count >= 8 else { return nil }
            let kind = reply[1] & 15
            if [1,3].contains(kind) { continue } // keyboards and number pads
            guard kind == 2, let nameReply = receiverRegister(device, sub: 0x60 + slot, extra: 1), nameReply.count >= 4 else { return nil }
            let length = min(Int(nameReply[2]), nameReply.count-3)
            let name = String(bytes: nameReply[3..<(3+length)], encoding: .utf8) ?? ""
            guard !name.isEmpty else { return nil }
            mice += 1
        }
        guard mice == 1 else { return nil }
        return DeviceIdentity.usbAncestor(IOHIDDeviceGetService(device))
    }
    private func receiverRegister(_ device: IOHIDDevice, sub: UInt8, extra: UInt8 = 0) -> [UInt8]? {
        let packet: [UInt8] = [0x10,0xFF,0x83,0xB5,sub,extra,0]
        condition.lock(); responseDevice = device; responses.removeAll(); condition.unlock()
        guard packet.withUnsafeBufferPointer({ IOHIDDeviceSetReport(device,kIOHIDReportTypeOutput,16,$0.baseAddress!,7) }) == kIOReturnSuccess else { return nil }
        let deadline = Date().addingTimeInterval(0.35)
        condition.lock(); defer { condition.unlock() }
        while Date() < deadline {
            if let index = responses.firstIndex(where: { $0[1] == 0xFF && (($0[2] == 0x83 && $0[3] == 0xB5 && $0[4] == sub) || ($0[2] == 0x8F && $0[3] == 0x83 && $0[4] == 0xB5)) }) {
                let reply = responses.remove(at: index)
                if reply[2] == 0x8F { return [2,3,8].contains(reply[5]) ? [] : nil }
                return Array(reply.dropFirst(4))
            }
            _ = condition.wait(until: deadline)
        }
        return nil
    }
    /// Returns only a temporary-diversion reset for known mouse button tasks.
    /// Persistent diversion and remappings are deliberately left unchanged.
    static func nativeButtonReset(info: [UInt8], reporting: [UInt8]) -> [UInt8]? {
        guard info.count >= 5, reporting.count >= 3,
              Array(info.prefix(2)) == Array(reporting.prefix(2)),
              info[4] & 0x21 == 0x21,
              [0x003A, 0x003C, 0x003E].contains(Int(info[2]) << 8 | Int(info[3])),
              reporting[2] & 1 != 0 else { return nil }
        return [info[0], info[1], 0x02, 0, 0]
    }
    func recoverNativeButtons(completion: @escaping (String) -> Void) {
        queue.async {
            self.finishButtonCapture(button: nil,reason: nil,notify: false)
            defer { self.startRuntimeButtonsIfNeeded() }
            guard let device = self.selected else { completion("Mouse indisponível. Consulte o dispositivo na seção Mouse."); return }
            let index = self.feature(0x1B04, on: device, address: self.address)
            guard index != 0, let count = self.request(device,address: self.address,feature: index,function: 0)?.first else {
                completion("Não foi possível consultar o modo dos botões."); return
            }
            var restored = 0
            for slot in 0..<min(count,32) {
                guard let info = self.request(device,address: self.address,feature: index,function: 1,params: [slot]), info.count >= 5,
                      let reporting = self.request(device,address: self.address,feature: index,function: 2,params: Array(info.prefix(2))) else {
                    completion("Falha ao consultar os botões. Tente novamente com o mouse acordado."); return
                }
                guard let params = Self.nativeButtonReset(info: info, reporting: reporting) else { continue }
                guard self.request(device,address: self.address,feature: index,function: 3,params: params) != nil,
                      let readback = self.request(device,address: self.address,feature: index,function: 2,params: Array(info.prefix(2))),
                      readback.count >= 3, Array(readback.prefix(2)) == Array(info.prefix(2)), readback[2] & 1 == 0 else {
                    completion("Não foi possível confirmar a restauração dos botões."); return
                }
                restored += 1
            }
            let result = "Modo nativo confirmado. Botões restaurados: \(restored)."
            Logger(subsystem: "br.com.clickplus",category: "HIDButtons").notice("\(result,privacy: .public)")
            completion(result)
        }
    }
    static func captureButton(info: [UInt8]) -> (UInt16, Int)? {
        guard info.count >= 5, info[4] & 0x21 == 0x21 else { return nil }
        let task = Int(info[2]) << 8 | Int(info[3])
        guard let button = [0x003A: 2, 0x003C: 3, 0x003E: 4][task] else { return nil }
        return (UInt16(info[0]) << 8 | UInt16(info[1]), button)
    }
    static func pressedControls(_ bytes: [UInt8]) -> Set<UInt16> {
        var result: Set<UInt16> = []
        for offset in stride(from: 0, to: min(bytes.count - bytes.count % 2, 8), by: 2) {
            let cid = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset+1])
            if cid != 0 { result.insert(cid) }
        }
        return result
    }
    private func captureNotification(_ bytes: [UInt8], device: IOHIDDevice) -> Bool {
        condition.lock()
        guard var session = buttonSession, session.device == device,
              bytes[1] == session.address, bytes[2] == session.feature, bytes[3] == 0 else {
            condition.unlock(); return false
        }
        let held = Self.pressedControls(Array(bytes.dropFirst(4)))
        let newlyPressed = held.subtracting(session.held)
        let released = session.held.subtracting(held).sorted().filter { session.buttons[$0] != nil }
        session.held = held
        buttonSession = session
        condition.unlock()
        let sessionID = session.id
        let identifying = session.identifying
        if !identifying {
            for cid in newlyPressed where session.buttons[cid] == session.panButton { onPanButtonState?(session.panButton, true) }
            for cid in released where session.buttons[cid] == session.panButton { onPanButtonState?(session.panButton, false) }
        }
        let releasedButtons = released.compactMap { session.buttons[$0] }.filter { identifying || $0 != session.panButton }
        if !releasedButtons.isEmpty {
            queue.async {
                self.condition.lock(); let active = self.buttonSession?.id == sessionID; self.condition.unlock()
                guard active else { return }
                if identifying {
                    self.finishButtonCapture(button: releasedButtons.first,reason: nil)
                    self.startRuntimeButtonsIfNeeded()
                } else {
                    for button in releasedButtons { self.onMappedButton?(button) }
                }
            }
        }
        return true
    }
    func configureButtons(_ preferences: Preferences) {
        queue.async {
            guard self.runtimePreferences != preferences else { return }
            self.runtimePreferences = preferences
            self.condition.lock(); let identifying = self.buttonSession?.identifying == true; self.condition.unlock()
            guard !identifying else { return }
            self.finishButtonCapture(button: nil,reason: nil,notify: false)
            self.startRuntimeButtonsIfNeeded()
        }
    }
    private func startRuntimeButtonsIfNeeded() {
        condition.lock(); let active = buttonSession != nil; condition.unlock()
        guard !active, selected != nil, state.buttonCaptureAvailable, runtimePreferences.enabled,
              (2...4).contains(where: { runtimePreferences.needsHardwareButton($0) }) else { return }
        prepareButtons(identifying: false)
    }
    func beginButtonCapture() {
        queue.async { self.prepareButtons(identifying: true) }
    }
    private func prepareButtons(identifying: Bool) {
            self.finishButtonCapture(button: nil, reason: nil, notify: false)
            guard let device = self.selected else { self.onCapturedButton?(nil,"Mouse indisponível. Consulte o dispositivo na seção Mouse."); return }
            let feature = self.feature(0x1B04,on: device,address: self.address)
            guard feature != 0, let count = self.request(device,address: self.address,feature: feature,function: 0)?.first else {
                self.onCapturedButton?(nil,"Não foi possível iniciar a identificação HID++. Acorde o mouse e tente novamente."); return
            }
            var session = CaptureSession(identifying: identifying,panButton: identifying ? -1 : self.runtimePreferences.panButton,device: device,address: self.address,feature: feature,buttons: [:],restore: [])
            for slot in 0..<min(count,32) {
                guard let info = self.request(device,address: session.address,feature: feature,function: 1,params: [slot]),
                      let (cid,button) = Self.captureButton(info: info) else { continue }
                if !identifying && !self.runtimePreferences.needsHardwareButton(button) { continue }
                guard let reporting = self.request(device,address: session.address,feature: feature,function: 2,params: Array(info.prefix(2))), reporting.count >= 3,
                      Array(reporting.prefix(2)) == Array(info.prefix(2)) else { continue }
                session.buttons[cid] = button
                session.restore.append([info[0],info[1],2 | (reporting[2] & 1),0,0])
            }
            guard !session.buttons.isEmpty else { self.onCapturedButton?(nil,"O dispositivo não confirmou botões disponíveis para identificação."); return }
            self.condition.lock(); self.buttonSession = session; self.condition.unlock()
            for restore in session.restore {
                let params: [UInt8] = [restore[0],restore[1],3,0,0]
                guard self.request(device,address: session.address,feature: feature,function: 3,params: params) != nil,
                      let readback = self.request(device,address: session.address,feature: feature,function: 2,params: Array(params.prefix(2))), readback.count >= 3,
                      Array(readback.prefix(2)) == Array(params.prefix(2)), readback[2] & 1 == 1 else {
                    self.finishButtonCapture(button: nil,reason: "Não foi possível preparar os botões. Tente novamente."); return
                }
            }
            guard identifying else { return }
            let timeout = DispatchWorkItem { [weak self] in
                self?.finishButtonCapture(button: nil,reason: "Nenhum botão detectado. Clique em Adicionar botão para tentar novamente.")
                self?.startRuntimeButtonsIfNeeded()
            }
            self.captureTimeout = timeout
            self.queue.asyncAfter(deadline: .now()+60,execute: timeout)
    }
    func cancelButtonCapture(completion: @escaping () -> Void = {}) {
        queue.async {
            self.condition.lock(); let identifying = self.buttonSession?.identifying == true; self.condition.unlock()
            if identifying { self.finishButtonCapture(button: nil,reason: nil); self.startRuntimeButtonsIfNeeded() }
            completion()
        }
    }
    func stopButtons(completion: @escaping () -> Void = {}) {
        queue.async {
            self.runtimePreferences.enabled = false
            self.finishButtonCapture(button: nil,reason: nil)
            completion()
        }
    }
    private func finishButtonCapture(button: Int?, reason: String?, notify: Bool = true) {
        captureTimeout?.cancel(); captureTimeout = nil
        condition.lock(); let session = buttonSession; buttonSession = nil; condition.unlock()
        guard let session else { return }
        if session.panButton >= 2 { onPanCancelled?() }
        var restored = true
        for params in session.restore {
            _ = request(session.device,address: session.address,feature: session.feature,function: 3,params: params)
            let reply = request(session.device,address: session.address,feature: session.feature,function: 2,params: Array(params.prefix(2)))
            if reply == nil || reply!.count < 3 || Array(reply!.prefix(2)) != Array(params.prefix(2)) || reply![2] & 1 != params[2] & 1 { restored = false }
        }
        if notify && session.identifying { onCapturedButton?(button,restored ? reason : "Não foi possível confirmar a restauração. Use Restaurar cliques nativos do mouse.") }
    }
    private func inspect(_ endpoints: [MouseEndpoint]) {
        guard let endpoint = endpoints.first(where: { $0.info.id == preferredMouse }) ?? endpoints.first(where: { $0.info.id == state.id }) ?? endpoints.first else {
            finishButtonCapture(button: nil,reason: "Mouse indisponível.")
            selected = nil; dpiFeature = 0; state = HardwareState(); onChange?(state); return
        }
        let device = endpoint.device, addr = endpoint.address
        if selected != device || address != addr {
            if let originalDPI, let previous = selected {
                writeDPI(originalDPI,device: previous)
                guard state.dpi == originalDPI else { state.detail = "Restaure o DPI do mouse anterior antes de trocar."; onChange?(state); return }
                UserDefaults.standard.removeObject(forKey: restoreKey)
            }
            finishButtonCapture(button: nil,reason: "Dispositivo alterado.")
            state = HardwareState()
            let serial = IOHIDDeviceGetProperty(device,kIOHIDSerialNumberKey as CFString) as? String ?? ""
            restoreKey = "originalDPI.\(serial.isEmpty ? endpoint.info.id : serial).\(addr)"
            originalDPI = UserDefaults.standard.object(forKey: restoreKey) as? Int
        }
        selected = device; address = addr
        state.id = endpoint.info.id; state.name = endpoint.info.name; state.transport = endpoint.info.transport
        state.mouseDeviceID = endpoint.rootID; state.receiverUSBID = endpoint.receiverID
        state.dpiControlled = originalDPI != nil
        state.dpi = nil; state.dpiValues = []; state.battery = nil; state.buttonCaptureAvailable = false
        dpiFeature = 0
        if endpoint.canQuery {
            dpiFeature = feature(0x2201,on: device,address: addr)
            if dpiFeature != 0 {
                if let list = request(device,address: addr,feature: dpiFeature,function: 1,params: [0]) { state.dpiValues = HIDPP.dpiList(list) }
                if let value = request(device,address: addr,feature: dpiFeature,function: 2,params: [0]) { state.dpi = HIDPP.currentDPI(value) }
            }
            state.battery = readBattery(device,address: addr)
            state.buttonCaptureAvailable = feature(0x1B04,on: device,address: addr) != 0
        }
        if state.battery == nil { state.battery = Self.batteryPercent(IOHIDDeviceGetProperty(device,"BatteryPercent" as CFString)) }
        state.detail = endpoint.canQuery ? "Modelo identificado. Bateria, DPI e botões avançados dependem das capacidades HID++ anunciadas por este dispositivo." : "Modelo identificado por HID. Recursos avançados indisponíveis nesta interface; movimento e rolagem usam eventos identificados do mouse."
        if endpoint.rootID == nil && endpoint.receiverID == nil { state.detail += " A origem dos movimentos pelo receptor é ambígua; velocidade e rolagem são preservadas." }
        onChange?(state); startRuntimeButtonsIfNeeded()
    }
    func setDPI(_ dpi: Int) {
        queue.async {
            guard let device = self.selected, self.dpiFeature != 0, self.state.dpiValues.contains(dpi), let current = self.state.dpi else { return }
            if self.originalDPI == nil { self.originalDPI = current; UserDefaults.standard.set(current, forKey: self.restoreKey) }
            self.writeDPI(dpi, device: device)
        }
    }
    private func writeDPI(_ dpi: Int, device: IOHIDDevice) {
        guard request(device,address: address,feature: dpiFeature,function: 3,params: [0,UInt8(dpi >> 8),UInt8(dpi & 255)]) != nil,
              let readback = request(device,address: address,feature: dpiFeature,function: 2,params: [0]), HIDPP.currentDPI(readback) == dpi else {
            state.detail = "Não foi possível confirmar o DPI. O valor exibido não foi atualizado."; onChange?(state); return
        }
        state.dpi = dpi; state.dpiControlled = originalDPI != nil
        state.detail = "DPI confirmado por leitura: \(dpi)."; onChange?(state)
    }
    func restoreDPI(completion: @escaping (Bool) -> Void = { _ in }) {
        queue.async {
            guard let original = self.originalDPI else { completion(true); return }
            guard let device = self.selected else { completion(false); return }
            self.writeDPI(original, device: device)
            if self.state.dpi == original { self.originalDPI = nil; UserDefaults.standard.removeObject(forKey: self.restoreKey); self.state.dpiControlled = false; self.onChange?(self.state); completion(true) } else { completion(false) }
        }
    }
}
