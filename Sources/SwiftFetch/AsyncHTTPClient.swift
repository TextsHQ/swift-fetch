#if !USE_URLSESSION && (os(macOS) || os(Linux))
/**
  * Configured to spoof chrome
  */
// TODO: add windows support
import Foundation
import NodeAPI
import NIO
import NIOSSL
import NIOHTTP1
import NIOFoundationCompat
import AsyncHTTPClient

let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

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
        try await Self.internalRequest(url: url, options: options) { response in
            let byteBuffer = try await response.body.collect(upTo: 1024 * 1024 * 100) // up to 100MB

            return await [
                "status": Int(response.status.code),
                "headers": Self.mapHeaders(response.headers),
                "body": Data(buffer: byteBuffer),
            ]
        }
    }

    public func requestStream(url: String, options: [String: NodeValue]?, callbackFn: NodeFunction) async throws -> NodeValueConvertible {
        let callback = { [queue] (event, data) in
            do {
                try queue.run { _ = try callbackFn(event, data) }
            } catch {
                print("\(error)")
            }
        }

        return try await Self.internalRequest(url: url, options: options) { response in
            await callback("response", [
                "status": Int(response.status.code),
                "headers": Self.mapHeaders(response.headers),
            ])

            do {
                for try await buffer in response.body {
                    callback("data", Data(buffer: buffer))
                }
            } catch {
                print("requestStream error \(error)")
                callback("error", String(describing: error))
                throw error
            }

            callback("end", undefined)

            return undefined
        }
    }

    static func internalRequest<T>(
        url: String,
        options: [String: NodeValue]?,
        completion: @Sendable @escaping (_ response: HTTPClientResponse) async throws -> T
    ) async throws -> T {
        let timeout = (try? options?["timeout"]?.as(Int.self)) ?? 30
        let followRedirect = (try? options?["redirect"]?.as(String.self)) == "follow"
        let maxRedirects = (try? options?["follow"]?.as(Int.self)) ?? 20
        let verifyCertificate = (try? options?["verifyCertificate"]?.as(Bool.self)) ?? true

        let httpClient = Self.makeHTTPClient(verifyCertificate: verifyCertificate, followRedirect: followRedirect, maxRedirects: maxRedirects)

        do {
            let request = try Self.mapToURLRequest(url: url, options: options)
            let response = try await httpClient.execute(request, timeout: .seconds(Int64(timeout)))
            let data = try await completion(response)

            return data
        } catch {
            print("internalRequest error \(error)")
            throw error
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
        var request = HTTPClientRequest(url: url)

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

    static func makeHTTPClient(verifyCertificate: Bool = true, followRedirect: Bool = false, maxRedirects: Int = 20) -> HTTPClient {
        var config = HTTPClient.Configuration()

        if !followRedirect {
            config.redirectConfiguration = .disallow
        } else {
            config.redirectConfiguration = .follow(max: maxRedirects, allowCycles: false)
        }

        config.decompression = .enabled(limit: .none)

        // TLS Configuration
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

        if !verifyCertificate || ProcessInfo.processInfo.environment["NODE_TLS_REJECT_UNAUTHORIZED"] == "0" {
            config.tlsConfiguration?.certificateVerification = .none
        }

        // TLS custom Configs from fork
        config.tlsConfiguration?.grease = true
        config.tlsConfiguration?.signedCertificateTimestamps = true
        config.tlsConfiguration?.ocspStapling = true
        config.tlsConfiguration?.brotliCertificateCompression = true
        config.tlsConfiguration?.renegotiationSupport = .explicit

        return HTTPClient(
            eventLoopGroupProvider: .shared(eventLoopGroup),
            configuration: config
        )
    }
}
#endif
