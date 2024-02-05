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

let clientConfig: HTTPClient.Configuration = {
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

@NodeActor @NodeClass final class Client {
    private static var retryTimeout: TimeInterval = 180

    private static var connectionTimeout: Int64 = 60

    let queue: NodeAsyncQueue

    @NodeConstructor init() throws {
        self.queue = try NodeAsyncQueue(label: "http-stream-callback-queue")
    }

    @NodeMethod public func request(url: String, options: [String: NodeValue]?) async throws -> NodeValueConvertible {
        do {
            return try await internalRequest(url: url, options: options) { response in
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

    @NodeMethod public func requestStream(url: String, options: [String: NodeValue]?, callbackFn: NodeFunction) async throws {
        let callback = { [queue] (event, data) in
            do {
                try queue.run { _ = try callbackFn(event, data) }
            } catch {
                print("swift-fetch requestStream callback error \(error)")
            }
        }

        do {
            try await internalRequest(url: url, options: options) { response in
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
            }
        } catch {
            print("swift-fetch requestStream error \(error)")
            callback("error", "\(error)")
        }
    }

    let client = HTTPClient(eventLoopGroupProvider: .shared(evGroup), configuration: clientConfig)

    func internalRequest<T>(
        url: String,
        options: [String: NodeValue]?,
        completion: @Sendable @escaping (_ response: HTTPClientResponse) async throws -> T
    ) async throws -> T {
        let options = try FetchOptions(url: url, raw: options)
        let request = try {
            var request = options.request
            if options.followRedirect == false {
                request.redirectConfiguration = .disallow
            }

            var tlsConfiguration = clientConfig.tlsConfiguration
            if options.skipCertificateVerification == true {
                tlsConfiguration?.certificateVerification = .none
            }
            if let pinnedCertificates = options.pinnedCertificates {
                tlsConfiguration?.trustRoots = try NIOSSLTrustRoots.certificates(pinnedCertificates.map { try NIOSSLCertificate(bytes: Array($0), format: .der) })
            }
            request.tlsConfiguration = tlsConfiguration

            return request
        }()

        return try await Self.retry(withTimeout: Self.retryTimeout) {
            do {
                let response = try await self.client.execute(
                    request,
                    timeout: .seconds(Self.connectionTimeout)
                )

                let data = try await completion(response)
                return data
            } catch {
                throw error
            }
        }
    }

    static func mapHeaders(_ headers: HTTPHeaders) -> NodeValueConvertible {
        headers.reduce(into: [:]) { (dict, item) in
            let key = item.name.lowercased()
            if key == "set-cookie" {
                dict[key] = (dict[key] as? [String] ?? []) + [item.value]
            } else if let existingValue = dict[key] {
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

                // Handle single connection failures
                // ex: NIOPosix.SingleConnectionFailure(target: [IPv4]slack.com/44.237.180.172:443, error: connection reset (error set): Connection refused (errno: 61)),
                // TODO: handle connection refused
                if !error.connectionErrors.isEmpty {
                    print("retry SingleConnectionFailure \(error)")
                    continue
                }

                break
            } catch let error as NIOSSLError {
                result = .failure(error)
                if case .handshakeFailed = error {
                    break
                }

                print("retry \(error)")
                continue
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
