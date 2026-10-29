import Foundation

/// A message to send, before it becomes RFC 5322 text.
struct OutgoingMail: Sendable {
    var fromName: String
    var fromAddress: String
    var to: [String]
    var cc: [String] = []
    var subject: String
    var body: String
    var inReplyTo: String?
    var references: String?
    var date = Date()
    var messageID: String

    init(fromName: String, fromAddress: String, to: [String], cc: [String] = [], subject: String, body: String,
         inReplyTo: String? = nil, references: String? = nil) {
        self.fromName = fromName
        self.fromAddress = fromAddress
        self.to = to
        self.cc = cc
        self.subject = subject
        self.body = body
        self.inReplyTo = inReplyTo
        self.references = references
        let domain = fromAddress.split(separator: "@").last.map(String.init) ?? "11am.local"
        messageID = "<\(UUID().uuidString.lowercased())@\(domain)>"
    }

    var recipients: [String] { to + cc }

    /// Plain-text mail, UTF-8, quoted-printable, CRLF line endings.
    func rfc5322() -> Data {
        var lines: [String] = []
        lines.append("Date: \(MailEncoding.rfc2822Date(date))")
        lines.append("From: \(MailEncoding.mailbox(name: fromName, address: fromAddress))")
        lines.append("To: \(to.joined(separator: ", "))")
        if !cc.isEmpty { lines.append("Cc: \(cc.joined(separator: ", "))") }
        lines.append("Subject: \(MailEncoding.header(subject))")
        lines.append("Message-ID: \(messageID)")
        if let inReplyTo, !inReplyTo.isEmpty { lines.append("In-Reply-To: \(inReplyTo)") }
        if let references, !references.isEmpty { lines.append("References: \(references)") }
        lines.append("MIME-Version: 1.0")
        lines.append("Content-Type: text/plain; charset=utf-8")
        lines.append("Content-Transfer-Encoding: quoted-printable")
        lines.append("X-Mailer: 11am")
        let text = lines.joined(separator: "\r\n") + "\r\n\r\n" + MailEncoding.quotedPrintable(body)
        return Data(text.utf8)
    }
}

enum MailEncoding {
    static func rfc2822Date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }

    static func mailbox(name: String, address: String) -> String {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return address }
        if clean.allSatisfy({ $0.isASCII && $0 != "\"" && $0 != "\\" }) { return "\"\(clean)\" <\(address)>" }
        return "\(header(clean)) <\(address)>"
    }

    /// RFC 2047 encoded words for anything that isn't plain ASCII, split so each stays short.
    static func header(_ text: String) -> String {
        guard !text.allSatisfy({ $0.isASCII }) else { return text }
        var words: [String] = []
        var chunk = ""
        for character in text {
            if (chunk + String(character)).utf8.count > 45 {
                words.append(chunk)
                chunk = ""
            }
            chunk.append(character)
        }
        if !chunk.isEmpty { words.append(chunk) }
        return words.map { "=?utf-8?B?\(Data($0.utf8).base64EncodedString())?=" }.joined(separator: "\r\n ")
    }

    /// Quoted-printable with soft breaks at 76 characters. A leading dot is encoded so SMTP never mistakes it for the end.
    static func quotedPrintable(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var output: [String] = []
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            var encoded = ""
            var length = 0
            let bytes = Array(line.utf8)
            for (index, byte) in bytes.enumerated() {
                let isLast = index == bytes.count - 1
                var piece: String
                if (byte == 46 && index == 0) || byte == 61 || byte > 126 || (byte < 32 && byte != 9) || ((byte == 32 || byte == 9) && isLast) {
                    piece = String(format: "=%02X", byte)
                } else {
                    piece = String(UnicodeScalar(byte))
                }
                if length + piece.count > 75 {
                    encoded += "=\r\n"
                    length = 0
                }
                encoded += piece
                length += piece.count
            }
            output.append(encoded)
        }
        return output.joined(separator: "\r\n")
    }
}

