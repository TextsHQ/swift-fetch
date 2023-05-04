import Foundation
import NodeAPI

enum HTTPStreamError: Error {
    case invalidCallback
}

@main struct SwiftFetch: NodeModule {
    let exports: NodeValueConvertible

    init() throws {
        exports = try Client.constructor()
    }
}
