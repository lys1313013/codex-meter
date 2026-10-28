import AppKit
import SwiftUI
import MeterCore

/// Renders the real views with synthetic quota data; never starts Codex or writes user preferences.
@MainActor
enum PreviewRenderer {
    static func render(to directory: URL) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: .darkAqua)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "io.github.lys1313013.codex-meter.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = MeterModel(defaults: defaults)
        let now = Date().timeIntervalSince1970
        let fixture = """
        {"rateLimits":{"planType":"plus","primary":{"usedPercent":26,"windowDurationMins":300,"resetsAt":\(now + 7200)},"secondary":{"usedPercent":18,"windowDurationMins":10080,"resetsAt":\(now + 259200)}}}
        """
        model.response = try JSONDecoder().decode(UsageResponse.self, from: Data(fixture.utf8))
        model.updatedAt = Date()
        model.ringSize = 96
        model.compact = true
        try saveMeter(model, to: directory.appendingPathComponent("desktop-ring.png"))
        model.compact = false
        try saveMeter(model, to: directory.appendingPathComponent("details.png"))
        let settings = NSHostingView(rootView: MeterSettingsView(model: model).environment(\.colorScheme, .dark))
        try save(settings, size: MeterSettingsView.windowSize, to: directory.appendingPathComponent("settings.png"))

        // Render the same native button used in the menu bar, including its fixed-width layout.
        for (name, remaining, stale) in [("menu-bar", 74.0, false), ("menu-bar-low", 9.0, false),
                                          ("menu-bar-full", 100.0, false), ("menu-bar-stale", 74.0, true)] {
            let button = NSButton(frame: NSRect(x: 0, y: 0, width: MenuBarIndicator.width, height: 28))
            button.isBordered = false
            MenuBarIndicator.configure(button, remaining: remaining, stale: stale)
            let backing = NSView(frame: button.frame)
            backing.wantsLayer = true
            backing.layer?.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
            backing.addSubview(button)
            try save(backing, size: button.frame.size, to: directory.appendingPathComponent(name + ".png"))
        }
        let popover = NSHostingView(rootView: MeterView(model: model, menuBarDetails: true, showMenu: {})
            .environment(\.colorScheme, .dark))
        popover.layoutSubtreeIfNeeded()
        try save(popover, size: NSSize(width: 320, height: popover.fittingSize.height),
                 to: directory.appendingPathComponent("menu-bar-details.png"))
        // Check both failure states with synthetic data, without changing real app preferences.
        model.error = MeterError.timeout.localizedDescription
        for (name, age) in [("recent-failure", 120.0), ("stale-failure", 360.0)] {
            model.updatedAt = Date().addingTimeInterval(-age)
            model.compact = true
            try saveMeter(model, to: directory.appendingPathComponent(name + "-ring.png"))
            model.compact = false
            try saveMeter(model, to: directory.appendingPathComponent(name + "-details.png"))
        }
        print("Rendered previews with example data: \(directory.path)")
    }

    private static func saveMeter(_ model: MeterModel, to url: URL) throws {
        let host = NSHostingView(rootView: MeterView(model: model, showMenu: {}).environment(\.colorScheme, .dark).environment(\.displayScale, 2))
        host.sizingOptions = [.intrinsicContentSize]
        host.layoutSubtreeIfNeeded()
        let size = model.compact
            ? NSSize(width: model.ringSize, height: model.ringSize)
            : NSSize(width: 320, height: max(190, host.fittingSize.height))
        if model.compact {
            let material = MeterMaterialView(hosted: host)
            material.update(size: size, compact: true)
            try save(material, size: size, to: url)
        } else {
            // WindowServer applies glass vibrancy after view drawing. Use an opaque backing for
            // offline documentation renders so semantic text colors stay legible in the PNG.
            let backing = NSView(frame: NSRect(origin: .zero, size: size))
            backing.wantsLayer = true
            backing.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
            backing.layer?.cornerRadius = 24
            backing.layer?.masksToBounds = true
            host.frame = backing.bounds
            backing.addSubview(host)
            try save(backing, size: size, to: url)
        }
    }

    private static func save(_ view: NSView, size: NSSize, to url: URL) throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        // Let SwiftUI commit its initial layout before taking the view snapshot.
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        view.layoutSubtreeIfNeeded()
        try bitmap(view, to: url)
        window.close()
    }

    private static func bitmap(_ view: NSView, to url: URL) throws {
        let bounds = view.bounds
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(bounds.width * 2)), pixelsHigh: Int(ceil(bounds.height * 2)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw CocoaError(.fileWriteUnknown)
        }
        rep.size = bounds.size
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: bounds, to: rep)
        }
        guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
    }
}
