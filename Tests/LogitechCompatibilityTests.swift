import XCTest
@testable import ClickPlus

final class LogitechCompatibilityTests: XCTestCase {
    func testSeveralLogitechModelsAreAcceptedByTheirHIDUsage() {
        for name in ["Logi M650 L","MX Master 3S","MX Anywhere 3","G Pro Wireless","M185","M705","ERGO M575"] {
            XCTAssertTrue(DeviceIdentity.isLogitechMouse(vendor: 0x046d,product: name,usages: [(1,2),(1,1)]),name)
        }
    }
    func testKeyboardIsNeverMistakenForMouse() {
        for name in ["Logi K950","MX Keys S","K380"] {
            XCTAssertFalse(DeviceIdentity.isLogitechMouse(vendor: 0x046d,product: name,usages: [(1,6)]),name)
            XCTAssertFalse(DeviceIdentity.isLogitechMouse(vendor: 0x046d,product: name,usages: [(1,6),(1,2)]),name)
        }
    }
    func testUnknownBrandsVirtualDevicesAndTrackpadsAreRejected() {
        XCTAssertFalse(DeviceIdentity.isLogitechMouse(vendor: 1452,product: "Magic Mouse",usages: [(1,2)]))
        XCTAssertFalse(DeviceIdentity.isLogitechMouse(vendor: 0x046d,product: "Mouse",usages: []))
        XCTAssertFalse(DeviceIdentity.isLogitechMouse(vendor: 0x046d,product: "Virtual mouse",usages: [(1,2)],virtual: true))
        XCTAssertFalse(DeviceIdentity.isLogitechMouse(vendor: 0x046d,product: "Wireless Trackpad",usages: [(1,2)]))
    }
    func testReceiverMustBeVerifiedSeparatelyEvenWithMouseUsage() {
        for name in ["Logi Bolt Receiver","USB Receiver","Unifying Receiver"] {
            XCTAssertFalse(DeviceIdentity.isLogitechMouse(vendor: 0x046d,product: name,usages: [(1,2)]))
        }
    }
}
