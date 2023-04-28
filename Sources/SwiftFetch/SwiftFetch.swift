import NodeAPI
import Foundation

@main struct SwiftFetch: NodeModule {
    let exports: NodeValueConvertible

    init() throws {
        exports = [
            "requestAsBuffer": try NodeFunction { (url: String) in
                let queue = try NodeAsyncQueue(label: "fetch-buffer")
                return try NodePromise { deferred in
                    Task {
                        let result = try await request(url: URL(string: url)!, string: false)
                        try? queue.run { try deferred(result) }
                    }
                }
            },

            "requestAsString": try NodeFunction { (url: String) in
                let queue = try NodeAsyncQueue(label: "fetch-string")
                return try NodePromise { deferred in
                    Task {
                        let result = try await request(url: URL(string: url)!, string: true)
                        try? queue.run { try deferred(result) }
                    }
                }
            },
        ]
    }
}

@NodeActor
func request(url: URL, string: Bool) async throws -> Result<NodeValueConvertible, Error> {
    let (data, urlResponse) = try await URLSession.shared.data(from: url)
    // Whenever you make an HTTP request, the URLResponse object you get back is actually an instance of the HTTPURLResponse class.
    let httpUrlResponse = urlResponse as! HTTPURLResponse

    return Result<NodeValueConvertible, Error> {
        try NodeObject([
            "body": string ? String(decoding: data, as: UTF8.self) : data,
            "statusCode": httpUrlResponse.statusCode,
            "headers": httpUrlResponse.allHeaderFields.reduce([:]) { (dict, item) in
                var dict = dict
                guard let key = item.key as? String, let value = item.value as? String else {
                    return dict
                }
                dict[key] = value
                return dict
            }
        ])
    }
}
