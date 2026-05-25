import Foundation
import Testing
@testable import Ping

struct PingEngineTests {

    // MARK: - parseLatency

    @Test func parseLatency_standardOutput() {
        let output = "64 bytes from 142.250.74.46: icmp_seq=0 ttl=117 time=12.345 ms"
        #expect(PingEngine.parseLatency(from: output) == 12.345)
    }

    @Test func parseLatency_integerTime() {
        let output = "64 bytes from 1.1.1.1: icmp_seq=0 ttl=57 time=1 ms"
        #expect(PingEngine.parseLatency(from: output) == 1.0)
    }

    @Test func parseLatency_noMatch() {
        let output = "Request timeout for icmp_seq 0"
        #expect(PingEngine.parseLatency(from: output) == nil)
    }

    @Test func parseLatency_fullPingOutput() {
        let output = """
        PING google.com (142.250.74.46): 56 data bytes
        64 bytes from 142.250.74.46: icmp_seq=0 ttl=117 time=8.123 ms

        --- google.com ping statistics ---
        1 packets transmitted, 1 packets received, 0.0% packet loss
        round-trip min/avg/max/stddev = 8.123/8.123/8.123/0.000 ms
        """
        #expect(PingEngine.parseLatency(from: output) == 8.123)
    }

    @Test func parseLatency_emptyString() {
        #expect(PingEngine.parseLatency(from: "") == nil)
    }

    @Test func parseLatency_highLatency() {
        let output = "64 bytes from 8.8.8.8: icmp_seq=0 ttl=117 time=523.456 ms"
        #expect(PingEngine.parseLatency(from: output) == 523.456)
    }

    // MARK: - appendToBuffer

    @Test @MainActor func appendToBuffer_underCapacity() {
        let engine = PingEngine()
        engine.appendToBuffer(success: true)
        engine.appendToBuffer(success: true)
        engine.appendToBuffer(success: false)
        #expect(engine.packetLoss > 0.33 - 0.01 && engine.packetLoss < 0.33 + 0.01)
    }

    @Test @MainActor func appendToBuffer_atCapacity() {
        let engine = PingEngine()
        for _ in 0..<30 { engine.appendToBuffer(success: true) }
        #expect(engine.packetLoss == 0)
        engine.appendToBuffer(success: false)
        #expect(engine.packetLoss > 0) // 1/30
    }

    @Test @MainActor func appendToBuffer_fifoEviction() {
        let engine = PingEngine()
        engine.appendToBuffer(success: false)
        for _ in 0..<30 { engine.appendToBuffer(success: true) }
        // The initial failure should have been evicted
        #expect(engine.packetLoss == 0)
    }

    @Test @MainActor func appendToBuffer_allFailed() {
        let engine = PingEngine()
        for _ in 0..<10 { engine.appendToBuffer(success: false) }
        #expect(engine.packetLoss == 1.0)
    }

    // MARK: - displayText

    @Test @MainActor func displayText_withLatency() {
        let engine = PingEngine()
        engine.latency = 42.7
        #expect(engine.displayText == "42ms (0%)")
    }

    @Test @MainActor func displayText_withoutLatency() {
        let engine = PingEngine()
        engine.latency = nil
        #expect(engine.displayText == "...ms (0%)")
    }

    @Test @MainActor func displayText_offline() {
        let engine = PingEngine()
        engine.isOffline = true
        #expect(engine.displayText == "Offline")
    }

    @Test @MainActor func displayText_withLoss() {
        let engine = PingEngine()
        engine.latency = 15.0
        for _ in 0..<5 { engine.appendToBuffer(success: true) }
        for _ in 0..<5 { engine.appendToBuffer(success: false) }
        #expect(engine.displayText == "15ms (50%)")
    }

    // MARK: - recordLatency

    @Test @MainActor func recordLatency_updatesSessionStats() {
        let engine = PingEngine()
        engine.sessionPingsSent = 2
        engine.recordLatency(10.0)
        engine.recordLatency(20.0)
        #expect(engine.sessionAvgResponse == 15.0)
        #expect(engine.sessionFastestResponse == 10.0)
        #expect(engine.sessionSlowestResponse == 20.0)
    }

    @Test @MainActor func recordLatency_updatesAllTimeStats() {
        let ud = UserDefaults.standard
        for key in ["allTimePingsSent", "allTimeRepliesLost", "allTimeFastestResponse",
                     "allTimeSlowestResponse", "allTimeTotalLatency", "allTimeSuccessCount"] {
            ud.removeObject(forKey: key)
        }
        let engine = PingEngine()
        engine.recordLatency(5.0)
        engine.recordLatency(50.0)
        #expect(engine.allTimeAvgResponse == 27.5)
        #expect(engine.allTimeFastestResponse == 5.0)
        #expect(engine.allTimeSlowestResponse == 50.0)
    }

    // MARK: - resetSessionStats

    @Test @MainActor func resetSessionStats_clearsAll() {
        let engine = PingEngine()
        engine.sessionPingsSent = 100
        engine.sessionRepliesLost = 10
        engine.recordLatency(42.0)
        engine.resetSessionStats()
        #expect(engine.sessionPingsSent == 0)
        #expect(engine.sessionRepliesLost == 0)
        #expect(engine.sessionAvgResponse == 0)
        #expect(engine.sessionFastestResponse == .infinity)
        #expect(engine.sessionSlowestResponse == 0)
    }

