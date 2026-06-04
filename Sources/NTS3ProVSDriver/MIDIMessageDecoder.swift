import Foundation

enum MIDIMessageDecoder {
    static func describe(packetBytes bytes: [UInt8], showRealtime: Bool) -> [String] {
        var descriptions: [String] = []
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]

            if byte < 0x80 {
                descriptions.append("data byte without status: \(formatByte(byte))")
                index += 1
                continue
            }

            if byte >= 0xF8 {
                if showRealtime {
                    descriptions.append(describeRealtime(byte))
                }
                index += 1
                continue
            }

            if byte == 0xF0 {
                if let endIndex = bytes[index...].firstIndex(of: 0xF7) {
                    let length = bytes.distance(from: index, to: endIndex) + 1
                    descriptions.append("SysEx \(length) bytes")
                    index = endIndex + 1
                } else {
                    descriptions.append("SysEx fragment \(bytes.count - index) bytes")
                    index = bytes.count
                }
                continue
            }

            let dataByteCount = expectedDataByteCount(forStatus: byte)
            guard dataByteCount > 0 else {
                descriptions.append(describeSystemCommon(status: byte, data: []))
                index += 1
                continue
            }

            let nextIndex = index + 1
            let endIndex = nextIndex + dataByteCount
            guard endIndex <= bytes.count else {
                descriptions.append("partial message: \(hexString(bytes[index...]))")
                break
            }

            let data = Array(bytes[nextIndex..<endIndex])
            descriptions.append(describe(status: byte, data: data))
            index = endIndex
        }

        if descriptions.isEmpty, !bytes.isEmpty, !showRealtime {
            return []
        }

        return descriptions
    }

    static func hexString<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map(formatByte).joined(separator: " ")
    }

    private static func describe(status: UInt8, data: [UInt8]) -> String {
        if status < 0xF0 {
            return describeChannelVoice(status: status, data: data)
        }
        return describeSystemCommon(status: status, data: data)
    }

    private static func describeChannelVoice(status: UInt8, data: [UInt8]) -> String {
        let type = status & 0xF0
        let channel = Int(status & 0x0F) + 1

        switch type {
        case 0x80:
            return "Note Off ch \(channel) note \(data[0]) velocity \(data[1])"
        case 0x90:
            let eventName = data[1] == 0 ? "Note Off" : "Note On"
            return "\(eventName) ch \(channel) note \(data[0]) velocity \(data[1])"
        case 0xA0:
            return "Poly Pressure ch \(channel) note \(data[0]) pressure \(data[1])"
        case 0xB0:
            let controller = data[0]
            let value = data[1]
            let name = nts3ControllerNames[Int(controller)].map { " \($0)" } ?? ""
            return "CC ch \(channel) #\(controller)\(name) = \(value)"
        case 0xC0:
            return "Program Change ch \(channel) program \(data[0])"
        case 0xD0:
            return "Channel Pressure ch \(channel) pressure \(data[0])"
        case 0xE0:
            let value = Int(data[0]) | (Int(data[1]) << 7)
            return "Pitch Bend ch \(channel) value \(value)"
        default:
            return "Unknown channel message \(formatByte(status)) \(hexString(data))"
        }
    }

    private static func describeSystemCommon(status: UInt8, data: [UInt8]) -> String {
        switch status {
        case 0xF1:
            return "MIDI Time Code Quarter Frame \(data.first ?? 0)"
        case 0xF2:
            let value = data.count == 2 ? Int(data[0]) | (Int(data[1]) << 7) : 0
            return "Song Position Pointer \(value)"
        case 0xF3:
            return "Song Select \(data.first ?? 0)"
        case 0xF6:
            return "Tune Request"
        case 0xF7:
            return "End SysEx"
        default:
            return "System Common \(formatByte(status)) \(hexString(data))"
        }
    }

    private static func describeRealtime(_ status: UInt8) -> String {
        switch status {
        case 0xF8:
            return "Timing Clock"
        case 0xFA:
            return "Start"
        case 0xFB:
            return "Continue"
        case 0xFC:
            return "Stop"
        case 0xFE:
            return "Active Sensing"
        case 0xFF:
            return "System Reset"
        default:
            return "Realtime \(formatByte(status))"
        }
    }

    private static func expectedDataByteCount(forStatus status: UInt8) -> Int {
        if status < 0xF0 {
            switch status & 0xF0 {
            case 0xC0, 0xD0:
                return 1
            default:
                return 2
            }
        }

        switch status {
        case 0xF1, 0xF3:
            return 1
        case 0xF2:
            return 2
        default:
            return 0
        }
    }

    private static func formatByte(_ byte: UInt8) -> String {
        String(format: "%02X", byte)
    }

    private static let nts3ControllerNames: [Int: String] = [
        0: "Bank Select MSB",
        6: "Data Entry MSB",
        7: "Master Volume MSB",
        12: "Total FX Pad X MSB",
        13: "Total FX Pad Y MSB",
        14: "Total FX Depth MSB",
        15: "Input Mute",
        16: "FX 1 Pad X MSB",
        17: "FX 1 Pad Y MSB",
        18: "FX 1 Pad Depth MSB",
        20: "FX 2 Pad X MSB",
        21: "FX 2 Pad Y MSB",
        22: "FX 2 Pad Depth MSB",
        24: "FX 3 Pad X MSB",
        25: "FX 3 Pad Y MSB",
        26: "FX 3 Pad Depth MSB",
        28: "FX 4 Pad X MSB",
        29: "FX 4 Pad Y MSB",
        30: "FX 4 Pad Depth MSB",
        32: "Bank Select LSB",
        38: "Data Entry LSB",
        39: "Master Volume LSB",
        44: "Total FX Pad X LSB",
        45: "Total FX Pad Y LSB",
        46: "Total FX Depth LSB",
        48: "FX 1 Pad X LSB",
        49: "FX 1 Pad Y LSB",
        50: "FX 1 Pad Depth LSB",
        52: "FX 2 Pad X LSB",
        53: "FX 2 Pad Y LSB",
        54: "FX 2 Pad Depth LSB",
        56: "FX 3 Pad X LSB",
        57: "FX 3 Pad Y LSB",
        58: "FX 3 Pad Depth LSB",
        60: "FX 4 Pad X LSB",
        61: "FX 4 Pad Y LSB",
        62: "FX 4 Pad Depth LSB",
        80: "FX 1 Selection",
        81: "FX 2 Selection",
        82: "FX 3 Selection",
        83: "FX 4 Selection",
        98: "NRPN LSB",
        99: "NRPN MSB",
        102: "Total FX Touch",
        103: "Total FX Freeze",
        104: "FX 1 Touch",
        105: "FX 1 Freeze",
        106: "FX 1 On/Off",
        108: "FX 2 Touch",
        109: "FX 2 Freeze",
        110: "FX 2 On/Off",
        112: "FX 3 Touch",
        113: "FX 3 Freeze",
        114: "FX 3 On/Off",
        116: "FX 4 Touch",
        117: "FX 4 Freeze",
        118: "FX 4 On/Off"
    ]
}
