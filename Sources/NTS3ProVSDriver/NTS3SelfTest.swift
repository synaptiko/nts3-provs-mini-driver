import Foundation

enum NTS3SelfTest {
    static func run() -> Bool {
        let tests: [(String, () -> [String])] = [
            ("master volume pair mode", testMasterVolumePreservesPairMode),
            ("pair mode coalesces to Live-compatible pairs", testPairModeCoalescesToLiveCompatiblePairs),
            ("trim mode", testTrimModeSendsMSBOnly),
            ("global mapping and release", testGlobalModeMapsXYDepthAndZerosXYOnTouchRelease),
            ("input mute global freeze", testInputMuteCommitsFrozenGlobalReleaseTarget),
            ("FX activation", testEnteringFXModeZerosGlobalAndActivatedSlot),
            ("individual FX freeze", testIndividualFXFreezeOverridesGlobalReleaseTarget),
            ("global freeze isolation in FX mode", testGlobalFreezeDoesNotLeakIntoFXMode),
            ("input mute freezes target FX independently", testInputMuteFreezesTargetFXIndependently),
            ("staged FX freezes keep independent targets", testStagedFXFreezesKeepIndependentTargets),
            ("frozen target FX still moves live", testFrozenTargetFXStillMovesLive),
            ("depth follows frozen target only", testDepthFollowsFrozenTargetOnly),
            ("target FX freeze persists across reactivation", testTargetFXFreezePersistsAcrossReactivation),
            ("long press input mute clears FX freezes", testLongPressInputMuteClearsFXFreezes),
            ("transformer parser", testTransformerParsesRunningStatusAndIgnoresOtherControls)
        ]

        var failureCount = 0
        for (name, test) in tests {
            let failures = test()
            if failures.isEmpty {
                print("ok - \(name)")
            } else {
                failureCount += failures.count
                print("not ok - \(name)")
                for failure in failures {
                    print("  \(failure)")
                }
            }
        }

        if failureCount == 0 {
            print("Self-test passed: \(tests.count) tests")
            return true
        }

        print("Self-test failed: \(failureCount) failure(s)")
        return false
    }

    private static func testMasterVolumePreservesPairMode() -> [String] {
        let engine = NTS3MappingEngine(outputMode: .pair)
        var failures: [String] = []

        expect(ccs(send(engine, cc(7, 64))), ["10:64", "42:0"], "master MSB", &failures)
        expect(ccs(send(engine, cc(39, 12))), ["10:64", "42:12"], "master LSB", &failures)
        return failures
    }

    private static func testPairModeCoalescesToLiveCompatiblePairs() -> [String] {
        let engine = NTS3MappingEngine(outputMode: .pair)
        var failures: [String] = []

        _ = engine.handle(change: cc(102, 127))
        _ = engine.handle(change: cc(12, 64))
        _ = engine.handle(change: cc(44, 9))
        expect(
            ccs(engine.flushPendingOutputs()),
            ["11:64", "43:9"],
            "coalesced X pair should emit MSB then LSB",
            &failures
        )

        _ = engine.handle(change: cc(12, 70))
        _ = engine.handle(change: cc(13, 80))
        _ = engine.handle(change: cc(45, 10))
        expect(
            ccs(engine.flushPendingOutputs()),
            ["11:70", "43:9", "12:80", "44:10"],
            "dirty targets should remain paired and ordered",
            &failures
        )

        return failures
    }

    private static func testTrimModeSendsMSBOnly() -> [String] {
        let engine = NTS3MappingEngine(outputMode: .trim)
        var failures: [String] = []

        expect(ccs(send(engine, cc(7, 64))), ["10:64"], "trim master MSB", &failures)
        expect(ccs(send(engine, cc(39, 12))), [], "trim master LSB", &failures)

        _ = send(engine, cc(102, 127))
        expect(ccs(send(engine, cc(12, 55))), ["11:55"], "trim X MSB", &failures)
        expect(ccs(send(engine, cc(44, 4))), [], "trim X LSB", &failures)
        expect(ccs(send(engine, cc(102, 0))), ["11:0", "12:0"], "trim release", &failures)
        return failures
    }

