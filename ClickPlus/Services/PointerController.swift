import Foundation
import IOKit
import CoreGraphics
import Darwin

/// Disable only the selected HID service's system acceleration while our curve is active.
/// Snapshot and restore properties; never change the global mouse/trackpad preferences.
final class PointerController {
    typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    typealias Services = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    typealias Get = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    typealias Set = @convention(c) (CFTypeRef, CFString, CFTypeRef) -> Bool
    typealias RegistryID = @convention(c) (CFTypeRef) -> Unmanaged<CFTypeRef>?
    private var client: CFTypeRef?
    private var list: Services?
    private var get: Get?
    private var set: Set?
    private var registry: RegistryID?
    private var originals: [UInt64: (CFTypeRef, String, CFTypeRef)] = [:]
    init() {
        let handle = dlopen(nil, RTLD_LAZY)
        if let symbol = dlsym(handle, "IOHIDEventSystemClientCreateSimpleClient") { client = unsafeBitCast(symbol, to: Create.self)(kCFAllocatorDefault)?.takeRetainedValue() }
        list = dlsym(handle,"IOHIDEventSystemClientCopyServices").map { unsafeBitCast($0,to: Services.self) }
        get = dlsym(handle,"IOHIDServiceClientCopyProperty").map { unsafeBitCast($0,to: Get.self) }
        set = dlsym(handle,"IOHIDServiceClientSetProperty").map { unsafeBitCast($0,to: Set.self) }
        registry = dlsym(handle,"IOHIDServiceClientGetRegistryID").map { unsafeBitCast($0,to: RegistryID.self) }
    }
    func prepare(senderID: UInt64) -> Bool {
        if originals[senderID] != nil { return true }
        guard let client, let list, let get, let set, let registry,
              let services = list(client)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        for service in services {
            guard let number = registry(service)?.takeUnretainedValue() as? NSNumber, number.uint64Value == senderID else { continue }
            let key = get(service,"HIDPointerAccelerationType" as CFString)?.takeRetainedValue() as? String ?? "HIDMouseAcceleration"
            guard let original = get(service,key as CFString)?.takeRetainedValue() else { return false }
            guard set(service,key as CFString,NSNumber(value: -65536)) else { return false }
            originals[senderID] = (service,key,original)
            return true
        }
        return false
    }
    func restore() {
        guard let set else { return }
        originals = originals.filter { _, value in !set(value.0,value.1 as CFString,value.2) }
    }
}
