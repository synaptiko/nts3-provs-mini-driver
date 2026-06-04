import Foundation

final class MIDIWatchViewModel: ObservableObject {
    @Published var inputNameFilter: String
    @Published var virtualSourceName: String
    @Published var statusMessages: [String] = []
    @Published var watches: [CCWatch] = []
    @Published var states: [UUID: CCWatchRuntimeState] = [:]
    @Published var isRunning = false
    @Published var startupError: String?

    private let baseConfiguration: Configuration
    private let parser = MIDIControlChangeParser()
    private let startDate = Date()
    private var remapper: MIDIRemapper?

    private let userDefaultsKey = "NTS3ProVSDriver.CCWatches"

    init(configuration: Configuration) {
        baseConfiguration = configuration
        inputNameFilter = configuration.inputNameFilter
        virtualSourceName = configuration.virtualSourceName
        watches = Self.loadWatches(defaultsKey: userDefaultsKey)
        if watches.isEmpty {
            watches = CCWatch.nts3Defaults
            saveWatches()
        }
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

        let remapper = MIDIRemapper(
            configuration: configuration,
            packetHandler: { [weak self] bytes in
                DispatchQueue.main.async {
                    self?.handlePacketBytes(bytes)
                }
            },
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
        isRunning = false
    }

    func restartBridge() {
        startBridge()
    }

    func addWatch(_ watch: CCWatch) {
        watches.append(watch)
        sortWatches()
        saveWatches()
    }

    func updateWatch(_ watch: CCWatch) {
        guard let index = watches.firstIndex(where: { $0.id == watch.id }) else {
            return
        }
        watches[index] = watch
        sortWatches()
        saveWatches()
    }

    func removeWatch(_ watch: CCWatch) {
        watches.removeAll { $0.id == watch.id }
        states[watch.id] = nil
        saveWatches()
    }

    func clearHistory(for watch: CCWatch) {
        states[watch.id]?.history.removeAll()
    }

    func loadDefaults() {
        watches = CCWatch.nts3Defaults
        states.removeAll()
        saveWatches()
    }

    func resetValues() {
        states.removeAll()
    }

    func state(for watch: CCWatch) -> CCWatchRuntimeState {
        states[watch.id] ?? CCWatchRuntimeState()
    }

    private func handlePacketBytes(_ bytes: [UInt8]) {
        let changes = parser.parse(packetBytes: bytes)
        for change in changes {
            record(change)
        }
    }

    private func record(_ change: MIDIControlChange) {
        let elapsed = Date().timeIntervalSince(startDate)

        for watch in watches where watch.matches(controller: change.controller) {
            var state = states[watch.id] ?? CCWatchRuntimeState()

            switch watch.mode {
            case .msb:
                state.latestMSB = change.value
                state.latestLSB = nil
            case .lsb:
                state.latestMSB = nil
                state.latestLSB = change.value
            case .both:
                if watch.msbCC == change.controller {
                    state.latestMSB = change.value
                }
                if watch.lsbCC == change.controller {
                    state.latestLSB = change.value
                }
            }

            state.latestChannel = change.channel
            state.latestController = change.controller
            state.latestRawValue = change.value
            state.latestElapsed = elapsed

            let combinedValue = state.latestMSB.flatMap { msb in
                state.latestLSB.map { lsb in
                    (msb << 7) | lsb
                }
            }

            let displayValue: String
            if let combinedValue {
                displayValue = "\(combinedValue)"
            } else {
                displayValue = state.latestValueText
            }

            state.history.append(
                CCValueEvent(
                    elapsed: elapsed,
                    channel: change.channel,
                    controller: change.controller,
                    rawValue: change.value,
                    msbValue: state.latestMSB,
                    lsbValue: state.latestLSB,
                    combinedValue: combinedValue,
                    displayValue: displayValue
                )
            )

            states[watch.id] = state
        }
    }

    private func appendStatus(_ message: String) {
        statusMessages.append(message)
        if statusMessages.count > 8 {
            statusMessages.removeFirst(statusMessages.count - 8)
        }
    }

    private func sortWatches() {
        watches.sort { lhs, rhs in
            let lhsCC = lhs.msbCC ?? lhs.lsbCC ?? 0
            let rhsCC = rhs.msbCC ?? rhs.lsbCC ?? 0
            if lhsCC == rhsCC {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return lhsCC < rhsCC
        }
    }

    private func saveWatches() {
        guard let data = try? JSONEncoder().encode(watches) else {
            return
        }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    private static func loadWatches(defaultsKey: String) -> [CCWatch] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let watches = try? JSONDecoder().decode([CCWatch].self, from: data) else {
            return []
        }
        return watches
    }
}
