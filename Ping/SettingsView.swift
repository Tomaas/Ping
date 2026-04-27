import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("pingHost") private var host = "google.com"
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("latencyThreshold") private var latencyThreshold = 100.0
    @AppStorage("packetLossThreshold") private var packetLossThreshold = 10.0

    var body: some View {
        Form {
            Section("Ping") {
                TextField("Host", text: $host)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Alert Thresholds") {
                HStack {
                    Text("Latency")
                    Spacer()
                    TextField("ms", value: $latencyThreshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("ms")
                }
                HStack {
                    Text("Packet Loss")
                    Spacer()
                    TextField("%", value: $packetLossThreshold, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("%")
                }
            }

            Section("System") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .padding()
    }
}
