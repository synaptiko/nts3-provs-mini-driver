import Foundation

struct Configuration {
    var inputNameFilter = "NTS-3"
    var outputNameFilter = "PRO VS"
    var clientName = "NTS-3 Pro VS Mini Driver"
    var outputChannel = 1
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
            case "--output", "-o":
                outputNameFilter = try Self.nextValue(after: argument, from: &iterator)
            case "--client-name":
                clientName = try Self.nextValue(after: argument, from: &iterator)
            case "--channel", "-c":
                outputChannel = try Self.channelValue(after: argument, from: &iterator)
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

    private static func channelValue(
        after argument: String,
        from iterator: inout ArraySlice<String>.Iterator
    ) throws -> Int {
        let value = try nextValue(after: argument, from: &iterator)
        guard let channel = Int(value), (1...16).contains(channel) else {
            throw ConfigurationError.invalidChannel(value)
        }
        return channel
    }
}

enum ConfigurationError: Error, CustomStringConvertible {
    case helpRequested
    case invalidChannel(String)
    case missingValue(String)
    case unknownArgument(String)

    var description: String {
        switch self {
        case .helpRequested:
            return ""
        case .invalidChannel(let value):
            return "Invalid MIDI channel: \(value). Expected 1...16."
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

        Reads MIDI from a Korg NTS-3 source, maps selected controls, and sends
        the resulting MIDI directly to a Behringer Pro VS Mini destination.

        Usage:
          nts3-provs-mini-driver [options]

        Options:
          -i, --input <text>          Source name substring to connect to. Default: NTS-3
          -o, --output <text>         Destination name substring. Default: PRO VS
          -c, --channel <1-16>        Output MIDI channel. Default: 1
              --client-name <name>    CoreMIDI client name. Default: NTS-3 Pro VS Mini Driver
              --all                   Connect to every MIDI source
          -l, --list                  List MIDI sources/destinations and exit
              --ui                    Launch the menu-bar app and auto-start the bridge
              --self-test             Run deterministic mapping self-tests and exit
              --trim                  Emit mapped 7-bit MSB CCs only; default preserves MSB/LSB pairs
          -q, --quiet                 Forward MIDI without per-message logging
              --show-realtime         Include MIDI clock/active-sensing in logs
          -h, --help                  Show this help

        Hardware setup:
          1. Start this process and keep it running.
          2. Enable external MIDI CC receive on the Pro VS Mini.
          3. Run with --list if either endpoint name needs a different substring.
        """
    )
}
