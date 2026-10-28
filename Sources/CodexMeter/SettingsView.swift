import AppKit
import SwiftUI

struct MeterSettingsView: View {
    static let windowSize = NSSize(width: 380, height: 500)
    @ObservedObject var model: MeterModel
    @StateObject private var launchAtLogin = LaunchAtLogin()

    var body: some View {
        Form {
            Section("启动") {
                Toggle("开机自启动", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { enabled in Task { await launchAtLogin.setEnabled(enabled) } }
                ))
                .disabled(!launchAtLogin.isAvailable || launchAtLogin.isUpdating)
                Text(launchAtLogin.detail)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if launchAtLogin.needsApproval {
                    Button("打开系统登录项设置…") { launchAtLogin.openSystemSettings() }
                }
            }
            Section {
                Picker("显示位置", selection: Binding(get: { model.placement }, set: {
                    model.placement = $0
                    if $0 == .desktop { model.compact = true }
                })) {
                    ForEach(DisplayPlacement.allCases) { placement in
                        Text(placement.title).tag(placement)
                    }
                }.pickerStyle(.segmented)
                Text("菜单栏显示进度环和剩余百分比；左键查看详情，右键打开菜单。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("桌面圆环") {
                HStack {
                    Text("大小")
                    Spacer()
                    Text("\(Int(model.ringSize)) pt").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $model.ringSize, in: 40...120, step: 4) {
                    Text("圆环大小")
                } minimumValueLabel: { Text("小").font(.caption) }
                    maximumValueLabel: { Text("大").font(.caption) }
                Picker("配色", selection: $model.palette) {
                    ForEach(RingPalette.allCases) { palette in
                        Text(palette.title).tag(palette)
                    }
                }.pickerStyle(.segmented)
                Toggle("窗口置顶", isOn: $model.pinned)
                Text("拖动圆环移动位置，双击查看详情，右键打开菜单。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .onChange(of: model.ringSize) { _ in model.compact = true }
        .onAppear { launchAtLogin.refreshStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            launchAtLogin.refreshStatus()
        }
        .alert("开机自启动设置失败", isPresented: Binding(
            get: { launchAtLogin.errorMessage != nil },
            set: { if !$0 { launchAtLogin.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { launchAtLogin.errorMessage = nil }
        } message: {
            Text(launchAtLogin.errorMessage ?? "")
        }
    }
}
