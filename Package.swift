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
        .package(url: "https://github.com/TextsHQ/swift-nio.git", branch: "main"),
        .package(url: "https://github.com/TextsHQ/async-http-client.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "SwiftFetch",
            dependencies: [
                .product(name: "NodeAPI", package: "node-swift"),
            ]
        )
    ]
)

// We only include these dependencies on non-ios platforms otherwise it still gets linked
if ProcessInfo.processInfo.environment["NODESWIFT_PLATFORM"] != "iphoneos" && ProcessInfo.processInfo.environment["USE_URLSESSION"] != "1" {
    package.targets[0].dependencies.append(contentsOf: [
        .product(name: "NIOFoundationCompat", package: "swift-nio"),
        .product(name: "AsyncHTTPClient", package: "async-http-client"),
    ])
}
