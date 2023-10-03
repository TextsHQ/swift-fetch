#if !USE_URLSESSION && (os(macOS) || os(Linux))
/**
  * Configured to spoof chrome
  */
// TODO: add windows support
import Foundation
import AsyncHTTPClient
import NIO
import NIOSSL
import NIOHTTP1
import NIOFoundationCompat
import NodeAPI

var clientConfig: HTTPClient.Configuration = {
    var config = HTTPClient.Configuration()

    config.decompression = .enabled(limit: .none)

    config.tlsConfiguration = .clientDefault
    config.tlsConfiguration?.cipherSuiteValues = [
        .TLS_AES_128_GCM_SHA256,
        .TLS_AES_256_GCM_SHA384,
        .TLS_CHACHA20_POLY1305_SHA256,
        .TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
        .TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
        .TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
        .TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
        .TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256,
        .TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256,
        .TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA,
        .TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA,
        .TLS_RSA_WITH_AES_128_GCM_SHA256,
        .TLS_RSA_WITH_AES_256_GCM_SHA384,
        .TLS_RSA_WITH_AES_128_CBC_SHA,
        .TLS_RSA_WITH_AES_256_CBC_SHA,
    ]
    config.tlsConfiguration?.minimumTLSVersion = .tlsv12
    config.tlsConfiguration?.maximumTLSVersion = .tlsv13
    config.tlsConfiguration?.applicationProtocols = ["h2", "http/1.1"]
    config.tlsConfiguration?.verifySignatureAlgorithms = [
        .ecdsaSecp256R1Sha256,
        .rsaPssRsaeSha256,
        .rsaPkcs1Sha256,
        .ecdsaSecp384R1Sha384,
        .rsaPssRsaeSha384,
        .rsaPkcs1Sha384,
        .rsaPssRsaeSha512,
        .rsaPkcs1Sha512,
    ]

    if ProcessInfo.processInfo.environment["NODE_TLS_REJECT_UNAUTHORIZED"] == "0" {
        config.tlsConfiguration?.certificateVerification = .none
    }

    // Custom Configs from fork
    config.tlsConfiguration?.grease = true
    config.tlsConfiguration?.signedCertificateTimestamps = true
    config.tlsConfiguration?.ocspStapling = true
    config.tlsConfiguration?.brotliCertificateCompression = true
    config.tlsConfiguration?.renegotiationSupport = .explicit

    return config
}()

let evGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

final class Client: NodeClass {
    public static var properties: NodeClassPropertyList = [
        "request": NodeMethod(request),
        "requestStream": NodeMethod(requestStream),
    ]

    private static var retryTimeout: TimeInterval = 180

    private static var connectionTimeout: Int64 = 60

    let queue: NodeAsyncQueue

    init(_ args: NodeArguments) throws {
        self.queue = try NodeAsyncQueue(label: "http-stream-callback-queue")
    }

    public func request(url: String, options: [String: NodeValue]?) async throws -> NodeValueConvertible {
        do {
            return try await Self.internalRequest(url: url, options: options) { response in
                let byteBuffer = try await response.body.collect(upTo: 1024 * 1024 * 100) // up to 100MB

                return await [
                    "body": Data(buffer: byteBuffer),
                    "statusCode": Int(response.status.code),
                    "headers": Self.mapHeaders(response.headers)
                ]
            }
        } catch {
            print("swift-fetch request error \(error)")
            throw error
        }
    }

    public func requestStream(url: String, options: [String: NodeValue]?, callbackFn: NodeFunction) async throws -> NodeValueConvertible {
        let callback = { [queue] (event, data) in
            do {
                try queue.run { _ = try callbackFn(event, data) }
            } catch {
                print("swift-fetch requestStream callback error \(error)")
            }
        }

        do {
            return try await Self.internalRequest(url: url, options: options) { response in
                await callback("response", [
                    "statusCode": Int(response.status.code),
                    "headers": Self.mapHeaders(response.headers)
                ])

                do {
                    for try await buffer in response.body {
                        callback("data", Data(buffer: buffer))
                    }
                } catch {
                    callback("error", "\(error)")
                    throw error
                }

                callback("end", undefined)
                return undefined
            }
        } catch {
            print("swift-fetch requestStream error \(error)")
            callback("error", "\(error)")
        }

        return undefined
    }

    static func internalRequest<T>(
        url: String,
        options: [String: NodeValue]?,
        completion: @Sendable @escaping (_ response: HTTPClientResponse) async throws -> T
    ) async throws -> T {
        try await Self.retry(withTimeout: Self.retryTimeout) {
            var clientConfig = clientConfig
            let followRedirect = try? await options?["followRedirect"]?.as(Bool.self)
            if followRedirect == false {
                clientConfig.redirectConfiguration = .disallow
            }
            let client = HTTPClient(eventLoopGroupProvider: .shared(evGroup), configuration: clientConfig)
            do {
                let response = try await client.execute(
                    Self.mapToURLRequest(url: url, options: options),
                    timeout: .seconds(Self.connectionTimeout)
                )

                let data = try await completion(response)
                try await client.shutdown()
                return data
            } catch {
                try await client.shutdown()
                throw error
            }
        }
    }

    static func mapHeaders(_ headers: HTTPHeaders) -> NodeValueConvertible {
        headers.reduce(into: [:]) { (dict, item) in
            let key = item.name.lowercased()
            if let existingValue = dict[key] {
                if let arrayValue = existingValue as? [String] {
                    dict[key] = arrayValue + [item.value]
                } else if let stringValue = existingValue as? String {
                    dict[key] = [stringValue, item.value]
                }
            } else {
                dict[key] = item.value
            }
        }
    }

    static func mapToURLRequest(url: String, options: [String: NodeValue]?) throws -> HTTPClientRequest {
        var request = HTTPClientRequest(url: url.replacingOccurrences(of: " ", with: "%20"))
        if let method = try options?["method"]?.as(String.self) {
            request.method = HTTPMethod(rawValue: method.uppercased())
        }

        if let headers = try options?["headers"]?.as([String: String].self) {
            for (key, value) in headers {
                request.headers.add(name: key, value: value)
            }
        }

        if let body = try options?["body"]?.as(Data.self) {
            request.body = .bytes(body)
        }

        return request
    }

    @discardableResult
    static func retry<T>(
        withTimeout timeout: TimeInterval,
        maxRetries: Int = 10,
        intervalMs: UInt64 = 100,
        _ closure: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        let start = Date()
        var result: Result<T, Error>
        var attempt = 0

        repeat {
            do {
                return try await closure()
            } catch let error as NIOConnectionError {
                result = .failure(error)
                // retry dns error indefinitely
                if error.dnsAError != nil || error.dnsAAAAError != nil {
                    print("retry dns error \(error)")
                    continue
                }

                // Hnadle single connection failures
                // ex: NIOPosix.SingleConnectionFailure(target: [IPv4]slack.com/44.237.180.172:443, error: connection reset (error set): Connection refused (errno: 61)),
                // TODO: handle connection refused
                if !error.connectionErrors.isEmpty {
                    print("retry SingleConnectionFailure \(error)")
                    continue
                }

                // fallthrough
                throw error
            } catch {
                result = .failure(error)
                if (error as? HTTPClientError) == .invalidURL {
                    break
                }

                print("retry error \(error)")
                attempt += 1
            }
            try? await Task.sleep(nanoseconds: intervalMs * 1_000_000)
        } while -start.timeIntervalSinceNow < timeout && attempt < maxRetries

        return try result.get()
    }
}
#endif
