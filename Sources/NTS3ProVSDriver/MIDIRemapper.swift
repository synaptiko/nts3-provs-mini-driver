import CoreMIDI
import Foundation

final class MIDIRemapper {
    private static let flushInterval: TimeInterval = 0.008

    private let configuration: Configuration
    private let transformer: MIDITransformer
    private let packetHandler: (([UInt8]) -> Void)?
    private let statusHandler: ((String) -> Void)?
    private let outputQueue = DispatchQueue(label: "NTS-3 Pro VS Driver Output")
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var virtualSource = MIDIEndpointRef()
    private var connectedSources = Set<MIDIEndpointRef>()
    private var hasReportedNoMatch = false
    private var flushTimer: DispatchSourceTimer?

    init(
        configuration: Configuration,
        transformer: MIDITransformer? = nil,
        packetHandler: (([UInt8]) -> Void)? = nil,
        statusHandler: ((String) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.transformer = transformer ?? NTS3MappingTransformer(outputMode: configuration.outputMode)
        self.packetHandler = packetHandler
        self.statusHandler = statusHandler
    }

    func start() throws {
        try createClient()
        try createVirtualSource()
        try createInputPort()
        startFlushTimer()

        reportStatus("Virtual MIDI source: \(configuration.virtualSourceName)")
        if configuration.quiet {
            reportStatus("Forwarding MIDI without per-message logging.")
        } else {
            reportStatus("Remapping MIDI and logging decoded input messages.")
        }
        reportStatus("Output mode: \(configuration.outputMode.rawValue)")
        connectMatchingSources()
        if statusHandler == nil {
            print("Press Ctrl-C to stop.")
        }
    }

    func stop() {
        stopFlushTimer()
        flushPendingOutputs()

        for source in connectedSources {
            MIDIPortDisconnectSource(inputPort, source)
        }
        connectedSources.removeAll()

        if inputPort != 0 {
            MIDIPortDispose(inputPort)
            inputPort = 0
        }
        if virtualSource != 0 {
            MIDIEndpointDispose(virtualSource)
            virtualSource = 0
        }
        if client != 0 {
            MIDIClientDispose(client)
            client = 0
        }
    }

    func send(messages: [MIDICCMessage]) {
        outputQueue.async { [weak self] in
            guard let self, self.virtualSource != 0 else {
                return
            }

            for message in messages {
                self.send(packetBytes: message.bytes)
            }
        }
    }

    private func createClient() throws {
        let status = MIDIClientCreateWithBlock(configuration.clientName as CFString, &client) { [weak self] notificationPointer in
            self?.handleMIDINotification(notificationPointer)
        }
        try checkMIDIStatus(status, "MIDIClientCreateWithBlock")
    }

    private func createVirtualSource() throws {
        let status = MIDISourceCreate(client, configuration.virtualSourceName as CFString, &virtualSource)
        try checkMIDIStatus(status, "MIDISourceCreate")
    }

    private func createInputPort() throws {
        let status = MIDIInputPortCreateWithBlock(client, "NTS-3 Pro VS Driver Input" as CFString, &inputPort) { [weak self] packetList, sourceConnectionRefCon in
            self?.receive(packetList: packetList, sourceConnectionRefCon: sourceConnectionRefCon)
        }
        try checkMIDIStatus(status, "MIDIInputPortCreateWithBlock")
    }

    private func handleMIDINotification(_ notificationPointer: UnsafePointer<MIDINotification>) {
        let messageID = notificationPointer.pointee.messageID

        switch messageID {
        case .msgObjectAdded, .msgObjectRemoved, .msgSetupChanged:
            DispatchQueue.main.async { [weak self] in
                self?.connectMatchingSources()
            }
        default:
            break
        }
    }

    private func connectMatchingSources() {
        let sourceCount = MIDIGetNumberOfSources()
        var matchedAnySource = false

        for index in 0..<sourceCount {
            let source = MIDIGetSource(index)
            guard source != 0, source != virtualSource else {
                continue
            }

            let name = midiDisplayName(source)
            guard shouldConnect(toSourceNamed: name) else {
                continue
            }

            matchedAnySource = true

            guard !connectedSources.contains(source) else {
                continue
            }

            let status = MIDIPortConnectSource(inputPort, source, nil)
            if status == noErr {
                connectedSources.insert(source)
                reportStatus("Connected source: \(midiEndpointSummary(source))")
            } else {
                fputs("Could not connect source \(name): OSStatus \(status)\n", stderr)
            }
        }

        if !matchedAnySource && !hasReportedNoMatch {
            hasReportedNoMatch = true
            if configuration.connectAllSources {
                reportStatus("No MIDI sources are currently available. Waiting for devices.")
            } else {
                reportStatus("No MIDI source matched \"\(configuration.inputNameFilter)\". Waiting for it to appear.")
                reportStatus("Run with --list to inspect CoreMIDI source names, or --all to connect everything.")
            }
        }
    }

    private func shouldConnect(toSourceNamed name: String) -> Bool {
        if configuration.connectAllSources {
            return name != configuration.virtualSourceName
        }
        return name.localizedCaseInsensitiveContains(configuration.inputNameFilter)
    }

    private func receive(
        packetList: UnsafePointer<MIDIPacketList>,
        sourceConnectionRefCon: UnsafeMutableRawPointer?
    ) {
        forEachPacketBytes(in: packetList) { [weak self] bytes in
            guard let self else {
                return
            }

            for outputBytes in transformer.transform(packetBytes: bytes) {
                send(packetBytes: outputBytes)
            }

            packetHandler?(bytes)
        }
        flushPendingOutputs()

        guard !configuration.quiet else {
            return
        }

        log(packetList: packetList)
    }

    private func startFlushTimer() {
        stopFlushTimer()

        let timer = DispatchSource.makeTimerSource(queue: outputQueue)
        timer.schedule(
            deadline: .now() + Self.flushInterval,
            repeating: Self.flushInterval,
            leeway: .milliseconds(1)
        )
        timer.setEventHandler { [weak self] in
            self?.flushPendingOutputs()
        }
        flushTimer = timer
        timer.resume()
    }

    private func stopFlushTimer() {
        flushTimer?.cancel()
        flushTimer = nil
    }

    private func flushPendingOutputs() {
        guard virtualSource != 0 else {
            return
        }

        for outputBytes in transformer.flushPendingOutputs() {
            send(packetBytes: outputBytes)
        }
    }

    private func send(packetBytes bytes: [UInt8]) {
        guard !bytes.isEmpty else {
            return
        }

        var packetList = MIDIPacketList()
        let listSize = MemoryLayout<MIDIPacketList>.size

        bytes.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return
            }

            var packet = MIDIPacketListInit(&packetList)
            packet = MIDIPacketListAdd(&packetList, listSize, packet, 0, buffer.count, baseAddress)

            let status = MIDIReceived(virtualSource, &packetList)
            if status != noErr {
                fputs("MIDIReceived failed with OSStatus \(status)\n", stderr)
            }
        }
    }

    private func log(packetList: UnsafePointer<MIDIPacketList>) {
        forEachPacketBytes(in: packetList) { bytes in
            let descriptions = MIDIMessageDecoder.describe(
                packetBytes: bytes,
                showRealtime: configuration.showRealtime
            )

            for description in descriptions {
                print("[\(timestamp())] \(MIDIMessageDecoder.hexString(bytes))  \(description)")
            }
        }
    }

    private func forEachPacketBytes(
        in packetList: UnsafePointer<MIDIPacketList>,
        _ body: ([UInt8]) -> Void
    ) {
        guard let packetOffset = MemoryLayout<MIDIPacketList>.offset(of: \.packet) else {
            fputs("Could not calculate MIDIPacketList packet offset\n", stderr)
            return
        }

        var packetPointer = UnsafeMutableRawPointer(mutating: packetList)
            .advanced(by: packetOffset)
            .assumingMemoryBound(to: MIDIPacket.self)

        for _ in 0..<packetList.pointee.numPackets {
            let packet = packetPointer.pointee
            let bytes = withUnsafeBytes(of: packet.data) { rawBuffer in
                Array(rawBuffer.prefix(Int(packet.length)))
            }
            body(bytes)

            packetPointer = MIDIPacketNext(packetPointer)
        }
    }

    private func timestamp() -> String {
        let interval = Date().timeIntervalSince1970
        return String(format: "%.3f", interval)
    }

    private func reportStatus(_ message: String) {
        if let statusHandler {
            statusHandler(message)
        } else {
            print(message)
        }
    }
}