    // MARK: - isAlert (hysteresis)

    @Test @MainActor func isAlert_noAlertInitially() {
        let engine = PingEngine()
        #expect(!engine.isAlert)
    }

    @Test @MainActor func isAlert_singleFailureNoAlert() {
        let engine = PingEngine()
        engine.updateAlertState(success: false)
        #expect(!engine.isAlert)
        #expect(engine.consecutiveFailures == 1)
    }

    @Test @MainActor func isAlert_threeFailuresTriggersAlert() {
        let engine = PingEngine()
        engine.updateAlertState(success: false)
        engine.updateAlertState(success: false)
        engine.updateAlertState(success: false)
        #expect(engine.isAlert)
        #expect(engine.consecutiveFailures == 3)
    }

    @Test @MainActor func isAlert_successClearsConsecutive() {
        let engine = PingEngine()
        engine.updateAlertState(success: false)
        engine.updateAlertState(success: false)
        engine.latency = 5.0
        engine.updateAlertState(success: true)
        #expect(!engine.isAlert)
        #expect(engine.consecutiveFailures == 0)
    }

    @Test @MainActor func isAlert_alertClearsOnSuccess() {
        let engine = PingEngine()
        // Trigger alert
        engine.updateAlertState(success: false)
        engine.updateAlertState(success: false)
        engine.updateAlertState(success: false)
        #expect(engine.isAlert)
        // Clear with success
        engine.latency = 5.0
        engine.updateAlertState(success: true)
        #expect(!engine.isAlert)
    }

    // MARK: - Jitter

    @Test @MainActor func recentJitter_emptyEntries() {
        let engine = PingEngine()
        #expect(engine.recentJitter == 0)
    }

    @Test @MainActor func recentJitter_singleEntry() {
        let engine = PingEngine()
        engine.recentEntries = [PingEngine.PingRecord(timestamp: Date(), latency: 10.0)]
        #expect(engine.recentJitter == 0)
    }

    @Test @MainActor func recentJitter_uniformLatency() {
        let engine = PingEngine()
        engine.recentEntries = (0..<10).map { _ in
            PingEngine.PingRecord(timestamp: Date(), latency: 50.0)
        }
        #expect(engine.recentJitter == 0)
    }

    @Test @MainActor func recentJitter_variableLatency() {
        let engine = PingEngine()
        engine.recentEntries = [
            PingEngine.PingRecord(timestamp: Date(), latency: 10.0),
            PingEngine.PingRecord(timestamp: Date(), latency: 20.0),
            PingEngine.PingRecord(timestamp: Date(), latency: 30.0),
        ]
        // mean = 20, variance = ((100 + 0 + 100) / 3) = 66.67, stddev ≈ 8.165
        #expect(engine.recentJitter > 8.16 && engine.recentJitter < 8.17)
    }

    @Test @MainActor func recentJitter_ignoresLostPackets() {
        let engine = PingEngine()
        engine.recentEntries = [
            PingEngine.PingRecord(timestamp: Date(), latency: 10.0),
            PingEngine.PingRecord(timestamp: Date(), latency: nil),
            PingEngine.PingRecord(timestamp: Date(), latency: 10.0),
        ]
        // Only two successful pings, both 10ms, jitter = 0
        #expect(engine.recentJitter == 0)
    }

    // MARK: - Recent stats

    @Test @MainActor func recentStats_empty() {
        let engine = PingEngine()
        #expect(engine.recentPingsSent == 0)
        #expect(engine.recentRepliesLost == 0)
        #expect(engine.recentPacketLossPercent == 0)
        #expect(engine.recentAvgResponse == 0)
    }

    @Test @MainActor func recentStats_withMixedResults() {
        let engine = PingEngine()
        engine.recentEntries = [
            PingEngine.PingRecord(timestamp: Date(), latency: 10.0),
            PingEngine.PingRecord(timestamp: Date(), latency: 20.0),
            PingEngine.PingRecord(timestamp: Date(), latency: nil),
        ]
        #expect(engine.recentPingsSent == 3)
        #expect(engine.recentRepliesLost == 1)
        #expect(engine.recentPacketLossPercent > 33.3 && engine.recentPacketLossPercent < 33.4)
        #expect(engine.recentAvgResponse == 15.0)
        #expect(engine.recentFastestResponse == 10.0)
        #expect(engine.recentSlowestResponse == 20.0)
    }

    // MARK: - Session packet loss

    @Test @MainActor func sessionPacketLoss_noSent() {
        let engine = PingEngine()
        #expect(engine.sessionPacketLossPercent == 0)
    }

    @Test @MainActor func sessionPacketLoss_withLoss() {
        let engine = PingEngine()
        engine.sessionPingsSent = 10
        engine.sessionRepliesLost = 3
        #expect(engine.sessionPacketLossPercent == 30.0)
    }

    // MARK: - All-time packet loss

    @Test @MainActor func allTimePacketLoss_withLoss() {
        let engine = PingEngine()
        engine.allTimePingsSent = 100
        engine.allTimeRepliesLost = 5
        #expect(engine.allTimePacketLossPercent == 5.0)
    }
}
