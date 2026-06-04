import Foundation

enum NTS3ControlAxis: String, CaseIterable, Equatable, Hashable, Identifiable {
    case x = "X"
    case y = "Y"
    case depth = "Depth"

    var id: String { rawValue }
}

enum NTS3CCPart {
    case msb
    case lsb
}

enum NTS3InputControl: String, Equatable {
    case masterVolume = "Master Volume"
    case totalFXPadX = "Total FX Pad X"
    case totalFXPadY = "Total FX Pad Y"
    case totalFXDepth = "Total FX Depth"
    case totalFXTouch = "Total FX Touch"
    case inputMute = "Input Mute"
    case fxOnOff = "FX On/Off"
}

struct NTS3CC14Value: Equatable {
    var msb: Int = 0
    var lsb: Int = 0

    static let zero = NTS3CC14Value()

    init(msb: Int = 0, lsb: Int = 0) {
        self.msb = Self.clamp7Bit(msb)
        self.lsb = Self.clamp7Bit(lsb)
    }

    init(combined: Int) {
        let clamped = max(0, min(combined, 16_383))
        self.msb = (clamped >> 7) & 0x7F
        self.lsb = clamped & 0x7F
    }

    var combined: Int {
        (msb << 7) | lsb
    }

    var normalized: Double {
        Double(combined) / 16_383.0
    }

    var midi7BitValue: Int {
        max(0, min(127, combined >> 7))
    }

    var proVSDisplayValue: Int {
        max(0, min(99, Int((normalized * 99.0).rounded())))
    }

    var debugText: String {
        "\(combined) -> MIDI \(midi7BitValue) / display \(proVSDisplayValue)"
    }

    mutating func update(part: NTS3CCPart, value: Int) {
        let clamped = Self.clamp7Bit(value)
        switch part {
        case .msb:
            msb = clamped
        case .lsb:
            lsb = clamped
        }
    }

    private static func clamp7Bit(_ value: Int) -> Int {
        max(0, min(value, 127))
    }
}

enum MappingBank: Equatable, Hashable, Identifiable {
    case global
    case fx(Int)

    static let ordered: [MappingBank] = [.global, .fx(1), .fx(2), .fx(3), .fx(4)]

    var id: String {
        switch self {
        case .global:
            return "global"
        case .fx(let slot):
            return "fx-\(slot)"
        }
    }

    var displayName: String {
        switch self {
        case .global:
            return "Global"
        case .fx(let slot):
            return "FX \(slot)"
        }
    }

    var slot: Int? {
        if case .fx(let slot) = self {
            return slot
        }
        return nil
    }
}

enum ProVSParameter: String, CaseIterable, Equatable, Hashable, Identifiable {
    case filterCutoff
    case filterResonance
    case chorusRate
    case chorusAmount
    case lfo1Rate
    case lfo1Amount
    case lfo2Rate
    case lfo2Amount
    case channelVolume
    case expression

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .filterCutoff:
            return "Filter Cutoff"
        case .filterResonance:
            return "Filter Resonance"
        case .chorusRate:
            return "Chorus Rate"
        case .chorusAmount:
            return "Chorus Amount"
        case .lfo1Rate:
            return "LFO 1 Rate"
        case .lfo1Amount:
            return "LFO 1 Amount"
        case .lfo2Rate:
            return "LFO 2 Rate"
        case .lfo2Amount:
            return "LFO 2 Amount"
        case .channelVolume:
            return "Channel Volume"
        case .expression:
            return "Expression"
        }
    }

    var controller: Int {
        switch self {
        case .filterCutoff:
            return 74
        case .filterResonance:
            return 71
        case .chorusRate:
            return 92
        case .chorusAmount:
            return 91
        case .lfo1Rate:
            return 72
        case .lfo1Amount:
            return 70
        case .lfo2Rate:
            return 73
        case .lfo2Amount:
            return 28
        case .channelVolume:
            return 7
        case .expression:
            return 11
        }
    }

    var isExperimental: Bool {
        switch self {
        case .channelVolume, .expression:
            return true
        default:
            return false
        }
    }
}

