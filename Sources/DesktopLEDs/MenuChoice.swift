import AppKit
import SwiftUI

/// A menu action with a persistent selection mark and optional color sample.
struct MenuChoice: View {
    let title: String
    let selected: Bool
    let hex: Int?
    let action: () -> Void

    init(_ title: String, selected: Bool, hex: Int? = nil, action: @escaping () -> Void) {
        self.title = title
        self.selected = selected
        self.hex = hex
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            if let hex {
                Label {
                    Text(selected ? "\(title)  ✓" : title)
                } icon: {
                    Image(nsImage: ColorSwatch.image(hex: hex)).renderingMode(.original)
                }
            } else {
                Text(selected ? "\(title)  ✓" : title)
            }
        }
    }
}

@MainActor
private enum ColorSwatch {
    private static var cache: [Int: NSImage] = [:]

    static func image(hex: Int) -> NSImage {
        if let image = cache[hex] { return image }
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            let circle = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 12, height: 12))
            NSColor(
                srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255,
                alpha: 1
            ).setFill()
            circle.fill()
            NSColor.black.withAlphaComponent(0.2).setStroke()
            circle.lineWidth = 0.5
            circle.stroke()
            return true
        }
        image.isTemplate = false
        cache[hex] = image
        return image
    }
}
