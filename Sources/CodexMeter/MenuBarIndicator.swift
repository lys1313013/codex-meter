import AppKit
import MeterCore

/// A native status button keeps system highlighting, accessibility and menu-bar contrast.
@MainActor
enum MenuBarIndicator {
    static let width: CGFloat = 84

    static func configure(_ button: NSButton, remaining: Double?, stale: Bool) {
        let title = MeterPresentation.menuNumber(remaining: remaining, stale: stale)
        // A fixed four-character cell keeps both the ring and text stationary at 9/10/100%.
        button.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        button.title = String(repeating: " ", count: max(0, 4 - title.count)) + title
        button.image = ring(remaining: remaining, stale: stale)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
    }

    private static func ring(remaining: Double?, stale: Bool) -> NSImage {
        let value = remaining.flatMap { $0.isFinite ? min(100, max(0, $0)) : nil }
        let color: NSColor = stale ? .systemOrange : (value.map { $0 < 10 ? .systemRed : ($0 < 20 ? .systemOrange : .labelColor) } ?? .labelColor)
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            color.withAlphaComponent(0.25).setStroke()
            let track = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 14, height: 14))
            track.lineWidth = 2
            track.stroke()
            color.setStroke()
            if stale {
                // Never draw stale progress as though it is current.
                let mark = NSBezierPath()
                mark.move(to: NSPoint(x: 9, y: 12))
                mark.line(to: NSPoint(x: 9, y: 8))
                mark.lineWidth = 1.8
                mark.lineCapStyle = .round
                mark.stroke()
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: 8.1, y: 4.5, width: 1.8, height: 1.8)).fill()
            } else if let value, value > 0 {
                let progress = NSBezierPath()
                progress.appendArc(withCenter: NSPoint(x: 9, y: 9), radius: 7,
                                   startAngle: 90, endAngle: 90 - CGFloat(value) * 3.6, clockwise: true)
                progress.lineWidth = 2
                progress.lineCapStyle = .round
                progress.stroke()
            }
            return true
        }
        image.isTemplate = !stale && ((value ?? 100) >= 20)
        return image
    }
}
