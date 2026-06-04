import CoreMIDI
import Foundation

enum CoreMIDIError: Error, CustomStringConvertible {
    case operationFailed(String, OSStatus)

    var description: String {
        switch self {
        case .operationFailed(let operation, let status):
            return "\(operation) failed with OSStatus \(status)"
        }
    }
}

func checkMIDIStatus(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else {
        throw CoreMIDIError.operationFailed(operation, status)
    }
}

func midiStringProperty(_ object: MIDIObjectRef, _ property: CFString) -> String? {
    var unmanagedValue: Unmanaged<CFString>?
    let status = MIDIObjectGetStringProperty(object, property, &unmanagedValue)
    guard status == noErr, let value = unmanagedValue?.takeRetainedValue() else {
        return nil
    }
    return value as String
}

func midiIntegerProperty(_ object: MIDIObjectRef, _ property: CFString) -> Int32? {
    var value: Int32 = 0
    let status = MIDIObjectGetIntegerProperty(object, property, &value)
    guard status == noErr else {
        return nil
    }
    return value
}

func midiDisplayName(_ object: MIDIObjectRef) -> String {
    midiStringProperty(object, kMIDIPropertyDisplayName)
        ?? midiStringProperty(object, kMIDIPropertyName)
        ?? "Unnamed endpoint \(object)"
}

func midiEndpointSummary(_ endpoint: MIDIEndpointRef) -> String {
    let name = midiDisplayName(endpoint)
    let manufacturer = midiStringProperty(endpoint, kMIDIPropertyManufacturer)
    let model = midiStringProperty(endpoint, kMIDIPropertyModel)
    let uniqueID = midiIntegerProperty(endpoint, kMIDIPropertyUniqueID)

    var details: [String] = []
    if let manufacturer, !manufacturer.isEmpty {
        details.append(manufacturer)
    }
    if let model, !model.isEmpty {
        details.append(model)
    }
    if let uniqueID {
        details.append("id=\(uniqueID)")
    }

    guard !details.isEmpty else {
        return name
    }
    return "\(name) (\(details.joined(separator: ", ")))"
}

func listMIDIDevices() {
    print("MIDI sources:")
    let sourceCount = MIDIGetNumberOfSources()
    if sourceCount == 0 {
        print("  none")
    } else {
        for index in 0..<sourceCount {
            let source = MIDIGetSource(index)
            print("  [\(index)] \(midiEndpointSummary(source))")
        }
    }

    print("")
    print("MIDI destinations:")
    let destinationCount = MIDIGetNumberOfDestinations()
    if destinationCount == 0 {
        print("  none")
    } else {
        for index in 0..<destinationCount {
            let destination = MIDIGetDestination(index)
            print("  [\(index)] \(midiEndpointSummary(destination))")
        }
    }
}
