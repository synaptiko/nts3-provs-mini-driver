import Foundation

enum NTS3OutputMode: String, Equatable {
    case pair = "Pair Mode"
    case trim = "Trim Mode"
}

enum NTS3MappingMode: String, Equatable {
    case global = "Global"
    case fx = "FX"
}

enum NTS3GlobalFreezePhase: String, Equatable {
    case normal
    case armingFreeze
    case frozen
    case armingUnfreeze
}

enum NTS3ControlAxis: String, Equatable, Hashable {
    case x = "X"
    case y = "Y"
    case depth = "Depth"
}

enum NTS3CCPart {
    case msb
    case lsb
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

struct NTS3CC14Pair: Equatable {
    var msb: Int
    var lsb: Int
}

struct NTS3MappingLearnGroup: Identifiable {
    var id: String { title }
    let title: String
    let targets: [NTS3MappingOutputID]
}

enum NTS3MappingOutputID: Hashable, Identifiable {
    case masterVolume
    case global(NTS3ControlAxis)
    case fx(slot: Int, axis: NTS3ControlAxis)

    var id: String {
        switch self {
        case .masterVolume:
            return "volume"
        case .global(let axis):
            return "global-\(axis.rawValue.lowercased())"
        case .fx(let slot, let axis):
            return "fx-\(slot)-\(axis.rawValue.lowercased())"
        }
    }

    var groupTitle: String {
        switch self {
        case .masterVolume:
            return "Volume"
        case .global:
            return "Global"
        case .fx(let slot, _):
            return "FX \(slot)"
        }
    }

    var shortTitle: String {
        switch self {
        case .masterVolume:
            return "Volume"
        case .global(let axis), .fx(_, let axis):
            return axis.rawValue
        }
    }

    var displayTitle: String {
        switch self {
        case .masterVolume:
            return "Volume"
        case .global(let axis):
            return "Global \(axis.rawValue)"
        case .fx(let slot, let axis):
            return "FX \(slot) \(axis.rawValue)"
        }
    }

    var ccText: String {
        let pair = controllerPair
        return "CC \(pair.msb)/\(pair.lsb)"
    }

    var controllerPair: NTS3CC14Pair {
        switch self {
        case .masterVolume:
            return NTS3CC14Pair(msb: 10, lsb: 42)
        case .global(.x):
            return NTS3CC14Pair(msb: 11, lsb: 43)
        case .global(.y):
            return NTS3CC14Pair(msb: 12, lsb: 44)
        case .global(.depth):
            return NTS3CC14Pair(msb: 13, lsb: 45)
        case .fx(let slot, let axis):
            let zeroBasedSlot = max(0, min(slot - 1, 3))
            let baseMSB = 14 + zeroBasedSlot * 3
            let baseLSB = 46 + zeroBasedSlot * 3
            switch axis {
            case .x:
                return NTS3CC14Pair(msb: baseMSB, lsb: baseLSB)
            case .y:
                return NTS3CC14Pair(msb: baseMSB + 1, lsb: baseLSB + 1)
            case .depth:
                return NTS3CC14Pair(msb: baseMSB + 2, lsb: baseLSB + 2)
            }
        }
    }

    func messages(
        value: NTS3CC14Value,
        channel: Int,
        outputMode: NTS3OutputMode
    ) -> [MIDICCMessage] {
        let pair = controllerPair
        switch outputMode {
        case .pair:
            return [
                MIDICCMessage(channel: channel, controller: pair.msb, value: value.msb),
                MIDICCMessage(channel: channel, controller: pair.lsb, value: value.lsb)
            ]
        case .trim:
            return [MIDICCMessage(channel: channel, controller: pair.msb, value: value.msb)]
        }
    }

