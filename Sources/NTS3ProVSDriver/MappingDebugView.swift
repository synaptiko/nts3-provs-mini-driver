import SwiftUI

struct MappingDebugView: View {
    @ObservedObject var model: MappingDebugViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                BankListView(state: model.mappingState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                StatePanel(model: model)
                    .frame(width: 360)
            }
        }
        .frame(minWidth: 1040, minHeight: 680)
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

                Text("Ch \(model.mappingState.outputChannel)")
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

private struct BankListView: View {
    let state: ProVSMappingSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(state.banks) { bank in
                    BankRow(bank: bank)
                }
            }
            .padding(18)
        }
    }
}

private struct BankRow: View {
    let bank: ProVSBankSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(bank.isCurrent ? Color.accentColor : bank.isActive ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 10, height: 10)

                Text(bank.bank.displayName)
                    .font(.headline)

                Text(bank.isCurrent ? "Current" : bank.isActive ? "Active" : "Latched")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(bank.isCurrent ? Color.accentColor : .secondary)

                Spacer()
            }

            HStack(alignment: .top, spacing: 12) {
                AxisValueColumn(axis: .x, value: bank.x, target: target(for: .x))
                AxisValueColumn(axis: .y, value: bank.y, target: target(for: .y))
                AxisValueColumn(axis: .depth, value: bank.depth, target: target(for: .depth))
            }
        }
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(bank.isCurrent ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: bank.isCurrent ? 1.5 : 1)
        }
    }

    private func target(for axis: NTS3ControlAxis) -> ProVSControlTarget? {
        bank.axisTargets.first { $0.axis == axis }?.target
    }
}

private struct AxisValueColumn: View {
    let axis: NTS3ControlAxis
    let value: NTS3CC14Value
    let target: ProVSControlTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(axis.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("\(value.combined)")
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .monospacedDigit()

            Text("MIDI \(value.midi7BitValue) / display \(value.proVSDisplayValue)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(target?.displayName ?? "Unmapped")
                .font(.caption)
                .foregroundStyle(target == nil ? .secondary : .primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    StateRow(label: "Play Toggle", value: state.playToggleState ? "started" : "stopped")
                }

                PanelSection(title: "Experimental") {
                    StateRow(label: "Volume", value: state.experimentalOptions.volumeMapping.displayName)
                    StateRow(label: "Play Start/Stop", value: state.experimentalOptions.playToggleEnabled ? "enabled" : "disabled")
                }

                PanelSection(title: "Volume Input") {
                    StateRow(label: "NTS-3 Volume", value: state.volume.debugText)
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
