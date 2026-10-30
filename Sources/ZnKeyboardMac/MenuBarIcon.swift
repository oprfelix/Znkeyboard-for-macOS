import AppKit

/// The menu bar icon: a rounded speech bubble with a four-point sparkle inside, drawn as a template
/// image so macOS tints it for light, dark and highlighted menu bars. [busy] fills the bubble and
/// cuts the sparkle out of it, shown while a request is running.
enum MenuBarIcon {
    static func image(busy: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let bubble = NSBezierPath()
            // Body: a rounded rectangle; tail at the lower left.
            let body = NSRect(x: 1.75, y: 4.25, width: 14.5, height: 11.5)
            bubble.appendRoundedRect(body, xRadius: 4, yRadius: 4)
            let tail = NSBezierPath()
            tail.move(to: NSPoint(x: 4.2, y: 4.6))
            tail.line(to: NSPoint(x: 3.2, y: 1.6))
            tail.line(to: NSPoint(x: 7.6, y: 4.6))
            tail.close()

            let sparkle = Self.sparkle(center: NSPoint(x: 9, y: 10), radius: 4.1, waist: 0.95)
            let small = Self.sparkle(center: NSPoint(x: 12.9, y: 13.0), radius: 1.6, waist: 0.4)

            NSColor.black.set()
            if busy {
                bubble.fill()
                tail.fill()
                // Punch the sparkles out of the filled bubble.
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                sparkle.fill()
                small.fill()
            } else {
                bubble.lineWidth = 1.5
                bubble.stroke()
                tail.fill()
                // Close the gap where the tail meets the outline.
                NSBezierPath(rect: NSRect(x: 4.0, y: 3.6, width: 3.4, height: 1.4)).fill()
                sparkle.fill()
                small.fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "ZnKeyboard"
        return image
    }

    /// A four-point star: long points up, down, left and right, pinched to [waist] between them.
    private static func sparkle(center: NSPoint, radius: CGFloat, waist: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let tips = [NSPoint(x: 0, y: radius), NSPoint(x: radius, y: 0), NSPoint(x: 0, y: -radius), NSPoint(x: -radius, y: 0)]
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