    static let learnGroups: [NTS3MappingLearnGroup] = [
        NTS3MappingLearnGroup(title: "Volume", targets: [.masterVolume]),
        NTS3MappingLearnGroup(title: "Global", targets: [
            .global(.depth),
            .global(.x),
            .global(.y)
        ]),
        NTS3MappingLearnGroup(title: "FX 1", targets: [
            .fx(slot: 1, axis: .depth),
            .fx(slot: 1, axis: .x),
            .fx(slot: 1, axis: .y)
        ]),
        NTS3MappingLearnGroup(title: "FX 2", targets: [
            .fx(slot: 2, axis: .depth),
            .fx(slot: 2, axis: .x),
            .fx(slot: 2, axis: .y)
        ]),
        NTS3MappingLearnGroup(title: "FX 3", targets: [
            .fx(slot: 3, axis: .depth),
            .fx(slot: 3, axis: .x),
            .fx(slot: 3, axis: .y)
        ]),
        NTS3MappingLearnGroup(title: "FX 4", targets: [
            .fx(slot: 4, axis: .depth),
            .fx(slot: 4, axis: .x),
            .fx(slot: 4, axis: .y)
        ])
    ]
}

struct NTS3FXSlotSnapshot: Equatable, Identifiable {
    let id: Int
    var isActive: Bool
    var isFrozen: Bool
    var x: NTS3CC14Value
    var y: NTS3CC14Value
    var depth: NTS3CC14Value
    var frozenX: NTS3CC14Value
    var frozenY: NTS3CC14Value
}

struct NTS3MappingSnapshot: Equatable {
    var outputMode: NTS3OutputMode
    var mappingMode: NTS3MappingMode
    var globalFreezePhase: NTS3GlobalFreezePhase
    var fxMuteFreezePhase: NTS3GlobalFreezePhase
    var fxFreezeTargetID: Int?
    var totalFXTouchValue: Int
    var inputMuteValue: Int
    var globalX: NTS3CC14Value
    var globalY: NTS3CC14Value
    var globalDepth: NTS3CC14Value
    var globalFrozenX: NTS3CC14Value
    var globalFrozenY: NTS3CC14Value
    var fxSlots: [NTS3FXSlotSnapshot]

    static func initial(outputMode: NTS3OutputMode) -> NTS3MappingSnapshot {
        NTS3MappingSnapshot(
            outputMode: outputMode,
            mappingMode: .global,
            globalFreezePhase: .normal,
            fxMuteFreezePhase: .normal,
            fxFreezeTargetID: nil,
            totalFXTouchValue: 0,
            inputMuteValue: 0,
            globalX: .zero,
            globalY: .zero,
            globalDepth: .zero,
            globalFrozenX: .zero,
            globalFrozenY: .zero,
            fxSlots: (1...4).map { slot in
                NTS3FXSlotSnapshot(
                    id: slot,
                    isActive: false,
                    isFrozen: false,
                    x: .zero,
                    y: .zero,
                    depth: .zero,
                    frozenX: .zero,
                    frozenY: .zero
                )
            }
        )
    }
}

struct MIDICCMessage: Equatable {
    var channel: Int
    var controller: Int
    var value: Int

    func routed(to channel: Int) -> MIDICCMessage {
        MIDICCMessage(channel: channel, controller: controller, value: value)
    }

    var bytes: [UInt8] {
        [
            UInt8(0xB0 | UInt8(max(0, min(channel - 1, 15)))),
            UInt8(max(0, min(controller, 127))),
            UInt8(max(0, min(value, 127)))
        ]
    }
}

final class NTS3MappingEngine {
    private struct PendingOutput {
        var value: NTS3CC14Value
        var channel: Int
    }

    static let fxMuteLongPressDuration: TimeInterval = 0.7

    private struct FXSlotState {
        var isActive = false
        var x = NTS3CC14Value.zero
        var y = NTS3CC14Value.zero
        var depth = NTS3CC14Value.zero
        var isFXFreezeActive = false
        var fxFrozenX = NTS3CC14Value.zero
        var fxFrozenY = NTS3CC14Value.zero
        var isMuteFrozen = false
        var muteFrozenX = NTS3CC14Value.zero
        var muteFrozenY = NTS3CC14Value.zero

        var isFrozen: Bool {
            isFXFreezeActive || isMuteFrozen
        }

        var frozenX: NTS3CC14Value {
            if isFXFreezeActive {
                return fxFrozenX
            }
            if isMuteFrozen {
                return muteFrozenX
            }
            return .zero
        }

        var frozenY: NTS3CC14Value {
            if isFXFreezeActive {
                return fxFrozenY
            }
            if isMuteFrozen {
                return muteFrozenY
            }
            return .zero
        }
    }

    let outputMode: NTS3OutputMode
    var onStateChange: ((NTS3MappingSnapshot) -> Void)?

