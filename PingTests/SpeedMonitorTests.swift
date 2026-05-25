import Testing
@testable import Ping

struct SpeedMonitorTests {

    // MARK: - formatSpeed

    @Test func formatSpeed_zero() {
        #expect(SpeedMonitor.formatSpeed(0) == "0 B/s")
    }

    @Test func formatSpeed_subByte() {
        #expect(SpeedMonitor.formatSpeed(0.5) == "0 B/s")
    }

    @Test func formatSpeed_bytes() {
        #expect(SpeedMonitor.formatSpeed(500) == "500 B/s")
    }

    @Test func formatSpeed_bytesUpperBound() {
        #expect(SpeedMonitor.formatSpeed(999) == "999 B/s")
    }

    @Test func formatSpeed_kilobytes() {
        #expect(SpeedMonitor.formatSpeed(1000) == "1 KB/s")
    }

    @Test func formatSpeed_kilobytesRounded() {
        #expect(SpeedMonitor.formatSpeed(1500) == "1 KB/s")
    }

    @Test func formatSpeed_megabytes() {
        #expect(SpeedMonitor.formatSpeed(1_500_000) == "1.5 MB/s")
    }

    @Test func formatSpeed_gigabytes() {
        #expect(SpeedMonitor.formatSpeed(1_500_000_000) == "1.5 GB/s")
    }

    // MARK: - readByteCounters

    @Test func readByteCounters_returnsNonEmpty() {
        let counters = SpeedMonitor.readByteCounters()
        #expect(!counters.isEmpty)
    }

    @Test func readByteCounters_excludesLoopback() {
        let counters = SpeedMonitor.readByteCounters()
        #expect(counters["lo0"] == nil)
    }

    // MARK: - computeDeltas

    @Test func computeDeltas_normalDelta() {
        let prev = ["en0": InterfaceCounters(bytesSent: 1000, bytesReceived: 2000)]
        let curr = ["en0": InterfaceCounters(bytesSent: 3000, bytesReceived: 6000)]
        let (sent, received) = SpeedMonitor.computeDeltas(previous: prev, current: curr, elapsed: 2.0)
        #expect(sent == 1000.0)
        #expect(received == 2000.0)
    }

    @Test func computeDeltas_zeroTraffic() {
        let counters = ["en0": InterfaceCounters(bytesSent: 5000, bytesReceived: 5000)]
        let (sent, received) = SpeedMonitor.computeDeltas(previous: counters, current: counters, elapsed: 2.0)
        #expect(sent == 0)
        #expect(received == 0)
    }

    @Test func computeDeltas_counterWrap() {
        let prev = ["en0": InterfaceCounters(bytesSent: UInt32.max - 999, bytesReceived: UInt32.max - 499)]
        let curr = ["en0": InterfaceCounters(bytesSent: 1000, bytesReceived: 500)]
        let (sent, received) = SpeedMonitor.computeDeltas(previous: prev, current: curr, elapsed: 1.0)
        #expect(sent == 2000.0)
        #expect(received == 1000.0)
    }

    @Test func computeDeltas_newInterfaceIgnored() {
        let prev: [String: InterfaceCounters] = [:]
        let curr = ["en0": InterfaceCounters(bytesSent: 50000, bytesReceived: 80000)]
        let (sent, received) = SpeedMonitor.computeDeltas(previous: prev, current: curr, elapsed: 1.0)
        #expect(sent == 0)
        #expect(received == 0)
    }

    @Test func computeDeltas_disappearedInterfaceIgnored() {
        let prev = ["en0": InterfaceCounters(bytesSent: 1000, bytesReceived: 2000)]
        let curr: [String: InterfaceCounters] = [:]
        let (sent, received) = SpeedMonitor.computeDeltas(previous: prev, current: curr, elapsed: 1.0)
        #expect(sent == 0)
        #expect(received == 0)
    }
}
