// ZnKeyboard's icon for every platform, drawn from one design: a bright front card with a
// sparkle, its right edge cut on a slant, over a pale back card with 文, and a folded corner
// where they meet.
//
// Usage (from the repository root): swift scripts/make_icon.swift [export-dir]
//   Always writes Resources/AppIcon.icns and Resources/AppIcon-1024.png for macOS.
//   With export-dir, also writes the files the Windows and Android projects copy in:
//   windows/AppIcon.ico, windows/TrayIcon.ico, android/mipmap-*/ic_launcher_foreground.png and
//   android/mipmap-*/ic_launcher_monochrome.png.
import AppKit

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

/// A four-point star pinched to [waist] between its points.
func sparkle(center: NSPoint, radius: CGFloat, waist: CGFloat) -> NSBezierPath {
    let tips = [NSPoint(x: 0, y: -radius), NSPoint(x: radius, y: 0), NSPoint(x: 0, y: radius), NSPoint(x: -radius, y: 0)]
    let path = NSBezierPath()
    path.move(to: NSPoint(x: center.x + tips[0].x, y: center.y + tips[0].y))
    for i in 0..<4 {
        let tip = tips[(i + 1) % 4]
        let c = NSPoint(x: center.x + (tips[i].x + tip.x) * waist / radius * 0.5, y: center.y + (tips[i].y + tip.y) * waist / radius * 0.5)
        path.curve(to: NSPoint(x: center.x + tip.x, y: center.y + tip.y), controlPoint1: c, controlPoint2: c)
    }
    path.close()
    return path
}

// Geometry on a flipped 1024 canvas (origin top-left); the artwork spans x and y 128...896.
let backRect = NSRect(x: 512, y: 290, width: 384, height: 606)
let frontRect = NSRect(x: 128, y: 128, width: 600, height: 606)
let slantTop = NSPoint(x: 465, y: 128), slantBottom = NSPoint(x: 678, y: 734)

/// Everything left of the front card's slanted right edge.
func slantClip() -> NSBezierPath {
    let dx = (slantBottom.x - slantTop.x) / (slantBottom.y - slantTop.y)
    let path = NSBezierPath()
    path.move(to: NSPoint(x: -100, y: -100))
    path.line(to: NSPoint(x: slantTop.x - dx * (slantTop.y + 100), y: -100))
    path.line(to: NSPoint(x: slantTop.x + dx * (1124 - slantTop.y), y: 1124))
    path.line(to: NSPoint(x: -100, y: 1124))
    path.close()
    return path
}