enum ProVSVolumeMappingMode: String, Equatable {
    case disabled
    case channelVolume
    case expression

    var parameter: ProVSParameter? {
        switch self {
        case .disabled:
            return nil
        case .channelVolume:
            return .channelVolume
        case .expression:
            return .expression
        }
    }

    var displayName: String {
        switch self {
        case .disabled:
            return "Disabled"
        case .channelVolume:
            return "CC 7 Channel Volume"
        case .expression:
            return "CC 11 Expression"
        }
    }
}

struct ProVSExperimentalOptions: Equatable {
    var volumeMapping: ProVSVolumeMappingMode = .disabled
    var playToggleEnabled = false

    static let disabled = ProVSExperimentalOptions()
}

struct ProVSControlTarget: Equatable, Hashable, Identifiable {
    var bank: MappingBank
    var axis: NTS3ControlAxis?
    var parameter: ProVSParameter

    var id: String {
        let axisID = axis?.rawValue.lowercased() ?? "direct"
        return "\(bank.id)-\(axisID)-cc\(parameter.controller)"
    }

    var displayName: String {
        "\(parameter.displayName) CC \(parameter.controller)"
    }
}

struct MIDICCMessage: Equatable {
    var channel: Int
    var controller: Int
    var value: Int

    var bytes: [UInt8] {
        [
            UInt8(0xB0 | UInt8(max(0, min(channel - 1, 15)))),
            UInt8(max(0, min(controller, 127))),
            UInt8(max(0, min(value, 127)))
        ]
    }
}

enum MIDIRealtimeMessage: UInt8, Equatable {
    case start = 0xFA
    case stop = 0xFC

    var displayName: String {
        switch self {
        case .start:
            return "Start"
        case .stop:
            return "Stop"
        }
    }
}

enum MIDIOutputMessage: Equatable {
    case controlChange(MIDICCMessage, ProVSControlTarget)
    case realtime(MIDIRealtimeMessage)

    var bytes: [UInt8] {
        switch self {
        case .controlChange(let message, _):
            return message.bytes
        case .realtime(let message):
            return [message.rawValue]
        }
    }

    var snapshot: ProVSOutgoingMessageSnapshot {
        switch self {
        case .controlChange(let message, let target):
            return ProVSOutgoingMessageSnapshot(
                kind: "CC",
                bankName: target.bank.displayName,
                targetName: target.parameter.displayName,
                detail: "ch \(message.channel) CC \(message.controller) = \(message.value)"
            )
        case .realtime(let message):
            return ProVSOutgoingMessageSnapshot(
                kind: "Realtime",
                bankName: "Global",
                targetName: "Play Toggle",
                detail: message.displayName
            )
        }
    }
}

struct ProVSAxisTargetSnapshot: Equatable, Identifiable {
    let axis: NTS3ControlAxis
    let target: ProVSControlTarget?

    var id: String { axis.id }
}

struct ProVSBankSnapshot: Equatable, Identifiable {
    let bank: MappingBank
    var isActive: Bool
    var isCurrent: Bool
    var x: NTS3CC14Value
    var y: NTS3CC14Value
    var depth: NTS3CC14Value
    var axisTargets: [ProVSAxisTargetSnapshot]

    var id: String { bank.id }
}

struct ProVSOutgoingMessageSnapshot: Equatable, Identifiable {
    let id = UUID()
    var kind: String
    var bankName: String
    var targetName: String
    var detail: String
}

struct ProVSMappingSnapshot: Equatable {
    var activeBank: MappingBank
    var lastActivatedFX: Int?
    var padTouchValue: Int
    var inputMuteValue: Int
    var playToggleState: Bool
    var volume: NTS3CC14Value
    var outputChannel: Int
    var experimentalOptions: ProVSExperimentalOptions
    var banks: [ProVSBankSnapshot]
    var recentOutputs: [ProVSOutgoingMessageSnapshot]

