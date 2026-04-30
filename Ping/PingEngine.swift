import Foundation

@Observable
@MainActor
final class PingEngine {
    var latency: Double?
    var packetLoss: Double = 0
    private var buffer: [Bool] = []
    private var isRunning = false
    private var loopTask: Task<Void, Never>?

    struct PingRecord {
        let timestamp: Date
        let latency: Double?
    }
    private var recentPings: [PingRecord] = []
    private static let recentWindow: TimeInterval = 300

    // Past 5 minutes (computed from recentPings)
    var recentPingsSent: Int { recentEntries.count }
    var recentRepliesLost: Int { recentEntries.filter { $0.latency == nil }.count }
    var recentPacketLossPercent: Double {
        recentPingsSent > 0 ? Double(recentRepliesLost) / Double(recentPingsSent) * 100 : 0
    }
    var recentAvgResponse: Double {
        let successes = recentEntries.compactMap(\.latency)
        return successes.isEmpty ? 0 : successes.reduce(0, +) / Double(successes.count)
    }
    var recentFastestResponse: Double {
        recentEntries.compactMap(\.latency).min() ?? 0
    }
    var recentSlowestResponse: Double {
        recentEntries.compactMap(\.latency).max() ?? 0
    }
    private(set) var recentEntries: [PingRecord] = []

    // Session stats (reset on app restart or manual reset)
    var sessionPingsSent: Int = 0
    var sessionRepliesLost: Int = 0
    var sessionFastestResponse: Double = .infinity
    var sessionSlowestResponse: Double = 0
    private var sessionTotalLatency: Double = 0
    private var sessionSuccessCount: Int = 0

    var sessionAvgResponse: Double {
        sessionSuccessCount > 0 ? sessionTotalLatency / Double(sessionSuccessCount) : 0
    }

    var sessionPacketLossPercent: Double {
        sessionPingsSent > 0 ? Double(sessionRepliesLost) / Double(sessionPingsSent) * 100 : 0
    }

    // All-time stats (persisted via UserDefaults)
    var allTimePingsSent: Int
    var allTimeRepliesLost: Int
    var allTimeFastestResponse: Double
    var allTimeSlowestResponse: Double
    private var allTimeTotalLatency: Double
    private var allTimeSuccessCount: Int

    var allTimeAvgResponse: Double {
        allTimeSuccessCount > 0 ? allTimeTotalLatency / Double(allTimeSuccessCount) : 0
    }

    var allTimePacketLossPercent: Double {
        allTimePingsSent > 0 ? Double(allTimeRepliesLost) / Double(allTimePingsSent) * 100 : 0
    }

    init() {
        let ud = UserDefaults.standard
        allTimePingsSent = ud.integer(forKey: DefaultsKeys.allTimePingsSent)
        allTimeRepliesLost = ud.integer(forKey: DefaultsKeys.allTimeRepliesLost)
        allTimeFastestResponse = ud.double(forKey: DefaultsKeys.allTimeFastestResponse)
        allTimeSlowestResponse = ud.double(forKey: DefaultsKeys.allTimeSlowestResponse)
        allTimeTotalLatency = ud.double(forKey: DefaultsKeys.allTimeTotalLatency)
        allTimeSuccessCount = ud.integer(forKey: DefaultsKeys.allTimeSuccessCount)
        if allTimeFastestResponse == 0 { allTimeFastestResponse = .infinity }
    }

    var isAlert: Bool {
        let latThreshold = UserDefaults.standard.double(forKey: DefaultsKeys.latencyThreshold)
        let lossThreshold = UserDefaults.standard.double(forKey: DefaultsKeys.packetLossThreshold)
        let effectiveLatThreshold = latThreshold > 0 ? latThreshold : 100
        let effectiveLossThreshold = lossThreshold > 0 ? lossThreshold : 10
        return (latency ?? .infinity) > effectiveLatThreshold || (packetLoss * 100) > effectiveLossThreshold
    }

    var displayText: String {
        if let latency {
            let latStr = String(Int(latency))
            let lossStr = String(Int(packetLoss * 100))
            return "\(latStr)ms (\(lossStr)%)"
        }
        return "...ms (0%)"
    }

    func start() {
        loopTask = Task {
            while !Task.isCancelled {
                await executePing()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    private func executePing() async {
        guard !isRunning else { return }
        isRunning = true

        let host = UserDefaults.standard.string(forKey: DefaultsKeys.pingHost) ?? "google.com"

        let result: Double? = await withCheckedContinuation { continuation in
            Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/sbin/ping")
                process.arguments = ["-c", "1", "-W", "1000", host]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                let timeoutWork = DispatchWorkItem { process.terminate() }
                DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeoutWork)

                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    timeoutWork.cancel()

                    if let output = String(data: data, encoding: .utf8) {
                        continuation.resume(returning: PingEngine.parseLatency(from: output))
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    timeoutWork.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }

        sessionPingsSent += 1
        allTimePingsSent += 1
        recentPings.append(PingRecord(timestamp: Date(), latency: result))
        pruneRecentPings()

        if let result {
            latency = result
            appendToBuffer(success: true)
            recordLatency(result)
        } else {
            latency = nil
            appendToBuffer(success: false)
            sessionRepliesLost += 1
            allTimeRepliesLost += 1
        }

        persistAllTimeStats()
        isRunning = false
    }

    private func recordLatency(_ ms: Double) {
        sessionTotalLatency += ms
        sessionSuccessCount += 1
        if ms < sessionFastestResponse { sessionFastestResponse = ms }
        if ms > sessionSlowestResponse { sessionSlowestResponse = ms }

        allTimeTotalLatency += ms
        allTimeSuccessCount += 1
        if ms < allTimeFastestResponse { allTimeFastestResponse = ms }
        if ms > allTimeSlowestResponse { allTimeSlowestResponse = ms }
    }

    func resetSessionStats() {
        sessionPingsSent = 0
        sessionRepliesLost = 0
        sessionFastestResponse = .infinity
        sessionSlowestResponse = 0
        sessionTotalLatency = 0
        sessionSuccessCount = 0
    }

    private func pruneRecentPings() {
        let cutoff = Date().addingTimeInterval(-Self.recentWindow)
        recentPings.removeAll { $0.timestamp < cutoff }
        recentEntries = recentPings
    }

    private func persistAllTimeStats() {
        let ud = UserDefaults.standard
        ud.set(allTimePingsSent, forKey: DefaultsKeys.allTimePingsSent)
        ud.set(allTimeRepliesLost, forKey: DefaultsKeys.allTimeRepliesLost)
        ud.set(allTimeFastestResponse == .infinity ? 0 : allTimeFastestResponse, forKey: DefaultsKeys.allTimeFastestResponse)
        ud.set(allTimeSlowestResponse, forKey: DefaultsKeys.allTimeSlowestResponse)
        ud.set(allTimeTotalLatency, forKey: DefaultsKeys.allTimeTotalLatency)
        ud.set(allTimeSuccessCount, forKey: DefaultsKeys.allTimeSuccessCount)
    }

    private func appendToBuffer(success: Bool) {
        buffer.append(success)
        if buffer.count > 10 {
            buffer.removeFirst()
        }
        packetLoss = buffer.isEmpty ? 0 : Double(buffer.filter { !$0 }.count) / Double(buffer.count)
    }

    nonisolated static func parseLatency(from output: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"time=(\d+\.?\d*)\s*ms"#),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return Double(output[range])
    }
}
