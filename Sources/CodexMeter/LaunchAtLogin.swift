import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var isUpdating = false
    @Published var errorMessage: String?

    private let service = SMAppService.mainApp
    let isAvailable = Bundle.main.bundleURL.pathExtension == "app"
        && Bundle.main.bundleIdentifier != nil

    init() {
        refreshStatus()
    }

    var isEnabled: Bool { status == .enabled }
    var needsApproval: Bool { status == .requiresApproval }

    var detail: String {
        if !isAvailable {
            return "请打开打包后的 Codex Meter.app，再设置开机自启动。"
        }
        switch status {
        case .requiresApproval:
            return "尚未获系统允许，请在系统设置的登录项中允许 Codex Meter。"
        case .notFound:
            return "登录 Mac 时自动启动。建议先将应用放入“应用程序”，再开启此选项。"
        default:
            return "开启后，登录 Mac 时自动启动 Codex Meter。"
        }
    }

    func refreshStatus() {
        // The system is the source of truth, including changes made in System Settings.
        status = isAvailable ? service.status : .notFound
    }

    func setEnabled(_ enabled: Bool) async {
        guard isAvailable, !isUpdating else { return }
        errorMessage = nil
        refreshStatus()
        if enabled && needsApproval {
            openSystemSettings()
            return
        }
        guard enabled != isEnabled else { return }
        isUpdating = true
        defer {
            refreshStatus()
            isUpdating = false
        }
        do {
            if enabled {
                try service.register()
            } else {
                try await service.unregister()
            }
        } catch {
            errorMessage = "无法\(enabled ? "开启" : "关闭")开机自启动：\(error.localizedDescription)"
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
