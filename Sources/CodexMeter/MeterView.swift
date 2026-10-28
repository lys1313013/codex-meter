import SwiftUI
import MeterCore

struct MeterView: View {
    @ObservedObject var model: MeterModel
    let showMenu: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var accent: Color { model.palette.accent }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Group {
                if model.compact {
                    compactContent
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        expandedContent(now: context.date)
                    }
                    .padding(22)
                    .frame(width: 320, alignment: .leading)
                }
            }
            .fixedSize()
        }
    }

    private var dragArea: some View {
        WindowDragArea(onDoubleClick: { model.compact.toggle() }, onMenu: showMenu)
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "circle.dashed.inset.filled")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(accent)
                Text("Codex Meter").font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
            }.overlay(dragArea)
            Button { model.pinned.toggle() } label: {
                Image(systemName: model.pinned ? "pin.fill" : "pin")
                    .foregroundStyle(model.pinned ? accent : .secondary)
            }.help(model.pinned ? "取消置顶" : "窗口置顶").accessibilityLabel("切换窗口置顶")
            Button { model.compact = true } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
            }.help("收起为圆环").accessibilityLabel("切换紧凑模式")
            Button(action: showMenu) { Image(systemName: "ellipsis") }
                .help("设置与退出").accessibilityLabel("设置与退出")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private var compactContent: some View {
        let remaining = model.indicatorWindow?.remaining
        let size = model.ringSize
        let width = max(3, size * 0.085)
        // One shared path for the track and progress, placed at the outer edge.
        let inset = width / 2 + 1
        let colors = model.isStale ? [Color.orange, .orange] : ringColors(remaining)
        return ZStack {
            Circle().stroke(.white.opacity(0.14), lineWidth: width).padding(inset)
            Circle().trim(from: 0, to: (remaining ?? 0) / 100)
                .stroke(AngularGradient(colors: colors, center: .center, startAngle: .zero, endAngle: .degrees(360)),
                        style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(inset)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: remaining)
            Text(remaining == nil ? (model.isRefreshing ? "…" : "--") : percent(remaining))
                .font(.system(size: size * 0.22, weight: .medium, design: .rounded))
                .monospacedDigit().foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
            if model.isStale {
                Circle().fill(.orange).frame(width: max(3, size * 0.06), height: max(3, size * 0.06))
                    .offset(y: size * 0.22)
            }
        }
        .frame(width: size, height: size)
        .overlay(dragArea)
        .help(model.indicatorDescription + "\n拖动移动 · 双击展开 · 右键设置")
        .accessibilityLabel(model.indicatorDescription)
    }

    @ViewBuilder private func expandedContent(now: Date) -> some View {
        HStack {
            Text("剩余额度").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            if let plan = model.bucket?.planType {
                Text(plan.uppercased()).font(.system(size: 9, weight: .semibold))
                    .tracking(1).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.primary.opacity(0.05), in: Capsule())
            }
        }
        if let response = model.response, response.buckets.count > 1 {
            Picker("额度类型", selection: Binding(get: { model.activeID }, set: { model.selectedID = $0 })) {
                ForEach(response.buckets.keys.sorted(), id: \.self) { id in
                    Text(response.buckets[id]?.limitName ?? id).tag(id)
                }
            }.font(.system(size: 11))
        }
        if let bucket = model.bucket, !bucket.windows.isEmpty {
            ForEach(Array(bucket.windows.enumerated()), id: \.offset) { _, window in
                quotaRow(window, now: now)
            }
        } else {
            VStack(alignment: .leading, spacing: 7) {
                Text(model.isRefreshing ? "正在连接 Codex…" : "暂无可用额度")
                    .font(.system(size: 16, weight: .medium))
                Text("使用本机 Codex 的 ChatGPT 登录状态")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.vertical, 8)
        }
        if let error = model.error {
            Text((model.response == nil ? "" : "当前显示旧数据。") + error)
                .font(.system(size: 11)).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        Divider()
        HStack(spacing: 6) {
            Circle().fill(model.isStale ? Color.orange : accent).frame(width: 4, height: 4)
            Text(statusText(now: now)).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer()
            Button { Task { await model.refresh() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
            }.buttonStyle(.plain).disabled(model.isRefreshing).help("立即刷新").accessibilityLabel("立即刷新")
        }
    }

    private func quotaRow(_ window: UsageWindow, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(percent(window.remaining)).font(.system(size: 28, weight: .medium, design: .rounded))
                    .monospacedDigit().foregroundStyle(.primary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule().fill(LinearGradient(colors: ringColors(window.remaining), startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * (window.remaining ?? 0) / 100)
                }
            }.frame(height: 4)
            Text(window.resetText(now: now)).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .overlay(dragArea)
        .accessibilityElement(children: .combine)
    }

    private func ringColors(_ remaining: Double?) -> [Color] {
        guard let remaining else { return [.gray, .gray] }
        if remaining <= 10 { return [.orange, .red] }
        if remaining <= 25 { return [.yellow, .orange] }
        return model.palette.colors
    }
    private func percent(_ value: Double?) -> String {
        value.map { String(format: "%.0f%%", $0) } ?? "--%"
    }
    private func statusText(now: Date) -> String {
        if model.isRefreshing { return "正在刷新…" }
        guard let updated = model.updatedAt else { return "尚未同步" }
        let minutes = max(0, Int(now.timeIntervalSince(updated) / 60))
        return (model.isStale ? "旧数据 · " : "") + (minutes == 0 ? "刚刚更新" : "\(minutes) 分钟前更新")
    }
}
