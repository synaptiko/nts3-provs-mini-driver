import SwiftUI

struct MappingDebugView: View {
    @ObservedObject var model: MappingDebugViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                ProVSPanelView(state: model.mappingState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                StatePanel(model: model)
                    .frame(width: 360)
            }
        }
        .frame(minWidth: 1120, minHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pro VS Mini Driver")
                        .font(.title2.weight(.semibold))
                    Text(model.isRunning ? "Bridge running" : "Bridge stopped")
                        .font(.caption)
                        .foregroundStyle(model.isRunning ? .green : .secondary)
                }

                Spacer()

                StatusPill(title: model.mappingState.activeBank.displayName, color: .accentColor)
                StatusPill(title: "Ch \(model.mappingState.outputChannel)", color: .teal)

                Button(model.isRunning ? "Restart" : "Start") {
                    model.restartBridge()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Stop") {
                    model.stopBridge()
                }
                .disabled(!model.isRunning)
            }

            HStack(spacing: 12) {
                labeledTextField("Input filter", text: $model.inputNameFilter, width: 210)
                labeledTextField("Pro VS destination", text: $model.outputNameFilter, width: 250)
                Spacer()
                statusText
            }
        }
        .padding(16)
    }

    private func labeledTextField(_ label: String, text: Binding<String>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
        }
    }

    private var statusText: some View {
        VStack(alignment: .trailing, spacing: 2) {
            ForEach(Array(model.statusMessages.suffix(2).enumerated()), id: \.offset) { _, message in
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: 400, alignment: .trailing)
    }
}

private struct ProVSPanelView: View {
    let state: ProVSMappingSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BankStrip(state: state)
                GlobalAndExperimentalRow(state: state)
                ParameterSectionGrid(state: state)
            }
            .padding(18)
        }
    }
}

private struct BankStrip: View {
    let state: ProVSMappingSnapshot

    var body: some View {
        HStack(spacing: 10) {
            ForEach(state.banks) { bank in
                BankChip(bank: bank)
            }
        }
    }
}

private struct BankChip: View {
    let bank: ProVSBankSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(bank.isCurrent ? Color.accentColor : bank.isActive ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 10, height: 10)

            Text(bank.bank.displayName)
                .font(.caption.weight(.semibold))

            Text(bank.isCurrent ? "Current" : bank.isActive ? "Active" : "Latched")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(bank.isCurrent ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.08), lineWidth: bank.isCurrent ? 1.5 : 1)
        }
    }
}

private struct GlobalAndExperimentalRow: View {
    let state: ProVSMappingSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            GlobalVectorPanel(global: state.bank(.global))
                .frame(maxWidth: .infinity)

            ExperimentalPanel(state: state)
                .frame(width: 250)
        }
    }
}

private struct GlobalVectorPanel: View {
    let global: ProVSBankSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Global Vector")
                    .font(.headline)
                StatusPill(title: "Mod + Portamento", color: .accentColor)
                Spacer()
            }

            HStack(spacing: 14) {
                VectorPad(valueX: global.x, valueY: global.y)
                    .frame(width: 230, height: 150)

                VStack(alignment: .leading, spacing: 10) {
                    AxisReadout(axis: .x, value: global.x, target: global.target(for: .x))
                    AxisReadout(axis: .y, value: global.y, target: global.target(for: .y))
                    AxisReadout(axis: .depth, value: global.depth, target: global.target(for: .depth))
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct VectorPad: View {
    let valueX: NTS3CC14Value
    let valueY: NTS3CC14Value

    var body: some View {
        GeometryReader { geometry in
            let x = CGFloat(valueX.normalized) * geometry.size.width
            let y = (1.0 - CGFloat(valueY.normalized)) * geometry.size.height

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .underPageBackgroundColor))
                GridLines()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                Path { path in
                    path.move(to: CGPoint(x: geometry.size.width / 2, y: 0))
                    path.addLine(to: CGPoint(x: geometry.size.width / 2, y: geometry.size.height))
                    path.move(to: CGPoint(x: 0, y: geometry.size.height / 2))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height / 2))
                }
                .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                Circle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 16, height: 16)
                    .position(x: x, y: y)
            }
        }
    }
}

private struct ExperimentalPanel: View {
    let state: ProVSMappingSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Experimental")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                IndicatorRow(
                    title: "Volume",
                    value: state.experimentalOptions.volumeMapping.displayName,
                    isEnabled: state.experimentalOptions.volumeMapping != .disabled
                )
                IndicatorRow(
                    title: "Play",
                    value: state.experimentalOptions.playToggleEnabled ? (state.playToggleState ? "Start" : "Stop") : "Disabled",
                    isEnabled: state.experimentalOptions.playToggleEnabled
                )
                AxisReadout(axis: .depth, value: state.volume, target: volumeTarget(for: state))
            }
        }
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func volumeTarget(for state: ProVSMappingSnapshot) -> ProVSControlTarget? {
        state.experimentalOptions.volumeMapping.parameter.map {
            ProVSControlTarget(bank: .global, axis: nil, parameter: $0)
        }
    }
}

