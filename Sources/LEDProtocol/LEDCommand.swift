import Foundation

public enum LEDCommand: Equatable {
    case power(Bool)
    case color(UInt8, UInt8, UInt8)
    case brightness(Int)

    public var channel: Int {
        switch self { case .power: return 0; case .color: return 1; case .brightness: return 2 }
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
