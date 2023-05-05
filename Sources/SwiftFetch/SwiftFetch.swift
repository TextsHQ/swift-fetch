import Foundation
import NodeAPI

enum SwiftFetchError: Error {
    case invalidCallback
    case unimplemented
}

@main struct SwiftFetch: NodeModule {
    let exports: NodeValueConvertible

    init() throws {
        exports = try Client.constructor()
    }
}
