// swift-tools-version:5.5

import PackageDescription
import Foundation

let package = Package(
    name: "swift-fetch",
    platforms: [.iOS("15.0"), .macOS("10.15")],
    products: [
        .library(
            name: "SwiftFetch",
            targets: ["SwiftFetch"]
        )
    ],
    dependencies: [
        .package(path: "node_modules/node-swift"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.50.0"),
        .package(url: "https://github.com/1Conan/async-http-client.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "SwiftFetch",
            dependencies: [
                .product(name: "NodeAPI", package: "node-swift"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
            ]
        )
    ]
)
