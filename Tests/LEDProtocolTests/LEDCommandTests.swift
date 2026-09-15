import XCTest
@testable import LEDProtocol

final class LEDCommandTests: XCTestCase {
    func testStandardWireCommands() {
        let driver = ELKBLEDOMDriver()
        XCTAssertEqual(Array(driver.packet(for: .power(true))), [0x7e, 0, 4, 0xf0, 0, 1, 0xff, 0, 0xef])
        XCTAssertEqual(Array(driver.packet(for: .power(false))), [0x7e, 0, 4, 0, 0, 0, 0xff, 0, 0xef])
        XCTAssertEqual(Array(driver.packet(for: .color(255, 128, 0))), [0x7e, 0, 5, 3, 255, 128, 0, 0, 0xef])
        XCTAssertEqual(Array(driver.packet(for: .brightness(50))), [0x7e, 0, 1, 50, 255, 0, 255, 0, 0xef])
    }

    func testAlternateWireCommands() {
        let driver = ELKBLEDOMDriver(variant: .alternate)
        XCTAssertEqual(Array(driver.packet(for: .color(1, 2, 3))), [0x7e, 7, 5, 3, 1, 2, 3, 10, 0xef])
        XCTAssertEqual(Array(driver.packet(for: .power(true))), [0x7e, 4, 4, 240, 0, 1, 255, 0, 0xef])
        XCTAssertEqual(Array(driver.packet(for: .brightness(50))), [0x7e, 4, 1, 50, 1, 255, 2, 1, 0xef])
    }

    func testAlternateProfileUsesTheDocumentedELKBLEDOMFrames() {
        let driver = ELKBLEDOMDriver(variant: .alternate)
        XCTAssertEqual(Array(driver.packet(for: .power(true))), [0x7e, 0x04, 0x04, 0xf0, 0, 1, 0xff, 0, 0xef])
        XCTAssertEqual(Array(driver.packet(for: .color(255, 0, 0))), [0x7e, 0x07, 0x05, 0x03, 255, 0, 0, 0x0a, 0xef])
        XCTAssertEqual(Array(driver.packet(for: .brightness(50))), [0x7e, 0x04, 0x01, 50, 1, 0xff, 2, 1, 0xef])
    }

    func testBrightnessClampsInsteadOfOverflowing() {
        let driver = ELKBLEDOMDriver()
        XCTAssertEqual(driver.packet(for: .brightness(-10))[3], 0)
        XCTAssertEqual(driver.packet(for: .brightness(1000))[3], 100)
    }

    func testCatalogDetectsOnlyCompatibleLight() {
        XCTAssertNotNil(DriverCatalog.shared.driver(forAdvertisedName: "ELK-BLEDOM"))
        XCTAssertNil(DriverCatalog.shared.driver(forAdvertisedName: "MELK-OA10"))
    }

    func testRapidChangesStayBoundedAndKeepLatestValue() {
        var queue = CommandBuffer()
        queue.append(.power(true))
        for value in 0...255 {
            queue.append(.color(UInt8(value), 0, 0))
            queue.append(.brightness(value))
        }
        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(queue.pop(), .power(true))
        XCTAssertEqual(queue.pop(), .color(255, 0, 0))
        XCTAssertEqual(queue.pop(), .brightness(255))
        XCTAssertNil(queue.pop())
    }

    func testPowerOffDropsPendingColorAndBrightness() {
        var queue = CommandBuffer()
        queue.append(.color(255, 0, 0))
        queue.append(.brightness(100))
        queue.append(.power(false))
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.pop(), .power(false))
        queue.append(.power(true))
        queue.clear()
        XCTAssertTrue(queue.isEmpty)
    }

    func testAmbientMixerWeightsDisplaysByAreaAndSmoothsTransitions() {
        var mixer = AmbientColorMixer(smoothing: 0.5)
        let first = mixer.mix([
            DisplayColorSample(color: AmbientRGB(red: 255, green: 0, blue: 0), weight: 3),
            DisplayColorSample(color: AmbientRGB(red: 0, green: 0, blue: 255), weight: 1)
        ])
        XCTAssertEqual(first, AmbientRGB(red: 191, green: 0, blue: 64))

        let second = mixer.mix([DisplayColorSample(color: AmbientRGB(red: 0, green: 255, blue: 0), weight: 1)])
        XCTAssertEqual(second, AmbientRGB(red: 96, green: 128, blue: 32))

        let third = mixer.mix([DisplayColorSample(color: AmbientRGB(red: 0, green: 255, blue: 0), weight: 1)])
        XCTAssertEqual(third, AmbientRGB(red: 48, green: 192, blue: 16))
    }
}