    private static func testGlobalModeMapsXYDepthAndZerosXYOnTouchRelease() -> [String] {
        let engine = NTS3MappingEngine(outputMode: .pair)
        var failures: [String] = []

        expect(ccs(send(engine, cc(14, 70))), ["13:70", "45:0"], "global depth MSB", &failures)
        expect(ccs(send(engine, cc(46, 3))), ["13:70", "45:3"], "global depth LSB", &failures)
        _ = send(engine, cc(102, 127))

        expect(ccs(send(engine, cc(12, 30))), ["11:30", "43:0"], "global X MSB", &failures)
        expect(ccs(send(engine, cc(44, 2))), ["11:30", "43:2"], "global X LSB", &failures)
        expect(ccs(send(engine, cc(13, 40))), ["12:40", "44:0"], "global Y MSB", &failures)
        expect(ccs(send(engine, cc(45, 5))), ["12:40", "44:5"], "global Y LSB", &failures)
        expect(
            ccs(send(engine, cc(102, 0))),
            ["11:0", "43:0", "12:0", "44:0"],
            "global touch release",
            &failures
        )
        return failures
    }

    private static func testInputMuteCommitsFrozenGlobalReleaseTarget() -> [String] {
        let engine = NTS3MappingEngine(outputMode: .pair)
        var failures: [String] = []

        _ = send(engine, cc(102, 127))
        _ = send(engine, cc(12, 10))
        _ = send(engine, cc(44, 1))
        _ = send(engine, cc(13, 20))
        _ = send(engine, cc(45, 2))
        expect(ccs(send(engine, cc(15, 127))), [], "freeze arm", &failures)

        _ = send(engine, cc(12, 30))
        _ = send(engine, cc(44, 3))
        _ = send(engine, cc(13, 40))
        _ = send(engine, cc(45, 4))
        expect(
            ccs(send(engine, cc(102, 0))),
            ["11:30", "43:3", "12:40", "44:4"],
            "freeze release target",
            &failures
        )
        expect(engine.snapshot.globalFreezePhase == .frozen, "phase should be frozen", &failures)

        _ = send(engine, cc(102, 127))
        expect(ccs(send(engine, cc(12, 50))), ["11:50", "43:3"], "frozen live update", &failures)
        expect(
            ccs(send(engine, cc(102, 0))),
            ["11:30", "43:3", "12:40", "44:4"],
            "frozen second release",
            &failures
        )

        expect(ccs(send(engine, cc(15, 127))), [], "unfreeze arm", &failures)
        expect(
            ccs(send(engine, cc(15, 0))),
            ["11:0", "43:0", "12:0", "44:0"],
            "unfreeze release target",
            &failures
        )
        expect(engine.snapshot.globalFreezePhase == .normal, "phase should return to normal", &failures)
        return failures
    }

    private static func testEnteringFXModeZerosGlobalAndActivatedSlot() -> [String] {
        let engine = NTS3MappingEngine(outputMode: .pair)
        var failures: [String] = []

        _ = send(engine, cc(102, 127))
        _ = send(engine, cc(12, 64))
        _ = send(engine, cc(13, 32))
        expect(
            ccs(send(engine, cc(106, 127))),
            [
                "11:0", "43:0", "12:0", "44:0", "13:0", "45:0",
                "14:0", "46:0", "15:0", "47:0", "16:0", "48:0"
            ],
            "FX1 activation zeroes",
            &failures
        )
        expect(engine.snapshot.mappingMode == .fx, "mapping mode should be FX", &failures)
        expect(ccs(send(engine, cc(12, 80))), ["14:80", "46:0"], "FX1 X update", &failures)
        expect(ccs(send(engine, cc(14, 51))), ["16:51", "48:0"], "FX1 depth update", &failures)
        expect(
            ccs(send(engine, cc(110, 127))),
            ["17:0", "49:0", "18:0", "50:0", "19:0", "51:0"],
            "FX2 activation zeroes",
            &failures
        )
        return failures
    }

    private static func testIndividualFXFreezeOverridesGlobalReleaseTarget() -> [String] {
        let engine = NTS3MappingEngine(outputMode: .pair)
        var failures: [String] = []

        _ = send(engine, cc(106, 127))
        _ = send(engine, cc(110, 127))
        _ = send(engine, cc(102, 127))
        _ = send(engine, cc(12, 10))
        _ = send(engine, cc(44, 1))
        _ = send(engine, cc(13, 20))
        _ = send(engine, cc(45, 2))
        _ = send(engine, cc(105, 127))

        _ = send(engine, cc(12, 30))
        _ = send(engine, cc(44, 3))
        _ = send(engine, cc(13, 40))
        _ = send(engine, cc(45, 4))
        expect(
            ccs(send(engine, cc(102, 0))),
            [
                "14:10", "46:1", "15:20", "47:2",
                "17:0", "49:0", "18:0", "50:0"
            ],
            "individual frozen release target",
            &failures
        )
        return failures
    }

