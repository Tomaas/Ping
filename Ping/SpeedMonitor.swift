import Foundation
import Darwin

struct InterfaceCounters {
    var bytesSent: UInt32
    var bytesReceived: UInt32
}

@Observable
@MainActor
final class SpeedMonitor {
    var uploadBytesPerSecond: Double = 0
    var downloadBytesPerSecond: Double = 0
    var isEnabled: Bool {
        didSet {
            if isEnabled {
                start()
            } else {
                stop()
            }
            UserDefaults.standard.set(isEnabled, forKey: DefaultsKeys.showSpeed)
        }
    }

    var uploadDisplay: String { Self.formatSpeed(uploadBytesPerSecond) }
    var downloadDisplay: String { Self.formatSpeed(downloadBytesPerSecond) }

    private var previousCounters: [String: InterfaceCounters] = [:]
    private var previousTimestamp: CFAbsoluteTime = 0
    private var isFirstReading = true
    private var loopTask: Task<Void, Never>?

    private static nonisolated let excludedPrefixes = ["lo", "awdl", "llw", "bridge", "vmnet", "utun"]

    init() {
        isEnabled = UserDefaults.standard.object(forKey: DefaultsKeys.showSpeed) == nil
            ? true
            : UserDefaults.standard.bool(forKey: DefaultsKeys.showSpeed)
    }

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task {
            while !Task.isCancelled {
                sample()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        isFirstReading = true
        previousCounters = [:]
    }

    private func sample() {
        let now = CFAbsoluteTimeGetCurrent()
        let current = Self.readByteCounters()

        if isFirstReading {
            previousCounters = current
            previousTimestamp = now
            isFirstReading = false
            return
        }

        let elapsed = now - previousTimestamp
        guard elapsed > 0 else { return }

        let (sent, received) = Self.computeDeltas(
            previous: previousCounters,
            current: current,
            elapsed: elapsed
        )

        uploadBytesPerSecond = sent
        downloadBytesPerSecond = received

        previousCounters = current
        previousTimestamp = now
    }

    nonisolated static func computeDeltas(
        previous: [String: InterfaceCounters],
        current: [String: InterfaceCounters],
        elapsed: TimeInterval
    ) -> (sent: Double, received: Double) {
        var totalSent: UInt64 = 0
        var totalReceived: UInt64 = 0

        for (name, cur) in current {
            guard let prev = previous[name] else { continue }

            let sentDelta: UInt64 = if cur.bytesSent >= prev.bytesSent {
                UInt64(cur.bytesSent) - UInt64(prev.bytesSent)
            } else {
                UInt64(UInt32.max) - UInt64(prev.bytesSent) + UInt64(cur.bytesSent) + 1
            }

            let recvDelta: UInt64 = if cur.bytesReceived >= prev.bytesReceived {
                UInt64(cur.bytesReceived) - UInt64(prev.bytesReceived)
            } else {
                UInt64(UInt32.max) - UInt64(prev.bytesReceived) + UInt64(cur.bytesReceived) + 1
            }

            totalSent += sentDelta
            totalReceived += recvDelta
        }

        return (
            sent: Double(totalSent) / elapsed,
            received: Double(totalReceived) / elapsed
        )
    }

    nonisolated static func readByteCounters() -> [String: InterfaceCounters] {
        var result: [String: InterfaceCounters] = [:]
        var ifaddrsPtr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddrsPtr) == 0, let firstAddr = ifaddrsPtr else {
            return result
        }
        defer { freeifaddrs(ifaddrsPtr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = cursor {
            defer { cursor = addr.pointee.ifa_next }

            guard addr.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) else { continue }

            let flags = Int32(addr.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0 else { continue }

            let name = String(cString: addr.pointee.ifa_name)
            guard !excludedPrefixes.contains(where: { name.hasPrefix($0) }) else { continue }

            guard let data = addr.pointee.ifa_data else { continue }
            let networkData = data.assumingMemoryBound(to: if_data.self).pointee

            result[name] = InterfaceCounters(
                bytesSent: networkData.ifi_obytes,
                bytesReceived: networkData.ifi_ibytes
            )
        }

        return result
    }

    nonisolated static func formatSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond < 1 { return "0 B/s" }
        if bytesPerSecond < 1000 { return "\(Int(bytesPerSecond)) B/s" }
        if bytesPerSecond < 1_000_000 { return "\(Int(bytesPerSecond / 1000)) KB/s" }
        if bytesPerSecond < 1_000_000_000 { return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000) }
        return String(format: "%.1f GB/s", bytesPerSecond / 1_000_000_000)
    }
}
