import AppKit
import SwiftUI

private var retainedAppDelegate: MenuBarAppDelegate?

func runMIDIWatchWindow(configuration: Configuration) {
    let app = NSApplication.shared
    let delegate = MenuBarAppDelegate(configuration: configuration)
    retainedAppDelegate = delegate

    app.setActivationPolicy(.accessory)
    app.delegate = delegate
    app.run()
}

private final class MenuBarAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model: MappingDebugViewModel
    private var statusItem: NSStatusItem?
    private var debugWindow: NSWindow?
    private var startItem: NSMenuItem?
    private var stopItem: NSMenuItem?

    init(configuration: Configuration) {
        model = MappingDebugViewModel(configuration: configuration)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        model.startBridge()
        updateBridgeMenuItems()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stopBridge()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateBridgeMenuItems()
    }

    private func installStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "NTS-3 Pro VS Mini Driver") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "NTS-3"
            }
            button.toolTip = "NTS-3 Pro VS Mini Driver"
        }

        let menu = NSMenu()
        menu.delegate = self

        let debugItem = NSMenuItem(title: "Debug", action: #selector(openDebugWindow), keyEquivalent: "")
        debugItem.target = self
        menu.addItem(debugItem)

        menu.addItem(.separator())

        let startItem = NSMenuItem(title: "Restart", action: #selector(startOrRestartBridge), keyEquivalent: "")
        startItem.target = self
        menu.addItem(startItem)
        self.startItem = startItem

        let stopItem = NSMenuItem(title: "Stop", action: #selector(stopBridge), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)
        self.stopItem = stopItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.statusItem = statusItem
    }

    @objc private func openDebugWindow() {
        let window = debugWindow ?? makeDebugWindow()
        debugWindow = window

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func makeDebugWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "Pro VS Mini Driver Debug"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MappingDebugView(model: model))
        return window
    }

    @objc private func startOrRestartBridge() {
        model.restartBridge()
        updateBridgeMenuItems()
    }

    @objc private func stopBridge() {
        model.stopBridge()
        updateBridgeMenuItems()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func updateBridgeMenuItems() {
        startItem?.title = model.isRunning ? "Restart" : "Start"
        stopItem?.isEnabled = model.isRunning
    }
}