    private static func testGlobalFreezeDoesNotLeakIntoFXMode() -> [String] {
        let engine = NTS3MappingEngine(outputMode: .pair)
        var failures: [String] = []

        _ = send(engine, cc(102, 127))
        _ = send(engine, cc(12, 30))
        _ = send(engine, cc(44, 3))
        _ = send(engine, cc(13, 40))
        _ = send(engine, cc(45, 4))
        _ = send(engine, cc(15, 127))
        _ = send(engine, cc(102, 0))
        expect(engine.snapshot.globalFreezePhase == .frozen, "global should freeze before FX activation", &failures)

        _ = send(engine, cc(106, 127))
        expect(engine.snapshot.mappingMode == .fx, "mapping mode should be FX", &failures)
        expect(engine.snapshot.globalFreezePhase == .frozen, "global freeze should be parked during FX mode", &failures)

        _ = send(engine, cc(102, 127))
        _ = send(engine, cc(12, 70))
        _ = send(engine, cc(44, 7))
        _ = send(engine, cc(13, 80))
        _ = send(engine, cc(45, 8))
        expect(
            ccs(send(engine, cc(102, 0))),
            ["14:0", "46:0", "15:0", "47:0"],
            "FX release should not use old global freeze",
            &failures
        )
        expect(
            ccs(send(engine, cc(106, 0))),
            [
                "14:0", "46:0", "15:0", "47:0", "16:0", "48:0",
                "11:30", "43:3", "12:40", "44:4"
            ],
            "global release target should resume after last FX turns off",
            &failures
        )
        expect(engine.snapshot.mappingMode == .global, "mapping mode should return to Global", &failures)
        expect(engine.snapshot.globalFreezePhase == .frozen, "global freeze should remain frozen after FX mode", &failures)
        return failures
    }

    private static func testInputMuteFreezesTargetFXIndependently() -> [String] {
        let engine = NTS3MappingEngine(outputMode: .pair)
        var failures: [String] = []

        _ = send(engine, cc(106, 127))
        _ = send(engine, cc(110, 127))
        expect(engine.snapshot.fxFreezeTargetID == 2, "FX2 should be the freeze target", &failures)
        _ = send(engine, cc(102, 127))
        _ = send(engine, cc(12, 10))
        _ = send(engine, cc(44, 1))
        _ = send(engine, cc(13, 20))
        _ = send(engine, cc(45, 2))
        expect(ccs(send(engine, cc(15, 127))), [], "FX mute freeze arm", &failures)

        _ = send(engine, cc(12, 50))
        _ = send(engine, cc(44, 5))
        _ = send(engine, cc(13, 60))
        _ = send(engine, cc(45, 6))
        expect(
            ccs(send(engine, cc(102, 0))),
            [
                "14:0", "46:0", "15:0", "47:0",
                "17:50", "49:5", "18:60", "50:6"
            ],
            "FX mute frozen release",
            &failures
        )
        expect(engine.snapshot.globalFreezePhase == .normal, "global freeze should remain normal", &failures)
        expect(!engine.snapshot.fxSlots[0].isFrozen, "FX1 should not be frozen", &failures)
        expect(engine.snapshot.fxSlots[1].isFrozen, "FX2 should be frozen", &failures)

        expect(ccs(send(engine, cc(15, 127))), [], "FX mute unfreeze arm", &failures)
        expect(
            ccs(send(engine, cc(15, 0))),
            ["17:0", "49:0", "18:0", "50:0"],
            "FX mute unfreeze release",
            &failures
        )
        expect(!engine.snapshot.fxSlots[0].isFrozen, "FX1 should unfreeze", &failures)
        expect(!engine.snapshot.fxSlots[1].isFrozen, "FX2 should unfreeze", &failures)
        return failures
    }

