import SwiftUI

struct MIDIWatchView: View {
    @ObservedObject var model: MIDIWatchViewModel
    @State private var editorDraft = WatchEditorDraft()
    @State private var isEditorPresented = false
    @State private var historyWatch: CCWatch?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            watchHeader
            Divider()
            watchList
        }
        .frame(minWidth: 980, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $isEditorPresented) {
            WatchEditorSheet(
                draft: $editorDraft,
                onCancel: { isEditorPresented = false },
                onSave: saveDraft
            )
        }
        .sheet(item: $historyWatch) { watch in
            HistorySheet(
                watch: watch,
                state: model.state(for: watch),
                onClear: { model.clearHistory(for: watch) }
            )
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NTS-3 Pro VS Mini Driver")
                        .font(.title2.weight(.semibold))
                    Text(model.isRunning ? "Bridge running" : "Bridge stopped")
                        .font(.caption)
                        .foregroundStyle(model.isRunning ? .green : .secondary)
                }

                Spacer()

                Button("Add CC") {
                    editorDraft = WatchEditorDraft()
                    isEditorPresented = true
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Load NTS-3 Defaults") {
                    model.loadDefaults()
                }

                Button("Clear Values") {
                    model.resetValues()
                }

                Button(model.isRunning ? "Restart" : "Start") {
                    model.restartBridge()
                }
                .keyboardShortcut("r", modifiers: [.command])
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
        .frame(maxWidth: 380, alignment: .trailing)
    }

    private var watchHeader: some View {
        HStack(spacing: 12) {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Mode").frame(width: 68, alignment: .leading)
            Text("CC").frame(width: 90, alignment: .leading)
            Text("Latest").frame(width: 120, alignment: .trailing)
            Text("Last Seen").frame(width: 86, alignment: .trailing)
            Text("Events").frame(width: 64, alignment: .trailing)
            Text("").frame(width: 190)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var watchList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.watches) { watch in
                    WatchRow(
                        watch: watch,
                        state: model.state(for: watch),
                        onHistory: { historyWatch = watch },
                        onEdit: {
                            editorDraft = WatchEditorDraft(watch: watch)
                            isEditorPresented = true
                        },
                        onRemove: { model.removeWatch(watch) }
                    )
                    Divider()
                }
            }
        }
    }

    private func saveDraft() {
        guard let watch = editorDraft.makeWatch() else {
            return
        }

        if model.watches.contains(where: { $0.id == watch.id }) {
            model.updateWatch(watch)
        } else {
            model.addWatch(watch)
        }

        isEditorPresented = false
    }
}

private struct WatchRow: View {
    let watch: CCWatch
    let state: CCWatchRuntimeState
    let onHistory: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(watch.name)
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(watch.mode.rawValue)
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .leading)
            Text(watch.ccSummary)
                .font(.system(.body, design: .monospaced))
                .frame(width: 90, alignment: .leading)
            Text(state.latestValueText)
                .font(.system(.body, design: .monospaced))
                .monospacedDigit()
                .frame(width: 120, alignment: .trailing)
            Text(state.latestTimeText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .trailing)
            Text("\(state.history.count)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)

            HStack(spacing: 8) {
                Button("History", action: onHistory)
                    .disabled(state.history.isEmpty)
                Button("Edit", action: onEdit)
                Button("Remove", action: onRemove)
            }
            .frame(width: 190, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(state.latestElapsed == nil ? Color.clear : Color.accentColor.opacity(0.06))
    }
}

private struct WatchEditorSheet: View {
    @Binding var draft: WatchEditorDraft
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.id == nil ? "Add MIDI CC" : "Edit MIDI CC")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 10) {
                TextField("Display name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)

                Picker("Value mode", selection: $draft.mode) {
                    ForEach(CCValueMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if draft.mode == .msb || draft.mode == .both {
                    TextField("MSB CC number", text: $draft.msbCC)
                        .textFieldStyle(.roundedBorder)
                }

                if draft.mode == .lsb || draft.mode == .both {
                    TextField("LSB CC number", text: $draft.lsbCC)
                        .textFieldStyle(.roundedBorder)
                }

                if let validationMessage = draft.validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.validationMessage != nil)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

private struct HistorySheet: View {
    let watch: CCWatch
    let state: CCWatchRuntimeState
    let onClear: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(watch.name)
                        .font(.title3.weight(.semibold))
                    Text("\(state.history.count) recorded values")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear") {
                    onClear()
                    dismiss()
                }
                .disabled(state.history.isEmpty)
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            historyHeader
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(state.history.reversed()) { event in
                        HStack(spacing: 12) {
                            Text(String(format: "%.3fs", event.elapsed))
                                .frame(width: 82, alignment: .trailing)
                            Text("ch \(event.channel)")
                                .frame(width: 44, alignment: .leading)
                            Text("CC \(event.controller)")
                                .frame(width: 54, alignment: .leading)
                            Text("\(event.rawValue)")
                                .frame(width: 52, alignment: .trailing)
                            Text(event.displayValue)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.system(.body, design: .monospaced))
                        .monospacedDigit()
                        .padding(.vertical, 5)
                        Divider()
                    }
                }
            }
            .frame(minHeight: 300)
        }
        .padding(18)
        .frame(width: 560, height: 460)
    }

    private var historyHeader: some View {
        HStack(spacing: 12) {
            Text("Time").frame(width: 82, alignment: .trailing)
            Text("Chan").frame(width: 44, alignment: .leading)
            Text("CC").frame(width: 54, alignment: .leading)
            Text("Raw").frame(width: 52, alignment: .trailing)
            Text("Value").frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}
