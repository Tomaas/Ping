import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let engine = PingEngine()
    private var settingsPopover: NSPopover!
    private var statsPopover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.wantsLayer = true
        }

        settingsPopover = NSPopover()
        settingsPopover.contentViewController = NSHostingController(rootView: SettingsView())
        settingsPopover.behavior = .transient

        statsPopover = NSPopover()
        statsPopover.contentViewController = NSHostingController(rootView: StatisticsView(engine: engine))
        statsPopover.behavior = .transient

        buildMenu()
        updateStatusItem()
        startObserving()
        engine.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.stop()
    }

    private func startObserving() {
        withObservationTracking {
            _ = engine.displayText
            _ = engine.isAlert
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateStatusItem()
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
