import Foundation

/// One message as read from disk, before triage.
struct ParsedMail {
    /// Lower-cased header names; the first occurrence wins.
    var headers: [String: String]
    var body: String
}

/// A small, forgiving RFC 5322 / MIME reader: headers, the plain-text body and the common encodings.
/// Enough for triage and drafting. The real Marc uses a full MIME parser in the Rust core.
enum MailParser {
    // MARK: Containers

    /// Splits an mbox file into messages, keeping only the newest `limit`.
    static func messages(inMbox text: String, limit: Int) -> [ParsedMail] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var chunks = normalized.components(separatedBy: "\nFrom ")
        if chunks.count > limit { chunks = Array(chunks.suffix(limit)) }
        return chunks.compactMap { chunk in
            // The first line is the mbox envelope ("From sender date"), not part of the message.
            guard let newline = chunk.firstIndex(of: "\n") else { return nil }
            let message = String(chunk[chunk.index(after: newline)...])
            guard message.contains(":") else { return nil }
            return parse(message)
        }
    }

    /// Apple Mail's .emlx: a byte count on the first line, the raw message, then a property list.
    static func parseEmlx(_ data: Data, headersOnly: Bool = false) -> ParsedMail? {
        guard let newline = data.firstIndex(of: UInt8(ascii: "\n")),
              let count = Int(String(decoding: data[data.startIndex..<newline], as: UTF8.self).trimmingCharacters(in: .whitespaces))
        else { return nil }
        let start = data.index(after: newline)
        let end = min(data.endIndex, start + count)
        guard start < end else { return nil }
        return parse(String(decoding: data[start..<end], as: UTF8.self), headersOnly: headersOnly)
    }

    // MARK: Message

    static func parse(_ raw: String, headersOnly: Bool = false) -> ParsedMail {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let (headerBlock, body) = splitHeaders(normalized)
        let headers = parseHeaders(headerBlock)
        return ParsedMail(headers: headers, body: headersOnly ? "" : decodeBody(headers: headers, body: body, depth: 0))
    }

    private static func splitHeaders(_ text: String) -> (String, String) {
        if let range = text.range(of: "\n\n") {
            return (String(text[..<range.lowerBound]), String(text[range.upperBound...]))
        }
        return (text, "")
    }

    private static func parseHeaders(_ block: String) -> [String: String] {
        var headers: [String: String] = [:]
        var name: String?
        var value = ""
        func commit() {
            if let name, headers[name] == nil {
                headers[name] = value.trimmingCharacters(in: .whitespaces)
            }
        }
        for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = line.first, first == " " || first == "\t" {
                value += " " + line.trimmingCharacters(in: .whitespaces) // folded header
            } else if let colon = line.firstIndex(of: ":") {
                commit()
                name = line[..<colon].lowercased().trimmingCharacters(in: .whitespaces)
                value = String(line[line.index(after: colon)...])
            }
        }
        commit()
        return headers
    }

    /// "text/plain; charset=utf-8" → ("text/plain", ["charset": "utf-8"])
    private static func contentType(_ value: String?) -> (type: String, params: [String: String]) {
        guard let value else { return ("text/plain", [:]) }
        let parts = value.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        var params: [String: String] = [:]
        for part in parts.dropFirst() {
            guard let equals = part.firstIndex(of: "=") else { continue }
            let key = part[..<equals].lowercased().trimmingCharacters(in: .whitespaces)
            var item = part[part.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if item.count >= 2, item.hasPrefix("\""), item.hasSuffix("\"") {
                item = String(item.dropFirst().dropLast())
            }
            params[key] = item
        }
        return ((parts.first ?? "text/plain").lowercased(), params)
    }

    /// Prefers text/plain, falls back to text/html with the tags stripped, skips attachments.
    private static func decodeBody(headers: [String: String], body: String, depth: Int) -> String {
        let (type, params) = contentType(headers["content-type"])
        if type.hasPrefix("multipart/") {
            guard depth < 5, let boundary = params["boundary"] else { return "" }
            let parts = body.components(separatedBy: "--" + boundary).dropFirst()
            var html: String?
            for part in parts where !part.hasPrefix("--") {
                let (partHeaderBlock, partBody) = splitHeaders(part.hasPrefix("\n") ? String(part.dropFirst()) : part)
                let partHeaders = parseHeaders(partHeaderBlock)
                if partHeaders["content-disposition"]?.lowercased().hasPrefix("attachment") == true { continue }
                let partType = contentType(partHeaders["content-type"]).type
                if partType == "text/plain" || partType.hasPrefix("multipart/") {
                    let text = decodeBody(headers: partHeaders, body: partBody, depth: depth + 1)
                    if !text.isEmpty { return text }
                } else if partType == "text/html", html == nil {
                    html = decodeBody(headers: partHeaders, body: partBody, depth: depth + 1)
                }
            }
            return html ?? ""
        }
        guard type.hasPrefix("text/") else { return "" }
        let charset = params["charset"]
        var text: String
        switch headers["content-transfer-encoding"]?.lowercased() ?? "" {
        case "base64": text = decodeBase64(body, charset: charset)
        case "quoted-printable": text = decodeQuotedPrintable(body, charset: charset)
        default: text = body
        }
        if type == "text/html" { text = stripHTML(text) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Encodings

    private static func stringEncoding(for charset: String?) -> String.Encoding {
        switch charset?.lowercased() {
        case "iso-8859-1", "latin1", "latin-1": return .isoLatin1
        case "windows-1252", "cp1252": return .windowsCP1252
        case "utf-16": return .utf16
        default: return .utf8
        }
    }

    private static func string(from data: Data, charset: String?) -> String {
        String(data: data, encoding: stringEncoding(for: charset)) ?? String(decoding: data, as: UTF8.self)
    }

    private static func decodeBase64(_ text: String, charset: String?) -> String {
        guard let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return text }
        return string(from: data, charset: charset)
    }

    private static func decodeQuotedPrintable(_ text: String, charset: String?) -> String {
        let input = Array(text.utf8)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(input.count)
        var index = 0
        while index < input.count {
            let byte = input[index]
            if byte == UInt8(ascii: "=") {
                if index + 1 < input.count, input[index + 1] == UInt8(ascii: "\n") {
                    index += 2 // soft line break
                    continue
                }
                if index + 2 < input.count, let high = hexDigit(input[index + 1]), let low = hexDigit(input[index + 2]) {
                    bytes.append(high << 4 | low)
                    index += 3
                    continue
                }
            }
            bytes.append(byte)
            index += 1
        }
        return string(from: Data(bytes), charset: charset)
    }

    private static func hexDigit(_ c: UInt8) -> UInt8? {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return c - UInt8(ascii: "A") + 10
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
        default: return nil
        }
    }

    /// RFC 2047 encoded words in headers: =?utf-8?Q?Caf=C3=A9?= and =?utf-8?B?Q2Fmw6k=?=
    static func decodeWords(_ value: String) -> String {
        guard value.contains("=?"),
              let regex = try? NSRegularExpression(pattern: #"=\?([^?]+)\?([bBqQ])\?([^?]*)\?="#)
        else { return value }
        let ns = value as NSString
        var result = ""
        var cursor = 0
        var previousWasEncoded = false
        for match in regex.matches(in: value, range: NSRange(location: 0, length: ns.length)) {
            let between = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            // Whitespace between two encoded words is folding, not content.
            if !(previousWasEncoded && between.allSatisfy(\.isWhitespace)) { result += between }
            let charset = ns.substring(with: match.range(at: 1))
            let payload = ns.substring(with: match.range(at: 3))
            if ns.substring(with: match.range(at: 2)).uppercased() == "B" {
                let padded = payload + String(repeating: "=", count: (4 - payload.count % 4) % 4)
                if let data = Data(base64Encoded: padded, options: .ignoreUnknownCharacters) {
                    result += string(from: data, charset: charset)
                }
            } else {
                result += decodeQuotedPrintable(payload.replacingOccurrences(of: "_", with: " "), charset: charset)
            }
            cursor = match.range.location + match.range.length
            previousWasEncoded = true
        }
        result += ns.substring(from: cursor)
        return result
    }

    // MARK: Fields

    /// "Priya Shah" <priya@example.com> → ("Priya Shah", "priya@example.com")
    static func address(_ value: String) -> (name: String, address: String) {
        let decoded = decodeWords(value)
        if let open = decoded.lastIndex(of: "<"), let close = decoded.lastIndex(of: ">"), open < close {
            let address = String(decoded[decoded.index(after: open)..<close])
            let name = decoded[..<open]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return (name.isEmpty ? address : name, address)
        }
        let address = decoded.trimmingCharacters(in: .whitespaces)
        return (address, address)
    }


    /// Every address in a To or Cc header, lower-cased: "A <a@x.com>, \"B, Jr\" <b@y.com>" → ["a@x.com", "b@y.com"].
    static func addresses(_ value: String?) -> [String] {
        guard let value else { return [] }
        var parts: [String] = []
        var current = ""
        var quoted = false
        var angled = false
        for character in value {
            if character == "\"" { quoted.toggle() }
            if character == "<" { angled = true }
            if character == ">" { angled = false }
            if character == ",", !quoted, !angled {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)
        return parts.map { address($0).address.lowercased() }.filter { $0.contains("@") }
    }

    /// The read, answered and flagged marks Apple Mail keeps in the property list after an .emlx message.
    static func emlxFlags(_ data: Data) -> (read: Bool, answered: Bool, flagged: Bool)? {
        guard let newline = data.firstIndex(of: UInt8(ascii: "\n")),
              let count = Int(String(decoding: data[data.startIndex..<newline], as: UTF8.self).trimmingCharacters(in: .whitespaces))
        else { return nil }
        let start = data.index(after: newline) + count
        guard start < data.endIndex,
              let plist = try? PropertyListSerialization.propertyList(from: data.subdata(in: start..<data.endIndex), format: nil) as? [String: Any],
              let flags = (plist["flags"] as? NSNumber)?.intValue else { return nil }
        return (flags & 1 != 0, flags & (1 << 2) != 0, flags & (1 << 4) != 0)
    }

    private static let dateFormats = [
        "EEE, d MMM yyyy HH:mm:ss Z",
        "d MMM yyyy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm Z",
        "EEE, d MMM yy HH:mm:ss Z",
        "EEE, d MMM yyyy HH:mm:ss zzz",
    ]

    static func date(_ value: String?) -> Date? {
        guard var value else { return nil }
        if let comment = value.firstIndex(of: "(") { value = String(value[..<comment]) } // "(AEST)"
        value = value.trimmingCharacters(in: .whitespaces)
        // A formatter per call: sync reads several accounts at once, and formatters aren't safe to share while changing.
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        for format in dateFormats {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: value) { return date }
        }
        return nil
    }

    static func stripHTML(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: "(?is)<(style|script|head)[^>]*>.*?</\\1>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>|</p>|</div>|</tr>|</li>|</h[1-6]>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"),
            ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&ldquo;", "“"), ("&rdquo;", "”"), ("&mdash;", "—"),
            ("&ndash;", "–"), ("&hellip;", "…"),
        ]
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n\\s*\\n\\s*\\n+", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
