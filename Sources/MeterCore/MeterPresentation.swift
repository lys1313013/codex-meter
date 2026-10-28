import Foundation

public enum MeterPresentation {
    public static func ringSize(_ value: Double) -> Double {
        guard value.isFinite else { return 56 }
        return min(120, max(40, value))
    }

    /// A menu bar item contains only a number; unknown/stale values must not look current.
    public static func menuNumber(remaining: Double?, stale: Bool) -> String {
        guard !stale, let remaining, remaining.isFinite else { return "--" }
        return String(format: "%.0f", min(100, max(0, remaining)))
    }
}

extension UsageBucket {
    public var indicatorWindow: UsageWindow? {
        windows.filter { $0.remaining != nil }.min {
            ($0.remaining ?? 100) < ($1.remaining ?? 100)
        }
    }
}
