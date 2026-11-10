import XCTest
@testable import ClickPlus

final class GalaxyBudsBatteryTests: XCTestCase {
    // Captured locally from the connected Galaxy Buds2, 10/11/2026.
    private let capture: [UInt8] = [0xfd,0x2a,0x08,0x61,0x0b,0x03,0x64,0x64,0x01,0x01,0x22,0x00,0x01,0x03,0xbf,0x22,0x00,0x00,0x3a,0x01,0x3a,0x01,0x08,0x00,0x03,0x66,0x01,0x01,0x00,0x10,0x00,0x00,0x00,0x00,0x11,0x02,0x01,0x00,0x00,0x01,0x40,0x00,0x00,0x99,0x63,0xdd]

    private func frame(id: UInt8 = 0x60, payload: [UInt8]) -> [UInt8] {
        let body = [id] + payload
        let crc = GalaxyBudsBatteryParser.checksum(body)
        return [0xfd, UInt8(body.count + 2), 0] + body + [UInt8(crc & 0xff), UInt8(crc >> 8), 0xdd]
    }

    func testActualBuds2CaptureHasTwoIndependentLevels() throws {
        var parser = GalaxyBudsBatteryParser()
        let levels = try XCTUnwrap(parser.receive(capture))
        XCTAssertEqual(levels.map(\.label), ["Esquerdo", "Direito"])
        XCTAssertEqual(levels.map(\.percent), [100, 100])
    }
    func testFragmentedTransportAndCombinedFrames() throws {
        for split in 1..<capture.count {
            var parser = GalaxyBudsBatteryParser()
            XCTAssertNil(parser.receive(Array(capture.prefix(split))))
            XCTAssertEqual(parser.receive(Array(capture.dropFirst(split)))?.map(\.percent), [100,100])
        }
        var parser = GalaxyBudsBatteryParser()
        XCTAssertEqual(parser.receive([1,2,3] + frame(id: 0x42,payload: [1]) + capture)?.map(\.percent), [100,100])
    }
    func testChecksumAndTruncatedPayloadRejected() {
        var parser = GalaxyBudsBatteryParser()
        var invalid = capture; invalid[7] = 99
        XCTAssertNil(parser.receive(invalid))
        XCTAssertNil(parser.receive(frame(payload: [1,20])))
        XCTAssertEqual(parser.receive(capture)?.count, 2)
    }
    func testIndependentLevelsAndUnavailableCase() {
        var parser = GalaxyBudsBatteryParser()
        XCTAssertEqual(parser.receive(frame(payload: [1,0,78,1,1,0x22,65]))?.map(\.percent), [0,78,65])
        XCTAssertEqual(parser.receive(frame(payload: [1,25,255,1,1,0x22,255]))?.map(\.percent), [25])
    }
    func testCaseUpdateAfterInitialStatusInSameCallback() throws {
        var parser = GalaxyBudsBatteryParser()
        let caseUpdate = frame(payload: [1,98,100,1,1,0x22,76])
        XCTAssertEqual(parser.receive(capture + caseUpdate)?.map(\.label), ["Esquerdo", "Direito"])
        let later = try XCTUnwrap(parser.receive([]))
        XCTAssertEqual(later.map(\.label), ["Esquerdo", "Direito", "Estojo"])
        XCTAssertEqual(later.map(\.percent), [98,100,76])
    }
    func testUnknownCaseDoesNotBecomeAnEmptyBatteryWarning() throws {
        for value: UInt8 in [0,101,255] {
            var parser = GalaxyBudsBatteryParser()
            let levels = try XCTUnwrap(parser.receive(frame(payload: [1,95,96,1,1,0x22,value])))
            XCTAssertFalse(levels.contains { $0.id == "device_batteryLevelCase" })
            let device = BluetoothBattery(id: "test", name: "Galaxy Buds2", kind: "Headset", levels: levels)
            XCTAssertTrue(device.caseBatteryUnavailable)
        }
    }
    func testActualBuds2CaptureIncludesCaseBattery() throws {
        var parser = GalaxyBudsBatteryParser()
        let captured: [UInt8] = [0xfd,0x2a,0x08,0x61,0x0b,0x03,0x62,0x63,0x01,0x01,0x33,0x63,0x01,0x03,0xbf,0x22,0x00,0x00,0x3a,0x01,0x3a,0x01,0x08,0x00,0x03,0x66,0x01,0x01,0x00,0x10,0x00,0x00,0x00,0x00,0x11,0x02,0x01,0x00,0x00,0x01,0x54,0x00,0x00,0x07,0xbb,0xdd]
        let levels = try XCTUnwrap(parser.receive(captured))
        XCTAssertEqual(levels.map(\.label), ["Esquerdo", "Direito", "Estojo"])
        XCTAssertEqual(levels.map(\.percent), [98,99,99])
    }
    func testModelScope() {
        XCTAssertTrue(GalaxyBudsBatteryParser.supports("Galaxy Buds 2 de Alison"))
        XCTAssertTrue(GalaxyBudsBatteryParser.supports("Galaxy Buds2"))
        XCTAssertFalse(GalaxyBudsBatteryParser.supports("Galaxy Buds2 Pro"))
        XCTAssertFalse(GalaxyBudsBatteryParser.supports("Other headset"))
    }
}
