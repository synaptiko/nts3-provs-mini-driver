import Foundation

final class MIDIControlChangeParser {
    private var runningStatus: UInt8?

    func parse(packetBytes bytes: [UInt8]) -> [MIDIControlChange] {
        var changes: [MIDIControlChange] = []
        var index = 0

        while index < bytes.count {
            var status = runningStatus
            let byte = bytes[index]

            if byte >= 0x80 {
                if byte >= 0xF8 {
                    index += 1
                    continue
                }

                if byte == 0xF0 {
                    runningStatus = nil
                    if let endIndex = bytes[index...].firstIndex(of: 0xF7) {
                        index = endIndex + 1
                    } else {
                        index = bytes.count
                    }
                    continue
                }

                if byte >= 0xF0 {
                    runningStatus = nil
                    index += 1 + expectedDataByteCount(forStatus: byte)
                    continue
                }

                runningStatus = byte
                status = byte
                index += 1
            }

            guard let status, status < 0xF0 else {
                index += 1
                continue
            }

            let dataCount = expectedDataByteCount(forStatus: status)
            guard dataCount > 0, index + dataCount <= bytes.count else {
                break
            }

            let data = bytes[index..<(index + dataCount)]
            if status & 0xF0 == 0xB0, data.count == 2 {
                changes.append(
                    MIDIControlChange(
                        channel: Int(status & 0x0F) + 1,
                        controller: Int(data[data.startIndex]),
                        value: Int(data[data.index(after: data.startIndex)])
                    )
                )
            }

            index += dataCount
        }

        return changes
    }

    private func expectedDataByteCount(forStatus status: UInt8) -> Int {
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
}
