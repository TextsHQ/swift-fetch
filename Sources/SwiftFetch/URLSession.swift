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
            let delegate = TaskDelegate(options: options)
            let (data, response) = try await urlSession.data(
                for: options.request,
                delegate: delegate
            )

            guard let httpResponse = response as? HTTPURLResponse  else {
                throw URLError(.badServerResponse)
            }

            return [
                "body": data,
                "statusCode": httpResponse.statusCode,
                "headers": mapHeaders(httpResponse.allHeaderFields),
                "newCookies": Dictionary(delegate.cookies.map { key, value in
                    (key, value as [NodeValueConvertible])
                }, uniquingKeysWith: { $1 })
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
            let delegate = TaskDelegate(options: options)
            let (stream, response) = try await urlSession.bytes(
                for: options.request,
                delegate: delegate
            )

            if let response = response as? HTTPURLResponse {
                callback("response", [
                    "statusCode": response.statusCode,
                    "headers": mapHeaders(response.allHeaderFields),
                    "newCookies": Dictionary(delegate.cookies.map { key, value in
                        (key, value as [NodeValueConvertible])
                    }, uniquingKeysWith: { $1 })
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
            } catch let error as NSError where error.domain == NSURLErrorDomain && error.code == NSURLErrorServerCertificateUntrusted {
                throw error
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
    public var cookies: [String: [String]] = [:]

    init(options: FetchOptions) {
        self.options = options
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        if let url = response.url?.absoluteString, let header = response.value(forHTTPHeaderField: "set-cookie") {
            self.cookies[url, default: []].append(contentsOf: SetCookieParser.splitHeader(header).map { String($0) })
        }
        return options.followRedirect ? request : nil
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler completion: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        var disposition: URLSession.AuthChallengeDisposition = .performDefaultHandling
        var credential: URLCredential?

        defer { completion(disposition, credential) }

        if options.skipCertificateVerification == true {
            disposition = .useCredential
            credential = URLCredential(trust: challenge.protectionSpace.serverTrust!)
            return
        }

        guard let pinnedCertificates = options.pinnedCertificates else {
            return
        }

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            return
        }

        guard #available(macOS 12, iOS 15, *) else {
            return
        }

        guard let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate], !certificateChain.isEmpty else {
            return
        }

        for certificate in certificateChain {
            let certificateData = SecCertificateCopyData(certificate) as Data
            if pinnedCertificates.contains(certificateData) {
                disposition = .useCredential
                credential = URLCredential(trust: challenge.protectionSpace.serverTrust!)
                return
            }
        }
    }
}
#endif
