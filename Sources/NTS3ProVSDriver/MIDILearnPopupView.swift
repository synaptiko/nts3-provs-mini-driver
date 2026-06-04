import SwiftUI

struct MIDILearnPopupView: View {
    @ObservedObject var model: MappingDebugViewModel
    let onSelect: (NTS3MappingOutputID) -> Void

    private let rows = MIDILearnTargetRow.all
    private let columns = MIDILearnTargetColumn.all
    private let rowLabelWidth: CGFloat = 64
    private let cellWidth: CGFloat = 84

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            targetMatrix
        }
        .padding(16)
        .frame(width: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Learn MIDI")
                .font(.headline)
            Text(model.isRunning ? "Bridge running" : "Bridge stopped")
                .font(.caption)
                .foregroundStyle(model.isRunning ? .green : .secondary)
        }
    }

    private var targetMatrix: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("")
                    .frame(width: rowLabelWidth)

                ForEach(columns) { column in
                    Text(column.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: cellWidth)
                }
            }

            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Text(row.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: rowLabelWidth, alignment: .leading)

                    ForEach(columns) { column in
                        if let target = row.target(for: column) {
                            MIDILearnTargetButton(
                                target: target,
                                isActive: model.activeMIDILearnTargetID == target.id,
                                isEnabled: model.isRunning
                            ) {
                                onSelect(target)
                            }
                            .frame(width: cellWidth)
                        } else {
                            Color.clear
                                .frame(width: cellWidth, height: 36)
                        }
                    }
                }
            }
        }
    }
}

private struct MIDILearnTargetColumn: Identifiable {
    let id: String
    let title: String

    static let all: [MIDILearnTargetColumn] = [
        MIDILearnTargetColumn(id: "global", title: "Global"),
        MIDILearnTargetColumn(id: "fx-1", title: "FX 1"),
        MIDILearnTargetColumn(id: "fx-2", title: "FX 2"),
        MIDILearnTargetColumn(id: "fx-3", title: "FX 3"),
        MIDILearnTargetColumn(id: "fx-4", title: "FX 4")
    ]
}

private struct MIDILearnTargetRow: Identifiable {
    let id: String
    let title: String
    private let targets: [String: NTS3MappingOutputID]

    func target(for column: MIDILearnTargetColumn) -> NTS3MappingOutputID? {
        targets[column.id]
    }

    static let all: [MIDILearnTargetRow] = [
        MIDILearnTargetRow(
            id: "volume",
            title: "Volume",
            targets: ["global": .masterVolume]
        ),
        MIDILearnTargetRow(
            id: "depth",
            title: "Depth",
            targets: [
                "global": .global(.depth),
                "fx-1": .fx(slot: 1, axis: .depth),
                "fx-2": .fx(slot: 2, axis: .depth),
                "fx-3": .fx(slot: 3, axis: .depth),
                "fx-4": .fx(slot: 4, axis: .depth)
            ]
        ),
        MIDILearnTargetRow(
            id: "x",
            title: "X",
            targets: [
                "global": .global(.x),
                "fx-1": .fx(slot: 1, axis: .x),
                "fx-2": .fx(slot: 2, axis: .x),
                "fx-3": .fx(slot: 3, axis: .x),
                "fx-4": .fx(slot: 4, axis: .x)
            ]
        ),
        MIDILearnTargetRow(
            id: "y",
            title: "Y",
            targets: [
                "global": .global(.y),
                "fx-1": .fx(slot: 1, axis: .y),
                "fx-2": .fx(slot: 2, axis: .y),
                "fx-3": .fx(slot: 3, axis: .y),
                "fx-4": .fx(slot: 4, axis: .y)
            ]
        )
    ]
}

private struct MIDILearnTargetButton: View {
    let target: NTS3MappingOutputID
    let isActive: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(target.ccText)
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .buttonStyle(MIDILearnCellButtonStyle(isActive: isActive))
        .disabled(!isEnabled)
        .help("\(target.displayTitle) \(target.ccText)")
    }
}

private struct MIDILearnCellButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let isActive: Bool

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 36)
            .padding(.horizontal, 8)
            .foregroundStyle(foregroundColor)
            .background(fillColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(strokeColor, lineWidth: isActive ? 1.5 : 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        if !isEnabled {
            return .secondary
        }
        return isActive ? .accentColor : .primary
    }

    private func fillColor(isPressed: Bool) -> Color {
        if !isEnabled {
            return Color(nsColor: .controlBackgroundColor).opacity(0.55)
        }
        if isActive {
            return Color.accentColor.opacity(isPressed ? 0.16 : 0.10)
        }
        if isPressed {
            return Color.primary.opacity(0.075)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var strokeColor: Color {
        if isActive {
            return Color.accentColor.opacity(0.65)
        }
        return Color.primary.opacity(0.14)
    }
}
