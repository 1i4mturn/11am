import Foundation

/// One value in an IMAP response: an atom, a string (quoted or literal), a parenthesised list, or NIL.
indirect enum IMAPValue: Sendable {
    case atom(String)
    case string(Data)
    case list([IMAPValue])
    case none

    var text: String? {
        switch self {
        case .atom(let value): return value
        case .string(let data): return String(decoding: data, as: UTF8.self)
        default: return nil
        }
    }

    var data: Data? {
        switch self {
        case .atom(let value): return Data(value.utf8)
        case .string(let data): return data
        default: return nil
        }
    }

    var items: [IMAPValue] {
        if case .list(let values) = self { return values }
        return []
    }
}

/// Reads one IMAP response (with any literals already inlined) into values.
/// Atoms keep bracketed sections whole, so `BODY[HEADER.FIELDS (FROM TO)]<0>` is a single atom.
struct IMAPParser {
    private let bytes: [UInt8]
    private var index = 0

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    mutating func values() -> [IMAPValue] {
        var out: [IMAPValue] = []
        while index < bytes.count {
            if let value = next() { out.append(value) }
        }
        return out
    }

    private mutating func skipSpaces() {
        while index < bytes.count, bytes[index] == 32 || bytes[index] == 13 || bytes[index] == 10 { index += 1 }
    }

    private mutating func next() -> IMAPValue? {
        skipSpaces()
        guard index < bytes.count else { return nil }
        switch bytes[index] {
        case 40: // (
            index += 1
            var items: [IMAPValue] = []
            while true {
                skipSpaces()
                guard index < bytes.count else { break }
                if bytes[index] == 41 {
                    index += 1
                    break
                }
                if let value = next() { items.append(value) }
            }
            return .list(items)
        case 41: // a stray ")"
            index += 1
            return nil
        case 34: // "
            index += 1
            var out: [UInt8] = []
            while index < bytes.count, bytes[index] != 34 {
                if bytes[index] == 92, index + 1 < bytes.count { index += 1 }
                out.append(bytes[index])
                index += 1
            }
            index += 1
            return .string(Data(out))
        case 123: // {n} CRLF then n bytes
            var cursor = index + 1
            var count = 0
            while cursor < bytes.count, bytes[cursor] >= 48, bytes[cursor] <= 57 {
                count = count * 10 + Int(bytes[cursor] - 48)
                cursor += 1
            }
            if cursor < bytes.count, bytes[cursor] == 43 { cursor += 1 }
            if cursor < bytes.count, bytes[cursor] == 125 { cursor += 1 }
            if cursor + 1 < bytes.count, bytes[cursor] == 13, bytes[cursor + 1] == 10 { cursor += 2 }
            let end = min(bytes.count, cursor + count)
            index = end
            return .string(Data(bytes[min(cursor, end)..<end]))
        default:
            var out: [UInt8] = []
            var depth = 0
            while index < bytes.count {
                let byte = bytes[index]
                if depth == 0 && (byte == 32 || byte == 40 || byte == 41 || byte == 13 || byte == 10) { break }
                if byte == 91 { depth += 1 }
                if byte == 93 { depth = max(0, depth - 1) }
                out.append(byte)
                index += 1
            }
            guard !out.isEmpty else {
                index += 1
                return nil
            }
            let text = String(decoding: out, as: UTF8.self)
            return text.uppercased() == "NIL" ? IMAPValue.none : .atom(text)
        }
    }
}

struct IMAPFolder: Sendable, Hashable {
    let name: String
    /// Lower-cased, e.g. "\\archive", "\\sent", "\\noselect".
    let attributes: Set<String>
}

/// The folders that matter for triage and actions, found by their special-use flags or usual names.
struct IMAPSpecialFolders: Sendable {
    var archive: String?
    var trash: String?
    var sent: String?
    var all: String?
    var junk: String?

