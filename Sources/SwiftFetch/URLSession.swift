#if USE_URLSESSION || os(iOS)
// Only supports macOS 12.0+ and iOS 15.0+
import Foundation
import NodeAPI
import AsyncAlgorithms

@NodeClass @NodeActor final class Client {
    private static var retryTimeout: TimeInterval = 180

    let queue: NodeAsyncQueue

    let urlSession: URLSession

    @NodeConstructor init() throws {
        queue = try NodeAsyncQueue(label: "http-stream-callback-queue")

        let urlSessionConfig = URLSessionConfiguration.ephemeral
        urlSessionConfig.httpCookieStorage = nil
        urlSessionConfig.httpCookieAcceptPolicy = .never
        urlSessionConfig.httpShouldSetCookies = false
        urlSession = URLSession(configuration: urlSessionConfig)
    }

    @NodeMethod func request(url: String, options: [String: NodeValue]?) async throws -> NodeValueConvertible {
        guard #available(macOS 12, iOS 15, *) else {
            throw SwiftFetchError.unimplemented
        }

        let options = try FetchOptions(url: url, raw: options)

        return try await Self.retry(withTimeout: Self.retryTimeout) { [self] in
            let (data, response) = try await urlSession.data(
                for: options.request,
                delegate: TaskDelegate(options: options)
            )

            guard let httpResponse = response as? HTTPURLResponse  else {
                throw URLError(.badServerResponse)
            }

            return [
                "body": data,
                "statusCode": httpResponse.statusCode,
                "headers": mapHeaders(httpResponse.allHeaderFields)
            ]
        }
    }

    @NodeMethod func requestStream(url: String, options: [String: NodeValue]?, callbackFn: NodeFunction) async throws {
        guard #available(macOS 12, iOS 15, *) else {
            throw SwiftFetchError.unimplemented
        }

        let options = try FetchOptions(url: url, raw: options)

        let callback = { [queue] (event, data) in
            do {
                try queue.run { _ = try callbackFn(event, data) }
            } catch {
                print("\(error)")
            }
        }

        do {
            let (stream, response) = try await Self.retry(withTimeout: Self.retryTimeout) { [self] in
                try await urlSession.bytes(
                    for: options.request,
                    delegate: TaskDelegate(options: options)
                )
            }

            if let response = response as? HTTPURLResponse {
                callback("response", [
                    "statusCode": response.statusCode,
                    "headers": mapHeaders(response.allHeaderFields)
                ])
            }

            // Node's default highWaterMark is 64k
            for try await bytes in stream.chunks(ofCount: 64 * 1024, into: Data.self) {
                callback("data", bytes)
            }
        } catch {
            callback("error", "\(error)")
        }

        callback("end", undefined)
    }

    nonisolated func mapHeaders(_ headers: [AnyHashable: Any]) -> NodeValueConvertible {
        guard let headers = headers as? [String: String] else {
            return [:]
        }
        return Dictionary(headers.map { key, value in
            let key = key.lowercased()
            let value = if key == "set-cookie" {
                SetCookieParser.splitHeader(value) as [NodeValueConvertible]
            } else {
                value as NodeValueConvertible
            }
            return (key, value)
        }, uniquingKeysWith: { $1 })
    }


    @discardableResult
    static nonisolated func retry<T>(
        withTimeout timeout: TimeInterval,
        maxRetries: Int = 100,
        intervalMS: UInt64 = 100,
        _ closure: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        let start = Date()
        var result: Result<T, Error>
        var attempt = 0

        repeat {
            do {
                return try await closure()
            } catch {
                print("retry error \(String(describing: error)) (attempt \(attempt)))")
                result = .failure(error)
                attempt += 1
            }
            try? await Task.sleep(nanoseconds: intervalMS * 1_000_000)
        } while -start.timeIntervalSinceNow < timeout && attempt < maxRetries

        return try result.get()
    }
}

private final class TaskDelegate: NSObject, URLSessionTaskDelegate {
    let options: FetchOptions

    init(options: FetchOptions) {
        self.options = options
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        options.followRedirect ? request : nil
    }
}


private struct FetchOptions {
    var url: URL
    var followRedirect: Bool
    var headers: [String: String]
    var method: String?
    var body: Data?

    var request: URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: .greatestFiniteMagnitude
        )

        request.httpMethod = method?.uppercased()
        request.httpBody = body

        for (key, value) in headers {
            request.addValue(value, forHTTPHeaderField: key)
        }

        return request
    }
}


