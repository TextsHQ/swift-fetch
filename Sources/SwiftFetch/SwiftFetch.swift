import Foundation
import NodeAPI

enum SwiftFetchError: Error {
    case invalidCallback
    case unimplemented
}

#NodeModule {
    try Client.constructor()
}
