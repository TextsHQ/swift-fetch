import Foundation
import AsyncHTTPClient
import NIOHTTP1
import NIOSSL
import NIOFoundationCompat
import NodeAPI

enum HTTPStreamError: Error {
    case invalidCallback
}

let httpClient: HTTPClient = {
    var config = HTTPClient.Configuration()
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
    config.tlsConfiguration?.renegotiationSupport = .explicit
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

    config.decompression = .enabled(limit: .none)

    if ProcessInfo.processInfo.environment["NODE_TLS_REJECT_UNAUTHORIZED"] == "0" {
        config.tlsConfiguration?.certificateVerification = .none
    }

    // Custom Configs from fork
    config.tlsConfiguration?.grease = true
    config.tlsConfiguration?.signedCertificateTimestamps = true
    config.tlsConfiguration?.ocspStapling = true
    config.tlsConfiguration?.brotliCertificateCompression = true

    return HTTPClient(
        eventLoopGroupProvider: .createNew,
        configuration: config
    )
}()

@NodeActor
func mapToURLRequest(url: String, options: [String: NodeValue]?) throws -> HTTPClientRequest {
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

@main struct SwiftFetch: NodeModule {
    let exports: NodeValueConvertible
    let queue: NodeAsyncQueue
    init() throws {
        let queue = try NodeAsyncQueue(label: "http-stream-callback-queue")

        exports = [
            "requestStream": try NodeFunction { (url: String, options: [String: NodeValue]?, callbackFn: NodeFunction) in
                let callback = { [queue] (event, data) in
                    do {
                        try queue.run { _ = try callbackFn(event, data) }
                    } catch {
                        print("\(error)")
                    }
                }

                let httpRequest = try mapToURLRequest(url: url, options: options)
                Task {
                    let response = try await httpClient.execute(httpRequest, timeout: .seconds(10))

                    callback("response", [
                        "statusCode": Int(response.status.code),
                        "headers": response.headers.reduce(into: [:]) { (dict, item) in
                            let key = item.name.lowercased()
                            if let existingValue = dict[key] {
                                dict[key] = "\(existingValue), \(item.value)"
                            } else {
                                dict[key] = item.value
                            }
                        }
                    ])

                    for try await buffer in response.body {
                        callback("data", Data(buffer: buffer))
                    }

                    callback("end", undefined)
                }
                return undefined
            },
            "request": try NodeFunction { (url: String, options: [String: NodeValue]?) in
                let httpRequest = try mapToURLRequest(url: url, options: options)

                return try NodePromise {
                    let response = try await httpClient.execute(httpRequest, timeout: .seconds(10))
                    let byteBuffer = try await response.body.collect(upTo: 1024 * 1024 * 100) // up to 100MB
                    return [
                        "body": Data(buffer: byteBuffer),
                        "statusCode": Int(response.status.code),
                        "headers": response.headers.reduce(into: [:]) { (dict, item) in
                            let key = item.name.lowercased()
                            if let existingValue = dict[key] {
                                dict[key] = "\(existingValue), \(item.value)"
                            } else {
                                dict[key] = item.value
                            }
                        }
                    ]
                }
            },
        ]

        self.queue = queue
    }
}
