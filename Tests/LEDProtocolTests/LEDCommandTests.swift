import XCTest
@testable import LEDProtocol

final class LEDCommandTests: XCTestCase {
    func testStandardWireCommands() {
        XCTAssertEqual(Array(LEDCommand.power(true).packet()), [0x7e, 0, 4, 0xf0, 0, 1, 0xff, 0, 0xef])
        XCTAssertEqual(Array(LEDCommand.power(false).packet()), [0x7e, 0, 4, 0, 0, 0, 0xff, 0, 0xef])
        XCTAssertEqual(Array(LEDCommand.color(255, 128, 0).packet()), [0x7e, 0, 5, 3, 255, 128, 0, 0, 0xef])
        XCTAssertEqual(Array(LEDCommand.brightness(50).packet()), [0x7e, 0, 1, 50, 255, 0, 255, 0, 0xef])
    }

    func testAlternateWireCommands() {
        XCTAssertEqual(Array(LEDCommand.color(1, 2, 3).packet(profile: .alternate)), [0x7e, 7, 5, 3, 1, 2, 3, 10, 0xef])
        XCTAssertEqual(Array(LEDCommand.power(true).packet(profile: .alternate)), [0x7e, 4, 4, 240, 0, 1, 255, 0, 0xef])
        XCTAssertEqual(Array(LEDCommand.brightness(50).packet(profile: .alternate)), [0x7e, 4, 1, 50, 1, 255, 2, 1, 0xef])
    }

    func testBrightnessClampsInsteadOfOverflowing() {
        XCTAssertEqual(LEDCommand.brightness(-10).packet()[3], 0)
        XCTAssertEqual(LEDCommand.brightness(1000).packet()[3], 100)
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
}