    private static func testStagedFXFreezesKeepIndependentTargets() -> [String] {
        let engine = NTS3MappingEngine(outputMode: .pair)
        var failures: [String] = []

        _ = send(engine, cc(106, 127))
        _ = send(engine, cc(102, 127))
        _ = send(engine, cc(12, 30))
        _ = send(engine, cc(44, 3))
        _ = send(engine, cc(13, 40))
        _ = send(engine, cc(45, 4))
        _ = send(engine, cc(15, 127))
        _ = send(engine, cc(102, 0))
        expect(engine.snapshot.fxSlots[0].isFrozen, "FX1 should be staged frozen", &failures)

        _ = send(engine, cc(110, 127))
        expect(engine.snapshot.fxFreezeTargetID == 2, "FX2 should become target", &failures)
        _ = send(engine, cc(102, 127))
        expect(ccs(send(engine, cc(12, 70))), ["17:70", "49:0"], "only unfrozen FX should move X", &failures)
        _ = send(engine, cc(44, 7))
        expect(ccs(send(engine, cc(13, 80))), ["18:80", "50:0"], "only unfrozen FX should move Y", &failures)
        _ = send(engine, cc(45, 8))
        _ = send(engine, cc(15, 127))
        _ = send(engine, cc(12, 90))
        _ = send(engine, cc(44, 9))
        _ = send(engine, cc(13, 100))
        _ = send(engine, cc(45, 10))

        expect(
            ccs(send(engine, cc(102, 0))),
            [
                "14:30", "46:3", "15:40", "47:4",
                "17:90", "49:9", "18:100", "50:10"
            ],
            "staged FX should return to independent frozen values",
            &failures
        )
        return failures
    }

    private static func testFrozenTargetFXStillMovesLive() -> [String] {
        let engine = NTS3MappingEngine(outputMode: .pair)
        var failures: [String] = []

        _ = send(engine, cc(106, 127))
        _ = send(engine, cc(102, 127))
        _ = send(engine, cc(12, 30))
        _ = send(engine, cc(13, 40))
        _ = send(engine, cc(15, 127))
        _ = send(engine, cc(102, 0))
        expect(engine.snapshot.fxSlots[0].isFrozen, "FX1 should be frozen", &failures)

        _ = send(engine, cc(102, 127))
        expect(ccs(send(engine, cc(12, 90))), ["14:90", "46:0"], "frozen target should move live X", &failures)
        expect(ccs(send(engine, cc(13, 100))), ["15:100", "47:0"], "frozen target should move live Y", &failures)
        expect(
            ccs(send(engine, cc(102, 0))),
            ["14:30", "46:0", "15:40", "47:0"],
            "frozen target should return to frozen release value",
            &failures
        )
        return failures
    }

    private static func testDepthFollowsFrozenTargetOnly() -> [String] {
        let engine = NTS3MappingEngine(outputMode: .pair)
        var failures: [String] = []

        _ = send(engine, cc(106, 127))
        expect(ccs(send(engine, cc(14, 20))), ["16:20", "48:0"], "FX1 initial depth", &failures)
        _ = send(engine, cc(102, 127))
        _ = send(engine, cc(12, 30))
        _ = send(engine, cc(13, 40))
        _ = send(engine, cc(15, 127))
        _ = send(engine, cc(102, 0))
        expect(engine.snapshot.fxSlots[0].isFrozen, "FX1 should be frozen", &failures)

        expect(ccs(send(engine, cc(14, 60))), ["16:60", "48:0"], "frozen target FX1 should receive depth", &failures)
        expect(engine.snapshot.fxSlots[0].depth.msb == 60, "FX1 target depth should update", &failures)

        _ = send(engine, cc(110, 127))
        expect(engine.snapshot.fxFreezeTargetID == 2, "FX2 should become target", &failures)
        expect(ccs(send(engine, cc(14, 70))), ["19:70", "51:0"], "only unfrozen FX2 should receive depth", &failures)
        expect(engine.snapshot.fxSlots[0].depth.msb == 60, "FX1 parked depth should remain unchanged", &failures)
        expect(engine.snapshot.fxSlots[1].depth.msb == 70, "FX2 depth should update", &failures)
        return failures
    }

    private static func testTargetFXFreezePersistsAcrossReactivation() -> [String] {
        let engine = NTS3MappingEngine(outputMode: .pair)
        var failures: [String] = []

        _ = send(engine, cc(106, 127))
        expect(engine.snapshot.fxFreezeTargetID == 1, "FX1 should start as freeze target", &failures)
        _ = send(engine, cc(102, 127))
        _ = send(engine, cc(12, 20))
        _ = send(engine, cc(44, 2))
        _ = send(engine, cc(13, 30))
        _ = send(engine, cc(45, 3))
        _ = send(engine, cc(15, 127))
        _ = send(engine, cc(12, 40))
        _ = send(engine, cc(44, 4))
        _ = send(engine, cc(13, 50))
        _ = send(engine, cc(45, 5))
        expect(
            ccs(send(engine, cc(102, 0))),
            ["14:40", "46:4", "15:50", "47:5"],
            "FX1 should freeze to latest armed target",
            &failures
        )

        expect(
            ccs(send(engine, cc(106, 0))),
            [
                "14:0", "46:0", "15:0", "47:0", "16:0", "48:0",
                "11:0", "43:0", "12:0", "44:0"
            ],
            "FX1 deactivate should zero outputs",
            &failures
        )
        expect(!engine.snapshot.fxSlots[0].isActive, "FX1 should be inactive", &failures)
        expect(engine.snapshot.fxSlots[0].isFrozen, "FX1 freeze should be stored while inactive", &failures)

        expect(
            ccs(send(engine, cc(106, 127))),
            [
                "11:0", "43:0", "12:0", "44:0", "13:0", "45:0",
                "14:40", "46:4", "15:50", "47:5", "16:0", "48:0"
            ],
            "FX1 reactivate should restore frozen X/Y",
            &failures
        )
        expect(engine.snapshot.fxFreezeTargetID == 1, "FX1 should become target again", &failures)
        return failures
    }

