#!/usr/bin/env swift
import AppKit

// Original vector artwork. Run from the repository root to regenerate the PNG and ICNS.
let fm = FileManager.default
let temporary = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let iconset = temporary.appendingPathComponent("AppIcon.iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: temporary) }
try fm.createDirectory(atPath: "docs/images", withIntermediateDirectories: true)

func png(size: Int) throws -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(size) / 1024)
    transform.concat()
    let rect = NSRect(x: 40, y: 40, width: 944, height: 944)
    let background = NSBezierPath(roundedRect: rect, xRadius: 210, yRadius: 210)
    NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.20, blue: 0.25, alpha: 1),
               ending: NSColor(srgbRed: 0.055, green: 0.08, blue: 0.11, alpha: 1))!.draw(in: background, angle: -90)
    let track = NSBezierPath(ovalIn: NSRect(x: 218, y: 218, width: 588, height: 588))
    track.lineWidth = 76
    NSColor(srgbRed: 0.23, green: 0.28, blue: 0.32, alpha: 1).setStroke()
    track.stroke()
    let progress = NSBezierPath()
    progress.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 294, startAngle: 90, endAngle: -176.4, clockwise: true)
    progress.lineWidth = 76
    progress.lineCapStyle = .round
    NSColor(srgbRed: 0.29, green: 0.91, blue: 0.62, alpha: 1).setStroke()
    progress.stroke()
    let prompt = NSBezierPath()
    prompt.move(to: NSPoint(x: 390, y: 574))
    prompt.line(to: NSPoint(x: 463, y: 512))
    prompt.line(to: NSPoint(x: 390, y: 450))
    prompt.move(to: NSPoint(x: 529, y: 450))
    prompt.line(to: NSPoint(x: 630, y: 450))
    prompt.lineWidth = 32
    prompt.lineCapStyle = .round
    prompt.lineJoinStyle = .round
    NSColor.white.setStroke()
    prompt.stroke()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try png(size: points * scale).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
try png(size: 1024).write(to: URL(fileURLWithPath: "docs/images/app-icon.png"))
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", "-o", "Resources/AppIcon.icns", iconset.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
print("Generated Resources/AppIcon.icns and docs/images/app-icon.png")