    static func initial(
        outputChannel: Int,
        experimentalOptions: ProVSExperimentalOptions = .disabled
    ) -> ProVSMappingSnapshot {
        ProVSMappingSnapshot(
            activeBank: .global,
            lastActivatedFX: nil,
            padTouchValue: 0,
            inputMuteValue: 0,
            playToggleState: false,
            volume: .zero,
            outputChannel: outputChannel,
            experimentalOptions: experimentalOptions,
            banks: MappingBank.ordered.map { bank in
                ProVSBankSnapshot(
                    bank: bank,
                    isActive: bank == .global,
                    isCurrent: bank == .global,
                    x: .zero,
                    y: .zero,
                    depth: .zero,
                    axisTargets: NTS3ControlAxis.allCases.map { axis in
                        ProVSAxisTargetSnapshot(axis: axis, target: ProVSMappingEngine.target(for: bank, axis: axis))
                    }
                )
            },
            recentOutputs: []
        )
    }
}

final class ProVSMappingEngine {
    private struct InputPair {
        var control: NTS3InputControl
        var msb: Int
        var lsb: Int
    }

    private struct BankState {
        var x = NTS3CC14Value.zero
        var y = NTS3CC14Value.zero
        var depth = NTS3CC14Value.zero
    }

    private static let recentOutputLimit = 10

    private let outputChannel: Int
    private let experimentalOptions: ProVSExperimentalOptions
    private var volume = NTS3CC14Value.zero
    private var padTouchValue = 0
    private var inputMuteValue = 0
    private var playToggleState = false
    private var activeFXSlots = Set<Int>()
    private var fxActivationOrder: [Int] = []
    private var banks: [MappingBank: BankState] = Dictionary(
        uniqueKeysWithValues: MappingBank.ordered.map { ($0, BankState()) }
    )
    private var pendingOutputOrder: [ProVSControlTarget] = []
    private var pendingOutputs: [ProVSControlTarget: MIDIOutputMessage] = [:]
    private var lastQueuedValues: [ProVSControlTarget: Int] = [:]
    private var recentOutputs: [ProVSOutgoingMessageSnapshot] = []

    var onStateChange: ((ProVSMappingSnapshot) -> Void)?

    init(
        outputChannel: Int,
        experimentalOptions: ProVSExperimentalOptions = .disabled
    ) {
        self.outputChannel = max(1, min(outputChannel, 16))
        self.experimentalOptions = experimentalOptions
    }

    var snapshot: ProVSMappingSnapshot {
        let activeBank = currentBank
        return ProVSMappingSnapshot(
            activeBank: activeBank,
            lastActivatedFX: fxActivationOrder.last,
            padTouchValue: padTouchValue,
            inputMuteValue: inputMuteValue,
            playToggleState: playToggleState,
            volume: volume,
            outputChannel: outputChannel,
            experimentalOptions: experimentalOptions,
            banks: MappingBank.ordered.map { bank in
                let state = banks[bank] ?? BankState()
                return ProVSBankSnapshot(
                    bank: bank,
                    isActive: bank == .global || bank.slot.map { activeFXSlots.contains($0) } == true,
                    isCurrent: bank == activeBank,
                    x: state.x,
                    y: state.y,
                    depth: state.depth,
                    axisTargets: NTS3ControlAxis.allCases.map { axis in
                        ProVSAxisTargetSnapshot(axis: axis, target: Self.target(for: bank, axis: axis))
                    }
                )
            },
            recentOutputs: recentOutputs
        )
    }

    func handle(change: MIDIControlChange) -> [MIDIOutputMessage] {
        guard (0...127).contains(change.value) else {
            return []
        }

        let output: [MIDIOutputMessage]
        if let pair = Self.inputPair(for: change.controller) {
            output = handlePairedInput(
                pair,
                part: Self.part(for: change.controller, in: pair),
                value: change.value
            )
        } else {
            output = handleSingleCC(change)
        }

        publishState()
        return output
    }

    func flushPendingOutputs() -> [MIDIOutputMessage] {
        let orderedTargets = pendingOutputOrder
        let outputs = pendingOutputs

        pendingOutputOrder.removeAll()
        pendingOutputs.removeAll()

        return orderedTargets.compactMap { outputs[$0] }
    }

