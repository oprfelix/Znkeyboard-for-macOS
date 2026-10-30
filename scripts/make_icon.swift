// Draws the app icon and writes Resources/AppIcon.icns: the menu bar icon's speech bubble and
// sparkle, white on the ink-blue of ZnKeyboard's language chip, on a macOS rounded square.
//
// Usage: swift scripts/make_icon.swift   (run from the repository root)
import AppKit

let canvas: CGFloat = 1024

func drawIcon() {
    // macOS icon grid: an 824 pt rounded square centred on the 1024 canvas.
    let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor(red: 0.14, green: 0.25, blue: 0.50, alpha: 1).setFill()
    platePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [
        NSColor(red: 0.27, green: 0.45, blue: 0.86, alpha: 1),
        NSColor(red: 0.12, green: 0.23, blue: 0.52, alpha: 1),
    ])!.draw(in: platePath, angle: -90)

    // A soft sheen across the top half.
    NSGraphicsContext.saveGraphicsState()
    platePath.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: plate.minX, y: plate.midY, width: plate.width, height: plate.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // White speech bubble with its tail at the lower left.
    let body = NSRect(x: 232, y: 352, width: 560, height: 420)
    let bubble = NSBezierPath(roundedRect: body, xRadius: 130, yRadius: 130)
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: 318, y: 372))
    tail.line(to: NSPoint(x: 276, y: 236))
    tail.line(to: NSPoint(x: 462, y: 368))
    tail.close()
    bubble.append(tail)

    NSGraphicsContext.saveGraphicsState()
    let bubbleShadow = NSShadow()
    bubbleShadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    bubbleShadow.shadowBlurRadius = 18
    bubbleShadow.shadowOffset = NSSize(width: 0, height: -8)
    bubbleShadow.set()
    NSColor.white.setFill()
    bubble.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Sparkles in the plate's blue.
    NSGradient(colors: [
        NSColor(red: 0.27, green: 0.45, blue: 0.86, alpha: 1),
        NSColor(red: 0.14, green: 0.27, blue: 0.60, alpha: 1),
    ])!.draw(in: sparkle(center: NSPoint(x: 494, y: 562), radius: 150, waist: 34), angle: -90)
    NSColor(red: 0.27, green: 0.45, blue: 0.86, alpha: 1).setFill()
    sparkle(center: NSPoint(x: 668, y: 680), radius: 58, waist: 14).fill()
}

/// A four-point star pinched to [waist] between its points, as in the menu bar icon.
func sparkle(center: NSPoint, radius: CGFloat, waist: CGFloat) -> NSBezierPath {
    let tips = [NSPoint(x: 0, y: radius), NSPoint(x: radius, y: 0), NSPoint(x: 0, y: -radius), NSPoint(x: -radius, y: 0)]
    let path = NSBezierPath()
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

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: canvas, height: canvas)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try! png(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try! png(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try! png(size: 1024).write(to: URL(fileURLWithPath: "Resources/AppIcon-1024.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
