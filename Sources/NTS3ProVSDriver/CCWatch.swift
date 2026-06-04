import Foundation

enum CCValueMode: String, CaseIterable, Codable, Identifiable {
    case msb = "MSB"
    case lsb = "LSB"
    case both = "Both"

    var id: String { rawValue }
}

struct CCWatch: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var mode: CCValueMode
    var msbCC: Int?
    var lsbCC: Int?

    var ccSummary: String {
        switch mode {
        case .msb:
            return msbCC.map(String.init) ?? "-"
        case .lsb:
            return lsbCC.map(String.init) ?? "-"
        case .both:
            return "\(msbCC.map(String.init) ?? "-") / \(lsbCC.map(String.init) ?? "-")"
        }
    }

    func matches(controller: Int) -> Bool {
        switch mode {
        case .msb:
            return msbCC == controller
        case .lsb:
            return lsbCC == controller
        case .both:
            return msbCC == controller || lsbCC == controller
        }
    }
}

struct CCValueEvent: Identifiable, Equatable {
    let id = UUID()
    let elapsed: TimeInterval
    let channel: Int
    let controller: Int
    let rawValue: Int
    let msbValue: Int?
    let lsbValue: Int?
    let combinedValue: Int?
    let displayValue: String
}

struct CCWatchRuntimeState: Equatable {
    var latestMSB: Int?
    var latestLSB: Int?
    var latestChannel: Int?
    var latestController: Int?
    var latestRawValue: Int?
    var latestElapsed: TimeInterval?
    var history: [CCValueEvent] = []

    var latestValueText: String {
        if let latestMSB, let latestLSB {
            return "\(latestMSB << 7 | latestLSB)"
        }
        if let latestMSB {
            return "MSB \(latestMSB)"
        }
        if let latestLSB {
            return "LSB \(latestLSB)"
        }
        return "-"
    }

    var latestTimeText: String {
        guard let latestElapsed else {
            return "-"
        }
        return String(format: "%.3fs", latestElapsed)
    }
}

struct MIDIControlChange {
    let channel: Int
    let controller: Int
    let value: Int
}

extension CCWatch {
    static let nts3Defaults: [CCWatch] = [
        paired("Master Volume", 7, 39),
        paired("Total FX X", 12, 44),
        paired("Total FX Y", 13, 45),
        paired("Total FX Depth", 14, 46),
        single("Input Mute", 15),
        paired("FX 1 X", 16, 48),
        paired("FX 1 Y", 17, 49),
        paired("FX 1 Depth", 18, 50),
        paired("FX 2 X", 20, 52),
        paired("FX 2 Y", 21, 53),
        paired("FX 2 Depth", 22, 54),
        paired("FX 3 X", 24, 56),
        paired("FX 3 Y", 25, 57),
        paired("FX 3 Depth", 26, 58),
        paired("FX 4 X", 28, 60),
        paired("FX 4 Y", 29, 61),
        paired("FX 4 Depth", 30, 62),
        single("FX 1 Selection", 80),
        single("FX 2 Selection", 81),
        single("FX 3 Selection", 82),
        single("FX 4 Selection", 83),
        single("Total FX Touch", 102),
        single("Total FX Freeze", 103),
        single("FX 1 Touch", 104),
        single("FX 1 Freeze", 105),
        single("FX 1 On/Off", 106),
        single("FX 2 Touch", 108),
        single("FX 2 Freeze", 109),
        single("FX 2 On/Off", 110),
        single("FX 3 Touch", 112),
        single("FX 3 Freeze", 113),
        single("FX 3 On/Off", 114),
        single("FX 4 Touch", 116),
        single("FX 4 Freeze", 117),
        single("FX 4 On/Off", 118)
    ]

    private static func paired(_ name: String, _ msb: Int, _ lsb: Int) -> CCWatch {
        CCWatch(name: name, mode: .both, msbCC: msb, lsbCC: lsb)
    }

    private static func single(_ name: String, _ cc: Int) -> CCWatch {
        CCWatch(name: name, mode: .msb, msbCC: cc, lsbCC: nil)
    }
}
