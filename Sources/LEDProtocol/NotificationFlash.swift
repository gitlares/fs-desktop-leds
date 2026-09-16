import Foundation

public enum NotificationFlash {
    /// Three short pulses, followed by restoration by the output coordinator.
    public static func color(elapsed: Double) -> AmbientRGB? {
        guard elapsed >= 0, elapsed < 1.8 else { return nil }
        let phase = Int(elapsed / 0.3)
        guard phase % 2 == 0 else { return AmbientRGB(hex: 0) }
        return AmbientRGB(hex: [0xFF0000, 0x00FF00, 0x0000FF][phase / 2])
    }
}
