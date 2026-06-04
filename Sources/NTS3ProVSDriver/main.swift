import Dispatch
import Foundation

do {
    let configuration = try Configuration(arguments: CommandLine.arguments.dropFirst())

    if configuration.runSelfTest {
        Foundation.exit(NTS3SelfTest.run() ? EXIT_SUCCESS : EXIT_FAILURE)
    }

    if configuration.listDevices {
        listMIDIDevices()
        Foundation.exit(EXIT_SUCCESS)
    }

    if configuration.launchUI {
        runMIDIWatchWindow(configuration: configuration)
        Foundation.exit(EXIT_SUCCESS)
    }

    let remapper = MIDIRemapper(configuration: configuration)
    try remapper.start()

    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)

    let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigint.setEventHandler {
        remapper.stop()
        Foundation.exit(EXIT_SUCCESS)
    }
    sigint.resume()

    let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    sigterm.setEventHandler {
        remapper.stop()
        Foundation.exit(EXIT_SUCCESS)
    }
    sigterm.resume()

    dispatchMain()
} catch ConfigurationError.helpRequested {
    printUsage()
    Foundation.exit(EXIT_SUCCESS)
} catch {
    fputs("\(error)\n\n", stderr)
    printUsage()
    Foundation.exit(EXIT_FAILURE)
}