/// Sends one message: TLS or STARTTLS, AUTH PLAIN (or LOGIN), MAIL, RCPT, DATA.
enum SMTPClient {
    static func send(_ mail: OutgoingMail, host: String, port: Int, security: MailSecurity, username: String, password: String) async throws {
        let socket = MailSocket(host: host, port: port, security: security)
        defer { socket.close() }

        _ = try await expect(socket, 220)
        var capabilities = try await hello(socket)
        if security == .startTLS {
            guard capabilities.contains("STARTTLS") else { throw MailError("\(host) doesn't offer an encrypted connection on port \(port).") }
            try await socket.write("STARTTLS\r\n")
            _ = try await expect(socket, 220)
            socket.startTLS()
            capabilities = try await hello(socket)
        }

        if capabilities.contains(where: { $0.hasPrefix("AUTH") && $0.contains("PLAIN") }) || !capabilities.contains(where: { $0.hasPrefix("AUTH") }) {
            let token = Data("\u{0}\(username)\u{0}\(password)".utf8).base64EncodedString()
            try await socket.write("AUTH PLAIN \(token)\r\n")
            _ = try await expect(socket, 235, failure: "Sign-in to send failed")
        } else {
            try await socket.write("AUTH LOGIN\r\n")
            _ = try await expect(socket, 334)
            try await socket.write(Data(username.utf8).base64EncodedString() + "\r\n")
            _ = try await expect(socket, 334)
            try await socket.write(Data(password.utf8).base64EncodedString() + "\r\n")
            _ = try await expect(socket, 235, failure: "Sign-in to send failed")
        }

        try await socket.write("MAIL FROM:<\(mail.fromAddress)>\r\n")
        _ = try await expect(socket, 250)
        for recipient in mail.recipients {
            try await socket.write("RCPT TO:<\(bareAddress(recipient))>\r\n")
            _ = try await expect(socket, 250, also: 251, failure: "The server wouldn't accept \(recipient)")
        }
        try await socket.write("DATA\r\n")
        _ = try await expect(socket, 354)
        try await socket.write(dotStuffed(mail.rfc5322()))
        _ = try await expect(socket, 250, failure: "The server didn't accept the message")
        try? await socket.write("QUIT\r\n")
    }

    /// "Priya Shah <priya@northwind.vc>" → "priya@northwind.vc".
    static func bareAddress(_ text: String) -> String {
        if let open = text.lastIndex(of: "<"), let close = text.lastIndex(of: ">"), open < close {
            return String(text[text.index(after: open)..<close])
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func hello(_ socket: MailSocket) async throws -> [String] {
        try await socket.write("EHLO 11am.local\r\n")
        return try await expect(socket, 250).map { $0.uppercased() }
    }

    /// Reads a reply (one or more "250-" lines ending with "250 ") and checks its code.
    @discardableResult
    private static func expect(_ socket: MailSocket, _ code: Int, also other: Int? = nil, failure: String? = nil) async throws -> [String] {
        var lines: [String] = []
        while true {
            let line = try await socket.readLineString()
            let text = line.count > 4 ? String(line.dropFirst(4)) : ""
            lines.append(text)
            guard line.count >= 3, let received = Int(line.prefix(3)) else { throw MailError("The mail server sent something unexpected.") }
            if line.count > 3, line[line.index(line.startIndex, offsetBy: 3)] == "-" { continue }
            guard received == code || received == other else {
                throw MailError("\(failure ?? "Sending failed"): \(line)")
            }
            return lines
        }
    }

    private static func dotStuffed(_ message: Data) -> Data {
        var text = String(decoding: message, as: UTF8.self)
        text = text.replacingOccurrences(of: "\r\n.", with: "\r\n..")
        if text.hasPrefix(".") { text = "." + text }
        return Data((text + "\r\n.\r\n").utf8)
    }
}
