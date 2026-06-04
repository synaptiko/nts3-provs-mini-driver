import Foundation

final class MappingDebugViewModel: ObservableObject {
    @Published var inputNameFilter: String
    @Published var outputNameFilter: String
    @Published var statusMessages: [String] = []
    @Published var isRunning = false
    @Published var startupError: String?
    @Published var mappingState: ProVSMappingSnapshot

    private let baseConfiguration: Configuration
    private var remapper: MIDIRemapper?
    private var transformer: NTS3MappingTransformer?

    init(configuration: Configuration) {
        baseConfiguration = configuration
        inputNameFilter = configuration.inputNameFilter
        outputNameFilter = configuration.outputNameFilter
        mappingState = .initial(
            outputChannel: configuration.outputChannel,
            experimentalOptions: configuration.experimentalOptions
        )
    }

    deinit {
        stopBridge()
    }

    func startBridge() {
        stopBridge()

        var configuration = baseConfiguration
        configuration.inputNameFilter = inputNameFilter
        configuration.outputNameFilter = outputNameFilter
        configuration.quiet = true

        let transformer = NTS3MappingTransformer(
            outputChannel: configuration.outputChannel,
            experimentalOptions: configuration.experimentalOptions
        ) { [weak self] snapshot in
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

    func select(bank: MappingBank) {
        guard let transformer else {
            return
        }

        remapper?.send(packetBytesList: transformer.select(bank: bank))
    }

    func setValue(bank: MappingBank, axis: NTS3ControlAxis, midiValue: Int) {
        guard let transformer else {
            return
        }

        let value = NTS3CC14Value(midi7BitValue: midiValue)
        remapper?.send(packetBytesList: transformer.setValue(bank: bank, axis: axis, value: value))
    }

    func setXY(bank: MappingBank, normalizedX: Double, normalizedY: Double) {
        guard let transformer else {
            return
        }

        let x = NTS3CC14Value(normalized: normalizedX)
        let y = NTS3CC14Value(normalized: normalizedY)
        remapper?.send(packetBytesList: transformer.setXY(bank: bank, x: x, y: y))
    }

    private func appendStatus(_ message: String) {
        statusMessages.append(message)
        if statusMessages.count > 8 {
            statusMessages.removeFirst(statusMessages.count - 8)
        }
    }
}
