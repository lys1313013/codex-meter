import Foundation

public enum RefreshPolicy {
    /// A failed request does not invalidate a recent successful reading.
    public static func isStale(updatedAt: Date?, hasError: Bool, now: Date = Date()) -> Bool {
        guard let updatedAt else { return hasError }
        return now.timeIntervalSince(updatedAt) > 300
    }

    /// Retry transient failures twice, keeping the whole refresh in flight.
    public static func fetch(
        operation: () async throws -> UsageResponse,
        sleep: (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) async throws -> UsageResponse {
        let delays: [UInt64] = [3_000_000_000, 10_000_000_000]
        for attempt in 0...delays.count {
            try Task.checkCancellation()
            do {
                let result = try await operation()
                try Task.checkCancellation()
                return result
            } catch {
                try Task.checkCancellation()
                guard let failure = error as? MeterError, failure.isRetryable,
                      attempt < delays.count else { throw error }
                try await sleep(delays[attempt])
            }
        }
        preconditionFailure("All attempts either return or throw")
    }
}
