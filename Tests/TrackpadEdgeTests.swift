import XCTest
@testable import ClickPlus

final class TrackpadEdgeTests: XCTestCase {
    private var p: TrackpadPreferences { var p = TrackpadPreferences(); p.enabled = true; return p }
    private func touch(_ x: Double,_ y: Double,_ id: Int = 1) -> [EdgeTouch] { [.init(id: id,x: x,y: y)] }
    func testStartsOffAndPreservesOtherPreferences() throws {
        XCTAssertFalse(TrackpadPreferences().enabled)
        XCTAssertEqual(p.edges[.right]?.mode,.brightness)
        XCTAssertEqual(p.edges[.left]?.mode,.volume)
        XCTAssertEqual(p.edges[.bottom]?.mode,.tracks)
        XCTAssertEqual(p.edges[.top]?.mode,.off)
        XCTAssertEqual(try JSONDecoder().decode(TrackpadPreferences.self,from: JSONEncoder().encode(p)),p)
    }
    func testRightEdgeBrightnessInBothDirections() {
        var r = EdgeRecognizer()
        XCTAssertTrue(r.process(touch(0.98,0.5),time: 0,preferences: p).isEmpty)
        XCTAssertEqual(r.process(touch(0.98,0.6),time: 0.1,preferences: p),[.init(edge: .right,direction: 1)])
        XCTAssertTrue(r.claimed)
        XCTAssertEqual(r.process(touch(0.98,0.4),time: 0.2,preferences: p),[.init(edge: .right,direction: -1)])
        _ = r.process([],time: 0.3,preferences: p); XCTAssertFalse(r.claimed)
    }
    func testHapticPreferencePreservesSavedEdgesAndDisabledChoice() throws {
        var prefs = p
        prefs.width = 0.1
        prefs.edges[.top] = .init(mode: .playback)
        let encoded = try JSONEncoder().encode(prefs)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "hapticFeedback")
        let restored = try JSONDecoder().decode(TrackpadPreferences.self,from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(restored,prefs)
        XCTAssertTrue(restored.hapticFeedback)
        prefs.hapticFeedback = false
        XCTAssertEqual(try JSONDecoder().decode(TrackpadPreferences.self,from: JSONEncoder().encode(prefs)),prefs)
    }
    func testCenterCannotEnterAnEdgeMidGesture() {
        var r = EdgeRecognizer()
        _ = r.process(touch(0.5,0.5),time: 0,preferences: p)
        XCTAssertTrue(r.process(touch(0.99,0.9),time: 0.2,preferences: p).isEmpty)
        XCTAssertFalse(r.claimed)
    }
    func testMultiFingerDisarmsUntilAllLift() {
        var r = EdgeRecognizer()
        _ = r.process(touch(0.02,0.5),time: 0,preferences: p)
        _ = r.process(touch(0.02,0.7) + touch(0.05,0.7,2),time: 0.1,preferences: p)
        XCTAssertTrue(r.process(touch(0.02,0.8),time: 0.2,preferences: p).isEmpty)
        XCTAssertFalse(r.claimed)
        _ = r.process([],time: 0.3,preferences: p)
        _ = r.process(touch(0.02,0.5),time: 0.4,preferences: p)
        XCTAssertEqual(r.process(touch(0.02,0.7),time: 0.5,preferences: p).first?.edge,.left)
    }
    func testBottomTrackSwitchFiresOncePerContact() {
        var r = EdgeRecognizer()
        _ = r.process(touch(0.5,0.02),time: 0,preferences: p)
        XCTAssertEqual(r.process(touch(0.6,0.02),time: 0.1,preferences: p),[.init(edge: .bottom,direction: 1)])
        XCTAssertTrue(r.process(touch(0.8,0.02),time: 0.2,preferences: p).isEmpty)
        XCTAssertTrue(r.process(touch(0.3,0.02),time: 0.3,preferences: p).isEmpty)
    }
    func testTopCustomAndDisabledModes() {
        var r = EdgeRecognizer(); var prefs = p
        _ = r.process(touch(0.5,0.99),time: 0,preferences: prefs)
        XCTAssertTrue(r.process(touch(0.8,0.99),time: 0.1,preferences: prefs).isEmpty)
        r.reset(); prefs.edges[.top] = .init(mode: .custom)
        _ = r.process(touch(0.5,0.99),time: 0,preferences: prefs)
        XCTAssertEqual(r.process(touch(0.3,0.99),time: 0.1,preferences: prefs),[.init(edge: .top,direction: -1)])
    }
    func testLeavingBandCancelsContact() {
        var r = EdgeRecognizer()
        _ = r.process(touch(0.99,0.5),time: 0,preferences: p)
        _ = r.process(touch(0.7,0.6),time: 0.1,preferences: p)
        XCTAssertTrue(r.process(touch(0.99,0.8),time: 0.2,preferences: p).isEmpty)
    }
    func testSmallMotionDoesNotClaimOrAct() {
        var r = EdgeRecognizer()
        _ = r.process(touch(0.99,0.5),time: 0,preferences: p)
        XCTAssertTrue(r.process(touch(0.99,0.51),time: 0.1,preferences: p).isEmpty)
        XCTAssertFalse(r.claimed)
    }
    func testOptionalTapOnlyBottomAndNotAfterSwipe() {
        var r = EdgeRecognizer(); var prefs = p
        prefs.edges[.bottom]?.tapToPlay = true
        _ = r.process(touch(0.5,0.02),time: 0,preferences: prefs)
        XCTAssertEqual(r.process([],time: 0.1,preferences: prefs),[.init(edge: .bottom,direction: 0)])
        _ = r.process(touch(0.5,0.02),time: 1,preferences: prefs)
        _ = r.process(touch(0.7,0.02),time: 1.1,preferences: prefs)
        XCTAssertTrue(r.process([],time: 1.2,preferences: prefs).isEmpty)
    }
    func testPauseClearsClaimedGesture() {
        var r = EdgeRecognizer(); var prefs = p
        _ = r.process(touch(0.99,0.5),time: 0,preferences: prefs)
        _ = r.process(touch(0.99,0.7),time: 0.1,preferences: prefs)
        prefs.enabled = false
        XCTAssertTrue(r.process(touch(0.99,0.9),time: 0.2,preferences: prefs).isEmpty)
        XCTAssertFalse(r.claimed)
    }
    func testInvalidCoordinatesAndChangedFingerAreRejected() {
        var r = EdgeRecognizer()
        _ = r.process(touch(0.99,0.5),time: 0,preferences: p)
        XCTAssertTrue(r.process(touch(0.99,0.8,2),time: 0.1,preferences: p).isEmpty)
        r.reset()
        XCTAssertTrue(r.process(touch(.nan,0.5),time: 0,preferences: p).isEmpty)
    }
}