    private var masterVolume = NTS3CC14Value.zero
    private var totalX = NTS3CC14Value.zero
    private var totalY = NTS3CC14Value.zero
    private var totalDepth = NTS3CC14Value.zero
    private var globalX = NTS3CC14Value.zero
    private var globalY = NTS3CC14Value.zero
    private var globalDepth = NTS3CC14Value.zero
    private var globalFrozenX = NTS3CC14Value.zero
    private var globalFrozenY = NTS3CC14Value.zero
    private var globalFreezePhase = NTS3GlobalFreezePhase.normal
    private var fxMuteFreezePhase = NTS3GlobalFreezePhase.normal
    private var fxFreezeTargetIndex: Int?
    private var fxMuteFreezeArmedIndex: Int?
    private var fxActivationOrder: [Int] = []
    private var totalFXTouchValue = 0
    private var inputMuteValue = 0
    private var inputMutePressedAt: TimeInterval?
    private var fxSlots = Array(repeating: FXSlotState(), count: 4)
    private var pendingOutputOrder: [NTS3MappingOutputID] = []
    private var pendingOutputs: [NTS3MappingOutputID: PendingOutput] = [:]

    init(outputMode: NTS3OutputMode) {
        self.outputMode = outputMode
    }

    var snapshot: NTS3MappingSnapshot {
        NTS3MappingSnapshot(
            outputMode: outputMode,
            mappingMode: hasActiveFX ? .fx : .global,
            globalFreezePhase: globalFreezePhase,
            fxMuteFreezePhase: fxMuteFreezePhase,
            fxFreezeTargetID: fxFreezeTargetIndex.map { $0 + 1 },
            totalFXTouchValue: totalFXTouchValue,
            inputMuteValue: inputMuteValue,
            globalX: globalX,
            globalY: globalY,
            globalDepth: globalDepth,
            globalFrozenX: globalFrozenX,
            globalFrozenY: globalFrozenY,
            fxSlots: fxSlots.enumerated().map { index, slot in
                NTS3FXSlotSnapshot(
                    id: index + 1,
                    isActive: slot.isActive,
                    isFrozen: slot.isFrozen,
                    x: slot.x,
                    y: slot.y,
                    depth: slot.depth,
                    frozenX: slot.frozenX,
                    frozenY: slot.frozenY
                )
            }
        )
    }

    func handle(change: MIDIControlChange) -> [MIDICCMessage] {
        handle(change: change, timestamp: Date().timeIntervalSinceReferenceDate)
    }

    func handle(change: MIDIControlChange, timestamp: TimeInterval) -> [MIDICCMessage] {
        guard isValidDataValue(change.value) else {
            return []
        }

        var output: [MIDICCMessage] = []

        if let pair = Self.inputPair(for: change.controller) {
            output.append(
                contentsOf: handlePairedInput(
                    pair,
                    part: Self.part(for: change.controller, in: pair),
                    value: change.value,
                    channel: change.channel
                )
            )
        } else {
            output.append(contentsOf: handleSingleCC(change, timestamp: timestamp))
        }

        publishState()
        return output
    }

    func flushPendingOutputs() -> [MIDICCMessage] {
        let orderedTargets = pendingOutputOrder
        let outputs = pendingOutputs

        pendingOutputOrder.removeAll()
        pendingOutputs.removeAll()

        return orderedTargets.flatMap { target in
            outputs[target].map {
                target.messages(value: $0.value, channel: $0.channel, outputMode: outputMode)
            } ?? []
        }
    }

    func discardPendingOutputs() {
        pendingOutputOrder.removeAll()
        pendingOutputs.removeAll()
    }

    private func handlePairedInput(
        _ pair: InputPair,
        part: NTS3CCPart,
        value: Int,
        channel: Int
    ) -> [MIDICCMessage] {
        switch pair.control {
        case .masterVolume:
            masterVolume.update(part: part, value: value)
            return queue(part: part, value: masterVolume, target: .masterVolume, channel: channel)
        case .totalX:
            totalX.update(part: part, value: value)
            return handleXYInput(axis: .x, part: part, value: value, channel: channel)
        case .totalY:
            totalY.update(part: part, value: value)
            return handleXYInput(axis: .y, part: part, value: value, channel: channel)
        case .totalDepth:
            totalDepth.update(part: part, value: value)
            return handleDepthInput(part: part, value: value, channel: channel)
        }
    }

