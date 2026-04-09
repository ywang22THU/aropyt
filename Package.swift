// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AropytEditor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AropytEditor", targets: ["AropytEditor"]),
        .library(name: "MarkdownCore", targets: ["MarkdownCore"]),
    ],
    targets: [
        .target(
            name: "MarkdownCore",
            path: "Sources/MarkdownCore"
        ),
        .executableTarget(
            name: "AropytEditor",
            dependencies: ["MarkdownCore"],
            path: "Sources/AropytEditor",
            exclude: [
                "Resources/Info.plist"
            ],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/AropytEditor/Resources/Info.plist"
                ])
            ]
        )
    ]
)
