import CryptoKit
import Foundation
import Network

// The link between your iPhone and your Mac: found on your own network (Bonjour), paired once with a QR code,
// and every message sealed with the key from that code (ChaChaPoly). No server and no account in between.

/// What the Mac's QR code holds. The key never travels any other way.
struct LinkPairing: Codable, Hashable, Sendable {
    var id: UUID
    var macName: String
    /// The Bonjour name the Mac advertises.
    var service: String
    /// Addresses to try when Bonjour can't find the Mac.
    var hosts: [String] = []
    var port: UInt16?
    /// 32 random bytes.
    var key: Data

    static let serviceType = "_11am._tcp"

    static func make(macName: String) -> LinkPairing {
        LinkPairing(id: UUID(), macName: macName, service: "11am on \(macName)", key: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
    }

    var symmetricKey: SymmetricKey { SymmetricKey(data: key) }

    /// elevenam://pair?d=…, for the QR code.
    var url: URL? {
        guard let json = try? JSONEncoder().encode(self) else { return nil }
        var components = URLComponents()
        components.scheme = "elevenam"
        components.host = "pair"
        components.queryItems = [URLQueryItem(name: "d", value: Self.base64URL(json))]
        return components.url
    }

    init(id: UUID, macName: String, service: String, hosts: [String] = [], port: UInt16? = nil, key: Data) {
        self.id = id
        self.macName = macName
        self.service = service
        self.hosts = hosts
        self.port = port
        self.key = key
    }

    init?(url: URL) {
        guard url.scheme == "elevenam", url.host == "pair",
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "d" })?.value,
              let json = Self.data(base64URL: value),
              let pairing = try? JSONDecoder().decode(LinkPairing.self, from: json),
              pairing.key.count == 32 else { return nil }
        self = pairing
    }

    init?(text: String) {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        self.init(url: url)
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func data(base64URL text: String) -> Data? {
        var base = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base.count % 4 != 0 { base += "=" }
        return Data(base64Encoded: base)
    }
}

struct LinkAttachment: Codable, Hashable, Sendable {
    var name: String
    /// A file extension: pdf, jpeg, m4a, txt.
    var kind: String
    var data: Data
}

