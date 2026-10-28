import AppKit
import SwiftUI
import Combine
import MeterCore

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = MeterModel()
    private var panel: FloatingPanel!
    private var host: NSHostingView<MeterView>!
    private var material: MeterMaterialView!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let statusPopover = NSPopover()
    private var subscriptions = Set<AnyCancellable>()
    private var lastPlacement: DisplayPlacement?
    private var lastCompact: Bool?
    private var layingOut = false
    private var statusTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let details = NSMenuItem(title: "查看额度详情", action: #selector(showDetails), keyEquivalent: "d")
        details.target = self
        appMenu.addItem(details)
        let settings = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        let quitItem = NSMenuItem(title: "退出 Codex Meter", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
        panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 56, height: 56),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Codex Meter"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = !model.compact
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        host = NSHostingView(rootView: MeterView(model: model, showMenu: { [weak self] in self?.showMenu() }))
        // Layout belongs to the window, not the hosting view's automatic minimum size.
        host.sizingOptions = [.intrinsicContentSize]
        material = MeterMaterialView(hosted: host)
        panel.contentView = material
        if let frame = UserDefaults.standard.string(forKey: "panelFrame") {
            panel.setFrame(NSRectFromString(frame), display: false)
        } else if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 100, y: screen.visibleFrame.maxY - 120))
        }
        panel.delegate = self
        statusItem = NSStatusBar.system.statusItem(withLength: MenuBarIndicator.width)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusPopover.behavior = .transient
        statusPopover.contentViewController = NSHostingController(
            rootView: MeterView(model: model, menuBarDetails: true, showMenu: { [weak self] in
                self?.showStatusMenu()
            })
        )
        model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateInterface() }
        }.store(in: &subscriptions)
        statusTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatusItem() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wokeUp), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        updateInterface()
        model.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if model.placement == .menuBar { showSettings() }
        else { panel.orderFrontRegardless() }
        return true
    }

    private func updateInterface() {
        guard panel != nil else { return }
        updateStatusItem()
        panel.level = model.pinned ? .floating : .normal
        panel.hasShadow = !model.compact
        host.layoutSubtreeIfNeeded()
        let size = model.compact
            ? NSSize(width: model.ringSize, height: model.ringSize)
            : NSSize(width: 320, height: max(190, host.fittingSize.height))
        let old = panel.frame
        var frame = NSRect(x: old.minX, y: old.maxY - size.height, width: size.width, height: size.height)
        if lastCompact == true && model.compact {
            frame.origin = NSPoint(x: old.midX - size.width / 2, y: old.midY - size.height / 2)
        }
        layingOut = true
        material.update(size: size, compact: model.compact)
        panel.setContentSize(size)
        panel.setFrame(frame, display: true)
        panel.displayIfNeeded()
        panel.invalidateShadow()
        keepOnScreen()
        layingOut = false
        lastCompact = model.compact
        saveFrame()
        if model.placement == .menuBar {
            panel.orderOut(nil)
        } else if lastPlacement != .desktop {
            panel.orderFrontRegardless()
        }
        lastPlacement = model.placement
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        MenuBarIndicator.configure(button, remaining: model.indicatorWindow?.remaining, stale: model.isStale)
        button.toolTip = model.indicatorDescription + (model.error.map { "\n" + $0 } ?? "") + "\n左键查看额度详情 · 右键打开菜单"
        statusItem.button?.setAccessibilityLabel("Codex 剩余额度：" + model.indicatorDescription)
    }

    private func keepOnScreen() {
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(panel.frame) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = panel.frame
        frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
        frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
        if frame != panel.frame { panel.setFrame(frame, display: true) }
    }

    private func saveFrame() {
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: "panelFrame")
    }
    func windowDidMove(_ notification: Notification) { if !layingOut { saveFrame() } }
    func windowDidResize(_ notification: Notification) { if !layingOut { saveFrame() } }
    @objc private func screenChanged() { keepOnScreen() }
    @objc private func wokeUp() { Task { await model.refresh() } }
    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else if statusPopover.isShown {
            statusPopover.performClose(nil)
        } else {
            showStatusDetails()
        }
    }
    private func showStatusDetails() {
        guard let button = statusItem.button else { return }
        statusPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        statusPopover.contentViewController?.view.window?.makeKey()
    }
    private func showStatusMenu() {
        statusPopover.performClose(nil)
        guard let button = statusItem.button else { return }
        buildMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }
    @objc private func useDesktop() {
        statusPopover.performClose(nil)
        model.compact = true
        model.placement = .desktop
        panel.orderFrontRegardless()
    }
    @objc private func useMenuBar() { model.placement = .menuBar }
    @objc private func showDetails() {
        if model.placement == .menuBar {
            showStatusDetails()
            return
        }
        model.compact = false
        model.placement = .desktop
        panel.orderFrontRegardless()
    }
    @objc private func refresh() { Task { await model.refresh() } }
    @objc private func togglePinned() { model.pinned.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func setRingSize(_ sender: NSMenuItem) {
        model.ringSize = Double(sender.tag)
        model.compact = true
    }
    @objc private func showSettings() {
        statusPopover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: MeterSettingsView.windowSize),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Codex Meter 设置"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MeterSettingsView(model: model))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func chooseCLI() {
        NSApp.activate(ignoringOtherApps: true)
        let picker = NSOpenPanel()
        picker.title = "选择 Codex CLI 可执行文件"
        picker.canChooseDirectories = false
        picker.showsHiddenFiles = true
        picker.treatsFilePackagesAsDirectories = true
        if picker.runModal() == .OK, let url = picker.url {
            model.customPath = url.path
            Task { await model.refresh() }
        }
    }
    @objc private func resetCLI() {
        model.customPath = nil
        Task { await model.refresh() }
    }
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, _ selector: Selector, checked: Bool = false) {
            let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            entry.target = self
            entry.state = checked ? .on : .off
            menu.addItem(entry)
        }
        let summary = NSMenuItem(title: model.indicatorDescription, action: nil, keyEquivalent: "")
        menu.addItem(summary)
        item("立即刷新", #selector(refresh))
        item("查看详情", #selector(showDetails))
        menu.addItem(.separator())
        item("桌面圆环", #selector(useDesktop), checked: model.placement == .desktop)
        item("仅菜单栏", #selector(useMenuBar), checked: model.placement == .menuBar)
        item("外观与大小…", #selector(showSettings))
        let sizes = NSMenuItem(title: "圆环大小", action: nil, keyEquivalent: "")
        let sizesMenu = NSMenu()
        for size in [40, 56, 72, 96, 120] {
            let entry = NSMenuItem(title: "\(size) pt", action: #selector(setRingSize(_:)), keyEquivalent: "")
            entry.tag = size
            entry.target = self
            entry.state = Int(model.ringSize) == size ? .on : .off
            sizesMenu.addItem(entry)
        }
        sizes.submenu = sizesMenu
        menu.addItem(sizes)
        item("窗口置顶", #selector(togglePinned), checked: model.pinned)
        menu.addItem(.separator())
        item("选择 Codex CLI…", #selector(chooseCLI))
        item("自动查找 Codex CLI", #selector(resetCLI))
        menu.addItem(.separator())
        item("退出 Codex Meter", #selector(quit))
        return menu
    }
    private func showMenu() {
        let event = NSApp.currentEvent
        let point = event.flatMap { event in event.window?.convertPoint(toScreen: event.locationInWindow) } ?? NSEvent.mouseLocation
        buildMenu().popUp(positioning: nil, at: point, in: nil)
    }
}

@main
enum CodexMeterMain {
    @MainActor static func main() async {
        if let index = CommandLine.arguments.firstIndex(of: "--render-previews") {
            guard CommandLine.arguments.indices.contains(index + 1) else {
                fputs("Usage: CodexMeter --render-previews <output-directory>\n", stderr)
                exit(1)
            }
            do {
                try PreviewRenderer.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true))
            } catch { fputs("Preview rendering failed: \(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        // Useful for checking real integration without starting the UI or printing account details.
        if CommandLine.arguments.contains("--check") {
            do {
                let result = try await CodexClient().fetch()
                for key in result.buckets.keys.sorted() {
                    for window in result.buckets[key]!.windows {
                        let remaining = window.remaining.map { String(format: "%.0f%%", $0) } ?? "unknown"
                        print("\(key): \(window.title), remaining=\(remaining), \(window.resetText())")
                    }
                }
                if result.buckets.isEmpty { print("Connected; no quota buckets returned.") }
            } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
