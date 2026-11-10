import Foundation
import CoreGraphics
import IOKit
import Darwin

/// macOS has no public CGEvent device identifier. Keep this optional SPI isolated.
/// No timing heuristics: unidentified events always pass through unchanged.
final class DeviceIdentity {
    typealias CopyEvent = @convention(c) (CGEvent) -> Unmanaged<CFTypeRef>?
    typealias Sender = @convention(c) (CFTypeRef) -> UInt64
    private let copyEvent: CopyEvent?
    private let sender: Sender?
    var receiverUSBID: UInt64? { didSet { cache.removeAll() } }
    var selectedMouseID: UInt64? { didSet { cache.removeAll() } }
    enum Source { case mouse, trackpad, other, unknown }
    private var cache: [UInt64: Source] = [:]
    init() {
        let handle = dlopen(nil, RTLD_LAZY)
        copyEvent = dlsym(handle, "CGEventCopyIOHIDEvent").map { unsafeBitCast($0, to: CopyEvent.self) }
        sender = dlsym(handle, "IOHIDEventGetSenderID").map { unsafeBitCast($0, to: Sender.self) }
    }
    static func usbAncestor(_ service: io_registry_entry_t) -> UInt64? {
        guard service != 0 else { return nil }
        IOObjectRetain(service)
        var current = service
        for _ in 0..<16 {
            if IOObjectConformsTo(current, "IOUSBHostDevice") != 0 {
                var id: UInt64 = 0
                IORegistryEntryGetRegistryEntryID(current, &id); IOObjectRelease(current)
                return id == 0 ? nil : id
            }
            var parent: io_registry_entry_t = 0
            IORegistryEntryGetParentEntry(current,kIOServicePlane,&parent)
            IOObjectRelease(current)
            guard parent != 0 else { return nil }
            current = parent
        }
        IOObjectRelease(current); return nil
    }
    static func isLogitechMouse(vendor: Int, product: String, usages: [(Int, Int)], virtual: Bool = false) -> Bool {
        guard vendor == 0x046d, !virtual, !product.localizedCaseInsensitiveContains("trackpad"),
              !product.localizedCaseInsensitiveContains("receiver"), !product.localizedCaseInsensitiveContains("bolt") else { return false }
        return usages.contains { $0 == (1,2) } && !usages.contains { $0 == (1,6) }
    }
    var available: Bool { copyEvent != nil && sender != nil }
    func reset() { cache.removeAll() }
    func senderID(_ event: CGEvent) -> UInt64 {
        guard let copyEvent, let sender, let hid = copyEvent(event)?.takeRetainedValue() else { return 0 }
        return sender(hid)
    }
    func isTarget(_ event: CGEvent) -> Bool { source(event) == .mouse }
    func source(_ event: CGEvent) -> Source {
        guard let copyEvent, let sender, let hid = copyEvent(event)?.takeRetainedValue() else { return .unknown }
        let id = sender(hid)
        guard id != 0 else { return .unknown }
        if let known = cache[id] { return known }
        var entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(id))
        if let receiverUSBID, Self.usbAncestor(entry) == receiverUSBID {
            IOObjectRelease(entry); cache[id] = .mouse; return .mouse
        }
        var target = Source.other
        for _ in 0..<8 {
            guard entry != 0 else { break }
            let product = IORegistryEntryCreateCFProperty(entry, "Product" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String ?? ""
            let vendor = IORegistryEntryCreateCFProperty(entry, "VendorID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int ?? 0
            let pairs = IORegistryEntryCreateCFProperty(entry,"DeviceUsagePairs" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? [[String: Int]] ?? []
            let usages = pairs.compactMap { pair -> (Int, Int)? in
                guard let page = pair["DeviceUsagePage"], let usage = pair["DeviceUsage"] else { return nil }; return (page,usage)
            }
            var registryID: UInt64 = 0; IORegistryEntryGetRegistryEntryID(entry,&registryID)
            if registryID == selectedMouseID, Self.isLogitechMouse(vendor: vendor,product: product,usages: usages,virtual: (IORegistryEntryCreateCFProperty(entry,"HIDVirtualDevice" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? Bool) == true) { target = .mouse; IOObjectRelease(entry); entry = 0; break }
            if product.localizedCaseInsensitiveContains("trackpad") {
                target = .trackpad; IOObjectRelease(entry); entry = 0; break
            }
            // A generic Bolt receiver may represent multiple mice: do not guess its identity.
            var parent: io_registry_entry_t = 0
            IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
            IOObjectRelease(entry); entry = parent
        }
        if entry != 0 { IOObjectRelease(entry) }
        cache[id] = target
        return target
    }
}