extension FetchOptions {
    @NodeActor init(url: String, raw: [String: NodeValue]?) throws {
        guard let url = URL(string: url) else { throw URLError(.badURL) }
        self.url = url
        followRedirect = try raw?["followRedirect"]?.as(Bool.self) ?? true
        headers = try raw?["headers"]?.as([String: String].self) ?? [:]
        method = try raw?["method"]?.as(String.self)
        body = try raw?["body"]?.as(NodeTypedArray<UInt8>.self)?.dataNoCopy() ?? Data()
    }
}

enum SetCookieParser {}

extension SetCookieParser {
    static func splitHeader(_ cookieHeader: String) -> [String] {
        splitHeader(cookieHeader[...]).map { String($0) }
    }

    // ported from: https://github.com/ktorio/ktor/blob/945e56085d06d2bed2a7dadbea01d7f1bd1a5409/ktor-http/common/src/io/ktor/http/HttpMessageProperties.kt#L108
    static func splitHeader(_ cookieHeader: Substring) -> [Substring] {
        guard var commaIndex = cookieHeader.firstIndex(of: ",") else {
            return [cookieHeader[...]]
        }

        var cookies: [Substring] = []
        var currentCookie = cookieHeader

        var afterComma: Substring { cookieHeader[commaIndex...].dropFirst() }

        var equalsIndex = afterComma.firstIndex(of: "=")
        var semicolonIndex = afterComma.firstIndex(of: ";")
        while !currentCookie.isEmpty {
            if equalsIndex.map({ $0 < commaIndex }) ?? true {
                equalsIndex = afterComma.firstIndex(of: "=")
            }

            var nextCommaIndex = afterComma.firstIndex(of: ",")
            while let next = nextCommaIndex, let equalsIndex, next < equalsIndex {
                commaIndex = next
                nextCommaIndex = afterComma.firstIndex(of: ",")
            }

            if semicolonIndex.map({ $0 < commaIndex }) ?? true {
                semicolonIndex = afterComma.firstIndex(of: ";")
            }

            // No more keys remaining.
            guard let equalsIndex else { break }

            // No ';' between ',' and '=' => We're on a header border.
            if semicolonIndex.map({ $0 > equalsIndex }) ?? true {
                cookies.append(currentCookie[..<commaIndex])

                // Update cookie at the end of loop.
                currentCookie = afterComma
            }

            // ',' in value, skip it and find next.
            guard let nextCommaIndex else { break }
            commaIndex = nextCommaIndex
        }

        if !currentCookie.isEmpty {
            cookies.append(currentCookie)
        }

        return cookies.map { $0.trimming(.whitespaces) }
    }
}

extension BidirectionalCollection<UnicodeScalar> {
    fileprivate func trimming(_ set: CharacterSet) -> Range<Index>? {
        guard let start = firstIndex(where: { !set.contains($0) }),
              let last = lastIndex(where: { !set.contains($0) }) else {
            return nil
        }
        let end = index(after: last)
        return start..<end
    }
}

extension Substring {
    public func trimming(_ set: CharacterSet) -> Substring {
        unicodeScalars.trimming(set).map { self[$0] } ?? .init()
    }
}

extension String {
    public func trimming(_ set: CharacterSet) -> Substring {
        self[...].trimming(set)
    }
}

extension NodeTypedArray<UInt8> {
    /// Bridges the buffer's contents to `Data`, potentially avoiding a copy.
    ///
    /// - Parameter threshold: The minimum length of the data for which no-copy
    /// bridging occurs. Under this length, performs a copy. The default value
    /// is 512. Pass 0 to never copy.
    ///
    /// No-copy bridging has a cost: the `TypedArray` has to be retained while
    /// the `Data` is alive. When the `Data` is deallocated, the `TypedArray` is
    /// relinquished to Node's garbage collector asynchronously, which may have
    /// a non-negligible cost.
    func dataNoCopy(threshold: Int = 512) throws -> Data {
        try withUnsafeMutableBytes { bytes in
            guard bytes.count >= threshold else { return Data(buffer: bytes) }
            guard let base = bytes.baseAddress else { return Data() }
            return Data(
                bytesNoCopy: base,
                count: bytes.count,
                // the buffer is alive as long as the receiver is
                deallocator: .custom { _, _ in _ = self }
            )
        }
    }
}
#endif
