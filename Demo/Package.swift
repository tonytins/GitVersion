// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GitVersionDemo",
    dependencies: [
        .package(path: "..")
    ],
    targets: [
        .executableTarget(
            name: "GitVersionDemo",
            dependencies: [.product(name: "GitVersion", package: "GitVersion")],
            plugins: [.plugin(name: "GitVersionPlugin", package: "GitVersion")]
        )
    ]
)
