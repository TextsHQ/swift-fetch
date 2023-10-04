# swift-fetch

Currently has 2 implementations to support iOS and Desktop app.

## Implementations

### URLSession

URLSession matches Safari JA3 and HTTP2 signatures for texts-app-ios usage.

### AsyncHTTPClient

Primarily used for texts-app-desktop. This uses patched async-http-client and its dependencies to mimic the JA3 and HTTP2 signature of Chrome.

#### swift-nio-* patches

##### swift-nio-http2

We had to patch this to match the HTTP2 client signature of Chrome

- [Header Sorting](https://github.com/TextsHQ/swift-nio-http2/commit/4ecd2e280b1f2ee6bcdbf663863792726751fd9b)
- [HTTP2 Header Table Sizes](https://github.com/TextsHQ/swift-nio-http2/commit/eeec9e24a628e8a15093136a8d5ec333adb3fcb3)

##### swift-nio-ssl

Added support for the following features not implemented in upstream. This was also needed to match the JA3 signature of Chrome. The configuration and settings were taken from the Chromium source code.

- Brotli Certificate Decompression
- Explicit SSL renegotiation
- Application Settings (`CNIOBoringSSL_SSL_add_application_settings(self.ssl, "h2", 2, nil, 0)`)
- OCSP stapling
- Enable GREASE/RFC8701