    private func handlePairedInput(
        _ pair: InputPair,
        part: NTS3CCPart,
        value: Int
    ) -> [MIDIOutputMessage] {
        switch pair.control {
        case .masterVolume:
            volume.update(part: part, value: value)
            queueVolumeIfEnabled()
        case .totalFXPadX:
            guard padTouchValue == 127 else { break }
            updateCurrentBank(axis: .x, part: part, value: value)
            queueCurrentBank(axis: .x)
        case .totalFXPadY:
            guard padTouchValue == 127 else { break }
            updateCurrentBank(axis: .y, part: part, value: value)
            queueCurrentBank(axis: .y)
        case .totalFXDepth:
            updateCurrentBank(axis: .depth, part: part, value: value)
            queueCurrentBank(axis: .depth)
        default:
            break
        }

        return []
    }

    private func handleSingleCC(_ change: MIDIControlChange) -> [MIDIOutputMessage] {
        switch change.controller {
        case Self.totalFXTouch:
            guard isSwitchValue(change.value) else { return [] }
            padTouchValue = change.value
            return []
        case Self.inputMute:
            return handleInputMute(value: change.value)
        case Self.fx1OnOff, Self.fx2OnOff, Self.fx3OnOff, Self.fx4OnOff:
            guard let slot = Self.fxOnOffSlots[change.controller], isSwitchValue(change.value) else {
                return []
            }
            handleFXOnOff(slot: slot, value: change.value)
            return []
        default:
            return []
        }
    }

    private func handleInputMute(value: Int) -> [MIDIOutputMessage] {
        guard isSwitchValue(value) else {
            return []
        }

        let wasPressed = inputMuteValue == 127
        inputMuteValue = value

        guard value == 127, !wasPressed, experimentalOptions.playToggleEnabled else {
            return []
        }

        playToggleState.toggle()
        let message: MIDIOutputMessage = .realtime(playToggleState ? .start : .stop)
        rememberOutput(message.snapshot)
        return [message]
    }

    private func handleFXOnOff(slot: Int, value: Int) {
        if value == 127 {
            activeFXSlots.insert(slot)
            fxActivationOrder.removeAll { $0 == slot }
            fxActivationOrder.append(slot)
        } else {
            activeFXSlots.remove(slot)
            fxActivationOrder.removeAll { $0 == slot }
        }
    }

    private func updateCurrentBank(axis: NTS3ControlAxis, part: NTS3CCPart, value: Int) {
        var state = banks[currentBank] ?? BankState()
        switch axis {
        case .x:
            state.x.update(part: part, value: value)
        case .y:
            state.y.update(part: part, value: value)
        case .depth:
            state.depth.update(part: part, value: value)
        }
        banks[currentBank] = state
    }

    private func queueCurrentBank(axis: NTS3ControlAxis) {
        let bank = currentBank
        guard let target = Self.target(for: bank, axis: axis),
              let value = value(for: axis, in: bank) else {
            return
        }

        queue(target: target, value: value.midi7BitValue)
    }

    private func queueVolumeIfEnabled() {
        guard let parameter = experimentalOptions.volumeMapping.parameter else {
            return
        }

        queue(
            target: ProVSControlTarget(bank: .global, axis: nil, parameter: parameter),
            value: volume.midi7BitValue
        )
    }

    private func queue(target: ProVSControlTarget, value: Int) {
        let clampedValue = max(0, min(value, 127))
        guard lastQueuedValues[target] != clampedValue else {
            return
        }

        lastQueuedValues[target] = clampedValue
        if pendingOutputs[target] == nil {
            pendingOutputOrder.append(target)
        }

        let message = MIDIOutputMessage.controlChange(
            MIDICCMessage(
                channel: outputChannel,
                controller: target.parameter.controller,
                value: clampedValue
            ),
            target
        )
        pendingOutputs[target] = message
        rememberOutput(message.snapshot)
    }

    private func value(for axis: NTS3ControlAxis, in bank: MappingBank) -> NTS3CC14Value? {
        guard let state = banks[bank] else {
            return nil
        }

        switch axis {
        case .x:
            return state.x
        case .y:
            return state.y
        case .depth:
            return state.depth
        }
    }

