import AppKit
import SwiftUI

enum DisplayPlacement: String, CaseIterable, Identifiable {
    case desktop, menuBar
    var id: String { rawValue }
    var title: String { self == .desktop ? "桌面圆环" : "仅菜单栏" }
}

enum RingPalette: String, CaseIterable, Identifiable {
    case green, blue, silver, violet
    var id: String { rawValue }
    var title: String {
        switch self {
        case .green: return "活力绿"
        case .blue: return "冰蓝"
        case .silver: return "石墨"
        case .violet: return "鸢尾"
        }
    }
    var colors: [Color] {
        switch self {
        case .green: return [Color(nsColor: .systemGreen), Color(nsColor: .systemGreen)]
        case .blue: return [Color(nsColor: .systemCyan), Color(nsColor: .systemBlue)]
        case .silver: return [Color(nsColor: .secondaryLabelColor), Color(nsColor: .labelColor)]
        case .violet: return [Color(nsColor: .systemIndigo), Color(nsColor: .systemPurple)]
        }
    }
    var accent: Color { colors.last! }
}

/// The compact indicator uses a borderless material, like the system Batteries widget.
/// Keep Liquid Glass for expanded controls, where its rim doesn't compete with progress.
final class MeterMaterialView: NSView {
    private var surface: NSView?
    private var compactBackdrop: NSVisualEffectView?
    private let hosted: NSView
    private var compactStyle: Bool?

    init(hosted: NSView) {
        self.hosted = hosted
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        hosted.autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configureSurface(compact: Bool) {
        guard compactStyle != compact else { return }
        if #available(macOS 26.0, *), let glass = surface as? NSGlassEffectView {
            glass.contentView = nil
        }
        hosted.removeFromSuperview()
        surface?.removeFromSuperview()
        compactBackdrop = nil
        let next: NSView
        if compact {
            let container = NSView()
            let material = NSVisualEffectView()
            material.material = .hudWindow
            material.blendingMode = .behindWindow
            material.state = .active
            material.appearance = NSAppearance(named: .darkAqua)
            material.autoresizingMask = [.width, .height]
            container.addSubview(material)
            // Fade only the background; keep the white number and progress fully opaque.
            container.addSubview(hosted)
            compactBackdrop = material
            next = container
        } else if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.contentView = hosted
            next = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .hudWindow
            material.blendingMode = .behindWindow
            material.state = .active
            material.addSubview(hosted)
            next = material
        }
        next.autoresizingMask = [.width, .height]
        addSubview(next)
        surface = next
        compactStyle = compact
    }

    func update(size: NSSize, compact: Bool) {
        configureSurface(compact: compact)
        guard let surface else { return }
        frame.size = size
        surface.frame = bounds
        if let compactBackdrop {
            compactBackdrop.frame = surface.bounds
            compactBackdrop.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0.45
        }
        hosted.frame = surface.bounds
        let radius = compact ? size.width / 2 : 24
        // Clip the whole content tree, not only the material's visible glass rim.
        layer?.cornerRadius = radius
        if #available(macOS 26.0, *), let glass = surface as? NSGlassEffectView {
            glass.cornerRadius = radius
        } else {
            surface.wantsLayer = true
            surface.layer?.cornerRadius = radius
            surface.layer?.masksToBounds = true
        }
    }
}
