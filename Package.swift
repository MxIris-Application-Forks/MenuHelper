// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MenuHelperIconCache",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .target(
            name: "MenuHelperIconCache",
            path: "Shared/Cache",
            sources: ["AppIconCache.swift"]
        ),
        .testTarget(
            name: "MenuHelperIconCacheTests",
            dependencies: ["MenuHelperIconCache"],
            path: "Tests/MenuHelperIconCacheTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
