import Combine
import Foundation
import MeterCore

@MainActor
final class MeterModel: ObservableObject {
    private let defaults: UserDefaults
    @Published var response: UsageResponse?
    @Published var isRefreshing = false
    @Published var error: String?
    @Published var updatedAt: Date?
    @Published var compact: Bool {
        didSet { defaults.set(compact, forKey: "compact") }
    }
    @Published var pinned: Bool {
        didSet { defaults.set(pinned, forKey: "pinned") }
    }
    @Published var selectedID: String {
        didSet { defaults.set(selectedID, forKey: "selectedID") }
    }
    @Published var placement: DisplayPlacement {
        didSet { defaults.set(placement.rawValue, forKey: "placement") }
    }
    @Published var ringSize: Double {
        didSet {
            let normalized = MeterPresentation.ringSize(ringSize)
            if normalized != ringSize { ringSize = normalized }
            defaults.set(normalized, forKey: "ringSize")
        }
    }
    @Published var palette: RingPalette {
        didSet { defaults.set(palette.rawValue, forKey: "palette") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        compact = defaults.object(forKey: "compact") as? Bool ?? true
        pinned = defaults.object(forKey: "pinned") as? Bool ?? true
        selectedID = defaults.string(forKey: "selectedID") ?? "codex"
        placement = DisplayPlacement(rawValue: defaults.string(forKey: "placement") ?? "") ?? .desktop
        ringSize = MeterPresentation.ringSize(defaults.object(forKey: "ringSize") as? Double ?? 56)
        palette = RingPalette(rawValue: defaults.string(forKey: "palette") ?? "") ?? .green
    }
    var indicatorWindow: UsageWindow? { bucket?.indicatorWindow }
    var indicatorDescription: String {
        let description = indicatorWindow.map {
            "\($0.title)剩余 \(String(format: "%.0f%%", $0.remaining ?? 0)) · \($0.resetText())"
        } ?? "暂无额度数据"
        return description + (isStale ? " · 旧数据，请刷新" : "")
    }
    var customPath: String? {
        get { defaults.string(forKey: "cliPath") }
        set { defaults.set(newValue, forKey: "cliPath") }
    }

    var bucket: UsageBucket? {
        guard let response, let key = response.selectedID(preferred: selectedID) else { return nil }
        return response.buckets[key]
    }
    var activeID: String { response?.selectedID(preferred: selectedID) ?? "codex" }
    var isStale: Bool { error != nil || (updatedAt.map { Date().timeIntervalSince($0) > 300 } ?? false) }
    private var refreshLoop: Task<Void, Never>?

    func start() {
        refreshLoop?.cancel()
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(nanoseconds: 120_000_000_000) }
                catch { return }
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            response = try await CodexClient().fetch(customPath: customPath)
            updatedAt = Date()
            error = nil
        } catch {
            self.error = (error as? MeterError)?.localizedDescription ?? "读取失败，请检查 Codex CLI 路径和登录状态。"
        }
    }
}
