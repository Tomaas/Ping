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
}
