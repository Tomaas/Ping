import SwiftUI

struct StatisticsView: View {
    var engine: PingEngine
    @State private var tab = 0

    private var host: String {
        UserDefaults.standard.string(forKey: "pingHost") ?? "google.com"
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Ping stats for \(host)")
                .font(.headline)

            Picker("", selection: $tab) {
                Text("5 Min").tag(0)
                Text("Session").tag(1)
                Text("All Time").tag(2)
            }
            .pickerStyle(.segmented)

            Grid(alignment: .leading, verticalSpacing: 8) {
                statRow("Pings Sent", value: formatInt(pings))
                statRow("Replies Lost", value: formatInt(lost))
                statRow("Packet Loss Percentage", value: formatPercent(lossPercent))
                statRow("Average Response (ms)", value: formatMs(avg))
                statRow("Fastest Response (ms)", value: formatMs(fastest))
                statRow("Slowest Response (ms)", value: formatMs(slowest))
            }
            .padding(.vertical, 4)

            if tab == 1 {
                Button("Reset Session Stats") {
                    engine.resetSessionStats()
                }
            }
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .padding()
    }

    @ViewBuilder
    private func statRow(_ label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
    }

    // MARK: - Data source switching

    private var pings: Int {
        switch tab {
        case 0: engine.recentPingsSent
        case 1: engine.sessionPingsSent
        default: engine.allTimePingsSent
        }
    }
    private var lost: Int {
        switch tab {
        case 0: engine.recentRepliesLost
        case 1: engine.sessionRepliesLost
        default: engine.allTimeRepliesLost
        }
    }
    private var lossPercent: Double {
        switch tab {
        case 0: engine.recentPacketLossPercent
        case 1: engine.sessionPacketLossPercent
        default: engine.allTimePacketLossPercent
        }
    }
    private var avg: Double {
        switch tab {
        case 0: engine.recentAvgResponse
        case 1: engine.sessionAvgResponse
        default: engine.allTimeAvgResponse
        }
    }
    private var fastest: Double {
        let v: Double = switch tab {
        case 0: engine.recentFastestResponse
        case 1: engine.sessionFastestResponse
        default: engine.allTimeFastestResponse
        }
        return v == .infinity ? 0 : v
    }
    private var slowest: Double {
        switch tab {
        case 0: engine.recentSlowestResponse
        case 1: engine.sessionSlowestResponse
        default: engine.allTimeSlowestResponse
        }
    }

    // MARK: - Formatting

    private func formatInt(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func formatPercent(_ value: Double) -> String {
        String(format: "%.2f%%", value)
    }

    private func formatMs(_ value: Double) -> String {
        value == 0 ? "-" : String(format: "%.2f", value)
    }
}
