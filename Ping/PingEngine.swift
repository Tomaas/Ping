import Foundation
import Network

@Observable
@MainActor
final class PingEngine {
    var latency: Double?
    var packetLoss: Double = 0
    private var buffer: [Bool] = []
    private var isRunning = false
    private var loopTask: Task<Void, Never>?
    private var currentProcess: Process?
    private(set) var consecutiveFailures: Int = 0
    private var alertActive = false
    var isOffline = false
    private var pathMonitor: NWPathMonitor?
    private var persistCounter = 0

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
    var recentJitter: Double {
        let latencies = recentEntries.compactMap(\.latency)
        guard latencies.count > 1 else { return 0 }
        let mean = latencies.reduce(0, +) / Double(latencies.count)
        let variance = latencies.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(latencies.count)
        return variance.squareRoot()
    }
    var recentEntries: [PingRecord] = []

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

    var isAlert: Bool { alertActive }

    private static let hysteresisThreshold = 3

    func updateAlertState(success: Bool) {
        if !success {
            consecutiveFailures += 1
            if consecutiveFailures >= Self.hysteresisThreshold { alertActive = true }
        } else {
            consecutiveFailures = 0
            alertActive = false
        }
    }

    var displayText: String {
        if isOffline { return "Offline" }
        if let latency {
            let latStr = String(Int(latency))
            let lossStr = String(Int(packetLoss * 100))
            return "\(latStr)ms (\(lossStr)%)"
        }
        return "...ms (\(Int(packetLoss * 100))%)"
    }

    func start() {
        guard loopTask == nil else { return }
        startPathMonitor()
        loopTask = Task {
            while !Task.isCancelled {
                if !isOffline {
                    await executePing()
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        if let p = currentProcess, p.isRunning { p.terminate() }
        currentProcess = nil
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOffline = path.status != .satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "ping.pathmonitor"))
        pathMonitor = monitor
    }

    private func executePing() async {
        guard !isRunning else { return }
        isRunning = true

        let host = UserDefaults.standard.string(forKey: DefaultsKeys.pingHost) ?? "google.com"

        let process = Process()
        currentProcess = process

        let result: Double? = await withCheckedContinuation { continuation in
            Task.detached {
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

        currentProcess = nil

        sessionPingsSent += 1
        allTimePingsSent += 1
        recentPings.append(PingRecord(timestamp: Date(), latency: result))
        pruneRecentPings()

        if let result {
            latency = result
            appendToBuffer(success: true)
            updateAlertState(success: true)
            recordLatency(result)
        } else {
            latency = nil
            appendToBuffer(success: false)
            updateAlertState(success: false)
            sessionRepliesLost += 1
            allTimeRepliesLost += 1
        }

        persistCounter += 1
        if persistCounter >= 30 {
            persistAllTimeStats()
            persistCounter = 0
        }
        isRunning = false
    }

    func recordLatency(_ ms: Double) {
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

    func flush() {
        persistAllTimeStats()
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

    func appendToBuffer(success: Bool) {
        buffer.append(success)
        if buffer.count > 30 {
            buffer.removeFirst()
        }
        packetLoss = buffer.isEmpty ? 0 : Double(buffer.filter { !$0 }.count) / Double(buffer.count)
    }

    // swiftlint:disable:next force_try
    private nonisolated static let latencyRegex = try! NSRegularExpression(pattern: #"time=(\d+\.?\d*)\s*ms"#)

    nonisolated static func parseLatency(from output: String) -> Double? {
        guard let match = latencyRegex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return Double(output[range])
    }
}
