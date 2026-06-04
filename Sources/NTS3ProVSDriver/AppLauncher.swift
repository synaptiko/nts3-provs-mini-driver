import AppKit
import Carbon.HIToolbox
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
    private let hotKeySignature = OSType(0x4E_54_53_33)
    private let hotKeyID = UInt32(1)

    private let model: MappingDebugViewModel
    private var statusItem: NSStatusItem?
    private var debugWindow: NSWindow?
    private var learnPanel: NSPanel?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var startItem: NSMenuItem?
    private var stopItem: NSMenuItem?

    init(configuration: Configuration) {
        model = MappingDebugViewModel(configuration: configuration)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        registerLearnHotKey()
        model.startBridge()
        updateBridgeMenuItems()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterLearnHotKey()
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

        let learnItem = NSMenuItem(title: "Learn MIDI", action: #selector(showLearnPanel), keyEquivalent: "")
        learnItem.target = self
        menu.addItem(learnItem)

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

        center(window)
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

        window.title = "NTS-3 Mapping Debug"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MappingDebugView(model: model))
        return window
    }

    @objc private func showLearnPanel() {
        let panel = learnPanel ?? makeLearnPanel()
        learnPanel = panel

        center(panel)
        panel.orderFrontRegardless()
    }

    private func makeLearnPanel() -> NSPanel {
        let panel = FloatingMIDILearnPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 310),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "Learn MIDI"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(
            rootView: MIDILearnPopupView(model: model) { [weak self] target in
                self?.selectMIDILearnTarget(target)
            }
        )

        return panel
    }

    private func selectMIDILearnTarget(_ target: NTS3MappingOutputID) {
        guard model.isRunning else {
            return
        }

        learnPanel?.orderOut(nil)
        model.startMIDILearn(for: target)
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

    private func center(_ window: NSWindow) {
        window.center()
    }

    private func registerLearnHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else {
                return noErr
            }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else {
                return status
            }

            let delegate = Unmanaged<MenuBarAppDelegate>
                .fromOpaque(userData)
                .takeUnretainedValue()

            guard hotKeyID.signature == delegate.hotKeySignature,
                  hotKeyID.id == delegate.hotKeyID else {
                return noErr
            }

            delegate.showLearnPanel()
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        let carbonHotKeyID = EventHotKeyID(signature: hotKeySignature, id: hotKeyID)
        let modifiers = UInt32(cmdKey | optionKey)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_L),
            modifiers,
            carbonHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            model.appendStatusForUI("Could not register Cmd+Option+L hotkey: OSStatus \(status)")
        }
    }

    private func unregisterLearnHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}

private final class FloatingMIDILearnPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }
}
