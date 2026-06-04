import CoreMIDI
import Foundation

protocol MIDITransformer {
    func transform(packetBytes: [UInt8]) -> [[UInt8]]
    func flushPendingOutputs() -> [[UInt8]]
}

extension MIDITransformer {
    func flushPendingOutputs() -> [[UInt8]] {
        []
    }
}

struct PassThroughTransformer: MIDITransformer {
    func transform(packetBytes: [UInt8]) -> [[UInt8]] {
        [packetBytes]
    }
}
