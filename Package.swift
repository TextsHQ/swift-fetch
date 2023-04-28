// swift-tools-version:5.4

import PackageDescription
import Foundation

let package = Package(
    name: "swift-fetch",
    platforms: [.iOS("15.0"), .macOS("11.0")],
    products: [
        .library(
            name: "SwiftFetch",
            targets: ["SwiftFetch"]
        )
    ],
    dependencies: [
        .package(path: "node_modules/node-swift")
    ],
    targets: [
        .target(
            name: "SwiftFetch",
            dependencies: [
                .product(name: "NodeAPI", package: "node-swift")
            ]
        )
    ]
)