    private func rememberOutput(_ output: ProVSOutgoingMessageSnapshot) {
        recentOutputs.append(output)
        if recentOutputs.count > Self.recentOutputLimit {
            recentOutputs.removeFirst(recentOutputs.count - Self.recentOutputLimit)
        }
    }

    private var currentBank: MappingBank {
        if let slot = fxActivationOrder.last {
            return .fx(slot)
        }
        return .global
    }

    private func publishState() {
        onStateChange?(snapshot)
    }

    private func isSwitchValue(_ value: Int) -> Bool {
        value == 0 || value == 127
    }

    static func target(for bank: MappingBank, axis: NTS3ControlAxis) -> ProVSControlTarget? {
        switch (bank, axis) {
        case (.fx(1), .x):
            return ProVSControlTarget(bank: bank, axis: axis, parameter: .filterCutoff)
        case (.fx(1), .y):
            return ProVSControlTarget(bank: bank, axis: axis, parameter: .filterResonance)
        case (.fx(2), .x):
            return ProVSControlTarget(bank: bank, axis: axis, parameter: .chorusRate)
        case (.fx(2), .y):
            return ProVSControlTarget(bank: bank, axis: axis, parameter: .chorusAmount)
        case (.fx(3), .x):
            return ProVSControlTarget(bank: bank, axis: axis, parameter: .lfo1Rate)
        case (.fx(3), .y):
            return ProVSControlTarget(bank: bank, axis: axis, parameter: .lfo1Amount)
        case (.fx(4), .x):
            return ProVSControlTarget(bank: bank, axis: axis, parameter: .lfo2Rate)
        case (.fx(4), .y):
            return ProVSControlTarget(bank: bank, axis: axis, parameter: .lfo2Amount)
        default:
            return nil
        }
    }
}

private extension ProVSMappingEngine {
    static let inputMute = 15
    static let totalFXTouch = 102

    static let fx1OnOff = 106
    static let fx2OnOff = 110
    static let fx3OnOff = 114
    static let fx4OnOff = 118

    private static let inputPairs: [InputPair] = [
        InputPair(control: .masterVolume, msb: 7, lsb: 39),
        InputPair(control: .totalFXPadX, msb: 12, lsb: 44),
        InputPair(control: .totalFXPadY, msb: 13, lsb: 45),
        InputPair(control: .totalFXDepth, msb: 14, lsb: 46)
    ]

    static let fxOnOffSlots: [Int: Int] = [
        fx1OnOff: 1,
        fx2OnOff: 2,
        fx3OnOff: 3,
        fx4OnOff: 4
    ]

    private static func inputPair(for controller: Int) -> InputPair? {
        inputPairs.first { $0.msb == controller || $0.lsb == controller }
    }

    private static func part(for controller: Int, in pair: InputPair) -> NTS3CCPart {
        controller == pair.msb ? .msb : .lsb
    }
}

final class NTS3MappingTransformer: MIDITransformer {
    private let parser = MIDIControlChangeParser()
    private let engine: ProVSMappingEngine
    private let lock = NSLock()

    init(
        outputChannel: Int,
        experimentalOptions: ProVSExperimentalOptions = .disabled,
        onStateChange: ((ProVSMappingSnapshot) -> Void)? = nil
    ) {
        engine = ProVSMappingEngine(
            outputChannel: outputChannel,
            experimentalOptions: experimentalOptions
        )
        engine.onStateChange = onStateChange
        onStateChange?(engine.snapshot)
    }

    func transform(packetBytes: [UInt8]) -> [[UInt8]] {
        lock.lock()
        defer { lock.unlock() }

        return parser.parse(packetBytes: packetBytes).flatMap { change in
            engine.handle(change: change).map(\.bytes)
        }
    }

    func flushPendingOutputs() -> [[UInt8]] {
        lock.lock()
        defer { lock.unlock() }

        return engine.flushPendingOutputs().map(\.bytes)
    }
}
