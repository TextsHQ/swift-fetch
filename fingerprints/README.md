# Fingerprints

## Chrome

```text
[ALPN] client offers:
 * h2
 * http/1.1
SSL/TLS handshake completed
The negotiated protocol: h2
[id=2] [  1.690] send SETTINGS frame <length=6, flags=0x00, stream_id=0>
          (niv=1)
          [SETTINGS_MAX_CONCURRENT_STREAMS(0x03):100]
[id=2] [  1.690] recv SETTINGS frame <length=30, flags=0x00, stream_id=0>
          (niv=5)
          [SETTINGS_HEADER_TABLE_SIZE(0x01):65536]
          [SETTINGS_ENABLE_PUSH(0x02):0]
          [SETTINGS_MAX_CONCURRENT_STREAMS(0x03):1000]
          [SETTINGS_INITIAL_WINDOW_SIZE(0x04):6291456]
          [SETTINGS_MAX_HEADER_LIST_SIZE(0x06):262144]
[id=2] [  1.690] recv WINDOW_UPDATE frame <length=4, flags=0x00, stream_id=0>
          (window_size_increment=15663105)
[id=2] [  1.690] recv (stream_id=1) :method: GET
[id=2] [  1.690] recv (stream_id=1) :authority: localhost:8000
[id=2] [  1.690] recv (stream_id=1) :scheme: https
[id=2] [  1.691] recv (stream_id=1) :path: /
[id=2] [  1.691] recv (stream_id=1) cache-control: max-age=0
[id=2] [  1.691] recv (stream_id=1) sec-ch-ua: "Chromium";v="112", "Google Chrome";v="112", "Not:A-Brand";v="99"
[id=2] [  1.691] recv (stream_id=1) sec-ch-ua-mobile: ?0
[id=2] [  1.691] recv (stream_id=1) sec-ch-ua-platform: "macOS"
[id=2] [  1.691] recv (stream_id=1) upgrade-insecure-requests: 1
[id=2] [  1.691] recv (stream_id=1) user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Safari/537.36
[id=2] [  1.691] recv (stream_id=1) accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7
[id=2] [  1.691] recv (stream_id=1) sec-fetch-site: none
[id=2] [  1.691] recv (stream_id=1) sec-fetch-mode: navigate
[id=2] [  1.691] recv (stream_id=1) sec-fetch-user: ?1
[id=2] [  1.691] recv (stream_id=1) sec-fetch-dest: document
[id=2] [  1.691] recv (stream_id=1) accept-encoding: gzip, deflate, br
[id=2] [  1.691] recv (stream_id=1) accept-language: en-US,en;q=0.9
[id=2] [  1.691] recv (stream_id=1) dnt: 1
[id=2] [  1.691] recv (stream_id=1) sec-gpc: 1
```

## Safari

```text
[ALPN] client offers:
 * h2
 * http/1.1
SSL/TLS handshake completed
The negotiated protocol: h2
[id=6] [ 21.055] send SETTINGS frame <length=6, flags=0x00, stream_id=0>
          (niv=1)
          [SETTINGS_MAX_CONCURRENT_STREAMS(0x03):100]
[id=6] [ 21.056] recv SETTINGS frame <length=12, flags=0x00, stream_id=0>
          (niv=2)
          [SETTINGS_INITIAL_WINDOW_SIZE(0x04):4194304]
          [SETTINGS_MAX_CONCURRENT_STREAMS(0x03):100]
[id=6] [ 21.056] recv WINDOW_UPDATE frame <length=4, flags=0x00, stream_id=0>
          (window_size_increment=10485760)
[id=6] [ 21.056] send SETTINGS frame <length=0, flags=0x01, stream_id=0>
          ; ACK
          (niv=0)
[id=6] [ 21.056] recv SETTINGS frame <length=0, flags=0x01, stream_id=0>
          ; ACK
          (niv=0)
[id=6] [ 21.066] recv (stream_id=1) :method: GET
[id=6] [ 21.066] recv (stream_id=1) :scheme: https
[id=6] [ 21.066] recv (stream_id=1) :path: /
[id=6] [ 21.066] recv (stream_id=1) :authority: localhost:8000
[id=6] [ 21.066] recv (stream_id=1) accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8
[id=6] [ 21.066] recv (stream_id=1) sec-fetch-site: none
[id=6] [ 21.066] recv (stream_id=1) accept-encoding: gzip, deflate, br
[id=6] [ 21.066] recv (stream_id=1) sec-fetch-mode: navigate
[id=6] [ 21.066] recv (stream_id=1) user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.4 Safari/605.1.15
[id=6] [ 21.066] recv (stream_id=1) accept-language: en-US,en;q=0.9
[id=6] [ 21.066] recv (stream_id=1) sec-fetch-dest: document
```
