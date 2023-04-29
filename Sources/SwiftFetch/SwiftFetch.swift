import NodeAPI
import Foundation

@NodeActor
func mapToURLRequest (url: URL, options: [String: NodeValue]?) throws -> URLRequest {
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)

    if let method = try options?["method"]?.as(String.self) {
        request.httpMethod = method.uppercased()
    }

    if let headers = try options?["headers"]?.as([String: String].self) {
        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }
    }

    if let body = try options?["body"]?.as(Data.self) {
        request.httpBody = body
    }

    return request
}

@main struct SwiftFetch: NodeModule {
    let exports: NodeValueConvertible

    init() throws {
        exports = [
            "request": try NodeFunction { (url: String, options: [String: NodeValue]?) in
                let queue = try NodeAsyncQueue(label: "request-queue")

                let urlRequest = try mapToURLRequest(url: URL(string: url)!, options: options)

                return try NodePromise { deferred in
                    Task {
                        let (data, urlResponse) = try await URLSession.shared.data(for: urlRequest)
                        // Whenever you make an HTTP request, the URLResponse object you get back is actually an instance of the HTTPURLResponse class.
                        let httpUrlResponse = urlResponse as! HTTPURLResponse
                        let result = Result<NodeValueConvertible, Error> {
                            try NodeObject([
                                "body": data,
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
                        try? queue.run { try deferred(result) }
                    }
                }
            }
        ]
    }
}