/// Something captured on the iPhone for the Mac.
struct LinkCapture: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case scan, photo, voice, note, link

        var title: String {
            switch self {
            case .scan: return "Scan"
            case .photo: return "Photo"
            case .voice: return "Voice note"
            case .note: return "Note"
            case .link: return "Link"
            }
        }
    }

    enum Destination: String, Codable, CaseIterable, Sendable {
        case notes, pdf, receipt

        var title: String {
            switch self {
            case .notes: return "Notes"
            case .pdf: return "PDF"
            case .receipt: return "Receipts"
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var destination: Destination = .notes
    var title: String
    /// Recognised or typed text.
    var text: String
    var created = Date()
    var attachments: [LinkAttachment] = []
}

struct LinkEvent: Codable, Hashable, Sendable {
    var title: String
    var start: Date
    var end: Date
    var location: String?
    var isAllDay = false
}

/// Today from the Mac: Leo's brief and the day's events.
struct LinkBrief: Codable, Hashable, Sendable {
    var macName: String
    var written: Date?
    var text: String
    var events: [LinkEvent]
}

enum LinkMessage: Codable, Hashable, Sendable {
    /// The phone's first words: who it is and which pairing it used.
    case hello(device: String, pairing: UUID)
    case welcome(macName: String)
    case energy([DayEnergy])
    case capture(LinkCapture)
    /// The Mac saved a capture.
    case received(UUID, where: String)
    case brief(LinkBrief)
    case ask(id: UUID, question: String)
    case answer(id: UUID, text: String, done: Bool)
    case ping
    case pong
}

enum LinkError: LocalizedError {
    case tooLarge, notPaired, closed

    var errorDescription: String? {
        switch self {
        case .tooLarge: return "That's too big to send in one go."
        case .notPaired: return "This iPhone isn't paired with that Mac. Scan the code in 11am on the Mac again."
        case .closed: return "The connection closed."
        }
    }
}

/// Sealing and framing: each message is JSON, sealed with ChaChaPoly, and sent with a 4-byte length in front.
enum LinkWire {
    static let maximumFrame = 96 * 1_024 * 1_024

    static func seal(_ message: LinkMessage, key: SymmetricKey) throws -> Data {
        let json = try JSONEncoder().encode(message)
        let sealed = try ChaChaPoly.seal(json, using: key).combined
        guard sealed.count <= maximumFrame else { throw LinkError.tooLarge }
        var length = UInt32(sealed.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(sealed)
        return frame
    }

    static func open(_ sealed: Data, key: SymmetricKey) throws -> LinkMessage {
        let box = try ChaChaPoly.SealedBox(combined: sealed)
        let json = try ChaChaPoly.open(box, using: key)
        return try JSONDecoder().decode(LinkMessage.self, from: json)
    }

    /// Collects bytes as they arrive and hands back whole frames.
    struct Reader {
        private var buffer = Data()

        mutating func append(_ data: Data) { buffer.append(data) }

        /// The next whole frame, nil if more bytes are needed. Throws if a frame claims to be too large.
        mutating func next() throws -> Data? {
            guard buffer.count >= 4 else { return nil }
            let start = buffer.startIndex
            let length = buffer[start..<start + 4].reduce(0) { ($0 << 8) | Int($1) }
            guard length <= maximumFrame else { throw LinkError.tooLarge }
            guard buffer.count >= 4 + length else { return nil }
            let frame = buffer.subdata(in: (start + 4)..<(start + 4 + length))
            buffer.removeSubrange(start..<(start + 4 + length))
            return frame
        }
    }
}

/// One connection, either end. Callbacks arrive on the main queue.
final class LinkChannel: @unchecked Sendable {
    enum State: Equatable { case connecting, ready, closed(String?) }

    let connection: NWConnection
    private let key: SymmetricKey
    private var reader = LinkWire.Reader()
    private let queue = DispatchQueue(label: "11am.link")
    private(set) var state = State.connecting
    var onMessage: ((LinkMessage) -> Void)?
    var onState: ((State) -> Void)?
    /// A started channel keeps itself alive until it closes, so a dropped reference can't lose messages.
    private var keepAlive: LinkChannel?

    init(connection: NWConnection, key: SymmetricKey) {
        self.connection = connection
        self.key = key
    }

    var endpointDescription: String { "\(connection.endpoint)" }

    func start() {
        keepAlive = self
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.update(.ready)
                self.receive()
            case .failed(let error):
                self.update(.closed(error.localizedDescription))
            case .cancelled:
                self.update(.closed(nil))
            case .waiting(let error):
                self.update(.closed(error.localizedDescription))
                self.connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func update(_ state: State) {
        DispatchQueue.main.async {
            guard self.state != state else { return }
            if case .closed = self.state { return }
            self.state = state
            self.onState?(state)
            if case .closed = state { self.keepAlive = nil }
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.reader.append(data)
                do {
                    while let frame = try self.reader.next() {
                        let message = try LinkWire.open(frame, key: self.key)
                        DispatchQueue.main.async { self.onMessage?(message) }
                    }
                } catch {
                    // A wrong key or a garbled frame: this isn't our iPhone or Mac.
                    self.update(.closed(LinkError.notPaired.localizedDescription))
                    self.connection.cancel()
                    return
                }
            }
            if complete || error != nil {
                self.update(.closed(error?.localizedDescription))
                self.connection.cancel()
                return
            }
            self.receive()
        }
    }

    func send(_ message: LinkMessage, completion: ((Error?) -> Void)? = nil) {
        do {
            let frame = try LinkWire.seal(message, key: key)
            connection.send(content: frame, completion: .contentProcessed { error in
                DispatchQueue.main.async { completion?(error) }
            })
        } catch {
            DispatchQueue.main.async { completion?(error) }
        }
    }

    func close() {
        connection.cancel()
    }
}

/// The Mac's side: advertises itself on the local network and accepts paired iPhones.
final class LinkServer: @unchecked Sendable {
    private var listener: NWListener?
    private let key: SymmetricKey
    private(set) var port: UInt16?
    var onReady: ((UInt16) -> Void)?
    var onFailure: ((String) -> Void)?
    var onChannel: ((LinkChannel) -> Void)?

    init(key: SymmetricKey) {
        self.key = key
    }

    func start(name: String?, port: UInt16 = 0) throws {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let listener = try NWListener(using: parameters, on: port == 0 ? .any : NWEndpoint.Port(rawValue: port) ?? .any)
        if let name { listener.service = NWListener.Service(name: name, type: LinkPairing.serviceType) }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self else { return }
            switch state {
            case .ready:
                let port = listener?.port?.rawValue ?? 0
                DispatchQueue.main.async {
                    self.port = port
                    self.onReady?(port)
                }
            case .failed(let error):
                DispatchQueue.main.async { self.onFailure?(error.localizedDescription) }
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            let channel = LinkChannel(connection: connection, key: self.key)
            DispatchQueue.main.async {
                self.onChannel?(channel)
                channel.start()
            }
        }
        listener.start(queue: DispatchQueue(label: "11am.link.listener"))
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}

/// The iPhone's side: finds the paired Mac by its Bonjour name, or tries its last known addresses.
final class LinkClient: @unchecked Sendable {
    private var browser: NWBrowser?
    private let pairing: LinkPairing
    private var found = false
    var onChannel: ((LinkChannel) -> Void)?
    var onFailure: ((String) -> Void)?

    init(pairing: LinkPairing) {
        self.pairing = pairing
    }

    func connect(timeout: TimeInterval = 6) {
        found = false
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: LinkPairing.serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, !self.found else { return }
            for result in results {
                if case .service(let name, _, _, _) = result.endpoint, name == self.pairing.service {
                    self.found = true
                    self.browser?.cancel()
                    self.open(NWConnection(to: result.endpoint, using: parameters))
                    return
                }
            }
        }
        browser.start(queue: DispatchQueue(label: "11am.link.browser"))
        self.browser = browser
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, !self.found else { return }
            self.browser?.cancel()
            self.tryAddresses()
        }
    }

    /// Straight to an address, for when Bonjour isn't available (and for tests).
    func connect(host: String, port: UInt16) {
        found = true
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return }
        open(NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp))
    }

    private func tryAddresses() {
        guard let port = pairing.port, let host = pairing.hosts.first else {
            DispatchQueue.main.async { self.onFailure?("Couldn't find \(self.pairing.macName) on this network. Is 11am open on the Mac, and are both on the same Wi-Fi?") }
            return
        }
        connect(host: host, port: port)
    }

    private func open(_ connection: NWConnection) {
        let channel = LinkChannel(connection: connection, key: pairing.symmetricKey)
        DispatchQueue.main.async {
            self.onChannel?(channel)
            channel.start()
        }
    }

    func cancel() {
        browser?.cancel()
    }
}
