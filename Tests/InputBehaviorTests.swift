import XCTest
import CoreGraphics
@testable import ClickPlus

final class InputBehaviorTests: XCTestCase {
    func testBatteryPercentRejectsInvalidOrBooleanReadings() {
        XCTAssertEqual(HardwareService.batteryPercent(NSNumber(value: 0)),0)
        XCTAssertEqual(HardwareService.batteryPercent(NSNumber(value: 100)),100)
        XCTAssertEqual(HardwareService.batteryPercent(NSNumber(value: 45)),45)
        XCTAssertNil(HardwareService.batteryPercent(NSNumber(value: true)))
        XCTAssertNil(HardwareService.batteryPercent(NSNumber(value: -1)))
        XCTAssertNil(HardwareService.batteryPercent(NSNumber(value: 101)))
        XCTAssertNil(HardwareService.batteryPercent(nil))
    }
    func testNativeResetIsScopedAndDoesNotChangePersistentFlags() {
        let info: [UInt8] = [0,0x53,0,0x3C,0x31]
        XCTAssertEqual(HardwareService.nativeButtonReset(info: info,reporting: [0,0x53,1]),[0,0x53,2,0,0])
        XCTAssertNil(HardwareService.nativeButtonReset(info: info,reporting: [0,0x53,0]))
        XCTAssertNil(HardwareService.nativeButtonReset(info: info,reporting: [0,0x56,1]))
        XCTAssertNil(HardwareService.nativeButtonReset(info: [0,0xD7,0,0xB4,0xA0],reporting: [0,0xD7,1]))
        XCTAssertNil(HardwareService.nativeButtonReset(info: [],reporting: []))
    }
    func testHardwareCaptureUsesAdvertisedMouseTasksOnly() {
        XCTAssertEqual(HardwareService.captureButton(info: [0,0x53,0,0x3C,0x31])?.1,3)
        XCTAssertEqual(HardwareService.captureButton(info: [0,0x56,0,0x3E,0x31])?.1,4)
        XCTAssertEqual(HardwareService.captureButton(info: [0,0x52,0,0x3A,0x31])?.1,2)
        XCTAssertNil(HardwareService.captureButton(info: [0,0x53,0,0x3C,1]))
        XCTAssertNil(HardwareService.captureButton(info: [0,0xD7,0,0xB4,0xA0]))
        XCTAssertNil(HardwareService.captureButton(info: []))
    }
    func testHardwarePressedControlListAndRelease() {
        let pressed = HardwareService.pressedControls([0,0x53,0,0x56,0,0,0,0])
        XCTAssertEqual(pressed,Set([UInt16(0x53),UInt16(0x56)]))
        let released = pressed.subtracting(HardwareService.pressedControls([0,0x56,0,0]))
        XCTAssertEqual(released,Set([UInt16(0x53)]))
        XCTAssertTrue(HardwareService.pressedControls([]).isEmpty)
        XCTAssertTrue(HardwareService.pressedControls([0]).isEmpty)
    }
    func testRemovedButtonCanBeAssignedAgain() {
        var p = Preferences(); p.buttons.removeValue(forKey: 3); p.captureBack = false
        p.assign(ButtonAction(kind: .missionControl),to: 3)
        XCTAssertEqual(p.buttons[3]?.kind,.missionControl)
        XCTAssertTrue(p.captures(3))
    }
    func testHardwareReleaseDispatchesSavedApplication() {
        var p = Preferences(); p.enabled = true
        let action = ButtonAction(kind: .application, applicationPath: "/Applications/LaunchOS.app")
        p.assign(action,to: 3)
        var actions: [ButtonAction] = []
        let engine = EventEngine(preferences: p,actionSink: { actions.append($0) })
        engine.handleHardwareRelease(3)
        XCTAssertEqual(actions,[action])
        engine.handleHardwareRelease(2)
        XCTAssertEqual(actions.count,1)
    }
    func testHardwareMappingRespectsPauseRemovalAndPan() {
        var p = Preferences(); p.enabled = false; p.assign(ButtonAction(kind: .missionControl),to: 3)
        XCTAssertNil(p.hardwareAction(3))
        p.enabled = true; XCTAssertNotNil(p.hardwareAction(3))
        p.captureBack = false; XCTAssertNil(p.hardwareAction(3))
        p.captureBack = true; p.panButton = 3; XCTAssertNil(p.hardwareAction(3))
        p.panButton = -1; p.buttons.removeValue(forKey: 3); XCTAssertNil(p.hardwareAction(3))
    }
    func testApplicationToggleOnlyHidesTheForegroundApp() {
        XCTAssertTrue(ActionService.shouldHideApplication(isActive: true,isHidden: false,toggle: true))
        XCTAssertFalse(ActionService.shouldHideApplication(isActive: false,isHidden: false,toggle: true))
        XCTAssertFalse(ActionService.shouldHideApplication(isActive: true,isHidden: true,toggle: true))
        XCTAssertFalse(ActionService.shouldHideApplication(isActive: true,isHidden: false,toggle: false))
    }
    func testPanClickReplaysExactlyOneClick() throws {
        var p = Preferences(); p.enabled = true; p.panButton = 2
        var output: [CGEvent] = []
        let engine = EventEngine(preferences: p,sourceResolver: { _ in .mouse },eventSink: { output.append($0) })
        XCTAssertNil(engine.handle(.otherMouseDown,try mouse(.otherMouseDown,button: 2)))
        XCTAssertTrue(output.isEmpty)
        XCTAssertNil(engine.handle(.otherMouseUp,try mouse(.otherMouseUp,button: 2)))
        XCTAssertEqual(output.map(\.type),[.otherMouseDown,.otherMouseUp])
    }
    func testPanDragScrollsWithoutClickAndIgnoresOtherButton() throws {
        var p = Preferences(); p.enabled = true; p.panButton = 2
        var output: [CGEvent] = []
        let engine = EventEngine(preferences: p,sourceResolver: { _ in .mouse },eventSink: { output.append($0) })
        _ = engine.handle(.otherMouseDown,try mouse(.otherMouseDown,button: 2))
        let wrong = try mouse(.rightMouseDragged,button: 1)
        wrong.setDoubleValueField(.mouseEventDeltaX,value: 10)
        XCTAssertTrue(engine.handle(.rightMouseDragged,wrong) != nil)
        XCTAssertTrue(output.isEmpty)
        let drag = try mouse(.otherMouseDragged,button: 2)
        drag.setDoubleValueField(.mouseEventDeltaX,value: 6)
        drag.setDoubleValueField(.mouseEventDeltaY,value: 8)
        _ = engine.handle(.otherMouseDragged,drag)
        _ = engine.handle(.otherMouseUp,try mouse(.otherMouseUp,button: 2))
        XCTAssertEqual(output.map(\.type),[.scrollWheel,.mouseMoved])
        XCTAssertEqual(output[0].getIntegerValueField(.scrollWheelEventPointDeltaAxis1),-8)
        XCTAssertEqual(output[0].getIntegerValueField(.scrollWheelEventPointDeltaAxis2),-6)
    }
    func testScrollZoomAndSpeedModifier() throws {
        var p = Preferences(); p.enabled = true; p.scrollEnabled = true; p.modifierGain = 3
        var keys: [ButtonAction] = []; var output: [CGEvent] = []
        let engine = EventEngine(preferences: p,sourceResolver: { _ in .mouse },eventSink: { output.append($0) },actionSink: { keys.append($0) })
        let input = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil,units: .pixel,wheelCount: 2,wheel1: 10,wheel2: 0,wheel3: 0))
        input.flags = .maskControl; _ = engine.handle(.scrollWheel,input)
        XCTAssertEqual(keys.map(\.keyCode),[24]); XCTAssertTrue(output.isEmpty)
        XCTAssertEqual(keys[0].flags,CGEventFlags.maskCommand.rawValue)
        input.flags = .maskCommand; _ = engine.handle(.scrollWheel,input)
        XCTAssertEqual(output[0].getIntegerValueField(.scrollWheelEventPointDeltaAxis1),30)
        XCTAssertFalse(output[0].flags.contains(.maskCommand))
    }
    func testZeroScrollDoesNotZoom() throws {
        var p = Preferences(); p.enabled = true; p.scrollEnabled = true
        let engine = EventEngine(preferences: p,sourceResolver: { _ in .mouse },actionSink: { _ in XCTFail("Zero movement must not zoom") })
        let input = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil,units: .pixel,wheelCount: 2,wheel1: 0,wheel2: 0,wheel3: 0))
        input.flags = .maskControl; _ = engine.handle(.scrollWheel,input)
    }
    func testPausedServicePreservesScrollAndHardwareButtons() throws {
        var p = Preferences(); p.enabled = false; p.scrollEnabled = true; p.cursorEnabled = true; p.assign(ButtonAction(kind: .copy),to: 3)
        let engine = EventEngine(preferences: p,sourceResolver: { _ in .mouse },eventSink: { _ in XCTFail("Paused") },actionSink: { _ in XCTFail("Paused") })
        let event = try mouse(.otherMouseDown)
        XCTAssertTrue(engine.handle(.otherMouseDown,event) != nil)
        engine.handleHardwareRelease(3)
    }
    func testHardwarePanWorksWithDivertedButtonAndDoesNotExecuteClick() throws {
        var p = Preferences(); p.enabled = true; p.panButton = 3
        p.assign(ButtonAction(kind: .missionControl),to: 3)
        var output: [CGEvent] = []; var actions: [ButtonAction] = []
        let engine = EventEngine(preferences: p,sourceResolver: { _ in .mouse },eventSink: { output.append($0) },actionSink: { actions.append($0) })
        XCTAssertTrue(p.needsHardwareButton(3))
        engine.handleHardwarePan(3,down: true,at: CGPoint(x: 400,y: 300))
        let move = try mouse(.mouseMoved)
        move.setDoubleValueField(.mouseEventDeltaY,value: 8)
        XCTAssertNil(engine.handle(.mouseMoved,move))
        engine.handleHardwarePan(3,down: false,at: move.location)
        XCTAssertEqual(output.filter { $0.type == .scrollWheel }.count,1)
        XCTAssertTrue(actions.isEmpty)
    }
    func testTrackpadCannotDriveHardwarePanAndClickKeepsItsAction() throws {
        var p = Preferences(); p.enabled = true; p.panButton = 3
        p.assign(ButtonAction(kind: .missionControl),to: 3)
        var actions: [ButtonAction] = []
        let engine = EventEngine(preferences: p,sourceResolver: { _ in .trackpad },eventSink: { _ in XCTFail("Trackpad must not pan") },actionSink: { actions.append($0) })
        engine.handleHardwarePan(3,down: true,at: CGPoint(x: 400,y: 300))
        let move = try mouse(.mouseMoved); move.setDoubleValueField(.mouseEventDeltaY,value: 20)
        XCTAssertTrue(engine.handle(.mouseMoved,move) != nil)
        engine.handleHardwarePan(3,down: false,at: move.location)
        XCTAssertEqual(actions.map(\.kind),[.missionControl])
    }
    func testCaptureConsumesOneCompleteClick() {
        var capture = ButtonCapture(); capture.begin()
        XCTAssertEqual(capture.process(type: .otherMouseDown,button: 3,isTarget: true),.consume)
        XCTAssertEqual(capture.process(type: .otherMouseDragged,button: 3,isTarget: true),.consume)
        XCTAssertEqual(capture.process(type: .otherMouseUp,button: 3,isTarget: true),.detected(3))
        XCTAssertFalse(capture.waiting)
        XCTAssertEqual(capture.process(type: .otherMouseUp,button: 3,isTarget: true),.pass)
    }
    func testCaptureIgnoresTrackpadAndPrimaryButtons() {
        var capture = ButtonCapture(); capture.begin()
        XCTAssertEqual(capture.process(type: .otherMouseDown,button: 3,isTarget: false),.pass)
        XCTAssertEqual(capture.process(type: .leftMouseDown,button: 0,isTarget: true),.pass)
        XCTAssertEqual(capture.process(type: .rightMouseDown,button: 1,isTarget: true),.pass)
        XCTAssertNil(capture.heldButton); XCTAssertTrue(capture.waiting)
    }
    func testCancelDoesNotLeakReleaseOrDetectAnotherDevice() {
        var capture = ButtonCapture(); capture.begin()
        _ = capture.process(type: .otherMouseDown,button: 4,isTarget: true)
        capture.cancel()
        XCTAssertEqual(capture.process(type: .otherMouseUp,button: 4,isTarget: false),.pass)
        XCTAssertEqual(capture.process(type: .otherMouseUp,button: 4,isTarget: true),.consume)
        XCTAssertFalse(capture.waiting)
    }
    func testAssigningDetectedButtonEnablesItWithoutDuplicates() {
        var p = Preferences()
        p.assign(ButtonAction(kind: .copy),to: 4)
        XCTAssertTrue(p.captures(4)); XCTAssertEqual(p.buttons.count,3)
        p.assign(ButtonAction(kind: .paste),to: 4)
        XCTAssertEqual(p.buttons.count,3); XCTAssertEqual(p.buttons[4]?.kind,.paste)
        p.assign(ButtonAction(kind: .copy),to: 0)
        XCTAssertNil(p.buttons[0]); XCTAssertFalse(p.captures(0))
    }
    private func mouse(_ type: CGEventType, button: UInt32 = 3) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(mouseEventSource: nil,mouseType: type,mouseCursorPosition: CGPoint(x: 400,y: 300),mouseButton: CGMouseButton(rawValue: button)!))
        event.setIntegerValueField(.mouseEventButtonNumber,value: Int64(button)); event.flags = []
        return event
    }
    func testMappedClickExecutesOnceOnRelease() throws {
        var p = Preferences(); p.enabled = true; p.assign(ButtonAction(kind: .copy),to: 3)
        var actions: [ButtonAction] = []
        let engine = EventEngine(preferences: p,sourceResolver: { _ in .mouse },eventSink: { _ in XCTFail("No mouse events should be posted") },actionSink: { actions.append($0) })
        XCTAssertNil(engine.handle(.otherMouseDown,try mouse(.otherMouseDown)))
        XCTAssertTrue(actions.isEmpty)
        XCTAssertNil(engine.handle(.otherMouseUp,try mouse(.otherMouseUp)))
        XCTAssertEqual(actions.map(\.kind),[.copy])
        let extraRelease = try mouse(.otherMouseUp)
        XCTAssertTrue(engine.handle(.otherMouseUp,extraRelease) != nil)
        XCTAssertEqual(actions.count,1)
    }
    func testTrackpadPassesUnmodifiedWithEveryControlEnabled() throws {
        var p = Preferences(); p.enabled = true; p.cursorEnabled = true; p.cursorSpeed = 5; p.scrollEnabled = true; p.invertVertical = true; p.panButton = 1; p.leftClickThrough = true; p.assign(ButtonAction(kind: .copy),to: 3)
        let engine = EventEngine(preferences: p,sourceResolver: { _ in .trackpad },pointerPreparation: { _ in XCTFail("Must not change trackpad acceleration"); return false },eventSink: { _ in XCTFail("Must not synthesize trackpad events") },actionSink: { _ in XCTFail("Must not map trackpad buttons") })
        let scroll = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil,units: .pixel,wheelCount: 2,wheel1: 17,wheel2: -9,wheel3: 0))
        let events = [try mouse(.mouseMoved),try mouse(.otherMouseDown),try mouse(.leftMouseDown,button: 0),scroll]
        for event in events {
            let location = event.location
            let vertical = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            XCTAssertNotNil(engine.handle(event.type,event))
            XCTAssertEqual(event.location,location)
            XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1),vertical)
        }
    }
    func testScrollSpeedInversionAndHorizontalModifier() throws {
        var p = Preferences(); p.enabled = true; p.scrollEnabled = true; p.scrollSpeed = 2; p.invertVertical = true
        var output: [CGEvent] = []
        let engine = EventEngine(preferences: p,sourceResolver: { _ in .mouse },eventSink: { output.append($0) })
        let input = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil,units: .pixel,wheelCount: 2,wheel1: 12,wheel2: 0,wheel3: 0)); input.flags = []
        XCTAssertNil(engine.handle(.scrollWheel,input))
        XCTAssertEqual(output.last?.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),-24)
        input.flags = .maskShift
        XCTAssertNil(engine.handle(.scrollWheel,input))
        XCTAssertEqual(output.last?.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),0)
        XCTAssertEqual(output.last?.getIntegerValueField(.scrollWheelEventPointDeltaAxis2),12)
        XCTAssertFalse(output.last!.flags.contains(.maskShift))
    }
    func testCursorSpeedAndPrecisionUseOnlyTargetService() throws {
        var p = Preferences(); p.enabled = true; p.cursorEnabled = true; p.cursorSpeed = 2; p.precisionModifier = .option; p.precisionGain = 0.25
        var preparations = 0
        let engine = EventEngine(preferences: p,sourceResolver: { _ in .mouse },pointerPreparation: { _ in preparations += 1; return true })
        let event = try mouse(.mouseMoved)
        event.setDoubleValueField(.mouseEventDeltaX,value: 10); event.setDoubleValueField(.mouseEventDeltaY,value: 4)
        _ = engine.handle(.mouseMoved,event)
        XCTAssertEqual(event.getDoubleValueField(.mouseEventDeltaX),20)
        XCTAssertEqual(event.location,CGPoint(x: 410,y: 304))
        event.flags = .maskAlternate
        event.setDoubleValueField(.mouseEventDeltaX,value: 10)
        _ = engine.handle(.mouseMoved,event)
        XCTAssertEqual(event.getDoubleValueField(.mouseEventDeltaX),5)
        XCTAssertEqual(preparations,2)
    }
    func testUnknownAndOwnSyntheticEventsAreNeverChanged() throws {
        var p = Preferences(); p.enabled = true; p.cursorEnabled = true; p.cursorSpeed = 3
        for source in [DeviceIdentity.Source.unknown,.mouse] {
            let engine = EventEngine(preferences: p,sourceResolver: { _ in source },pointerPreparation: { _ in XCTFail("Must not prepare a device"); return true })
            let event = try mouse(.mouseMoved)
            if source == .mouse { event.setIntegerValueField(.eventSourceUserData,value: ActionService.marker) }
            XCTAssertNotNil(engine.handle(.mouseMoved,event)); XCTAssertEqual(event.location,CGPoint(x: 400,y: 300))
        }
    }
}
