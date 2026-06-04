import SwiftUI

struct MappingDebugView: View {
    @ObservedObject var model: MappingDebugViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            DashboardGrid(model: model)
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
    @ObservedObject var model: MappingDebugViewModel

    private var state: ProVSMappingSnapshot {
        model.mappingState
    }

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            XYPadCard(model: model, state: state)
            GlobalCard(
                bank: state.bank(.global),
                onSelect: { model.select(bank: .global) },
                onValueChange: { axis, value in model.setValue(bank: .global, axis: axis, midiValue: value) }
            )
            EffectCard(
                bank: state.bank(.fx(1)),
                onSelect: { model.select(bank: .fx(1)) },
                onValueChange: { axis, value in model.setValue(bank: .fx(1), axis: axis, midiValue: value) }
            )
            ParameterCard(
                title: "Filter",
                bank: state.bank(.fx(2)),
                color: .cyan,
                fields: [
                    ValueField(title: "Cutoff", axis: .x),
                    ValueField(title: "Resonance", axis: .y)
                ],
                onSelect: { model.select(bank: .fx(2)) },
                onValueChange: { axis, value in model.setValue(bank: .fx(2), axis: axis, midiValue: value) }
            )
            ParameterCard(
                title: "LFO 1",
                bank: state.bank(.fx(3)),
                color: .orange,
                fields: [
                    ValueField(title: "Rate", axis: .x),
                    ValueField(title: "Amount", axis: .y)
                ],
                onSelect: { model.select(bank: .fx(3)) },
                onValueChange: { axis, value in model.setValue(bank: .fx(3), axis: axis, midiValue: value) }
            )
            ParameterCard(
                title: "LFO 2",
                bank: state.bank(.fx(4)),
                color: .green,
                fields: [
                    ValueField(title: "Rate", axis: .x),
                    ValueField(title: "Amount", axis: .y)
                ],
                onSelect: { model.select(bank: .fx(4)) },
                onValueChange: { axis, value in model.setValue(bank: .fx(4), axis: axis, midiValue: value) }
            )
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct XYPadCard: View {
    @ObservedObject var model: MappingDebugViewModel
    let state: ProVSMappingSnapshot

    private var activeBank: ProVSBankSnapshot {
        state.bank(state.activeBank)
    }

    private var activeColor: Color {
        activeBank.bank.dashboardColor
    }

    var body: some View {
        CardShell(
            title: "X/Y Pad",
            subtitle: activeBank.bank.displayName,
            color: activeColor,
            isCurrent: true,
            onSelect: {}
        ) {
            VectorPad(valueX: activeBank.x, valueY: activeBank.y, color: activeColor) { x, y in
                model.setXY(bank: activeBank.bank, normalizedX: x, normalizedY: y)
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct GlobalCard: View {
    let bank: ProVSBankSnapshot
    let onSelect: () -> Void
    let onValueChange: (NTS3ControlAxis, Int) -> Void

    var body: some View {
        ParameterCard(
            title: "Global",
            bank: bank,
            color: .accentColor,
            fields: [
                ValueField(title: "Modulation", axis: .x),
                ValueField(title: "Portamento", axis: .y)
            ],
            onSelect: onSelect,
            onValueChange: onValueChange
        )
    }
}

private struct EffectCard: View {
    let bank: ProVSBankSnapshot
    let onSelect: () -> Void
    let onValueChange: (NTS3ControlAxis, Int) -> Void

    private var engine: FXEngineDisplay {
        FXEngineDisplay(bank: bank)
    }

    var body: some View {
        CardShell(
            title: engine.title,
            subtitle: bank.bank.displayName,
            color: bank.bank.dashboardColor,
            isCurrent: bank.isCurrent,
            onSelect: onSelect
        ) {
            VStack(spacing: 8) {
                FXEngineSelector(activeEngine: engine) { selectedEngine in
                    onSelect()
                    onValueChange(.depth, selectedEngine.midiValue)
                }

                ParameterMeter(
                    title: engine.xLabel,
                    value: bank.x,
                    target: bank.target(for: .x),
                    outputValue: bank.outputValue(for: .x),
                    color: bank.bank.dashboardColor,
                    onEditingBegan: onSelect,
                    onValueChange: { value in onValueChange(.x, value) }
                )

                ParameterMeter(
                    title: engine.yLabel,
                    value: bank.y,
                    target: bank.target(for: .y),
                    outputValue: bank.outputValue(for: .y),
                    color: bank.bank.dashboardColor,
                    onEditingBegan: onSelect,
                    onValueChange: { value in onValueChange(.y, value) }
                )
            }
        }
    }
}

private struct ParameterCard: View {
    let title: String
    let bank: ProVSBankSnapshot
    let color: Color
    let fields: [ValueField]
    let onSelect: () -> Void
    let onValueChange: (NTS3ControlAxis, Int) -> Void

    var body: some View {
        CardShell(
            title: title,
            subtitle: bank.bank.displayName,
            color: color,
            isCurrent: bank.isCurrent,
            onSelect: onSelect
        ) {
            VStack(spacing: 10) {
                ForEach(fields) { field in
                    ParameterMeter(
                        title: field.title,
                        value: bank.value(for: field.axis),
                        target: bank.target(for: field.axis),
                        outputValue: bank.outputValue(for: field.axis),
                        color: color,
                        onEditingBegan: onSelect,
                        onValueChange: { value in
                            onValueChange(field.axis, value)
                        }
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
    let onSelect: () -> Void
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
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onSelect)
    }
}

private struct VectorPad: View {
    let valueX: NTS3CC14Value
    let valueY: NTS3CC14Value
    let color: Color
    var onChange: (Double, Double) -> Void = { _, _ in }

    var body: some View {
        GeometryReader { geometry in
            let plotInset: CGFloat = 13
            let plotWidth = max(geometry.size.width - (plotInset * 2), 1)
            let plotHeight = max(geometry.size.height - (plotInset * 2), 1)
            let x = plotInset + (CGFloat(valueX.normalized) * plotWidth)
            let y = plotInset + ((1.0 - CGFloat(valueY.normalized)) * plotHeight)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .underPageBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(color.opacity(0.2), lineWidth: 1)
                    }
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
                    .fill(color.opacity(0.78))
                    .frame(width: 18, height: 18)
                    .position(x: x, y: y)
            }
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let normalizedX = clamp(Double((gesture.location.x - plotInset) / plotWidth))
                        let normalizedY = clamp(Double(1.0 - ((gesture.location.y - plotInset) / plotHeight)))
                        onChange(normalizedX, normalizedY)
                    }
            )
        }
    }

    private func clamp(_ value: Double) -> Double {
        max(0.0, min(value, 1.0))
    }
}

private struct ValueField: Identifiable {
    var title: String
    var axis: NTS3ControlAxis

    var id: NTS3ControlAxis {
        axis
    }
}

private struct ParameterMeter: View {
    let title: String
    let value: NTS3CC14Value
    let target: ProVSControlTarget?
    let outputValue: Int?
    let color: Color
    let onEditingBegan: () -> Void
    let onValueChange: (Int) -> Void

    @State private var isDragging = false

    private var midiValue: Int {
        outputValue ?? value.midi7BitValue
    }

    var body: some View {
        GeometryReader { geometry in
            let drag = DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    if !isDragging {
                        isDragging = true
                        onEditingBegan()
                    }

                    onValueChange(midiValue(at: gesture.location.x, width: geometry.size.width))
                }
                .onEnded { _ in
                    isDragging = false
                }

            VStack(alignment: .leading, spacing: 4) {
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

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(target == nil ? Color.secondary.opacity(0.35) : color.opacity(0.75))
                        .frame(width: max(4, geometry.size.width * CGFloat(midiValue) / 127.0))
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
            .padding(.vertical, 6)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .highPriorityGesture(drag)
        }
        .frame(height: 58)
    }

    private func midiValue(at xPosition: CGFloat, width: CGFloat) -> Int {
        let fraction = max(0.0, min(xPosition / max(width, 1), 1.0))
        return Int((fraction * 127.0).rounded())
    }
}

private struct FXEngineSelector: View {
    let activeEngine: FXEngineDisplay
    let onSelect: (FXEngineDisplay) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("Selected Effect:")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            ForEach(FXEngineDisplay.allCases) { engine in
                Button {
                    onSelect(engine)
                } label: {
                    Text(engine.title)
                        .font(.caption.weight(engine == activeEngine ? .semibold : .medium))
                        .foregroundStyle(engine == activeEngine ? Color.primary : Color.secondary.opacity(0.6))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum FXEngineDisplay: CaseIterable, Identifiable {
    case chorus
    case ensemble
    case reverb

    var id: String {
        title
    }

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

    var midiValue: Int {
        switch self {
        case .chorus:
            return 21
        case .ensemble:
            return 64
        case .reverb:
            return 106
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

private extension MappingBank {
    var dashboardColor: Color {
        switch self {
        case .global:
            return .accentColor
        case .fx(1):
            return .purple
        case .fx(2):
            return .cyan
        case .fx(3):
            return .orange
        case .fx(4):
            return .green
        default:
            return .secondary
        }
    }
}
