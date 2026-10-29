import Foundation

struct MailError: LocalizedError, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }

    static let closed = MailError("The mail server closed the connection.")
}

/// A line-based connection for IMAP and SMTP over TLS, using the system's certificate checks.
/// Implicit TLS (IMAP 993, SMTP 465) or plain-then-STARTTLS (SMTP 587).
final class MailSocket: @unchecked Sendable {
    private let session: URLSession
    private let task: URLSessionStreamTask
    private var buffer = Data()
    private static let crlf = Data([13, 10])

    init(host: String, port: Int, security: MailSecurity) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        session = URLSession(configuration: configuration)
        task = session.streamTask(withHostName: host, port: port)
        task.resume()
        if security == .tls { task.startSecureConnection() }
    }

    /// For STARTTLS: everything after this is encrypted.
    func startTLS() {
        buffer.removeAll()
        task.startSecureConnection()
    }

    func write(_ text: String) async throws {
        try await write(Data(text.utf8))
    }

    func write(_ data: Data) async throws {
        try await task.write(data, timeout: 45)
    }

    /// The next line, without its CRLF.
    func readLine() async throws -> Data {
        while true {
            if let range = buffer.range(of: MailSocket.crlf) {
                let line = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                return line
            }
            try await fill()
        }
    }

    func readLineString() async throws -> String {
        String(decoding: try await readLine(), as: UTF8.self)
    }

    /// Exactly `count` bytes, for IMAP literals.
    func read(count: Int) async throws -> Data {
        while buffer.count < count { try await fill() }
        let chunk = buffer.subdata(in: buffer.startIndex..<(buffer.startIndex + count))
        buffer.removeSubrange(buffer.startIndex..<(buffer.startIndex + count))
        return chunk
    }

    private func fill() async throws {
        let (data, atEOF) = try await task.readData(ofMinLength: 1, maxLength: 262_144, timeout: 90)
        if let data, !data.isEmpty {
            buffer.append(data)
        } else if atEOF {
            throw MailError.closed
        }
    }

    func close() {
        task.cancel()
        session.invalidateAndCancel()
    }
}
