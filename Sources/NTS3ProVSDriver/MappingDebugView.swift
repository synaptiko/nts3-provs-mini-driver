import SwiftUI

struct MappingDebugView: View {
    @ObservedObject var model: MappingDebugViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 18) {
                    FXStatusRow(state: model.mappingState)
                    ControlSurfaceView(state: model.mappingState)
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()
                StatePanel(model: model)
                    .frame(width: 340)
            }
        }
        .frame(minWidth: 1120, minHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NTS-3 Mapping Debug")
                        .font(.title2.weight(.semibold))
                    Text(model.isRunning ? "Bridge running" : "Bridge stopped")
                        .font(.caption)
                        .foregroundStyle(model.isRunning ? .green : .secondary)
                }

                Spacer()

                Text(model.mappingState.outputMode.rawValue)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())

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
                labeledTextField("Virtual source", text: $model.virtualSourceName, width: 250)
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

private struct FXStatusRow: View {
    let state: NTS3MappingSnapshot

    var body: some View {
        HStack(spacing: 10) {
            ForEach(state.fxSlots) { slot in
                FXStatusIndicator(
                    slot: slot,
                    isFreezeTarget: state.fxFreezeTargetID == slot.id
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FXStatusIndicator: View {
    let slot: NTS3FXSlotSnapshot
    let isFreezeTarget: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(fxColor(slot.id))
                .frame(width: 12, height: 12)
                .shadow(color: slot.isActive ? fxColor(slot.id).opacity(0.85) : .clear, radius: 8)

            Text("FX \(slot.id)")
                .font(.body.weight(.semibold))

            Text(slot.isActive ? "Active" : "Inactive")
                .font(.caption)
                .foregroundStyle(slot.isActive ? .primary : .secondary)

            if slot.isFrozen {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(fxColor(slot.id))
            }

            if isFreezeTarget {
                Image(systemName: "scope")
                    .font(.caption)
                    .foregroundStyle(fxColor(slot.id))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(slot.isActive ? fxColor(slot.id).opacity(0.12) : Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(slot.isFrozen || isFreezeTarget ? fxColor(slot.id) : Color.clear, lineWidth: isFreezeTarget ? 2 : 1.5)
        }
    }
}

private struct ControlSurfaceView: View {
    let state: NTS3MappingSnapshot

    var body: some View {
        GeometryReader { geometry in
            let depthWidth: CGFloat = 74
            let gap: CGFloat = 18
            let availableWidth = max(320, geometry.size.width - depthWidth - gap)
            let padWidth = min(availableWidth, max(360, geometry.size.height * 2.2))
            let padHeight = padWidth / 2.2

            HStack(alignment: .top, spacing: gap) {
                DepthStripView(state: state)
                    .frame(width: depthWidth, height: padHeight)
                XYPadView(state: state)
                    .frame(width: padWidth, height: padHeight)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
        .frame(minHeight: 430)
    }
}

private struct XYPadView: View {
    let state: NTS3MappingSnapshot

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.22), lineWidth: 1)
                GridLines()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)

                if state.mappingMode == .global, state.globalFreezePhase != .normal {
                    FrozenRing(
                        valueX: state.globalFrozenX,
                        valueY: state.globalFrozenY,
                        color: .black,
                        radius: 18,
                        size: geometry.size
                    )
                }

                if state.mappingMode == .global {
                    ValueCircle(
                        valueX: state.globalX,
                        valueY: state.globalY,
                        color: .black,
                        radius: 13,
                        size: geometry.size,
                        opacity: 0.32
                    )
                }

                ForEach(Array(state.fxSlots.filter(\.isActive).reversed())) { slot in
                    if slot.isFrozen {
                        FrozenRing(
                            valueX: slot.frozenX,
                            valueY: slot.frozenY,
                            color: fxColor(slot.id),
                            radius: fxRadius(slot.id) + 7,
                            size: geometry.size
                        )
                    }

                    ValueCircle(
                        valueX: slot.x,
                        valueY: slot.y,
                        color: fxColor(slot.id),
                        radius: fxRadius(slot.id),
                        size: geometry.size,
                        opacity: 0.28
                    )
                }
            }
        }
        .aspectRatio(2.2, contentMode: .fit)
    }
}

private struct DepthStripView: View {
    let state: NTS3MappingSnapshot

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.22), lineWidth: 1)

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 8)
                    .cornerRadius(4)

                if state.mappingMode == .global {
                    DepthMarker(value: state.globalDepth, color: .black, size: geometry.size, xOffset: 0)
                }

                ForEach(state.fxSlots.filter(\.isActive)) { slot in
                    DepthMarker(
                        value: slot.depth,
                        color: fxColor(slot.id),
                        size: geometry.size,
                        xOffset: markerOffset(slot.id)
                    )
                }
            }
        }
    }

    private func markerOffset(_ slot: Int) -> CGFloat {
        switch slot {
        case 1:
            return -18
        case 2:
            return -6
        case 3:
            return 6
        default:
            return 18
        }
    }
}

