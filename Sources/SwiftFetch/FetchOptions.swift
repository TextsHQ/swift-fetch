import Foundation
import NodeAPI

#if !USE_URLSESSION && (os(macOS) || os(Linux))
import AsyncHTTPClient
import NIO
import NIOSSL
import NIOHTTP1
import NIOFoundationCompat
#endif

public struct FetchOptions {
    var url: URL
    var followRedirect: Bool
    var headers: [String: String]
    var method: String?
    var body: Data?
    var skipCertificateVerification: Bool?
    var pinnedCertificates: [Data]?

    #if USE_URLSESSION || os(iOS)
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
    #endif

    #if !USE_URLSESSION && (os(macOS) || os(Linux))
    var request: HTTPClientRequest {
        var request = HTTPClientRequest(url: url.absoluteString)
        if let method = method {
            request.method = HTTPMethod(rawValue: method.uppercased())
        }

        for (key, value) in headers {
            request.headers.add(name: key, value: value)
        }

        if let body = body {
            request.body = .bytes(body)
        }

        return request
    }
    #endif
}

extension FetchOptions {
    @NodeActor init(url: String, raw: [String: NodeValue]?) throws {
        guard let url = URL(string: url.replacingOccurrences(of: " ", with: "%20")) else { 
            throw URLError(.badURL)
        }
        self.url = url
        followRedirect = try raw?["followRedirect"]?.as(Bool.self) ?? true
        headers = try raw?["headers"]?.as([String: String].self) ?? [:]
        method = try raw?["method"]?.as(String.self)
        body = try raw?["body"]?.as(NodeTypedArray<UInt8>.self)?.dataNoCopy()
        skipCertificateVerification = try raw?["skipCertificateVerification"]?.as(Bool.self)
        pinnedCertificates = try raw?["pinnedCertificates"]?.as([NodeValue].self)?.compactMap {
            try $0.as(NodeTypedArray<UInt8>.self)?.dataNoCopy()
        }
    }
}
