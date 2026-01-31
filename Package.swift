// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "focus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "focus", targets: ["focus"]),
        .executable(name: "focusd", targets: ["focusd"]),
        .library(name: "FocusCore", targets: ["FocusCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "FocusCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .executableTarget(
            name: "focusd",
            dependencies: ["FocusCore"],
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
        .executableTarget(
            name: "focus",
            dependencies: [
                "FocusCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
        .testTarget(
            name: "FocusCoreTests",
            dependencies: ["FocusCore"]
        )
    ]
)