/// The full-colour icon. [detailed] adds 文, the fold, rims and the small sparkle, which blur
/// away at tray sizes.
func drawColor(detailed: Bool) {
    let back = NSBezierPath(roundedRect: backRect, xRadius: 72, yRadius: 72)
    if detailed {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = rgb(30, 70, 160, 0.16)
        shadow.shadowBlurRadius = 28
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.set()
        rgb(214, 228, 255).setFill()
        back.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGradient(starting: rgb(232, 240, 255), ending: rgb(196, 216, 255))!.draw(in: back, angle: -60)

    if detailed {
        rgb(255, 255, 255, 0.75).setStroke()
        back.lineWidth = 6
        back.stroke()
        let wen = NSFont(name: "PingFangSC-Semibold", size: 250) ?? .boldSystemFont(ofSize: 250)
        let attributes: [NSAttributedString.Key: Any] = [.font: wen, .foregroundColor: rgb(104, 150, 240)]
        let size = ("文" as NSString).size(withAttributes: attributes)
        ("文" as NSString).draw(at: NSPoint(x: 736 - size.width / 2, y: 556 - size.height / 2), withAttributes: attributes)

        let fold = NSBezierPath()
        fold.move(to: NSPoint(x: 512, y: 734))
        fold.line(to: NSPoint(x: 678, y: 734))
        fold.line(to: NSPoint(x: 530, y: 884))
        fold.close()
        NSGraphicsContext.saveGraphicsState()
        back.addClip()
        NSGradient(starting: rgb(58, 120, 255), ending: rgb(160, 196, 255))!.draw(in: fold, angle: -40)
        NSGraphicsContext.restoreGraphicsState()
    }

    let card = NSBezierPath(roundedRect: frontRect, xRadius: 76, yRadius: 76)
    NSGraphicsContext.saveGraphicsState()
    slantClip().addClip()
    NSGradient(starting: rgb(42, 112, 255), ending: rgb(118, 168, 255))!.draw(in: card, angle: -50)
    if detailed {
        rgb(255, 255, 255, 0.35).setStroke()
        card.lineWidth = 10
        card.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    if detailed {
        NSGraphicsContext.saveGraphicsState()
        card.addClip()
        let edge = NSBezierPath()
        edge.move(to: slantTop)
        edge.line(to: slantBottom)
        edge.lineWidth = 6
        rgb(255, 255, 255, 0.45).setStroke()
        edge.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    rgb(255, 255, 255, 0.95).setFill()
    if detailed {
        sparkle(center: NSPoint(x: 330, y: 431), radius: 150, waist: 30).fill()
        sparkle(center: NSPoint(x: 462, y: 290), radius: 50, waist: 11).fill()
    } else {
        sparkle(center: NSPoint(x: 318, y: 431), radius: 190, waist: 46).fill()
    }
}

/// One colour with transparency, for Android's themed icons: the front card with the sparkle cut
/// out, and the back card half strength.
func drawMonochrome() {
    NSColor.white.withAlphaComponent(0.5).setFill()
    NSBezierPath(roundedRect: backRect, xRadius: 72, yRadius: 72).fill()
    // A clear gap between the cards.
    NSGraphicsContext.current?.compositingOperation = .clear
    let gap = NSBezierPath(roundedRect: frontRect.insetBy(dx: -22, dy: -22), xRadius: 96, yRadius: 96)
    NSGraphicsContext.saveGraphicsState()
    let dx = (slantBottom.x - slantTop.x) / (slantBottom.y - slantTop.y)
    let shifted = NSBezierPath()
    shifted.move(to: NSPoint(x: -100, y: -100))
    shifted.line(to: NSPoint(x: slantTop.x + 24 - dx * (slantTop.y + 100), y: -100))
    shifted.line(to: NSPoint(x: slantTop.x + 24 + dx * (1124 - slantTop.y), y: 1124))
    shifted.line(to: NSPoint(x: -100, y: 1124))
    shifted.close()
    shifted.addClip()
    gap.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.current?.compositingOperation = .sourceOver
    NSGraphicsContext.saveGraphicsState()
    slantClip().addClip()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: frontRect, xRadius: 76, yRadius: 76).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.current?.compositingOperation = .clear
    sparkle(center: NSPoint(x: 330, y: 431), radius: 150, waist: 30).fill()
    sparkle(center: NSPoint(x: 462, y: 290), radius: 50, waist: 11).fill()
    NSGraphicsContext.current?.compositingOperation = .sourceOver
}

/// [draw] on a [pixels]-square bitmap; the 1024 design is scaled by [scale] about the centre
/// (Android's adaptive layer keeps the artwork inside its safe zone).
func png(pixels: Int, scale: CGFloat = 1, _ draw: () -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let cg = context.cgContext
    // Flip to a top-left origin and map 1024 design units onto the bitmap.
    cg.translateBy(x: 0, y: CGFloat(pixels))
    cg.scaleBy(x: CGFloat(pixels) / 1024, y: -CGFloat(pixels) / 1024)
    cg.translateBy(x: 512, y: 512)
    cg.scaleBy(x: scale, y: scale)
    cg.translateBy(x: -512, y: -512)
    let flipped = NSGraphicsContext(cgContext: cg, flipped: true)
    NSGraphicsContext.current = flipped
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// A Windows .ico holding PNG frames (Windows Vista and later).
func ico(_ frames: [(Int, Data)]) -> Data {
    var data = Data()
    func le16(_ v: Int) { data.append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)]) }
    func le32(_ v: Int) { for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8(v >> shift & 0xFF)) } }
    le16(0); le16(1); le16(frames.count)
    var offset = 6 + 16 * frames.count
    for (size, frame) in frames {
        data.append(UInt8(size >= 256 ? 0 : size)); data.append(UInt8(size >= 256 ? 0 : size))
        data.append(0); data.append(0); le16(1); le16(32); le32(frame.count); le32(offset)
        offset += frame.count
    }
    for (_, frame) in frames { data.append(frame) }
    return data
}

