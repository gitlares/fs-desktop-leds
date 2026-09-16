import Foundation

public enum LEDCommand: Equatable {
    case power(Bool)
    case color(UInt8, UInt8, UInt8)
    case brightness(Int)
    case effect(LEDEffect)
    case effectSpeed(Int)

    public var channel: Int {
        switch self {
        case .power: return 0
        case .color: return 1
        case .brightness: return 2
        case .effect: return 1
        case .effectSpeed: return 3
        }
    }

}

/// A bounded queue: replace stale slider values, never replay a backlog.
public struct CommandBuffer {
    private var commands: [LEDCommand] = []
    public init() {}
    public var isEmpty: Bool { commands.isEmpty }
    public var count: Int { commands.count }
    public mutating func append(_ command: LEDCommand) {
        if case .power(false) = command { commands.removeAll() }
        commands.removeAll { $0.channel == command.channel }
        commands.append(command)
    }
    public mutating func pop() -> LEDCommand? {
        commands.isEmpty ? nil : commands.removeFirst()
    }
    public mutating func clear() { commands.removeAll() }
}

/// Conservative, documented built-in effects; no strobe or unknown opcodes.
public enum LEDEffect: UInt8, CaseIterable, Identifiable, Sendable {
    case redFade = 139
    case rgbFade = 137
    case rainbowFade = 138
    public var id: UInt8 { rawValue }
    public var title: String {
        switch self {
        case .redFade: return L("Red fade", "Fundido rojo")
        case .rgbFade: return L("RGB fade", "Fundido RGB")
        case .rainbowFade: return L("Seven-color fade", "Fundido de siete colores")
        }
    }
}
