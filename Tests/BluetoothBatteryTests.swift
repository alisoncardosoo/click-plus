import XCTest
@testable import ClickPlus

final class BluetoothBatteryTests: XCTestCase {
    func testOnlyConnectedDevicesAndSeparateBudLevels() throws {
        let data = Data(#"""
        {"SPBluetoothDataType":[{
          "device_connected":[
            {"Galaxy Buds2":{"device_address":"AA-BB", "device_minorType":"Headset", "device_batteryLevelLeft":"80%", "device_batteryLevelRight":"0%", "device_batteryLevelCase":"42%"}},
            {"Speaker":{"device_address":"CC:DD", "device_minorType":"Speaker"}},
            {"Logi K950":{"device_address":"EE:FF", "device_minorType":"Keyboard", "device_vendorID":"0x046D", "device_batteryLevelMain":"100%"}}
          ],
          "device_not_connected":[{"Old headphones":{"device_address":"00:11","device_batteryLevelMain":"90%"}}]
        }]}
        """#.utf8)
        let devices = try BluetoothBatteryService.parse(data)
        XCTAssertEqual(devices.map(\.name), ["Galaxy Buds2", "Speaker"])
        XCTAssertEqual(devices[0].id, "aa:bb")
        XCTAssertEqual(devices[0].levels.map(\.percent), [80, 0, 42])
        XCTAssertEqual(devices[0].levels.map(\.label), ["Esquerdo", "Direito", "Estojo"])
        XCTAssertEqual(devices[1].summary, "Bateria não informada")
    }

    func testRejectInvalidPercentages() {
        for value: Any in [true, -1, 101, 12.5, "101%", "-1%", "nan", "80%%", "", NSNull()] {
            XCTAssertNil(BluetoothBatteryService.percent(value), "\(value)")
        }
        XCTAssertEqual(BluetoothBatteryService.percent(" 100% "), 100)
        XCTAssertEqual(BluetoothBatteryService.percent(0), 0)
    }

    func testDeduplicatesByAddressAndAllowsOtherBrandsOfMouse() throws {
        let data = Data(#"{"SPBluetoothDataType":[{"device_connected":[{"Mouse":{"device_address":"AA:BB","device_minorType":"Mouse","device_batteryLevelMain":"53%"}},{"Mouse":{"device_address":"aa:bb","device_minorType":"Mouse","device_batteryLevelMain":"53%"}}]}]}"#.utf8)
        let devices = try BluetoothBatteryService.parse(data)
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices.first?.levels.first?.percent, 53)
    }

    func testBluetoothOffAndInvalidReport() throws {
        XCTAssertTrue(try BluetoothBatteryService.parse(Data(#"{"SPBluetoothDataType":[{}]}"#.utf8)).isEmpty)
        XCTAssertThrowsError(try BluetoothBatteryService.parse(Data("{}".utf8)))
    }
}

final class CaseBatteryHistoryTests: XCTestCase {
    private func device(_ id: String = "buds-a", casePercent: Int? = nil) -> BluetoothBattery {
        var levels: [BluetoothBattery.Level] = [.init(id: "device_batteryLevelLeft", label: "Esquerdo", percent: 90)]
        if let casePercent { levels.append(.init(id: "device_batteryLevelCase", label: "Estojo", percent: casePercent)) }
        return .init(id: id, name: "Galaxy Buds2", kind: "Headset", levels: levels)
    }

    func testClosedCaseKeepsLastRealReadingAndTimestamp() throws {
        var history = CaseBatteryHistory()
        let time = Date(timeIntervalSince1970: 1000)
        let fresh = history.apply(to: device(casePercent: 99), now: time)
        XCTAssertNil(fresh.levels.last?.lastKnownAt)
        let closed = history.apply(to: device(), now: time.addingTimeInterval(60))
        XCTAssertEqual(closed.levels.last?.percent, 99)
        XCTAssertEqual(closed.levels.last?.lastKnownAt, time)
        XCTAssertFalse(closed.caseBatteryUnavailable)
        // A refresh must not make an old measurement look new.
        XCTAssertEqual(history.apply(to: closed, now: time.addingTimeInterval(120)).levels.last?.lastKnownAt, time)
    }

    func testNewCaseReadingReplacesHistoryAndClearsHistoricalLabel() {
        var history = CaseBatteryHistory()
        _ = history.apply(to: device(casePercent: 99), now: Date(timeIntervalSince1970: 1000))
        let newer = Date(timeIntervalSince1970: 2000)
        let fresh = history.apply(to: device(casePercent: 75), now: newer)
        XCTAssertNil(fresh.levels.last?.lastKnownAt)
        let closed = history.apply(to: device())
        XCTAssertEqual(closed.levels.last?.percent, 75)
        XCTAssertEqual(closed.levels.last?.lastKnownAt, newer)
    }

    func testUnknownAndDifferentCasesNeverInventOrShareBattery() {
        var history = CaseBatteryHistory()
        XCTAssertTrue(history.apply(to: device()).caseBatteryUnavailable)
        _ = history.apply(to: device(casePercent: 99))
        XCTAssertTrue(history.apply(to: device("buds-b")).caseBatteryUnavailable)
        XCTAssertEqual(history.apply(to: device(casePercent: 0)).levels.last?.percent, 99)
    }
}
