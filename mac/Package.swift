// swift-tools-version: 5.9
import PackageDescription

// Ether Beat Lab for Mac: the Beat Lab page in a native window, plus your Native Instruments
// sounds and a local AI Producer. Build and install with ../install-mac-app.sh.
let package = Package(
    name: "EtherBeatLab",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "EtherBeatLab", path: "Sources/EtherBeatLab")
    ]
)
