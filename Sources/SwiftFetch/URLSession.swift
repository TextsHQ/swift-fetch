#if USE_URLSESSION || os(iOS)
// Only supports macOS 12.0+ and iOS 15.0+
import Foundation
import NodeAPI

fileprivate class TaskDelegate: NSObject, URLSessionTaskDelegate {
    let followRedirect: Bool

    public init(followRedirect: Bool) {
        self.followRedirect = followRedirect
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        if followRedirect {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }
}

extension String {
    func firstIndex(of character: Character, offsetBy: String.Index) -> Index? {
        let substring = self[offsetBy...]
        return substring.firstIndex(of: character)
    }
}

final class Client: NodeClass {
    public static var properties: NodeClassPropertyList = [
        "request": NodeMethod(request),
        "requestStream": NodeMethod(requestStream),
    ]

    let queue: NodeAsyncQueue

    let urlSession: URLSession

    init(_ args: NodeArguments) throws {
        queue = try NodeAsyncQueue(label: "http-stream-callback-queue")

        let urlSessionConfig = URLSessionConfiguration.ephemeral
        urlSessionConfig.httpCookieStorage = nil
        urlSessionConfig.httpCookieAcceptPolicy = .never
        urlSessionConfig.httpShouldSetCookies = false
        urlSession = URLSession(configuration: urlSessionConfig)
    }

    public func request(url: String, options: [String: NodeValue]?) async throws -> NodeValueConvertible {
        let (data, response) = try await urlSession.data(
            for: mapToURLRequest(url: URL(string: url)!, options: options),
            delegate: TaskDelegate(followRedirect: false)
        )
        let httpUrlResponse = response as! HTTPURLResponse

        return [
            "body": data,
            "status": httpUrlResponse.statusCode,
            "headers": try mapHeaders(httpUrlResponse.allHeaderFields)
        ]
    }

    public func requestStream(url: String, options: [String: NodeValue]?, callbackFn: NodeFunction) async throws -> NodeValueConvertible {
        throw SwiftFetchError.unimplemented
    }

    func mapHeaders(_ headers: [AnyHashable: Any]) throws -> NodeValueConvertible {
        try headers.reduce(into: [:]) { (dict, item) in
            guard let key = item.key as? String, let value = item.value as? String else {
                return
            }
            if key.lowercased() == "set-cookie" {
                let cookies = splitSetCookieHeader(value)
                if cookies.count == 1 {
                    dict[key.lowercased()] = cookies[0]
                } else {
                    // swift complains when using the array directly
                    let nodeArray = try NodeArray(capacity: cookies.count)
                    for i in 0..<cookies.count {
                        try nodeArray[i].set(to: cookies[i])
                    }
                    dict[key.lowercased()] = nodeArray
                }
            } else {
                dict[key] = value
            }
        }
    }

    func mapToURLRequest(url: URL, options: [String: NodeValue]?) throws -> URLRequest {
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

    // ported from: https://github.com/ktorio/ktor/blob/main/ktor-http/common/src/io/ktor/http/HttpMessageProperties.kt#L117
    func splitSetCookieHeader(_ cookieHeader: String) -> [String] {
        var commaIndex = cookieHeader.firstIndex(of: ",")
        if commaIndex == nil {
            return [cookieHeader]
        }

        var cookies = [String]()
        var current = 0

        var equalsIndex = cookieHeader.firstIndex(of: "=", offsetBy: commaIndex!)
        var semicolonIndex = cookieHeader.firstIndex(of: ";", offsetBy: commaIndex!)
        while current < cookieHeader.count, commaIndex != nil {
            if equalsIndex == nil || equalsIndex! < commaIndex! {
                equalsIndex = cookieHeader.firstIndex(of: "=", offsetBy: commaIndex!)
            }

            var nextCommaIndex = cookieHeader.firstIndex(of: ",", offsetBy: cookieHeader.index(commaIndex!, offsetBy: 1))
            while nextCommaIndex != nil, equalsIndex != nil, nextCommaIndex! < equalsIndex! {
                commaIndex = nextCommaIndex
                nextCommaIndex = cookieHeader.firstIndex(of: ",", offsetBy: cookieHeader.index(nextCommaIndex!, offsetBy: 1))
            }

            if semicolonIndex == nil || semicolonIndex! < commaIndex! {
                semicolonIndex = cookieHeader.firstIndex(of: ";", offsetBy: commaIndex!)
            }

            // No more keys remaining.
            if equalsIndex == nil {
                cookies.append(String(cookieHeader[cookieHeader.index(cookieHeader.startIndex, offsetBy: current)...]).trimmingCharacters(in: .whitespaces))
                return cookies
            }

            // No ';' between ',' and '=' => We're on a header border.
            if semicolonIndex == nil || semicolonIndex! > equalsIndex! {
                let start = cookieHeader.index(cookieHeader.startIndex, offsetBy: current)
                let end = commaIndex!
                cookies.append(String(cookieHeader[start..<end]).trimmingCharacters(in: .whitespaces))

                // Update comma index at the end of loop.
                current = cookieHeader.distance(from: cookieHeader.startIndex, to: commaIndex!) + 1
            }

            // ',' in value, skip it and find next.
            commaIndex = nextCommaIndex
        }

        if current < cookieHeader.count {
            cookies.append(String(cookieHeader[cookieHeader.index(cookieHeader.startIndex, offsetBy: current)...]).trimmingCharacters(in: .whitespaces))
        }

        return cookies
    }
}
#endif
