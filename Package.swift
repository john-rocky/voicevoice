// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceVoice",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "VoiceVoice",
            targets: ["VoiceVoice"]
        ),
        .library(
            name: "VoiceVoiceMLX",
            targets: ["VoiceVoiceMLX"]
        ),
        .executable(
            name: "voicevoice",
            targets: ["voicevoice-cli"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "VoiceVoice",
            dependencies: []
        ),
        .target(
            name: "VoiceVoiceMLX",
            dependencies: [
                "VoiceVoice",
                .product(name: "MLXAudioTTS", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
            ]
        ),
        .executableTarget(
            name: "voicevoice-cli",
            dependencies: []
        ),
    ]
)
