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
        completionHandler(followRedirect ? request : nil)
    }
}

extension String {
    func firstIndex(of character: Character, offsetBy: String.Index) -> Index? {
        let substring = self[offsetBy...]
        return substring.firstIndex(of: character)
    }
}

class HTTPStream: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    typealias CallbackArguments = (event: String, data: Any)

    private var callback: ((String, Any) -> Void)? = nil

    public var stream: AsyncStream<CallbackArguments>!

    public var dataTask: URLSessionDataTask!

    let followRedirect: Bool

    public init(request: URLRequest, followRedirect: Bool) {
        self.followRedirect = followRedirect
        super.init()
        stream = AsyncStream<CallbackArguments> { continuation in
            self.callback = { event, data in
                if event == "end" {
                    continuation.finish()
                } else {
                    continuation.yield((event, data))
                }
            }
        }
        dataTask = URLSession.shared.dataTask(with: request)
        if #available(macOS 12, *) {
            dataTask.delegate = self
        }
        dataTask.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        callback?("data", data)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        callback?("response", response)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            callback?("error", error)
        } else {
            callback?("end", undefined)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(followRedirect ? request : nil)
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
        guard #available(macOS 12, *) else {
            throw SwiftFetchError.unimplemented
        }
        let followRedirect = (try? options?["followRedirect"]?.as(Bool.self)) ?? true
        let (data, response) = try await urlSession.data(
            for: mapToURLRequest(url: URL(string: url)!, options: options),
            delegate: TaskDelegate(followRedirect: followRedirect)
        )

        let httpUrlResponse = response as! HTTPURLResponse

        return [
            "body": data,
            "statusCode": httpUrlResponse.statusCode,
            "headers": mapHeaders(httpUrlResponse.allHeaderFields)
        ]
    }

    public func requestStream(url: String, options: [String: NodeValue]?, callbackFn: NodeFunction) async throws -> NodeValueConvertible {
        let callback = { [queue] (event, data) in
            do {
                try queue.run { _ = try callbackFn(event, data) }
            } catch {
                print("\(error)")
            }
        }

        let followRedirect = (try? options?["followRedirect"]?.as(Bool.self)) ?? true

        let httpStream = try HTTPStream(
            request: mapToURLRequest(url: URL(string: url)!, options: options),
            followRedirect: followRedirect
        )

        for await (event, data) in httpStream.stream {
            if event == "response", let response = data as? HTTPURLResponse {
                callback("response", [
                    "statusCode": response.statusCode,
                    "headers": mapHeaders(response.allHeaderFields)
                ])
            } else if event == "data", let data = data as? Data {
                callback("data", data)
            } else if event == "error", let error = data as? Error {
                callback("error", String(describing: error))
            }
        }
        callback("end", undefined)
        return undefined
    }

    func mapHeaders(_ headers: [AnyHashable: Any]) -> NodeValueConvertible {
        headers.reduce(into: [:]) { (dict, item) in
            guard let key = item.key as? String, let value = item.value as? String else {
                return
            }
            if key.lowercased() == "set-cookie" {
                let cookies = splitSetCookieHeader(value)
                if cookies.count == 1 {
                    dict[key.lowercased()] = cookies[0]
                } else {
                    dict[key.lowercased()] = cookies as [NodeValueConvertible]
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
