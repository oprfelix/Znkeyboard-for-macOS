import AppKit

/// The menu bar icon: the app icon's two cards in one colour. The front card is solid with its
/// sparkle cut out and its right edge on a slant; the back card peeks out at the lower right.
/// Drawn as a template image so macOS tints it for light, dark and highlighted menu bars.
/// [busy] fills the back card in, shown while a request is running.
enum MenuBarIcon {
    static func image(busy: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let context = NSGraphicsContext.current
            NSColor.black.set()

            let back = NSBezierPath(roundedRect: NSRect(x: 8.2, y: 5.2, width: 8.3, height: 11.3), xRadius: 2.2, yRadius: 2.2)
            if busy {
                back.fill()
            } else {
                back.lineWidth = 1.4
                back.stroke()
            }

            // Clear a gap around the front card so the two read as separate cards.
            context?.compositingOperation = .clear
            NSGraphicsContext.saveGraphicsState()
            slant(offset: 1.3).addClip()
            NSBezierPath(roundedRect: NSRect(x: 0.2, y: 0.2, width: 12.6, height: 13.6), xRadius: 3.4, yRadius: 3.4).fill()
            NSGraphicsContext.restoreGraphicsState()

            context?.compositingOperation = .sourceOver
            NSGraphicsContext.saveGraphicsState()
            slant(offset: 0).addClip()
            NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 10.5, height: 11), xRadius: 2.4, yRadius: 2.4).fill()
            NSGraphicsContext.restoreGraphicsState()

            // The sparkle is cut out of the front card.
            context?.compositingOperation = .clear
            sparkle(center: NSPoint(x: 5.5, y: 7.1), radius: 3.6, waist: 0.75).fill()
            context?.compositingOperation = .sourceOver
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "ZnKeyboard"
        return image
    }

    /// Everything left of the front card's slanted right edge, pushed right by [offset].
    private static func slant(offset: CGFloat) -> NSBezierPath {
        let top = NSPoint(x: 8.4 + offset, y: 1.5), bottom = NSPoint(x: 11.9 + offset, y: 12.5)
        let dx = (bottom.x - top.x) / (bottom.y - top.y)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: -2, y: -2))
        path.line(to: NSPoint(x: top.x - dx * (top.y + 2), y: -2))
        path.line(to: NSPoint(x: top.x + dx * (20 - top.y), y: 20))
        path.line(to: NSPoint(x: -2, y: 20))
        path.close()
        return path
    }

    /// A four-point star pinched to [waist] between its points, as in the app icon.
    private static func sparkle(center: NSPoint, radius: CGFloat, waist: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let tips = [NSPoint(x: 0, y: -radius), NSPoint(x: radius, y: 0), NSPoint(x: 0, y: radius), NSPoint(x: -radius, y: 0)]
        path.move(to: NSPoint(x: center.x + tips[0].x, y: center.y + tips[0].y))
        for index in 0..<4 {
            let tip = tips[(index + 1) % 4]
            let control = NSPoint(
                x: center.x + (tips[index].x + tip.x) * waist / radius * 0.5,
                y: center.y + (tips[index].y + tip.y) * waist / radius * 0.5
            )
            path.curve(to: NSPoint(x: center.x + tip.x, y: center.y + tip.y), controlPoint1: control, controlPoint2: control)
        }
        path.close()
        return path
    }
}
