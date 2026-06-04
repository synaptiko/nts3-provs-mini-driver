import Foundation

struct Configuration {
    var inputNameFilter = "NTS-3"
    var virtualSourceName = "NTS-3 Pro VS Mini Driver"
    var clientName = "NTS-3 Pro VS Mini Driver"
    var connectAllSources = false
    var listDevices = false
    var launchUI = false
    var runSelfTest = false
    var outputMode: NTS3OutputMode = .pair
    var quiet = false
    var showRealtime = false

    init(arguments: ArraySlice<String>) throws {
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--input", "-i":
                inputNameFilter = try Self.nextValue(after: argument, from: &iterator)
            case "--virtual-name", "-v":
                virtualSourceName = try Self.nextValue(after: argument, from: &iterator)
            case "--client-name":
                clientName = try Self.nextValue(after: argument, from: &iterator)
            case "--all":
                connectAllSources = true
            case "--list", "-l":
                listDevices = true
            case "--ui":
                launchUI = true
            case "--self-test":
                runSelfTest = true
            case "--trim":
                outputMode = .trim
            case "--quiet", "-q":
                quiet = true
            case "--show-realtime":
                showRealtime = true
            case "--help", "-h":
                throw ConfigurationError.helpRequested
            default:
                throw ConfigurationError.unknownArgument(argument)
            }
        }
    }

    private static func nextValue(
        after argument: String,
        from iterator: inout ArraySlice<String>.Iterator
    ) throws -> String {
        guard let value = iterator.next(), !value.hasPrefix("-") else {
            throw ConfigurationError.missingValue(argument)
        }
        return value
    }
}

enum ConfigurationError: Error, CustomStringConvertible {
    case helpRequested
    case missingValue(String)
    case unknownArgument(String)

    var description: String {
        switch self {
        case .helpRequested:
            return ""
        case .missingValue(let argument):
            return "Missing value after \(argument)."
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument)"
        }
    }
}

func printUsage() {
    print(
        """
        NTS-3 Pro VS Mini Driver

        Reads MIDI from a hardware source, creates a virtual MIDI source, and forwards
        the mapped NTS-3 control stream while logging useful decoded messages.

        Usage:
          nts3-provs-mini-driver [options]

        Options:
          -i, --input <text>          Source name substring to connect to. Default: NTS-3
          -v, --virtual-name <name>   Virtual MIDI source name. Default: NTS-3 Pro VS Mini Driver
              --client-name <name>    CoreMIDI client name. Default: NTS-3 Pro VS Mini Driver
              --all                   Connect to every MIDI source except our virtual source
          -l, --list                  List MIDI sources/destinations and exit
              --ui                    Launch the menu-bar app and auto-start the bridge
              --self-test             Run deterministic mapping self-tests and exit
              --trim                  Emit mapped 7-bit MSB CCs only; default preserves MSB/LSB pairs
          -q, --quiet                 Forward MIDI without per-message logging
              --show-realtime         Include MIDI clock/active-sensing in logs
          -h, --help                  Show this help

        Ableton Live setup:
          1. Start this process and keep it running.
          2. In Live's MIDI preferences, enable Track/Remote for the virtual input
             named "NTS-3 Pro VS Mini Driver" or your custom --virtual-name.
          3. Use the virtual input in MIDI mapping or on a MIDI track.
        """
    )
}