private struct StatePanel: View {
    @ObservedObject var model: MappingDebugViewModel

    private var state: NTS3MappingSnapshot {
        model.mappingState
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PanelSection(title: "State") {
                    StateRow(label: "Mode", value: state.mappingMode.rawValue)
                    StateRow(label: "Global Freeze", value: state.globalFreezePhase.rawValue)
                    StateRow(label: "FX Mute Freeze", value: state.fxMuteFreezePhase.rawValue)
                    StateRow(label: "FX Freeze Target", value: state.fxFreezeTargetID.map { "FX \($0)" } ?? "-")
                    StateRow(label: "Touch", value: "\(state.totalFXTouchValue)")
                    StateRow(label: "Mute", value: "\(state.inputMuteValue)")
                    StateRow(label: "Output", value: state.outputMode.rawValue)
                }

                PanelSection(title: "Global") {
                    StateRow(label: "X", value: state.globalX.debugText)
                    StateRow(label: "Y", value: state.globalY.debugText)
                    StateRow(label: "Depth", value: state.globalDepth.debugText)
                    StateRow(label: "Frozen X", value: state.globalFrozenX.debugText)
                    StateRow(label: "Frozen Y", value: state.globalFrozenY.debugText)
                }

                ForEach(state.fxSlots) { slot in
                    PanelSection(title: "FX \(slot.id)") {
                        StateRow(label: "Active", value: slot.isActive ? "yes" : "no")
                        StateRow(label: "Frozen", value: slot.isFrozen ? "yes" : "no")
                        StateRow(label: "X", value: slot.x.debugText)
                        StateRow(label: "Y", value: slot.y.debugText)
                        StateRow(label: "Depth", value: slot.depth.debugText)
                        StateRow(label: "Frozen X", value: slot.frozenX.debugText)
                        StateRow(label: "Frozen Y", value: slot.frozenY.debugText)
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
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct StateRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
                .monospacedDigit()
        }
        .font(.callout)
    }
}

private struct ValueCircle: View {
    let valueX: NTS3CC14Value
    let valueY: NTS3CC14Value
    let color: Color
    let radius: CGFloat
    let size: CGSize
    let opacity: Double

    var body: some View {
        Circle()
            .fill(color.opacity(opacity))
            .overlay(Circle().stroke(color, lineWidth: 2))
            .frame(width: radius * 2, height: radius * 2)
            .position(point(forX: valueX, y: valueY, in: size))
    }
}

private struct FrozenRing: View {
    let valueX: NTS3CC14Value
    let valueY: NTS3CC14Value
    let color: Color
    let radius: CGFloat
    let size: CGSize

    var body: some View {
        Circle()
            .stroke(color.opacity(0.58), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            .frame(width: radius * 2, height: radius * 2)
            .position(point(forX: valueX, y: valueY, in: size))
    }
}

private struct DepthMarker: View {
    let value: NTS3CC14Value
    let color: Color
    let size: CGSize
    let xOffset: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .frame(width: 38, height: 8)
            .shadow(color: color.opacity(0.45), radius: 5)
            .position(x: size.width / 2 + xOffset, y: yPosition(for: value, height: size.height))
    }
}

private struct GridLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 1...3 {
            let x = rect.minX + rect.width * CGFloat(index) / 4
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        for index in 1...3 {
            let y = rect.minY + rect.height * CGFloat(index) / 4
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

private func point(forX x: NTS3CC14Value, y: NTS3CC14Value, in size: CGSize) -> CGPoint {
    CGPoint(
        x: max(0, min(size.width, CGFloat(x.normalized) * size.width)),
        y: yPosition(for: y, height: size.height)
    )
}

private func yPosition(for value: NTS3CC14Value, height: CGFloat) -> CGFloat {
    max(0, min(height, (1 - CGFloat(value.normalized)) * height))
}

private func fxColor(_ slot: Int) -> Color {
    switch slot {
    case 1:
        return Color(red: 0.86, green: 0.14, blue: 0.18)
    case 2:
        return Color(red: 0.12, green: 0.62, blue: 0.30)
    case 3:
        return Color(red: 0.12, green: 0.36, blue: 0.88)
    default:
        return Color(red: 0.94, green: 0.68, blue: 0.10)
    }
}

private func fxRadius(_ slot: Int) -> CGFloat {
    CGFloat(10 + slot * 5)
}

private extension NTS3CC14Value {
    var debugText: String {
        "\(msb)/\(lsb) (\(combined))"
    }
}
