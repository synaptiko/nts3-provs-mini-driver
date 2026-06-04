import Foundation

final class MappingDebugViewModel: ObservableObject {
    private static let midiLearnPulseValues = [2_173, 8_291, 14_237, 8_113]
    private static let midiLearnPulseInterval: TimeInterval = 0.05
    private static let midiLearnPulseCount = 40

    @Published var inputNameFilter: String
    @Published var virtualSourceName: String
    @Published var statusMessages: [String] = []
    @Published var isRunning = false
    @Published var startupError: String?
    @Published var mappingState: NTS3MappingSnapshot
    @Published var activeMIDILearnTargetID: String?

    private let baseConfiguration: Configuration
    private var remapper: MIDIRemapper?
    private var transformer: NTS3MappingTransformer?
    private var midiLearnTimer: DispatchSourceTimer?

    init(configuration: Configuration) {
        baseConfiguration = configuration
        inputNameFilter = configuration.inputNameFilter
        virtualSourceName = configuration.virtualSourceName
        mappingState = .initial(outputMode: configuration.outputMode)
    }

    deinit {
        stopBridge()
    }

    func startBridge() {
        stopBridge()

        var configuration = baseConfiguration
        configuration.inputNameFilter = inputNameFilter
        configuration.virtualSourceName = virtualSourceName
        configuration.quiet = true

        let transformer = NTS3MappingTransformer(outputMode: configuration.outputMode) { [weak self] snapshot in
            DispatchQueue.main.async {
                self?.mappingState = snapshot
            }
        }
        self.transformer = transformer

        let remapper = MIDIRemapper(
            configuration: configuration,
            transformer: transformer,
            statusHandler: { [weak self] message in
                DispatchQueue.main.async {
                    self?.appendStatus(message)
                }
            }
        )

        do {
            try remapper.start()
            self.remapper = remapper
            isRunning = true
            startupError = nil
        } catch {
            isRunning = false
            startupError = String(describing: error)
            appendStatus("Startup failed: \(error)")
        }
    }

    func stopBridge() {
        stopMIDILearn()
        remapper?.stop()
        remapper = nil
        transformer = nil
        isRunning = false
    }

    func restartBridge() {
        startBridge()
    }

    func appendStatusForUI(_ message: String) {
        appendStatus(message)
    }

    func toggleMIDILearn(for target: NTS3MappingOutputID) {
        if activeMIDILearnTargetID == target.id {
            stopMIDILearn()
        } else {
            startMIDILearn(for: target)
        }
    }

    func stopMIDILearn() {
        midiLearnTimer?.cancel()
        midiLearnTimer = nil
        transformer?.setMIDILearnSoloTarget(nil)
        activeMIDILearnTargetID = nil
    }

    func startMIDILearn(for target: NTS3MappingOutputID) {
        guard isRunning, remapper != nil else {
            appendStatus("Start the bridge before MIDI Learn.")
            return
        }

        stopMIDILearn()
        activeMIDILearnTargetID = target.id
        transformer?.setMIDILearnSoloTarget(target)
        appendStatus("MIDI Learn: \(target.displayTitle) \(target.ccText)")
        sendMIDILearnPulse(for: target, tick: 0)

        var tick = 1
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + Self.midiLearnPulseInterval,
            repeating: Self.midiLearnPulseInterval,
            leeway: .milliseconds(5)
        )
        timer.setEventHandler { [weak self] in
            guard let self, self.activeMIDILearnTargetID == target.id else {
                return
            }

            guard tick < Self.midiLearnPulseCount else {
                self.stopMIDILearn()
                return
            }

            self.sendMIDILearnPulse(for: target, tick: tick)
            tick += 1
        }
        midiLearnTimer = timer
        timer.resume()
    }

    private func sendMIDILearnPulse(for target: NTS3MappingOutputID, tick: Int) {
        let combinedValue = Self.midiLearnPulseValues[tick % Self.midiLearnPulseValues.count]
        let value = NTS3CC14Value(combined: combinedValue)
        let messages = target.messages(value: value, channel: 1, outputMode: baseConfiguration.outputMode)
        remapper?.send(messages: messages)
    }

    private func appendStatus(_ message: String) {
        statusMessages.append(message)
        if statusMessages.count > 8 {
            statusMessages.removeFirst(statusMessages.count - 8)
        }
    }
}