    private func handleXYInput(
        axis: NTS3ControlAxis,
        part: NTS3CCPart,
        value: Int,
        channel: Int
    ) -> [MIDICCMessage] {
        guard totalFXTouchValue == 127 else {
            return []
        }

        if hasActiveFX {
            var output: [MIDICCMessage] = []
            for index in fxSlots.indices where fxSlots[index].isActive {
                guard shouldFXSlotFollowLiveXY(index) else {
                    continue
                }

                updateFXSlot(index, axis: axis, part: part, value: value)
                if fxMuteFreezePhase == .armingFreeze,
                   inputMuteValue == 127,
                   fxMuteFreezeArmedIndex == index {
                    captureFXMuteFreezeCandidate(forSlot: index)
                }
                output.append(
                    contentsOf: queue(
                        part: part,
                        value: fxValue(slot: index, axis: axis),
                        target: .fx(slot: index + 1, axis: axis),
                        channel: channel
                    )
                )
            }
            return output
        }

        if globalFreezePhase == .armingFreeze, inputMuteValue == 127 {
            captureGlobalFreezeCandidate()
        }

        updateGlobal(axis: axis, part: part, value: value)
        return queue(part: part, value: globalValue(axis: axis), target: .global(axis), channel: channel)
    }

    private func handleDepthInput(part: NTS3CCPart, value: Int, channel: Int) -> [MIDICCMessage] {
        if hasActiveFX {
            var output: [MIDICCMessage] = []
            for index in fxSlots.indices where fxSlots[index].isActive && shouldFXSlotFollowLiveXY(index) {
                fxSlots[index].depth.update(part: part, value: value)
                output.append(
                    contentsOf: queue(
                        part: part,
                        value: fxSlots[index].depth,
                        target: .fx(slot: index + 1, axis: .depth),
                        channel: channel
                    )
                )
            }
            return output
        }

        globalDepth.update(part: part, value: value)
        return queue(part: part, value: globalDepth, target: .global(.depth), channel: channel)
    }

    private func handleSingleCC(_ change: MIDIControlChange, timestamp: TimeInterval) -> [MIDICCMessage] {
        switch change.controller {
        case Self.inputMute:
            return handleInputMute(value: change.value, channel: change.channel, timestamp: timestamp)
        case Self.totalFXTouch:
            return handleTotalFXTouch(value: change.value, channel: change.channel)
        case Self.fx1Freeze, Self.fx2Freeze, Self.fx3Freeze, Self.fx4Freeze:
            guard let slot = Self.fxFreezeSlots[change.controller] else {
                return []
            }
            return handleFXFreeze(slot: slot, value: change.value, channel: change.channel)
        case Self.fx1OnOff, Self.fx2OnOff, Self.fx3OnOff, Self.fx4OnOff:
            guard let slot = Self.fxOnOffSlots[change.controller] else {
                return []
            }
            return handleFXOnOff(slot: slot, value: change.value, channel: change.channel)
        default:
            return []
        }
    }

    private func handleInputMute(value: Int, channel: Int, timestamp: TimeInterval) -> [MIDICCMessage] {
        guard isSwitchValue(value) else {
            return []
        }

        inputMuteValue = value
        if value == 127 {
            inputMutePressedAt = timestamp
        }

        if hasActiveFX {
            return handleFXInputMute(value: value, channel: channel, timestamp: timestamp)
        }

        if value == 0 {
            inputMutePressedAt = nil
        }

        if value == 127 {
            switch globalFreezePhase {
            case .normal where totalFXTouchValue == 127:
                globalFreezePhase = .armingFreeze
                captureGlobalFreezeCandidate()
            case .frozen:
                globalFreezePhase = .armingUnfreeze
            default:
                break
            }
            return []
        }

        switch globalFreezePhase {
        case .armingFreeze:
            commitGlobalFreeze()
            return []
        case .armingUnfreeze:
            return commitGlobalUnfreeze(channel: channel)
        default:
            return []
        }
    }

