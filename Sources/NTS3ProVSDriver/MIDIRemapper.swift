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
    private var outputPort = MIDIPortRef()
    private var destination = MIDIEndpointRef()
    private var connectedSources = Set<MIDIEndpointRef>()
    private var hasReportedNoMatch = false
    private var hasReportedNoDestination = false
    private var flushTimer: DispatchSourceTimer?

    init(
        configuration: Configuration,
        transformer: MIDITransformer? = nil,
        packetHandler: (([UInt8]) -> Void)? = nil,
        statusHandler: ((String) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.transformer = transformer ?? NTS3MappingTransformer(
            outputChannel: configuration.outputChannel,
            experimentalOptions: configuration.experimentalOptions
        )
        self.packetHandler = packetHandler
        self.statusHandler = statusHandler
    }

    func start() throws {
        try createClient()
        try createOutputPort()
        try createInputPort()
        startFlushTimer()

        reportStatus("MIDI destination filter: \(configuration.outputNameFilter)")
        if configuration.quiet {
            reportStatus("Forwarding MIDI without per-message logging.")
        } else {
            reportStatus("Remapping MIDI and logging decoded input messages.")
        }
        reportStatus("Output channel: \(configuration.outputChannel)")
        connectMatchingDestination()
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
        if outputPort != 0 {
            MIDIPortDispose(outputPort)
            outputPort = 0
        }
        destination = 0
        if client != 0 {
            MIDIClientDispose(client)
            client = 0
        }
    }

    func send(messages: [MIDICCMessage]) {
        outputQueue.async { [weak self] in
            guard let self, self.destination != 0 else {
                return
            }

            for message in messages {
                self.send(packetBytes: message.bytes)
            }
        }
    }

    func send(packetBytesList: [[UInt8]]) {
        outputQueue.async { [weak self] in
            guard let self, self.destination != 0 else {
                return
            }

            for bytes in packetBytesList {
                self.send(packetBytes: bytes)
            }
        }
    }

    private func createClient() throws {
        let status = MIDIClientCreateWithBlock(configuration.clientName as CFString, &client) { [weak self] notificationPointer in
            self?.handleMIDINotification(notificationPointer)
        }
        try checkMIDIStatus(status, "MIDIClientCreateWithBlock")
    }

    private func createOutputPort() throws {
        let status = MIDIOutputPortCreate(client, "NTS-3 Pro VS Mini Output" as CFString, &outputPort)
        try checkMIDIStatus(status, "MIDIOutputPortCreate")
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
                self?.connectMatchingDestination()
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
            guard source != 0 else {
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
            return true
        }
        return name.localizedCaseInsensitiveContains(configuration.inputNameFilter)
    }

    private func connectMatchingDestination() {
        let destinationCount = MIDIGetNumberOfDestinations()

        for index in 0..<destinationCount {
            let candidate = MIDIGetDestination(index)
            guard candidate != 0 else {
                continue
            }

            let name = midiDisplayName(candidate)
            guard name.localizedCaseInsensitiveContains(configuration.outputNameFilter) else {
                continue
            }

            if destination != candidate {
                destination = candidate
                hasReportedNoDestination = false
                reportStatus("Connected destination: \(midiEndpointSummary(candidate))")
            }
            return
        }

        destination = 0
        if !hasReportedNoDestination {
            hasReportedNoDestination = true
            reportStatus("No MIDI destination matched \"\(configuration.outputNameFilter)\". Waiting for it to appear.")
            reportStatus("Run with --list to inspect CoreMIDI destination names.")
        }
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
        guard destination != 0 else {
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
        guard outputPort != 0, destination != 0 else {
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

            let status = MIDISend(outputPort, destination, &packetList)
            if status != noErr {
                fputs("MIDISend failed with OSStatus \(status)\n", stderr)
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
