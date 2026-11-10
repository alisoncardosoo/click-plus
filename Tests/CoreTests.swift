import XCTest
import CoreGraphics

@testable import ClickPlus
final class CoreTests: XCTestCase {
    func testImpulseConservesDistance() {
        for duration in [0.02,0.16,1.0] { for brake in [0.05,0.5,0.95] { for extra in [0.0,5.0] {
            let weights = ScrollMath.weights(duration: duration, brake: brake, extra: extra)
            XCTAssertEqual(weights.reduce(0,+), 1, accuracy: 0.000001)
            XCTAssertTrue(weights.allSatisfy { $0 >= 0 && $0.isFinite })
        } } }
    }
    func testNoAccelerationIsLinear() {
        XCTAssertEqual(ScrollMath.distance(-5,speed: 2,acceleration: 0), -10)
        XCTAssertEqual(ScrollMath.distance(10,speed: 2,acceleration: 0), 20)
    }
    func testPreferencesRoundTrip() throws {
        var prefs = Preferences(); prefs.captureBack = true; prefs.buttons[3] = ButtonAction(kind: .shortcut,keyCode: 8,flags: 1 << 20,label: "⌘C")
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(prefs)), prefs)
        XCTAssertTrue(Preferences().enabled)
    }
    func testDPIListAndRange() {
        XCTAssertEqual(HIDPP.dpiList([0,0x01,0x90,0xE0,0x64,0x03,0x20,0,0]), [400,500,600,700,800])
        XCTAssertEqual(HIDPP.dpiList([0,0xE0,0,0,0]), [])
        XCTAssertEqual(HIDPP.currentDPI([0,0,0,4,0xB0]), 1200)
        XCTAssertNil(HIDPP.currentDPI([0]))
    }
    func testPacketBoundsAndSoftwareID() {
        let p = HIDPP.packet(device: 0xFF,feature: 8,function: 3,parameters: [0,4,0xB0])
        XCTAssertEqual(p.count,20); XCTAssertEqual(Array(p.prefix(7)),[0x11,0xFF,8,0x3A,0,4,0xB0])
    }
    func testModifierNoneNeverMatches() { XCTAssertFalse(Modifier.none.matches([])); XCTAssertTrue(Modifier.shift.matches([.maskShift,.maskCommand])) }
}

final class DeviceIsolationTests: XCTestCase {
    func testSyntheticMouseEventNeverMatchesHardware() throws {
        let event = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: .zero, mouseButton: .left))
        let identity = DeviceIdentity()
        XCTAssertFalse(identity.isTarget(event))
    }
    func testMissingUSBServiceIsNotTrusted() { XCTAssertNil(DeviceIdentity.usbAncestor(0)) }
    func testUnknownDPIListCannotOfferWrites() {
        XCTAssertEqual(HIDPP.dpiList([]), [])
        XCTAssertEqual(HIDPP.dpiList([0,0xE0,0x64]), [])
        XCTAssertNil(HIDPP.currentDPI([]))
    }
    func testDefaultActionsDoNotInterceptButtons() {
        let p = Preferences()
        XCTAssertFalse(p.captureBack); XCTAssertFalse(p.captureForward)
        XCTAssertEqual(p.panButton,-1)
        XCTAssertTrue(p.buttons.values.allSatisfy { $0.kind == .original })
        XCTAssertFalse(p.leftClickThrough); XCTAssertFalse(p.rightClickThrough); XCTAssertFalse(p.panClickThrough)
    }
}
