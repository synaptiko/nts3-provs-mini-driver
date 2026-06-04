// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NTS3ProVSDriver",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "nts3-provs-mini-driver", targets: ["NTS3ProVSDriver"])
    ],
    targets: [
        .executableTarget(
            name: "NTS3ProVSDriver"
        )
    ]
)
