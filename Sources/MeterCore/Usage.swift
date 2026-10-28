import Foundation

public struct UsageWindow: Decodable, Sendable {
    public let usedPercent: Double?
    public let windowDurationMins: Int?
    public let resetsAt: Double?

    public var remaining: Double? {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        return min(100, max(0, 100 - usedPercent))
    }

    public var title: String {
        switch windowDurationMins {
        case 300: return "5 小时"
        case 10080: return "每周"
        case let minutes? where minutes > 0 && minutes % 1440 == 0: return "\(minutes / 1440) 天"
        case let minutes? where minutes > 0 && minutes % 60 == 0: return "\(minutes / 60) 小时"
        case let minutes? where minutes > 0: return "\(minutes) 分钟"
        default: return "额度窗口"
        }
    }

    public func resetText(now: Date = Date()) -> String {
        guard let resetsAt else { return "重置时间未知" }
        let seconds = resetsAt - now.timeIntervalSince1970
        guard seconds > 0 else { return "等待额度更新" }
        let minutes = Int(ceil(seconds / 60))
        if minutes >= 1440 { return "\(minutes / 1440) 天 \((minutes % 1440) / 60) 小时后重置" }
        if minutes >= 60 { return "\(minutes / 60) 小时 \(minutes % 60) 分钟后重置" }
        return "\(minutes) 分钟后重置"
    }
}

public struct UsageBucket: Decodable, Sendable {
    public let limitId: String?
    public let limitName: String?
    public let primary: UsageWindow?
    public let secondary: UsageWindow?
    public let planType: String?

    public var windows: [UsageWindow] {
        [primary, secondary].compactMap { $0 }.sorted {
            ($0.windowDurationMins ?? Int.max) < ($1.windowDurationMins ?? Int.max)
        }
    }
}

public struct UsageResponse: Decodable, Sendable {
    public let rateLimits: UsageBucket?
    public let rateLimitsByLimitId: [String: UsageBucket]?

    public var buckets: [String: UsageBucket] {
        if let map = rateLimitsByLimitId, !map.isEmpty { return map }
        if let rateLimits { return [rateLimits.limitId ?? "codex": rateLimits] }
        return [:]
    }

    public func selectedID(preferred: String) -> String? {
        if buckets[preferred] != nil { return preferred }
        if buckets["codex"] != nil { return "codex" }
        return buckets.keys.sorted().first
    }
}
