import Foundation

public struct AmbientRGB: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public var command: LEDCommand { .color(red, green, blue) }
}

public struct DisplayColorSample: Equatable, Sendable {
    public let color: AmbientRGB
    public let weight: Double

    public init(color: AmbientRGB, weight: Double) {
        self.color = color
        self.weight = max(0, weight)
    }
}

/// Combines all active displays and softens rapid scene transitions.
/// The capture implementation stays outside this type so it remains portable.
public struct AmbientColorMixer: Sendable {
    private let smoothing: Double
    private var previous: AmbientRGB?

    public init(smoothing: Double = 0.35) {
        self.smoothing = min(1, max(0, smoothing))
    }

    public mutating func mix(_ samples: [DisplayColorSample]) -> AmbientRGB? {
        let totalWeight = samples.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }

        let red = samples.reduce(0.0) { $0 + Double($1.color.red) * $1.weight } / totalWeight
        let green = samples.reduce(0.0) { $0 + Double($1.color.green) * $1.weight } / totalWeight
        let blue = samples.reduce(0.0) { $0 + Double($1.color.blue) * $1.weight } / totalWeight
        let raw = AmbientRGB(red: UInt8(red.rounded()), green: UInt8(green.rounded()), blue: UInt8(blue.rounded()))
        defer { previous = raw }
        guard let previous else { return raw }
        func blend(_ from: UInt8, _ to: UInt8) -> UInt8 {
            UInt8((Double(from) + (Double(to) - Double(from)) * smoothing).rounded())
        }
        return AmbientRGB(red: blend(previous.red, raw.red), green: blend(previous.green, raw.green), blue: blend(previous.blue, raw.blue))
    }

    public mutating func reset() { previous = nil }
}
