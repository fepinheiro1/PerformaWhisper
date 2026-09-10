// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PerformaWhisper",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
        // Motor usado apenas na fatia x86_64: o WhisperKit depende do CoreML, que
        // trava em hardware Intel. Ver a seção "Macs Intel" do README.
        .package(url: "https://github.com/exPHAT/SwiftWhisper.git", branch: "master")
    ],
    targets: [
        .executableTarget(
            name: "PerformaWhisper",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "SwiftWhisper", package: "SwiftWhisper")
            ],
            path: "Sources/PerformaWhisper"
        )
    ]
)