let fm = FileManager.default
func write(_ data: Data, _ path: String) {
    try! fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try! data.write(to: URL(fileURLWithPath: path))
}

/// macOS: the artwork on a white rounded tile in the standard 824-point icon grid. macOS 26 puts
/// icons without a full tile on a grey one of its own.
func drawMacIcon(detailed: Bool) {
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 20
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.white.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    let art = NSAffineTransform()
    art.translateX(by: 512, yBy: 512)
    art.scale(by: 0.74)
    art.translateX(by: -512, yBy: -512)
    art.concat()
    drawColor(detailed: detailed)
    NSGraphicsContext.restoreGraphicsState()
}

/// Windows: the same white tile, filling more of the canvas as Windows icons do. [small] sizes
/// (the tray, small list views) use nearly the whole square so the artwork stays legible.
func drawWindowsIcon(detailed: Bool, small: Bool) {
    let inset: CGFloat = small ? 16 : 56
    let side = 1024 - 2 * inset
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: side, height: side), xRadius: side * 0.2, yRadius: side * 0.2).fill()
    // A hairline keeps the white tile visible on light backgrounds.
    NSColor.black.withAlphaComponent(0.10).setStroke()
    let edge = NSBezierPath(roundedRect: NSRect(x: inset + 6, y: inset + 6, width: side - 12, height: side - 12), xRadius: side * 0.2 - 6, yRadius: side * 0.2 - 6)
    edge.lineWidth = small ? 40 : 12
    edge.stroke()
    NSGraphicsContext.saveGraphicsState()
    let art = NSAffineTransform()
    art.translateX(by: 512, yBy: 512)
    art.scale(by: small ? 0.86 : 0.78)
    art.translateX(by: -512, yBy: -512)
    art.concat()
    drawColor(detailed: detailed)
    NSGraphicsContext.restoreGraphicsState()
}

// macOS: an iconset with the small sizes simplified, then iconutil.
let iconset = NSTemporaryDirectory() + "AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
for points in [16, 32, 128, 256, 512] {
    for (suffix, pixels) in [("", points), ("@2x", points * 2)] {
        write(png(pixels: pixels) { drawMacIcon(detailed: pixels >= 64) }, "\(iconset)/icon_\(points)x\(points)\(suffix).png")
    }
}
write(png(pixels: 1024) { drawMacIcon(detailed: true) }, "Resources/AppIcon-1024.png")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
print("Wrote Resources/AppIcon.icns")

if CommandLine.arguments.count > 1 {
    let out = CommandLine.arguments[1]
    // Windows: the exe icon, and a tray icon that stays legible at 16-32 px.
    write(ico([16, 24, 32, 48, 64, 128, 256].map { size in (size, png(pixels: size) { drawWindowsIcon(detailed: size >= 48, small: size < 48) }) }), "\(out)/windows/AppIcon.ico")
    write(ico([16, 20, 24, 32, 40, 48].map { size in (size, png(pixels: size) { drawWindowsIcon(detailed: false, small: true) }) }), "\(out)/windows/TrayIcon.ico")
    // Android adaptive layers: 108 dp canvases, artwork kept inside the 66 dp safe zone.
    for (density, pixels) in [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)] {
        write(png(pixels: pixels, scale: 0.62) { drawColor(detailed: true) }, "\(out)/android/mipmap-\(density)/ic_launcher_foreground.png")
        write(png(pixels: pixels, scale: 0.62) { drawMonochrome() }, "\(out)/android/mipmap-\(density)/ic_launcher_monochrome.png")
    }
    print("Wrote Windows and Android icons to \(out)")
}