    private func handleFXInputMute(value: Int, channel: Int, timestamp: TimeInterval) -> [MIDICCMessage] {
        guard let targetIndex = fxFreezeTargetIndex, fxSlots[targetIndex].isActive else {
            if value == 0 {
                inputMutePressedAt = nil
            }
            return []
        }

        if value == 127 {
            fxMuteFreezeArmedIndex = targetIndex

            if fxSlots[targetIndex].isMuteFrozen {
                fxMuteFreezePhase = .armingUnfreeze
            } else if totalFXTouchValue == 127 {
                fxMuteFreezePhase = .armingFreeze
                captureFXMuteFreezeCandidate(forSlot: targetIndex)
            } else {
                fxMuteFreezeArmedIndex = nil
            }
            return []
        }

        let isLongPress = inputMutePressedAt.map {
            timestamp - $0 >= Self.fxMuteLongPressDuration
        } ?? false
        inputMutePressedAt = nil

        if isLongPress {
            return clearAllFXFreezes(channel: channel)
        }

        switch fxMuteFreezePhase {
        case .armingFreeze:
            commitFXMuteFreeze()
            return []
        case .armingUnfreeze:
            return commitFXMuteUnfreeze(channel: channel)
        default:
            return []
        }
    }

    private func handleTotalFXTouch(value: Int, channel: Int) -> [MIDICCMessage] {
        guard isSwitchValue(value) else {
            return []
        }

        totalFXTouchValue = value

        guard value == 0 else {
            return []
        }

        if hasActiveFX {
            switch fxMuteFreezePhase {
            case .armingFreeze:
                commitFXMuteFreeze()
            case .armingUnfreeze:
                return commitFXMuteUnfreeze(channel: channel)
            default:
                break
            }

            return emitReleaseTargets(channel: channel)
        }

        switch globalFreezePhase {
        case .armingFreeze:
            commitGlobalFreeze()
        case .armingUnfreeze:
            return commitGlobalUnfreeze(channel: channel)
        default:
            break
        }

        return emitReleaseTargets(channel: channel)
    }

    private func handleFXFreeze(slot oneBasedSlot: Int, value: Int, channel: Int) -> [MIDICCMessage] {
        guard isSwitchValue(value) else {
            return []
        }

        let index = oneBasedSlot - 1
        guard fxSlots.indices.contains(index), fxSlots[index].isActive else {
            return []
        }

        if value == 127 {
            fxSlots[index].isFXFreezeActive = true
            fxSlots[index].fxFrozenX = fxSlots[index].x
            fxSlots[index].fxFrozenY = fxSlots[index].y
            return []
        }

        fxSlots[index].isFXFreezeActive = false
        fxSlots[index].fxFrozenX = .zero
        fxSlots[index].fxFrozenY = .zero

        guard totalFXTouchValue == 0 else {
            return []
        }

        let target = releaseTarget(forFXSlot: index)
        fxSlots[index].x = target.x
        fxSlots[index].y = target.y
        return emitFXXY(slot: index, x: target.x, y: target.y, channel: channel)
    }

    private func handleFXOnOff(slot oneBasedSlot: Int, value: Int, channel: Int) -> [MIDICCMessage] {
        guard isSwitchValue(value) else {
            return []
        }

        let index = oneBasedSlot - 1
        guard fxSlots.indices.contains(index) else {
            return []
        }

        if value == 127 {
            guard !fxSlots[index].isActive else {
                return []
            }

            let wasGlobalMode = !hasActiveFX
            activateFXSlot(at: index)
            let initialTarget = releaseTarget(forFXSlot: index)
            fxSlots[index].x = initialTarget.x
            fxSlots[index].y = initialTarget.y
            fxSlots[index].depth = .zero

            var output: [MIDICCMessage] = []
            if wasGlobalMode {
                globalX = .zero
                globalY = .zero
                globalDepth = .zero
                output.append(contentsOf: emitGlobalXYZ(x: .zero, y: .zero, depth: .zero, channel: channel))
            }
            output.append(contentsOf: emitFXXYZ(slot: index, x: initialTarget.x, y: initialTarget.y, depth: .zero, channel: channel))
            return output
        }

        guard fxSlots[index].isActive else {
            return []
        }

        var output = emitFXXYZ(slot: index, x: .zero, y: .zero, depth: .zero, channel: channel)
        deactivateFXSlot(at: index)
        if !hasActiveFX {
            fxMuteFreezePhase = .normal
            fxMuteFreezeArmedIndex = nil
            let target = releaseTargetForGlobal()
            globalX = target.x
            globalY = target.y
            output.append(contentsOf: emitGlobalXY(x: target.x, y: target.y, channel: channel))
        }
        return output
    }

