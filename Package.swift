// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GitVersion",
    products: [
        .library(name: "GitVersion", targets: ["GitVersion"]),
        .plugin(name: "GitVersionPlugin", targets: ["GitVersionPlugin"])
    ],
    targets: [
        .target(name: "GitVersion"),
        .target(name: "GitVersionGeneratorCore"),
        .executableTarget(name: "GitVersionGenerator", dependencies: ["GitVersionGeneratorCore"]),
        .plugin(
            name: "GitVersionPlugin",
            capability: .buildTool(),
            dependencies: ["GitVersionGenerator"]
        ),
        .testTarget(
            name: "GitVersionTests",
            dependencies: ["GitVersion", "GitVersionGeneratorCore"],
            plugins: ["GitVersionPlugin"]
        )
    ]
)
