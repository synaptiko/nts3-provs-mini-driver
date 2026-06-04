import Foundation

struct WatchEditorDraft {
    var id: UUID?
    var name = ""
    var mode: CCValueMode = .msb
    var msbCC = ""
    var lsbCC = ""

    init() {}

    init(watch: CCWatch) {
        id = watch.id
        name = watch.name
        mode = watch.mode
        msbCC = watch.msbCC.map(String.init) ?? ""
        lsbCC = watch.lsbCC.map(String.init) ?? ""
    }

    var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Name is required."
        }

        switch mode {
        case .msb:
            return validateCC(msbCC, label: "MSB CC")
        case .lsb:
            return validateCC(lsbCC, label: "LSB CC")
        case .both:
            return validateCC(msbCC, label: "MSB CC") ?? validateCC(lsbCC, label: "LSB CC")
        }
    }

    func makeWatch() -> CCWatch? {
        guard validationMessage == nil else {
            return nil
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let watchID = id ?? UUID()

        switch mode {
        case .msb:
            return CCWatch(id: watchID, name: trimmedName, mode: .msb, msbCC: Int(msbCC), lsbCC: nil)
        case .lsb:
            return CCWatch(id: watchID, name: trimmedName, mode: .lsb, msbCC: nil, lsbCC: Int(lsbCC))
        case .both:
            return CCWatch(id: watchID, name: trimmedName, mode: .both, msbCC: Int(msbCC), lsbCC: Int(lsbCC))
        }
    }

    private func validateCC(_ text: String, label: String) -> String? {
        guard let value = Int(text) else {
            return "\(label) must be a number."
        }
        guard (0...127).contains(value) else {
            return "\(label) must be between 0 and 127."
        }
        return nil
    }
}