    private func activateFXSlot(at index: Int) {
        fxSlots[index].isActive = true
        fxActivationOrder.removeAll { $0 == index }
        fxActivationOrder.append(index)
        fxFreezeTargetIndex = index
    }

    private func deactivateFXSlot(at index: Int) {
        fxSlots[index].isActive = false
        fxSlots[index].x = .zero
        fxSlots[index].y = .zero
        fxSlots[index].depth = .zero
        fxActivationOrder.removeAll { $0 == index }

        if fxMuteFreezeArmedIndex == index {
            fxMuteFreezeArmedIndex = nil
            fxMuteFreezePhase = .normal
        }

        fxFreezeTargetIndex = fxActivationOrder.last
    }

    private func commitGlobalFreeze() {
        captureGlobalFreezeCandidate()
        globalFreezePhase = .frozen
    }

    private func commitFXMuteFreeze() {
        if let targetIndex = fxMuteFreezeArmedIndex, fxSlots[targetIndex].isActive {
            captureFXMuteFreezeCandidate(forSlot: targetIndex)
        }
        fxMuteFreezePhase = .normal
        fxMuteFreezeArmedIndex = nil
    }

    private func commitGlobalUnfreeze(channel: Int) -> [MIDICCMessage] {
        globalFreezePhase = .normal
        globalFrozenX = .zero
        globalFrozenY = .zero

        guard totalFXTouchValue == 0 else {
            return emitLiveXYFromLatestTotal(channel: channel)
        }

        return emitReleaseTargets(channel: channel)
    }

    private func commitFXMuteUnfreeze(channel: Int) -> [MIDICCMessage] {
        guard let targetIndex = fxMuteFreezeArmedIndex, fxSlots[targetIndex].isActive else {
            fxMuteFreezePhase = .normal
            fxMuteFreezeArmedIndex = nil
            return []
        }

        fxMuteFreezePhase = .normal
        fxMuteFreezeArmedIndex = nil
        fxSlots[targetIndex].isMuteFrozen = false
        fxSlots[targetIndex].muteFrozenX = .zero
        fxSlots[targetIndex].muteFrozenY = .zero

        guard totalFXTouchValue == 0 else {
            return emitLiveXYFromLatestTotal(channel: channel)
        }

        let target = releaseTarget(forFXSlot: targetIndex)
        fxSlots[targetIndex].x = target.x
        fxSlots[targetIndex].y = target.y
        return emitFXXY(slot: targetIndex, x: target.x, y: target.y, channel: channel)
    }

    private func clearAllFXFreezes(channel: Int) -> [MIDICCMessage] {
        fxMuteFreezePhase = .normal
        fxMuteFreezeArmedIndex = nil

        for index in fxSlots.indices {
            fxSlots[index].isFXFreezeActive = false
            fxSlots[index].fxFrozenX = .zero
            fxSlots[index].fxFrozenY = .zero
            fxSlots[index].isMuteFrozen = false
            fxSlots[index].muteFrozenX = .zero
            fxSlots[index].muteFrozenY = .zero
        }

        if totalFXTouchValue == 127 {
            return emitLiveXYForUnfrozenFX(channel: channel)
        }

        return emitReleaseTargets(channel: channel)
    }

    private func emitLiveXYFromLatestTotal(channel: Int) -> [MIDICCMessage] {
        if hasActiveFX {
            return emitLiveXYForUnfrozenFX(channel: channel)
        }

        globalX = totalX
        globalY = totalY
        return emitGlobalXY(x: totalX, y: totalY, channel: channel)
    }

    private func emitLiveXYForUnfrozenFX(channel: Int) -> [MIDICCMessage] {
        var output: [MIDICCMessage] = []
        for index in fxSlots.indices where fxSlots[index].isActive && shouldFXSlotFollowLiveXY(index) {
            fxSlots[index].x = totalX
            fxSlots[index].y = totalY
            output.append(contentsOf: emitFXXY(slot: index, x: totalX, y: totalY, channel: channel))
        }
        return output
    }

