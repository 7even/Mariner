// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Mariner",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "Mariner",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ]),
        .testTarget(
            name: "MarinerTests",
            dependencies: ["Mariner"]),
    ]
)
