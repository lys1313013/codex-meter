import Foundation
import MeterCore

var count = 0
func check(_ condition: @autoclosure () -> Bool, _ description: String) {
    guard condition() else { fatalError("FAIL: \(description)") }
    count += 1
    print("PASS: \(description)")
}
func decode(_ json: String) throws -> UsageResponse {
    try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8))
}

// A primary window may be weekly; never assume that primary means five hours.
let weekly = try decode(#"{"rateLimits":{"primary":{"usedPercent":23,"windowDurationMins":10080,"resetsAt":2000000000},"secondary":null}}"#)
check(weekly.buckets["codex"]?.windows.count == 1, "single window does not fabricate another limit")
check(weekly.buckets["codex"]?.windows.first?.title == "每周", "weekly primary is labelled by duration")
check(weekly.buckets["codex"]?.windows.first?.remaining == 77, "remaining equals 100 minus usage")

let multi = try decode(#"{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":30,"windowDurationMins":10080},"secondary":{"usedPercent":10,"windowDurationMins":300}},"other":{"primary":{"usedPercent":4,"windowDurationMins":15}}}}"#)
check(multi.buckets.count == 2, "multi-bucket response takes precedence over legacy")
check(multi.buckets["codex"]?.windows.first?.title == "5 小时", "windows sort by actual duration")
check(multi.selectedID(preferred: "missing") == "codex", "missing selected bucket falls back to Codex")
check(multi.selectedID(preferred: "other") == "other", "explicit bucket selection preserved")
check(multi.buckets["other"]?.windows.first?.title == "15 分钟", "unusual duration remains accurate")

let bounds = try decode(#"{"rateLimits":{"primary":{"usedPercent":120},"secondary":{"usedPercent":-5}}}"#)
check(bounds.buckets["codex"]?.primary?.remaining == 0, "over-limit usage clamps to zero")
check(bounds.buckets["codex"]?.secondary?.remaining == 100, "negative usage clamps to 100")
let missing = try decode(#"{"rateLimits":{"primary":{}}}"#)
check(missing.buckets["codex"]?.primary?.remaining == nil, "missing usage remains unknown, not 100%")
check(missing.buckets["codex"]?.primary?.resetText() == "重置时间未知", "missing reset is explicit")
let empty = try decode(#"{"rateLimits":null,"rateLimitsByLimitId":null}"#)
check(empty.buckets.isEmpty, "null data produces empty state")
let w = weekly.buckets["codex"]!.primary!
check(w.resetText(now: Date(timeIntervalSince1970: 2000000001)) == "等待额度更新", "expired reset does not invent a replenished quota")
check(w.resetText(now: Date(timeIntervalSince1970: 1999999999)) == "1 分钟后重置", "countdown rounds up")
check(CodexClient.executable(customPath: "/definitely/not/a/codex") == nil, "invalid custom CLI path does not silently select a different account source")

// Exercise the actual stdio transport, including notifications interleaved with replies.
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }
let fixture = temporary.appendingPathComponent("codex")
func writeFixture(_ script: String) throws {
    try script.write(to: fixture, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
}
try writeFixture("""
#!/bin/sh
read -r initialize
printf '%s\\n' '{"id":1,"result":{}}'
read -r initialized
read -r request
printf '%s\\n' '{"method":"account/updated","params":{}}' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":42,"windowDurationMins":300}}}}'
read -r done
""")
let transport = try await CodexClient().fetch(customPath: fixture.path)
check(transport.buckets["codex"]?.primary?.remaining == 58, "stdio handshake and notification filtering work")
try writeFixture("""
#!/bin/sh
read -r initialize
printf '%s\\n' '{"id":1,"error":{"code":-1,"message":"private server details"}}'
""")
do {
    _ = try await CodexClient().fetch(customPath: fixture.path)
    fatalError("server error should fail")
} catch {
    check(!error.localizedDescription.contains("private server details"), "server errors do not leak raw response details")
}
try writeFixture("#!/bin/sh\nexit 0\n")
do {
    _ = try await CodexClient().fetch(customPath: fixture.path)
    fatalError("closed transport should fail")
} catch {
    check(true, "early child exit reports an error without terminating the host")
}
check(MeterPresentation.menuNumber(remaining: 74, stale: false) == "74%", "menu bar includes the percentage unit")
check(MeterPresentation.menuNumber(remaining: nil, stale: false) == "--", "unknown menu value is not zero")
check(MeterPresentation.menuNumber(remaining: 74, stale: true) == "--", "stale menu value is not shown as live")
check(MeterPresentation.menuNumber(remaining: 0, stale: false) == "0%", "zero remaining is displayed correctly")
check(MeterPresentation.ringSize(5) == 40 && MeterPresentation.ringSize(200) == 120, "ring size stays within usable limits")
check(MeterPresentation.ringSize(.nan) == 56, "invalid stored size falls back safely")
check(multi.buckets["codex"]?.indicatorWindow?.title == "每周", "ring and menu use the most constrained quota window")
// Retry and freshness behavior uses synthetic time and injected operations; no network or real sleeps.
let refreshedAt = Date(timeIntervalSince1970: 1000)
check(!RefreshPolicy.isStale(updatedAt: refreshedAt, hasError: true, now: refreshedAt.addingTimeInterval(120)), "one failed refresh keeps recent data usable")
check(!RefreshPolicy.isStale(updatedAt: refreshedAt, hasError: true, now: refreshedAt.addingTimeInterval(300)), "five-minute boundary remains usable")
check(RefreshPolicy.isStale(updatedAt: refreshedAt, hasError: false, now: refreshedAt.addingTimeInterval(301)), "old data expires even without a request error")
check(RefreshPolicy.isStale(updatedAt: nil, hasError: true), "first-load failure remains visible")
check(!RefreshPolicy.isStale(updatedAt: nil, hasError: false), "initial loading is not an error")

var attempts = 0
var retryDelays: [UInt64] = []
let recovered = try await RefreshPolicy.fetch(operation: {
    attempts += 1
    if attempts == 1 { throw MeterError.timeout }
    if attempts == 2 { throw MeterError.disconnected }
    return weekly
}, sleep: { retryDelays.append($0) })
check(attempts == 3 && recovered.buckets["codex"]?.primary?.remaining == 77, "transient failures recover on the third attempt")
check(retryDelays == [3_000_000_000, 10_000_000_000], "retries use short bounded delays")

attempts = 0
retryDelays = []
do {
    _ = try await RefreshPolicy.fetch(operation: {
        attempts += 1
        throw MeterError.server
    }, sleep: { retryDelays.append($0) })
    fatalError("persistent failure should throw")
} catch MeterError.server {
    check(attempts == 3 && retryDelays.count == 2, "persistent failures stop after two retries and preserve the error")
}
for failure in [MeterError.missingCLI, .invalidResponse] {
    attempts = 0
    retryDelays = []
    do {
        _ = try await RefreshPolicy.fetch(operation: {
            attempts += 1
            throw failure
        }, sleep: { retryDelays.append($0) })
        fatalError("permanent failure should throw")
    } catch {
        check(attempts == 1 && retryDelays.isEmpty, "configuration and protocol errors are not retried")
    }
}
attempts = 0
do {
    _ = try await RefreshPolicy.fetch(operation: {
        attempts += 1
        throw MeterError.timeout
    }, sleep: { _ in throw CancellationError() })
    fatalError("cancelled backoff should throw")
} catch is CancellationError {
    check(attempts == 1, "cancelling backoff prevents another request")
}
print("\(count) checks passed")