    private func emitReleaseTargets(channel: Int) -> [MIDICCMessage] {
        if hasActiveFX {
            var output: [MIDICCMessage] = []
            for index in fxSlots.indices where fxSlots[index].isActive {
                let target = releaseTarget(forFXSlot: index)
                fxSlots[index].x = target.x
                fxSlots[index].y = target.y
                output.append(contentsOf: emitFXXY(slot: index, x: target.x, y: target.y, channel: channel))
            }
            return output
        }

        let target = releaseTargetForGlobal()
        globalX = target.x
        globalY = target.y
        return emitGlobalXY(x: target.x, y: target.y, channel: channel)
    }

    private func releaseTargetForGlobal() -> (x: NTS3CC14Value, y: NTS3CC14Value) {
        if globalFreezePhase == .frozen || globalFreezePhase == .armingUnfreeze {
            return (globalFrozenX, globalFrozenY)
        }
        return (.zero, .zero)
    }

    private func releaseTarget(forFXSlot index: Int) -> (x: NTS3CC14Value, y: NTS3CC14Value) {
        if fxSlots[index].isFXFreezeActive {
            return (fxSlots[index].fxFrozenX, fxSlots[index].fxFrozenY)
        }
        if fxSlots[index].isMuteFrozen {
            return (fxSlots[index].muteFrozenX, fxSlots[index].muteFrozenY)
        }
        return (.zero, .zero)
    }

    private func captureGlobalFreezeCandidate() {
        globalFrozenX = totalX
        globalFrozenY = totalY
    }

    private func captureFXMuteFreezeCandidate(forSlot index: Int) {
        fxSlots[index].isMuteFrozen = true
        fxSlots[index].muteFrozenX = fxSlots[index].x
        fxSlots[index].muteFrozenY = fxSlots[index].y
    }

    private func shouldFXSlotFollowLiveXY(_ index: Int) -> Bool {
        if fxMuteFreezePhase == .armingFreeze, fxMuteFreezeArmedIndex == index {
            return true
        }
        if fxFreezeTargetIndex == index {
            return true
        }
        return !fxSlots[index].isFrozen
    }

    private func updateGlobal(axis: NTS3ControlAxis, part: NTS3CCPart, value: Int) {
        switch axis {
        case .x:
            globalX.update(part: part, value: value)
        case .y:
            globalY.update(part: part, value: value)
        case .depth:
            globalDepth.update(part: part, value: value)
        }
    }

    private func updateFXSlot(_ index: Int, axis: NTS3ControlAxis, part: NTS3CCPart, value: Int) {
        switch axis {
        case .x:
            fxSlots[index].x.update(part: part, value: value)
        case .y:
            fxSlots[index].y.update(part: part, value: value)
        case .depth:
            fxSlots[index].depth.update(part: part, value: value)
        }
    }

    private func emitGlobalXY(x: NTS3CC14Value, y: NTS3CC14Value, channel: Int) -> [MIDICCMessage] {
        queue(value: x, target: .global(.x), channel: channel)
            + queue(value: y, target: .global(.y), channel: channel)
    }

    private func emitGlobalXYZ(x: NTS3CC14Value, y: NTS3CC14Value, depth: NTS3CC14Value, channel: Int) -> [MIDICCMessage] {
        emitGlobalXY(x: x, y: y, channel: channel)
            + queue(value: depth, target: .global(.depth), channel: channel)
    }

    private func emitFXXY(slot index: Int, x: NTS3CC14Value, y: NTS3CC14Value, channel: Int) -> [MIDICCMessage] {
        queue(value: x, target: .fx(slot: index + 1, axis: .x), channel: channel)
            + queue(value: y, target: .fx(slot: index + 1, axis: .y), channel: channel)
    }

    private func emitFXXYZ(slot index: Int, x: NTS3CC14Value, y: NTS3CC14Value, depth: NTS3CC14Value, channel: Int) -> [MIDICCMessage] {
        emitFXXY(slot: index, x: x, y: y, channel: channel)
            + queue(value: depth, target: .fx(slot: index + 1, axis: .depth), channel: channel)
    }

    private func queue(part: NTS3CCPart, value: NTS3CC14Value, target: NTS3MappingOutputID, channel: Int) -> [MIDICCMessage] {
        if outputMode == .trim, part == .lsb {
            return []
        }

        return queue(value: value, target: target, channel: channel)
    }

