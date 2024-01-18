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