    init(_ folders: [IMAPFolder]) {
        func find(_ flag: String, names: [String]) -> String? {
            if let folder = folders.first(where: { $0.attributes.contains(flag) }) { return folder.name }
            return folders.first { folder in names.contains { folder.name.caseInsensitiveCompare($0) == .orderedSame } }?.name
        }
        archive = find("\\archive", names: ["Archive", "Archives", "INBOX.Archive"])
        trash = find("\\trash", names: ["Trash", "Deleted Messages", "Deleted Items", "INBOX.Trash"])
        sent = find("\\sent", names: ["Sent", "Sent Messages", "Sent Items", "Sent Mail", "INBOX.Sent"])
        all = find("\\all", names: ["[Gmail]/All Mail", "[Google Mail]/All Mail"])
        junk = find("\\junk", names: ["Junk", "Spam", "Junk E-mail", "[Gmail]/Spam"])
    }
}

/// A small IMAP4rev1 client: enough to sync an inbox, learn from past flags, and archive, delete, flag and file sent mail.
actor IMAPClient {
    struct Selected: Sendable {
        var exists = 0
        var uidValidity: UInt32 = 0
        var uidNext: UInt32 = 0
    }

    struct Fetched: Sendable {
        var uid: UInt32 = 0
        /// Lower-cased, e.g. "\\seen".
        var flags: Set<String> = []
        var internalDate: Date?
        var header: Data?
        var body: Data?
    }

    private let socket: MailSocket
    private var tagNumber = 0
    private var greeting: String?
    private(set) var capabilities: Set<String> = []

    init(host: String, port: Int, security: MailSecurity) {
        socket = MailSocket(host: host, port: port, security: security)
    }

    /// Reads the greeting (once), then signs in. Safe to call again with other details after a refused sign-in.
    func login(username: String, password: String) async throws {
        if try await readGreeting() {
            do {
                try await command("LOGIN \(IMAPClient.quote(username)) \(IMAPClient.quote(password))")
            } catch let error as MailError {
                throw MailError("Sign-in failed: \(error.message)")
            }
        }
        try await loadCapabilities()
    }

    /// Signs in with an OAuth access token (SASL XOAUTH2), as Microsoft requires now that app passwords are gone.
    func authenticate(user: String, token: String) async throws {
        if try await readGreeting() {
            let payload = Data("user=\(user)\u{1}auth=Bearer \(token)\u{1}\u{1}".utf8).base64EncodedString()
            let tag = nextTag()
            let prefix = Data((tag + " ").utf8)
            try await socket.write("\(tag) AUTHENTICATE XOAUTH2\r\n")
            var answered = false
            while true {
                let response = try await readResponse()
                if response.first == 43 { // "+": the go-ahead, or an error report after a refused token
                    try await socket.write(answered ? "\r\n" : payload + "\r\n")
                    answered = true
                    continue
                }
                guard response.starts(with: prefix) else { continue }
                let status = String(decoding: response.dropFirst(prefix.count), as: UTF8.self)
                if status.uppercased().hasPrefix("OK") { break }
                throw MailError("Sign-in was refused: \(IMAPClient.readable(status))")
            }
        }
        try await loadCapabilities()
    }

    /// True when the server still wants a sign-in (it didn't greet with PREAUTH).
    private func readGreeting() async throws -> Bool {
        if greeting == nil {
            let hello = String(decoding: try await readResponse(), as: UTF8.self)
            guard hello.uppercased().hasPrefix("* OK") || hello.uppercased().hasPrefix("* PREAUTH") else {
                throw MailError("The mail server didn't say hello: \(hello.prefix(80))")
            }
            greeting = hello
        }
        return greeting?.uppercased().hasPrefix("* PREAUTH") == false
    }

    private func loadCapabilities() async throws {
        for line in try await command("CAPABILITY") {
            let text = String(decoding: line, as: UTF8.self)
            guard text.uppercased().hasPrefix("* CAPABILITY") else { continue }
            capabilities = Set(text.split(separator: " ").dropFirst(2).map { $0.uppercased() })
        }
    }

    func logout() async {
        _ = try? await command("LOGOUT")
        socket.close()
    }

    func folders() async throws -> [IMAPFolder] {
        try await command("LIST \"\" \"*\"").compactMap { raw in
            var parser = IMAPParser(raw)
            let values = parser.values()
            guard values.count >= 5, values[1].text?.uppercased() == "LIST", let name = values[4].text else { return nil }
            return IMAPFolder(name: name, attributes: Set(values[2].items.compactMap { $0.text?.lowercased() }))
        }
    }

    @discardableResult
    func select(_ mailbox: String, readOnly: Bool = false) async throws -> Selected {
        var result = Selected()
        for raw in try await command("\(readOnly ? "EXAMINE" : "SELECT") \(IMAPClient.quote(mailbox))") {
            let text = String(decoding: raw, as: UTF8.self)
            let parts = text.split(separator: " ")
            if parts.count >= 3, parts[2].uppercased() == "EXISTS" { result.exists = Int(parts[1]) ?? 0 }
            if let value = IMAPClient.bracketNumber(text, "UIDVALIDITY") { result.uidValidity = value }
            if let value = IMAPClient.bracketNumber(text, "UIDNEXT") { result.uidNext = value }
        }
        return result
    }

    /// UIDs matching the criteria, oldest first.
    func search(_ criteria: String) async throws -> [UInt32] {
        var uids: [UInt32] = []
        for raw in try await command("UID SEARCH \(criteria)") {
            let text = String(decoding: raw, as: UTF8.self)
            guard text.uppercased().hasPrefix("* SEARCH") else { continue }
            uids += text.split(separator: " ").dropFirst(2).compactMap { UInt32($0) }
        }
        return uids.sorted()
    }

    func fetch(_ uids: [UInt32], items: String) async throws -> [Fetched] {
        guard !uids.isEmpty else { return [] }
        return try await command("UID FETCH \(IMAPClient.sequenceSet(uids)) \(items)").compactMap(IMAPClient.parseFetch)
    }

    func store(_ uids: [UInt32], flags: [String], add: Bool) async throws {
        guard !uids.isEmpty else { return }
        try await command("UID STORE \(IMAPClient.sequenceSet(uids)) \(add ? "+" : "-")FLAGS.SILENT (\(flags.joined(separator: " ")))")
    }

    func move(_ uids: [UInt32], to mailbox: String) async throws {
        guard !uids.isEmpty else { return }
        let set = IMAPClient.sequenceSet(uids)
        if capabilities.contains("MOVE") {
            try await command("UID MOVE \(set) \(IMAPClient.quote(mailbox))")
        } else {
            try await command("UID COPY \(set) \(IMAPClient.quote(mailbox))")
            try await store(uids, flags: ["\\Deleted"], add: true)
            try await command(capabilities.contains("UIDPLUS") ? "UID EXPUNGE \(set)" : "EXPUNGE")
        }
    }

    /// Files a message (a sent copy) into a mailbox.
    func append(_ message: Data, to mailbox: String, flags: [String]) async throws {
        let literalPlus = capabilities.contains("LITERAL+")
        let tag = nextTag()
        try await socket.write("\(tag) APPEND \(IMAPClient.quote(mailbox)) (\(flags.joined(separator: " "))) {\(message.count)\(literalPlus ? "+" : "")}\r\n")
        if !literalPlus {
            let reply = try await readResponse()
            guard reply.first == 43 else { // "+"
                throw MailError("The server wouldn't file the sent copy: \(String(decoding: reply, as: UTF8.self).prefix(120))")
            }
        }
        var payload = message
        payload.append(contentsOf: [13, 10])
        try await socket.write(payload)
        _ = try await finish(tag)
    }

    // MARK: Protocol

    @discardableResult
    func command(_ text: String) async throws -> [Data] {
        let tag = nextTag()
        try await socket.write("\(tag) \(text)\r\n")
        return try await finish(tag)
    }

    private func finish(_ tag: String) async throws -> [Data] {
        let prefix = Data((tag + " ").utf8)
        var untagged: [Data] = []
        while true {
            let response = try await readResponse()
            guard response.starts(with: prefix) else {
                untagged.append(response)
                continue
            }
            let status = String(decoding: response.dropFirst(prefix.count), as: UTF8.self)
            if status.uppercased().hasPrefix("OK") { return untagged }
            throw MailError(IMAPClient.readable(status))
        }
    }

    private func nextTag() -> String {
        tagNumber += 1
        return "E\(tagNumber)"
    }

    /// One whole response: a line, plus any literals and the lines that continue after them.
    private func readResponse() async throws -> Data {
        var raw = Data()
        while true {
            let line = try await socket.readLine()
            raw.append(line)
            guard let count = IMAPClient.literalLength(line) else { return raw }
            raw.append(contentsOf: [13, 10])
            raw.append(try await socket.read(count: count))
        }
    }

    // MARK: Helpers

    static func literalLength(_ line: Data) -> Int? {
        guard line.last == 125, let open = line.lastIndex(of: 123) else { return nil }
        var digits = String(decoding: line[line.index(after: open)..<line.index(before: line.endIndex)], as: UTF8.self)
        if digits.hasSuffix("+") { digits.removeLast() }
        return Int(digits)
    }

    static func parseFetch(_ raw: Data) -> Fetched? {
        var parser = IMAPParser(raw)
        let values = parser.values()
        guard values.count >= 4, values[2].text?.uppercased() == "FETCH" else { return nil }
        let items = values[3].items
        var result = Fetched()
        var index = 0
        while index + 1 < items.count {
            let key = items[index].text?.uppercased() ?? ""
            let value = items[index + 1]
            if key == "UID" {
                result.uid = UInt32(value.text ?? "") ?? 0
            } else if key == "FLAGS" {
                result.flags = Set(value.items.compactMap { $0.text?.lowercased() })
            } else if key == "INTERNALDATE" {
                result.internalDate = value.text.flatMap(IMAPClient.internalDate)
            } else if key.hasPrefix("BODY[HEADER") {
                result.header = value.data
            } else if key.hasPrefix("BODY[]") || key == "RFC822" {
                result.body = value.data
            }
            index += 2
        }
        return result.uid == 0 ? nil : result
    }

    /// "1:5,7,9:12" from a list of UIDs.
    static func sequenceSet(_ uids: [UInt32]) -> String {
        let sorted = Array(Set(uids)).sorted()
        var parts: [String] = []
        var index = 0
        while index < sorted.count {
            let start = sorted[index]
            var end = start
            while index + 1 < sorted.count, sorted[index + 1] == end + 1 {
                index += 1
                end = sorted[index]
            }
            parts.append(start == end ? "\(start)" : "\(start):\(end)")
            index += 1
        }
        return parts.joined(separator: ",")
    }

    static func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func bracketNumber(_ text: String, _ key: String) -> UInt32? {
        guard let range = text.range(of: "[\(key) ") else { return nil }
        return UInt32(text[range.upperBound...].prefix { $0.isNumber })
    }

    /// The date form IMAP searches use, e.g. 1-Oct-2026.
    static func searchDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "d-MMM-yyyy"
        return formatter.string(from: date)
    }

    static func internalDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d-MMM-yyyy HH:mm:ss Z"
        return formatter.date(from: text.trimmingCharacters(in: .whitespaces))
    }

    /// Server status text without the tag noise, e.g. "[AUTHENTICATIONFAILED] Invalid credentials".
    static func readable(_ status: String) -> String {
        var text = status
        for word in ["NO ", "BAD "] where text.uppercased().hasPrefix(word) {
            text = String(text.dropFirst(word.count))
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}
