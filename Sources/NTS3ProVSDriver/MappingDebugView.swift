import SwiftUI

struct MappingDebugView: View {
    @ObservedObject var model: MappingDebugViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            DashboardGrid(state: model.mappingState)
        }
        .frame(minWidth: 1120, minHeight: 620)
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
}

private struct DashboardGrid: View {
    let state: ProVSMappingSnapshot

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            XYPadCard(state: state)
            GlobalCard(bank: state.bank(.global))
            EffectCard(bank: state.bank(.fx(1)))
            ParameterCard(
                title: "Filter",
                bank: state.bank(.fx(2)),
                color: .cyan,
                fields: [
                    ValueField(title: "Cutoff", axis: .x),
                    ValueField(title: "Resonance", axis: .y)
                ]
            )
            ParameterCard(
                title: "LFO 1",
                bank: state.bank(.fx(3)),
                color: .orange,
                fields: [
                    ValueField(title: "Rate", axis: .x),
                    ValueField(title: "Amount", axis: .y)
                ]
            )
            ParameterCard(
                title: "LFO 2",
                bank: state.bank(.fx(4)),
                color: .green,
                fields: [
                    ValueField(title: "Rate", axis: .x),
                    ValueField(title: "Amount", axis: .y)
                ]
            )
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct XYPadCard: View {
    let state: ProVSMappingSnapshot

    private var activeBank: ProVSBankSnapshot {
        state.bank(state.activeBank)
    }

    var body: some View {
        CardShell(
            title: "X/Y Pad",
            subtitle: activeBank.bank.displayName,
            color: .accentColor,
            isCurrent: true
        ) {
            VectorPad(valueX: activeBank.x, valueY: activeBank.y)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct GlobalCard: View {
    let bank: ProVSBankSnapshot

    var body: some View {
        ParameterCard(
            title: "Global",
            bank: bank,
            color: .accentColor,
            fields: [
                ValueField(title: "Modulation", axis: .x),
                ValueField(title: "Portamento", axis: .y)
            ]
        )
    }
}

private struct EffectCard: View {
    let bank: ProVSBankSnapshot

    private var engine: FXEngineDisplay {
        FXEngineDisplay(bank: bank)
    }

    var body: some View {
        ParameterCard(
            title: engine.title,
            bank: bank,
            color: .purple,
            fields: [
                ValueField(title: engine.xLabel, axis: .x),
                ValueField(title: engine.yLabel, axis: .y)
            ]
        )
    }
}

private struct ParameterCard: View {
    let title: String
    let bank: ProVSBankSnapshot
    let color: Color
    let fields: [ValueField]

    var body: some View {
        CardShell(
            title: title,
            subtitle: bank.bank.displayName,
            color: color,
            isCurrent: bank.isCurrent
        ) {
            VStack(spacing: 14) {
                ForEach(fields) { field in
                    ParameterMeter(
                        title: field.title,
                        value: bank.value(for: field.axis),
                        target: bank.target(for: field.axis),
                        outputValue: bank.outputValue(for: field.axis),
                        color: color
                    )
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct CardShell<Content: View>: View {
    let title: String
    let subtitle: String
    let color: Color
    let isCurrent: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isCurrent ? color : Color.secondary.opacity(0.35))
                    .frame(width: 11, height: 11)
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isCurrent ? color : .secondary)
                    .lineLimit(1)
            }

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isCurrent ? color.opacity(0.65) : Color.primary.opacity(0.08), lineWidth: isCurrent ? 1.5 : 1)
        }
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
                    .fill(Color.accentColor.opacity(0.75))
                    .frame(width: 16, height: 16)
                    .position(x: x, y: y)
            }
        }
    }
}

private struct ValueField: Identifiable {
    let id = UUID()
    var title: String
    var axis: NTS3ControlAxis
}

private struct ParameterMeter: View {
    let title: String
    let value: NTS3CC14Value
    let target: ProVSControlTarget?
    let outputValue: Int?
    let color: Color

    private var midiValue: Int {
        outputValue ?? value.midi7BitValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(target.map { "CC \($0.parameter.controller)" } ?? "Unmapped")
                    .font(.caption)
                    .foregroundStyle(target == nil ? .secondary : .primary)
                    .lineLimit(1)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(target == nil ? Color.secondary.opacity(0.35) : color.opacity(0.75))
                        .frame(width: max(4, geometry.size.width * CGFloat(midiValue) / 127.0))
                }
            }
            .frame(height: 8)

            HStack {
                Text("MIDI \(midiValue)")
                Spacer()
                Text("Display \(value.proVSDisplayValue)")
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }
}

private enum FXEngineDisplay {
    case chorus
    case ensemble
    case reverb

    init(bank: ProVSBankSnapshot) {
        if let outputValue = bank.outputValue(for: .depth) {
            switch outputValue {
            case 0...42:
                self = .chorus
            case 43...84:
                self = .ensemble
            default:
                self = .reverb
            }
            return
        }

        switch bank.depth.midi7BitValue {
        case 0...42:
            self = .chorus
        case 43...84:
            self = .ensemble
        default:
            self = .reverb
        }
    }

    var title: String {
        switch self {
        case .chorus:
            return "Chorus"
        case .ensemble:
            return "Ensemble"
        case .reverb:
            return "Reverb"
        }
    }

    var xLabel: String {
        switch self {
        case .chorus, .ensemble:
            return "Rate"
        case .reverb:
            return "Time"
        }
    }

    var yLabel: String {
        switch self {
        case .chorus:
            return "Amount"
        case .ensemble:
            return "Depth"
        case .reverb:
            return "Level"
        }
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
                ProVSAxisTargetSnapshot(
                    axis: axis,
                    target: ProVSMappingEngine.target(for: bank, axis: axis),
                    outputValue: nil
                )
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

    func outputValue(for axis: NTS3ControlAxis) -> Int? {
        axisTargets.first { $0.axis == axis }?.outputValue
    }
}
