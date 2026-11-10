import XCTest
@testable import ClickPlus

final class BatteryAlertTests: XCTestCase {
    private var preferences: BatteryAlertPreferences {
        var value = BatteryAlertPreferences(); value.enabled = true; return value
    }
    private func reading(_ percent: Int, id: String = "mouse") -> BatteryReading {
        .init(id: id, name: "Mouse", percent: percent)
    }
    func testThresholdsAndNoRepeatedWarnings() {
        var history = BatteryAlertHistory()
        XCTAssertNil(history.threshold(for: reading(21), preferences: preferences))
        XCTAssertEqual(history.threshold(for: reading(20), preferences: preferences), 20)
        history.record(reading(20), threshold: 20, preferences: preferences)
        XCTAssertNil(history.threshold(for: reading(19), preferences: preferences))
        XCTAssertEqual(history.threshold(for: reading(4), preferences: preferences), 5)
        history.record(reading(4), threshold: 5, preferences: preferences)
        XCTAssertNil(history.threshold(for: reading(3), preferences: preferences))
        XCTAssertNil(history.threshold(for: reading(10), preferences: preferences))
    }
    func testFirstCriticalReadingOnlyWarnsOnceAndDevicesAreIndependent() {
        var history = BatteryAlertHistory()
        XCTAssertEqual(history.threshold(for: reading(2), preferences: preferences), 5)
        history.record(reading(2), threshold: 5, preferences: preferences)
        XCTAssertNil(history.threshold(for: reading(12), preferences: preferences))
        XCTAssertEqual(history.threshold(for: reading(12, id: "keyboard"), preferences: preferences), 20)
    }
    func testRechargeRequiresMarginAndHistorySurvivesRestart() throws {
        var history = BatteryAlertHistory()
        history.record(reading(20), threshold: 20, preferences: preferences)
        history = try JSONDecoder().decode(BatteryAlertHistory.self, from: JSONEncoder().encode(history))
        XCTAssertNil(history.threshold(for: reading(22), preferences: preferences))
        XCTAssertNil(history.threshold(for: reading(20), preferences: preferences))
        XCTAssertNil(history.threshold(for: reading(60), preferences: preferences))
        XCTAssertEqual(history.threshold(for: reading(18), preferences: preferences), 20)
    }
    func testDisabledUnknownAndCustomLimits() {
        var history = BatteryAlertHistory()
        XCTAssertNil(history.threshold(for: reading(3), preferences: BatteryAlertPreferences()))
        XCTAssertNil(history.threshold(for: reading(-1), preferences: preferences))
        XCTAssertNil(history.threshold(for: reading(101), preferences: preferences))
        var custom = preferences; custom.low = 30; custom.critical = 10
        XCTAssertEqual(history.threshold(for: reading(25), preferences: custom), 30)
        XCTAssertEqual(history.threshold(for: reading(8), preferences: custom), 10)
        custom.low = -2; custom.critical = 200
        XCTAssertEqual(custom.normalized.low, 2)
        XCTAssertEqual(custom.normalized.critical, 1)
    }
}
