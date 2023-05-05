#if USE_URLSESSION || os(iOS)
import Foundation
import NodeAPI

final class Client: NodeClass {
    public static var properties: NodeClassPropertyList = [
        "request": NodeMethod(request),
        "requestStream": NodeMethod(requestStream),
    ]

    let queue: NodeAsyncQueue

    init(_ args: NodeArguments) throws {
        self.queue = try NodeAsyncQueue(label: "http-stream-callback-queue")
    }

    public func request(url: String, options: [String: NodeValue]?) async throws -> NodeValueConvertible {
        let (data, response) = try await URLSession.shared.data(from: URL(string: url)!)
        let httpUrlResponse = response as! HTTPURLResponse
        return [
            "body": data,
            "status": httpUrlResponse.statusCode,
            "headers": httpUrlResponse.allHeaderFields.reduce([:]) { (dict, item) in
                var dict = dict
                guard let key = item.key as? String, let value = item.value as? String else {
                    return dict
                }
                dict[key.lowercased()] = value
                return dict
            }
        ]
    }

    public func requestStream(url: String, options: [String: NodeValue]?, callbackFn: NodeFunction) async throws -> NodeValueConvertible {
        throw SwiftFetchError.unimplemented
    }
}
#endif