    private static func testLongPressInputMuteClearsFXFreezes() -> [String] {
        let engine = NTS3MappingEngine(outputMode: .pair)
        var failures: [String] = []

        _ = send(engine, cc(106, 127))
        _ = send(engine, cc(102, 127))
        _ = send(engine, cc(12, 30))
        _ = send(engine, cc(13, 40))
        _ = send(engine, cc(15, 127), timestamp: 0.0)
        _ = send(engine, cc(102, 0), timestamp: 0.1)
        _ = send(engine, cc(110, 127))
        _ = send(engine, cc(102, 127))
        _ = send(engine, cc(12, 70))
        _ = send(engine, cc(13, 80))
        _ = send(engine, cc(15, 127), timestamp: 0.2)
        _ = send(engine, cc(102, 0), timestamp: 0.3)
        expect(engine.snapshot.fxSlots[0].isFrozen, "FX1 should be frozen before long press", &failures)
        expect(engine.snapshot.fxSlots[1].isFrozen, "FX2 should be frozen before long press", &failures)

        _ = send(engine, cc(15, 127), timestamp: 1.0)
        expect(
            ccs(send(engine, cc(15, 0), timestamp: 1.0 + NTS3MappingEngine.fxMuteLongPressDuration + 0.05)),
            [
                "14:0", "46:0", "15:0", "47:0",
                "17:0", "49:0", "18:0", "50:0"
            ],
            "long press should clear active FX release targets",
            &failures
        )
        expect(!engine.snapshot.fxSlots[0].isFrozen, "FX1 should clear after long press", &failures)
        expect(!engine.snapshot.fxSlots[1].isFrozen, "FX2 should clear after long press", &failures)

        _ = send(engine, cc(106, 0))
        _ = send(engine, cc(106, 127))
        expect(!engine.snapshot.fxSlots[0].isFrozen, "FX1 stored freeze should stay cleared", &failures)
        return failures
    }

    private static func testTransformerParsesRunningStatusAndIgnoresOtherControls() -> [String] {
        let transformer = NTS3MappingTransformer(outputMode: .trim)
        var failures: [String] = []

        expect(transformer.transform(packetBytes: [0xB0, 99, 1]), [], "ignored NRPN", &failures)
        expect(transformer.transform(packetBytes: [0xB0, 7, 64, 39, 3]), [], "running status input should queue", &failures)
        expect(transformer.flushPendingOutputs(), [[0xB0, 10, 64]], "running status flush", &failures)
        return failures
    }

    private static func cc(_ controller: Int, _ value: Int, channel: Int = 1) -> MIDIControlChange {
        MIDIControlChange(channel: channel, controller: controller, value: value)
    }

    private static func ccs(_ messages: [MIDICCMessage]) -> [String] {
        messages.map { "\($0.controller):\($0.value)" }
    }

    private static func send(_ engine: NTS3MappingEngine, _ change: MIDIControlChange) -> [MIDICCMessage] {
        _ = engine.handle(change: change)
        return engine.flushPendingOutputs()
    }

    private static func send(
        _ engine: NTS3MappingEngine,
        _ change: MIDIControlChange,
        timestamp: TimeInterval
    ) -> [MIDICCMessage] {
        _ = engine.handle(change: change, timestamp: timestamp)
        return engine.flushPendingOutputs()
    }

    private static func expect<T: Equatable>(_ actual: T, _ expected: T, _ label: String, _ failures: inout [String]) {
        guard actual != expected else {
            return
        }
        failures.append("\(label): expected \(expected), got \(actual)")
    }

    private static func expect(_ condition: Bool, _ label: String, _ failures: inout [String]) {
        guard condition else {
            failures.append(label)
            return
        }
    }
}
