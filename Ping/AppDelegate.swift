import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let engine = PingEngine()
    private let speedMonitor = SpeedMonitor()
    private var speedStatusItem: NSStatusItem!
    private var speedView: StatusBarView!
    private var settingsPopover: NSPopover!
    private var statsPopover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.wantsLayer = true
        }

        settingsPopover = NSPopover()
        settingsPopover.contentViewController = NSHostingController(rootView: SettingsView(speedMonitor: speedMonitor))
        settingsPopover.behavior = .transient

        statsPopover = NSPopover()
        statsPopover.contentViewController = NSHostingController(rootView: StatisticsView(engine: engine))
        statsPopover.behavior = .transient

        speedStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        speedView = StatusBarView()
        if let button = speedStatusItem.button {
            speedView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(speedView)
            NSLayoutConstraint.activate([
                speedView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                speedView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                speedView.topAnchor.constraint(equalTo: button.topAnchor),
                speedView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
        }

        buildMenu()
        updateStatusItem()
        updateSpeedItem()
        startObserving()
        engine.start()
        if speedMonitor.isEnabled { speedMonitor.start() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.flush()
        engine.stop()
        speedMonitor.stop()
    }

    private func startObserving() {
        withObservationTracking {
            _ = engine.displayText
            _ = engine.isAlert
            _ = engine.isOffline
            _ = speedMonitor.uploadDisplay
            _ = speedMonitor.downloadDisplay
            _ = speedMonitor.isEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateStatusItem()
                self?.updateSpeedItem()
                self?.startObserving()
            }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        if engine.isAlert {
            button.title = "🔴 \(engine.displayText)"
        } else {
            button.title = engine.displayText
        }
    }

    private func updateSpeedItem() {
        speedStatusItem.isVisible = speedMonitor.isEnabled
        if speedMonitor.isEnabled {
            speedView.update(upload: speedMonitor.uploadDisplay, download: speedMonitor.downloadDisplay)
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let statsItem = NSMenuItem(title: "Statistics", action: #selector(openStatistics), keyEquivalent: "")
        statsItem.target = self
        menu.addItem(statsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Ping", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func openSettings() {
        guard let button = statusItem.button else { return }
        statsPopover.performClose(nil)
        if settingsPopover.isShown {
            settingsPopover.performClose(nil)
        } else {
            settingsPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func openStatistics() {
        guard let button = statusItem.button else { return }
        settingsPopover.performClose(nil)
        if statsPopover.isShown {
            statsPopover.performClose(nil)
        } else {
            statsPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
