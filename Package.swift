// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "swift-package-graph",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
        .tvOS(.v27),
        .watchOS(.v27),
        .visionOS(.v27),
    ],
    products: [
        .library(name: "Package Graph", targets: ["Package Graph"]),
        .executable(name: "package-graph", targets: ["Package Graph CLI"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swift-molecules/swift-graph.git",
            branch: "main"
        ),
        .package(url: "https://github.com/swift-standards/swift-spm-standard.git", branch: "main"),
        .package(
            url: "https://github.com/swift-compositions/swift-package-manager.git",
            branch: "main"
        ),
        .package(url: "https://github.com/swift-compositions/swift-file-system.git", branch: "main"),
        .package(url: "https://github.com/swift-compositions/swift-paths.git", branch: "main"),
        .package(url: "https://github.com/swift-compositions/swift-arguments.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-ascii.git", branch: "main", traits: ["Coder", "Parser", "Serializer"]),
        .package(url: "https://github.com/swift-atoms/swift-coder.git", branch: "main", traits: ["Carrier", "Map"]),
        .package(url: "https://github.com/swift-atoms/swift-ratio.git", branch: "main", traits: ["Bit", "Ordinal", "Difference"]),
        .package(url: "https://github.com/swift-atoms/swift-span.git", branch: "main", traits: ["Iterator"]),
        .package(url: "https://github.com/swift-atoms/swift-finite.git", branch: "main", traits: ["Tagged"]),
        .package(url: "https://github.com/swift-atoms/swift-memory.git", branch: "main", traits: ["Lock", "Map", "Shared", "Cursor"]),
    ],
    targets: [
        .target(
            name: "Package Graph",
            dependencies: [
                .product(name: "Graph", package: "swift-graph"),
                .product(name: "SPM Standard", package: "swift-spm-standard"),
                .product(name: "Package Manager", package: "swift-package-manager"),
                .product(name: "File System", package: "swift-file-system"),
                .product(name: "Paths", package: "swift-paths"),
            ],
            path: "Sources/Package Graph"
        ),
        .executableTarget(
            name: "Package Graph CLI",
            dependencies: [
                "Package Graph",
                .product(name: "Command", package: "swift-arguments"),
            ],
            path: "Sources/Package Graph CLI"
        ),
        .testTarget(
            name: "Package Graph Tests",
            dependencies: [
                "Package Graph",
                .product(name: "File System", package: "swift-file-system"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("Lifetimes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