    private func queue(value: NTS3CC14Value, target: NTS3MappingOutputID, channel: Int) -> [MIDICCMessage] {
        if pendingOutputs[target] == nil {
            pendingOutputOrder.append(target)
        }
        pendingOutputs[target] = PendingOutput(value: value, channel: channel)
        return []
    }

    private var hasActiveFX: Bool {
        fxSlots.contains { $0.isActive }
    }

    private func publishState() {
        onStateChange?(snapshot)
    }

    private func isValidDataValue(_ value: Int) -> Bool {
        (0...127).contains(value)
    }

    private func isSwitchValue(_ value: Int) -> Bool {
        value == 0 || value == 127
    }

    private func globalValue(axis: NTS3ControlAxis) -> NTS3CC14Value {
        switch axis {
        case .x:
            return globalX
        case .y:
            return globalY
        case .depth:
            return globalDepth
        }
    }

    private func fxValue(slot index: Int, axis: NTS3ControlAxis) -> NTS3CC14Value {
        switch axis {
        case .x:
            return fxSlots[index].x
        case .y:
            return fxSlots[index].y
        case .depth:
            return fxSlots[index].depth
        }
    }
}

private extension NTS3MappingEngine {
    enum InputControl {
        case masterVolume
        case totalX
        case totalY
        case totalDepth
    }

    struct InputPair {
        let control: InputControl
        let msb: Int
        let lsb: Int
    }

    static let inputMute = 15
    static let totalFXTouch = 102

    static let fx1Freeze = 105
    static let fx1OnOff = 106
    static let fx2Freeze = 109
    static let fx2OnOff = 110
    static let fx3Freeze = 113
    static let fx3OnOff = 114
    static let fx4Freeze = 117
    static let fx4OnOff = 118

    static let inputPairs: [InputPair] = [
        InputPair(control: .masterVolume, msb: 7, lsb: 39),
        InputPair(control: .totalX, msb: 12, lsb: 44),
        InputPair(control: .totalY, msb: 13, lsb: 45),
        InputPair(control: .totalDepth, msb: 14, lsb: 46)
    ]

    static let fxFreezeSlots: [Int: Int] = [
        fx1Freeze: 1,
        fx2Freeze: 2,
        fx3Freeze: 3,
        fx4Freeze: 4
    ]

    static let fxOnOffSlots: [Int: Int] = [
        fx1OnOff: 1,
        fx2OnOff: 2,
        fx3OnOff: 3,
        fx4OnOff: 4
    ]

    static func inputPair(for controller: Int) -> InputPair? {
        inputPairs.first { $0.msb == controller || $0.lsb == controller }
    }

    static func part(for controller: Int, in pair: InputPair) -> NTS3CCPart {
        controller == pair.msb ? .msb : .lsb
    }
}

final class NTS3MappingTransformer: MIDITransformer {
    private let parser = MIDIControlChangeParser()
    private let engine: NTS3MappingEngine
    private let outputChannel: Int
    private let lock = NSLock()
    private var midiLearnSoloTarget: NTS3MappingOutputID?

    init(
        outputMode: NTS3OutputMode,
        outputChannel: Int = 1,
        onStateChange: ((NTS3MappingSnapshot) -> Void)? = nil
    ) {
        engine = NTS3MappingEngine(outputMode: outputMode)
        self.outputChannel = outputChannel
        engine.onStateChange = onStateChange
        onStateChange?(engine.snapshot)
    }

    func transform(packetBytes: [UInt8]) -> [[UInt8]] {
        lock.lock()
        defer { lock.unlock() }

        return parser.parse(packetBytes: packetBytes).flatMap { change in
            engine.handle(change: change)
                .map { $0.routed(to: outputChannel).bytes }
        }
    }

    func flushPendingOutputs() -> [[UInt8]] {
        lock.lock()
        defer { lock.unlock() }

        if midiLearnSoloTarget != nil {
            engine.discardPendingOutputs()
            return []
        }

        return engine.flushPendingOutputs()
            .map { $0.routed(to: outputChannel).bytes }
    }

    func setMIDILearnSoloTarget(_ target: NTS3MappingOutputID?) {
        lock.lock()
        defer { lock.unlock() }

        midiLearnSoloTarget = target
        if target != nil {
            engine.discardPendingOutputs()
        }
    }
}