private struct ParameterSectionGrid: View {
    let state: ProVSMappingSnapshot

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
            ParameterSection(
                title: "Filter",
                bank: state.bank(.fx(1)),
                color: .cyan,
                rows: [
                    ParameterRow(title: "Cutoff", axis: .x),
                    ParameterRow(title: "Resonance", axis: .y)
                ]
            )
            ParameterSection(
                title: "Chorus",
                bank: state.bank(.fx(2)),
                color: .purple,
                rows: [
                    ParameterRow(title: "Rate", axis: .x),
                    ParameterRow(title: "Amount", axis: .y)
                ]
            )
            ParameterSection(
                title: "LFO 1",
                bank: state.bank(.fx(3)),
                color: .orange,
                rows: [
                    ParameterRow(title: "Rate", axis: .x),
                    ParameterRow(title: "Amount", axis: .y)
                ]
            )
            ParameterSection(
                title: "LFO 2",
                bank: state.bank(.fx(4)),
                color: .green,
                rows: [
                    ParameterRow(title: "Rate", axis: .x),
                    ParameterRow(title: "Amount", axis: .y)
                ]
            )
        }
    }
}

private struct ParameterRow: Identifiable {
    let id = UUID()
    var title: String
    var axis: NTS3ControlAxis
}

private struct ParameterSection: View {
    let title: String
    let bank: ProVSBankSnapshot
    let color: Color
    let rows: [ParameterRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Circle()
                    .fill(bank.isCurrent ? color : bank.isActive ? color.opacity(0.7) : Color.secondary.opacity(0.35))
                    .frame(width: 11, height: 11)
                Text(title)
                    .font(.headline)
                Text(bank.bank.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(bank.isCurrent ? "Current" : bank.isActive ? "Active" : "Latched")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(bank.isCurrent ? color : .secondary)
            }

            ForEach(rows) { row in
                ParameterMeter(
                    title: row.title,
                    value: bank.value(for: row.axis),
                    target: bank.target(for: row.axis),
                    color: color
                )
            }

            ParameterMeter(
                title: "Depth",
                value: bank.depth,
                target: bank.target(for: .depth),
                color: .secondary
            )
        }
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(bank.isCurrent ? color.opacity(0.65) : Color.primary.opacity(0.08), lineWidth: bank.isCurrent ? 1.5 : 1)
        }
    }
}

private struct ParameterMeter: View {
    let title: String
    let value: NTS3CC14Value
    let target: ProVSControlTarget?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(target.map { "CC \($0.parameter.controller)" } ?? "Unmapped")
                    .font(.caption)
                    .foregroundStyle(target == nil ? .secondary : .primary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(target == nil ? Color.secondary.opacity(0.35) : color.opacity(0.75))
                        .frame(width: max(4, geometry.size.width * CGFloat(value.midi7BitValue) / 127.0))
                }
            }
            .frame(height: 8)

            HStack {
                Text("MIDI \(value.midi7BitValue)")
                Spacer()
                Text("Display \(value.proVSDisplayValue)")
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }
}

private struct AxisReadout: View {
    let axis: NTS3ControlAxis
    let value: NTS3CC14Value
    let target: ProVSControlTarget?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(axis.rawValue)
                .font(.caption.weight(.semibold))
                .frame(width: 42, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(value.combined)")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                Text(target?.displayName ?? "Unmapped")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct IndicatorRow: View {
    let title: String
    let value: String
    let isEnabled: Bool

    var body: some View {
        HStack {
            Circle()
                .fill(isEnabled ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 9, height: 9)
            Text(title)
                .font(.caption.weight(.semibold))
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct StatePanel: View {
    @ObservedObject var model: MappingDebugViewModel

    private var state: ProVSMappingSnapshot {
        model.mappingState
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PanelSection(title: "Routing") {
                    StateRow(label: "Current Bank", value: state.activeBank.displayName)
                    StateRow(label: "Last FX", value: state.lastActivatedFX.map { "FX \($0)" } ?? "-")
                    StateRow(label: "Touch", value: "\(state.padTouchValue)")
                    StateRow(label: "Mute", value: "\(state.inputMuteValue)")
                    StateRow(label: "Output Channel", value: "\(state.outputChannel)")
                }

                PanelSection(title: "Global") {
                    let global = state.bank(.global)
                    StateRow(label: "X", value: global.x.debugText)
                    StateRow(label: "Y", value: global.y.debugText)
                    StateRow(label: "Depth", value: global.depth.debugText)
                    StateRow(label: "Volume", value: state.volume.debugText)
                }

                PanelSection(title: "Recent Output") {
                    if state.recentOutputs.isEmpty {
                        Text("No output yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(state.recentOutputs.reversed()) { output in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(output.bankName) - \(output.targetName)")
                                    .font(.caption.weight(.semibold))
                                Text(output.detail)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StateRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 10)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}

private struct StatusPill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.13), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct GridLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for fraction in stride(from: 0.25, through: 0.75, by: 0.25) {
            let x = rect.minX + rect.width * fraction
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))

            let y = rect.minY + rect.height * fraction
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

private extension ProVSMappingSnapshot {
    func bank(_ bank: MappingBank) -> ProVSBankSnapshot {
        banks.first { $0.bank == bank } ?? ProVSBankSnapshot(
            bank: bank,
            isActive: bank == .global,
            isCurrent: activeBank == bank,
            x: .zero,
            y: .zero,
            depth: .zero,
            axisTargets: NTS3ControlAxis.allCases.map { axis in
                ProVSAxisTargetSnapshot(axis: axis, target: ProVSMappingEngine.target(for: bank, axis: axis))
            }
        )
    }
}

private extension ProVSBankSnapshot {
    func value(for axis: NTS3ControlAxis) -> NTS3CC14Value {
        switch axis {
        case .x:
            return x
        case .y:
            return y
        case .depth:
            return depth
        }
    }

    func target(for axis: NTS3ControlAxis) -> ProVSControlTarget? {
        axisTargets.first { $0.axis == axis }?.target
    }
}
