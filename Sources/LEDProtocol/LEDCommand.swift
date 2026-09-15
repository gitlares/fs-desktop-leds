import Foundation

public enum LEDProfile: String, CaseIterable {
    case standard, alternate
}

/// Wire formats referenced in dave-code-ruiz/elkbledom. See THIRD_PARTY_NOTICES.md.
public enum LEDCommand: Equatable {
    case power(Bool)
    case color(UInt8, UInt8, UInt8)
    case brightness(Int)

    public var channel: Int {
        switch self { case .power: return 0; case .color: return 1; case .brightness: return 2 }
    }

    public func packet(profile: LEDProfile = .standard) -> Data {
        let alternate = profile == .alternate
        switch self {
        case .power(let on):
            return Data([0x7e, alternate ? 4 : 0, 4, on ? 0xf0 : 0, 0, on ? 1 : 0, 0xff, 0, 0xef])
        case .color(let red, let green, let blue):
            return Data([0x7e, alternate ? 7 : 0, 5, 3, red, green, blue, alternate ? 10 : 0, 0xef])
        case .brightness(let percent):
            let value = UInt8(min(100, max(0, percent)))
            return alternate
                ? Data([0x7e, 4, 1, value, 1, 0xff, 2, 1, 0xef])
                : Data([0x7e, 0, 1, value, 0xff, 0, 0xff, 0, 0xef])
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
