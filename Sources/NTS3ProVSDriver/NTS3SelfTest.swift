import Foundation

enum NTS3SelfTest {
    static func run() -> Bool {
        let tests: [(String, () -> [String])] = [
            ("NTS-3 CC parser", testParserRunningStatusAndIgnoresNonCC),
            ("14-bit scaling", test14BitScaling),
            ("Global modulation and portamento mappings", testGlobalModulationAndPortamentoMappings),
            ("confirmed FX mappings", testConfirmedFXMappings),
            ("FX1 depth selects FX engine", testFX1DepthSelectsFXEngine),
            ("last activated FX wins", testLastActivatedFXWins),
            ("bank switching emits no reset", testBankSwitchingEmitsNoReset),
            ("touch release latches values", testTouchReleaseLatchesValues),
            ("unmapped depth is stored", testUnmappedDepthIsStored),
            ("volume experimental flags", testVolumeExperimentalFlags),
            ("input mute play toggle is edge detected", testInputMutePlayToggleIsEdgeDetected),
            ("transformer channel and running status", testTransformerChannelAndRunningStatus),
            ("manual debug interactions", testManualDebugInteractions)
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

    private static func testParserRunningStatusAndIgnoresNonCC() -> [String] {
        let parser = MIDIControlChangeParser()
        var failures: [String] = []

        expect(
            parser.parse(packetBytes: [0xB0, 12, 64, 44, 1]).map { "\($0.controller):\($0.value)" },
            ["12:64", "44:1"],
            "running status CCs",
            &failures
        )
        expect(parser.parse(packetBytes: [0x90, 60, 100]).isEmpty, "note on should be ignored", &failures)
        expect(parser.parse(packetBytes: [0xF8]).isEmpty, "realtime should be ignored by parser", &failures)
        return failures
    }

    private static func test14BitScaling() -> [String] {
        var failures: [String] = []

        expect(NTS3CC14Value(combined: 0).midi7BitValue, 0, "minimum MIDI value", &failures)
        expect(NTS3CC14Value(combined: 16_383).midi7BitValue, 127, "maximum MIDI value", &failures)
        expect(NTS3CC14Value(combined: 8_192).midi7BitValue, 64, "midpoint MIDI value", &failures)
        expect(NTS3CC14Value(combined: 16_383).proVSDisplayValue, 99, "maximum display projection", &failures)
        return failures
    }

    private static func testGlobalModulationAndPortamentoMappings() -> [String] {
        let engine = ProVSMappingEngine(outputChannel: 1)
        var failures: [String] = []

        _ = send(engine, cc(102, 127))
        expect(outputs(send(engine, cc(12, 64))), ["cc ch1 1:64"], "global X -> modulation", &failures)
        expect(outputs(send(engine, cc(13, 32))), ["cc ch1 5:32"], "global Y -> portamento", &failures)
        expect(engine.snapshot.activeBank, .global, "active bank should remain global", &failures)
        let global = bank(.global, in: engine.snapshot)
        expect(global?.x.msb, 64, "global X should latch", &failures)
        expect(global?.y.msb, 32, "global Y should latch", &failures)
        return failures
    }

    private static func testConfirmedFXMappings() -> [String] {
        let engine = ProVSMappingEngine(outputChannel: 1)
        var failures: [String] = []

        _ = send(engine, cc(102, 127))
        _ = send(engine, cc(106, 127))
        expect(outputs(send(engine, cc(12, 64))), ["cc ch1 92:64"], "FX1 X -> chorus rate", &failures)
        expect(outputs(send(engine, cc(13, 96))), ["cc ch1 91:96"], "FX1 Y -> chorus amount", &failures)
        expect(outputs(send(engine, cc(14, 20))), ["cc ch1 9:21"], "FX1 Depth -> chorus engine", &failures)

        _ = send(engine, cc(110, 127))
        expect(outputs(send(engine, cc(12, 20))), ["cc ch1 74:20"], "FX2 X -> cutoff", &failures)
        expect(outputs(send(engine, cc(13, 40))), ["cc ch1 71:40"], "FX2 Y -> resonance", &failures)

        _ = send(engine, cc(114, 127))
        expect(outputs(send(engine, cc(12, 50))), ["cc ch1 72:50"], "FX3 X -> LFO1 rate", &failures)
        expect(outputs(send(engine, cc(13, 60))), ["cc ch1 70:60"], "FX3 Y -> LFO1 amount", &failures)

        _ = send(engine, cc(118, 127))
        expect(outputs(send(engine, cc(12, 70))), ["cc ch1 73:70"], "FX4 X -> LFO2 rate", &failures)
        expect(outputs(send(engine, cc(13, 80))), ["cc ch1 28:80"], "FX4 Y -> LFO2 amount", &failures)
        return failures
    }

    private static func testFX1DepthSelectsFXEngine() -> [String] {
        let engine = ProVSMappingEngine(outputChannel: 1)
        var failures: [String] = []

        _ = send(engine, cc(106, 127))
        expect(outputs(send(engine, cc(14, 0))), ["cc ch1 9:21"], "lowest depth should select chorus", &failures)
        expect(outputs(send(engine, cc(14, 44))), [], "hysteresis should keep chorus near ensemble split", &failures)
        expect(outputs(send(engine, cc(14, 45))), ["cc ch1 9:64"], "depth above hysteresis should select ensemble", &failures)
        expect(outputs(send(engine, cc(14, 83))), [], "hysteresis should keep ensemble near reverb split", &failures)
        expect(outputs(send(engine, cc(14, 87))), ["cc ch1 9:106"], "depth above hysteresis should select reverb", &failures)
        expect(outputs(send(engine, cc(14, 83))), [], "hysteresis should keep reverb near ensemble split", &failures)
        expect(outputs(send(engine, cc(14, 82))), ["cc ch1 9:64"], "depth below hysteresis should return to ensemble", &failures)
        expect(outputs(send(engine, cc(14, 41))), [], "hysteresis should keep ensemble near chorus split", &failures)
        expect(outputs(send(engine, cc(14, 40))), ["cc ch1 9:21"], "depth below hysteresis should return to chorus", &failures)
        return failures
    }

    private static func testLastActivatedFXWins() -> [String] {
        let engine = ProVSMappingEngine(outputChannel: 1)
        var failures: [String] = []

        _ = send(engine, cc(102, 127))
        _ = send(engine, cc(106, 127))
        _ = send(engine, cc(110, 127))
        expect(engine.snapshot.activeBank, .fx(2), "FX2 should win after activation", &failures)
        expect(outputs(send(engine, cc(12, 64))), ["cc ch1 74:64"], "pad X should route to FX2", &failures)

        _ = send(engine, cc(110, 0))
        expect(engine.snapshot.activeBank, .fx(1), "FX1 should resume after FX2 off", &failures)
        expect(outputs(send(engine, cc(13, 32))), ["cc ch1 91:32"], "pad Y should route to FX1", &failures)
        return failures
    }

    private static func testBankSwitchingEmitsNoReset() -> [String] {
        let engine = ProVSMappingEngine(outputChannel: 1)
        var failures: [String] = []

        _ = send(engine, cc(102, 127))
        _ = send(engine, cc(106, 127))
        _ = send(engine, cc(12, 64))
        expect(outputs(send(engine, cc(110, 127))), [], "activating FX2 should not reset FX1 or emit FX2 zero", &failures)
        expect(outputs(send(engine, cc(110, 0))), [], "deactivating FX2 should not reset or restore values", &failures)
        expect(outputs(send(engine, cc(106, 0))), [], "leaving last FX should not reset values", &failures)
        return failures
    }

    private static func testTouchReleaseLatchesValues() -> [String] {
        let engine = ProVSMappingEngine(outputChannel: 1)
        var failures: [String] = []

        _ = send(engine, cc(102, 127))
        _ = send(engine, cc(106, 127))
        _ = send(engine, cc(12, 80))
        expect(outputs(send(engine, cc(102, 0))), [], "touch release should emit no reset", &failures)
        expect(outputs(send(engine, cc(12, 10))), [], "X movement while not touched should be ignored", &failures)
        expect(bank(.fx(1), in: engine.snapshot)?.x.msb, 80, "FX1 X should stay latched", &failures)
        return failures
    }

    private static func testUnmappedDepthIsStored() -> [String] {
        let engine = ProVSMappingEngine(outputChannel: 1)
        var failures: [String] = []

        _ = send(engine, cc(110, 127))
        expect(outputs(send(engine, cc(14, 70))), [], "FX depth should be unmapped", &failures)
        expect(bank(.fx(2), in: engine.snapshot)?.depth.msb, 70, "FX depth should latch", &failures)
        return failures
    }

    private static func testVolumeExperimentalFlags() -> [String] {
        var failures: [String] = []

        let defaultEngine = ProVSMappingEngine(outputChannel: 1)
        expect(outputs(send(defaultEngine, cc(7, 64))), [], "volume should be disabled by default", &failures)

        let cc7Engine = ProVSMappingEngine(
            outputChannel: 2,
            experimentalOptions: ProVSExperimentalOptions(volumeMapping: .channelVolume)
        )
        expect(outputs(send(cc7Engine, cc(7, 64))), ["cc ch2 7:64"], "volume CC7 flag", &failures)

        let cc11Engine = ProVSMappingEngine(
            outputChannel: 3,
            experimentalOptions: ProVSExperimentalOptions(volumeMapping: .expression)
        )
        expect(outputs(send(cc11Engine, cc(7, 32))), ["cc ch3 11:32"], "volume CC11 flag", &failures)
        return failures
    }

    private static func testInputMutePlayToggleIsEdgeDetected() -> [String] {
        let engine = ProVSMappingEngine(
            outputChannel: 1,
            experimentalOptions: ProVSExperimentalOptions(playToggleEnabled: true)
        )
        var failures: [String] = []

        expect(outputs(send(engine, cc(15, 127))), ["rt start"], "first press should start", &failures)
        expect(outputs(send(engine, cc(15, 127))), [], "held press should not repeat", &failures)
        expect(outputs(send(engine, cc(15, 0))), [], "release should not toggle", &failures)
        expect(outputs(send(engine, cc(15, 127))), ["rt stop"], "second press should stop", &failures)
        return failures
    }

    private static func testTransformerChannelAndRunningStatus() -> [String] {
        let transformer = NTS3MappingTransformer(outputChannel: 4)
        var failures: [String] = []

        expect(transformer.transform(packetBytes: [0xB0, 102, 127, 106, 127]), [], "switches should emit nothing", &failures)
        expect(transformer.transform(packetBytes: [0xB0, 12, 64]), [], "FX1 X should queue", &failures)
        expect(transformer.flushPendingOutputs(), [[0xB3, 92, 64]], "flush should use output channel 4", &failures)
        return failures
    }

    private static func testManualDebugInteractions() -> [String] {
        let transformer = NTS3MappingTransformer(outputChannel: 2)
        var failures: [String] = []

        expect(transformer.select(bank: .fx(2)), [], "manual select should not emit", &failures)
        expect(
            transformer.setValue(bank: .fx(2), axis: .x, value: NTS3CC14Value(midi7BitValue: 77)),
            [[0xB1, 74, 77]],
            "manual filter cutoff",
            &failures
        )
        expect(
            transformer.setXY(
                bank: .fx(1),
                x: NTS3CC14Value(midi7BitValue: 33),
                y: NTS3CC14Value(midi7BitValue: 44)
            ),
            [[0xB1, 92, 33], [0xB1, 91, 44]],
            "manual effects XY",
            &failures
        )
        expect(
            transformer.setXY(
                bank: .global,
                x: NTS3CC14Value(midi7BitValue: 10),
                y: NTS3CC14Value(midi7BitValue: 20)
            ),
            [[0xB1, 1, 10], [0xB1, 5, 20]],
            "manual global XY",
            &failures
        )
        return failures
    }

    private static func cc(_ controller: Int, _ value: Int, channel: Int = 1) -> MIDIControlChange {
        MIDIControlChange(channel: channel, controller: controller, value: value)
    }

    private static func send(_ engine: ProVSMappingEngine, _ change: MIDIControlChange) -> [MIDIOutputMessage] {
        let immediate = engine.handle(change: change)
        return immediate + engine.flushPendingOutputs()
    }

    private static func outputs(_ messages: [MIDIOutputMessage]) -> [String] {
        messages.map { message in
            switch message {
            case .controlChange(let cc, _):
                return "cc ch\(cc.channel) \(cc.controller):\(cc.value)"
            case .realtime(let realtime):
                return "rt \(realtime.displayName.lowercased())"
            }
        }
    }

    private static func bank(_ bank: MappingBank, in snapshot: ProVSMappingSnapshot) -> ProVSBankSnapshot? {
        snapshot.banks.first { $0.bank == bank }
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
