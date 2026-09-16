import Foundation

/// A driver owns all controller-specific knowledge. Bluetooth transport only
/// discovers services and writes the packets supplied by a selected driver.
public protocol LightDriver: Sendable {
    var id: String { get }
    var displayName: String { get }
    var writeCharacteristicUUID: UUID { get }
    var diagnosticEffects: [LEDEffect] { get }

    /// Determines whether an advertised name is a candidate for this driver.
    func matches(advertisedName: String) -> Bool

    /// Encodes an app-level command for the device's BLE protocol.
    func packet(for command: LEDCommand) -> Data
}

extension LightDriver {
    public var diagnosticEffects: [LEDEffect] { [] }
}

public enum ELKBLEDOMVariant: String, CaseIterable, Sendable {
    case standard
    case alternate
}

/// ELK-BLEDOM formats referenced in dave-code-ruiz/elkbledom.
/// See THIRD_PARTY_NOTICES.md for attribution and license.
public struct ELKBLEDOMDriver: LightDriver, Sendable {
    public let variant: ELKBLEDOMVariant

    public init(variant: ELKBLEDOMVariant = .standard) {
        self.variant = variant
    }

    public var diagnosticEffects: [LEDEffect] { LEDEffect.allCases }
    public var id: String { "elk-bledom.\(variant.rawValue)" }
    public var displayName: String { "ELK-BLEDOM" }
    public var writeCharacteristicUUID: UUID { UUID(uuidString: "0000FFF3-0000-1000-8000-00805F9B34FB")! }

    public func matches(advertisedName: String) -> Bool {
        advertisedName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() == "ELK-BLEDOM"
    }

    public func packet(for command: LEDCommand) -> Data {
        let alternate = variant == .alternate
        switch command {
        case .power(let on):
            return Data([0x7e, alternate ? 4 : 0, 4, on ? 0xf0 : 0, 0, on ? 1 : 0, 0xff, 0, 0xef])
        case .color(let red, let green, let blue):
            return Data([0x7e, alternate ? 7 : 0, 5, 3, red, green, blue, alternate ? 10 : 0, 0xef])
        case .effect(let effect):
            return Data([
                0x7e, alternate ? 7 : 0, 3, effect.rawValue, 3, alternate ? 255 : 0, alternate ? 255 : 0, 0,
                0xef,
            ])
        case .effectSpeed(let percent):
            return Data([0x7e, alternate ? 7 : 0, 2, UInt8(min(100, max(0, percent))), 0, 0, 0, 0, 0xef])
        case .brightness(let percent):
            let value = UInt8(min(100, max(0, percent)))
            return alternate
                ? Data([0x7e, 4, 1, value, 1, 0xff, 2, 1, 0xef])
                : Data([0x7e, 0, 1, value, 0xff, 0, 0xff, 0, 0xef])
        }
    }
}

/// Register each supported controller family here. Adding one does not change
/// SwiftUI or the CoreBluetooth connection lifecycle.
public struct DriverCatalog: Sendable {
    public static let shared = DriverCatalog()
    private let detectorDrivers: [any LightDriver] = [ELKBLEDOMDriver()]

    public init() {}

    public func driver(forAdvertisedName name: String) -> (any LightDriver)? {
        detectorDrivers.first { $0.matches(advertisedName: name) }
    }
}
