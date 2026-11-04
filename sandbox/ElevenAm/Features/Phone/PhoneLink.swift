import AppKit
import CoreImage.CIFilterBuiltins
import Foundation

/// 11am on this Mac, talking to the 11am iPhone app: pairing, Energy from Health, captures, the brief and Ask.
@MainActor
final class PhoneLinkModel: ObservableObject {
    struct Phone: Identifiable, Equatable {
        let id: ObjectIdentifier
        var name: String
        var since: Date
    }

    @Published private(set) var pairing: LinkPairing?
    @Published private(set) var listening = false
    @Published private(set) var phones: [Phone] = []
    @Published private(set) var energy: [DayEnergy]
    @Published private(set) var activity: [String] = []
    @Published private(set) var problem: String?
    @Published var showsPairing = false

    private let brain: Brain
    private let notes: NotesModel
    private let today: TodayModel
    private var server: LinkServer?
    private var channels: [ObjectIdentifier: LinkChannel] = [:]
    private var greeted: Set<ObjectIdentifier> = []
    /// A fixed port, so the address in the pairing code stays right; another is used if it's taken.
    static let preferredPort: UInt16 = 52_811
    private static let keychainAccount = "iphone-pairing"

    init(brain: Brain, notes: NotesModel, today: TodayModel) {
        self.brain = brain
        self.notes = notes
        self.today = today
        energy = JSONStore.load([DayEnergy].self, from: "energy") ?? []
        if let saved = Keychain.read(account: Self.keychainAccount), let data = saved.data(using: .utf8) {
            pairing = try? JSONDecoder().decode(LinkPairing.self, from: data)
        }
    }

    var macName: String { Host.current().localizedName ?? "Mac" }

    var isConnected: Bool { !phones.isEmpty }

    func start() {
        guard pairing != nil, server == nil else { return }
        listen(on: Self.preferredPort)
    }

    // MARK: Pairing

    /// Makes a new key and code. Any iPhone paired before has to scan again.
    func makePairing() {
        stop()
        var fresh = LinkPairing.make(macName: macName)
        fresh.hosts = Self.localAddresses()
        fresh.port = Self.preferredPort
        save(fresh)
        listen(on: Self.preferredPort)
    }

    func unpair() {
        stop()
        Keychain.delete(account: Self.keychainAccount)
        pairing = nil
        note("Unpaired. The iPhone can't connect until you pair again.")
    }

    private func save(_ pairing: LinkPairing) {
        self.pairing = pairing
        if let data = try? JSONEncoder().encode(pairing), let text = String(data: data, encoding: .utf8) {
            Keychain.save(text, account: Self.keychainAccount)
        }
    }

    /// The code the iPhone scans.
    var qrImage: NSImage? {
        guard let text = pairing?.url?.absoluteString else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    func copyPairingLink() {
        guard let text = pairing?.url?.absoluteString else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        note("Pairing link copied. On the iPhone, open 11am › Mac › Paste the pairing link.")
    }

    // MARK: Listening

    private func listen(on port: UInt16) {
        guard let pairing else { return }
        let server = LinkServer(key: pairing.symmetricKey)
        server.onReady = { [weak self] actual in
            guard let self else { return }
            self.listening = true
            self.problem = nil
            if var current = self.pairing, current.port != actual || current.hosts != Self.localAddresses() {
                current.port = actual
                current.hosts = Self.localAddresses()
                self.save(current)
            }
        }
        server.onFailure = { [weak self] message in
            guard let self else { return }
            self.listening = false
            if port != 0 {
                // The usual port is busy; take any free one.
                self.server?.stop()
                self.server = nil
                self.listen(on: 0)
            } else {
                self.problem = "Couldn't listen for the iPhone: \(message)"
            }
        }
        server.onChannel = { [weak self] channel in self?.accept(channel) }
        do {
            try server.start(name: pairing.service, port: port)
            self.server = server
        } catch {
            problem = "Couldn't listen for the iPhone: \(error.localizedDescription)"
        }
    }

    func stop() {
        server?.stop()
        server = nil
        channels.values.forEach { $0.close() }
        channels = [:]
        greeted = []
        phones = []
        listening = false
    }

    private func accept(_ channel: LinkChannel) {
        let id = ObjectIdentifier(channel)
        channels[id] = channel
        channel.onState = { [weak self] state in
            guard let self, case .closed = state else { return }
            self.channels[id] = nil
            self.greeted.remove(id)
            self.phones.removeAll { $0.id == id }
        }
        channel.onMessage = { [weak self] message in self?.handle(message, from: channel) }
    }

    private func handle(_ message: LinkMessage, from channel: LinkChannel) {
        let id = ObjectIdentifier(channel)
        if case .hello(let device, let pairingID) = message {
            guard pairingID == pairing?.id else {
                channel.close()
                return
            }
            greeted.insert(id)
            phones.removeAll { $0.id == id }
            phones.append(Phone(id: id, name: device, since: Date()))
            channel.send(.welcome(macName: macName))
            channel.send(.brief(brief()))
            note("\(device) connected.")
            return
        }
        // Nothing counts before the iPhone has said hello with the right pairing.
        guard greeted.contains(id) else { return }
        switch message {
        case .energy(let days):
            energy = Array(EnergyDay.merge(energy, days).suffix(120))
            JSONStore.save(energy, to: "energy")
            note("Energy from Health: \(days.count) days.")
        case .capture(let capture):
            let place = file(capture)
            channel.send(.received(capture.id, where: place))
            note("\(capture.kind.title) from the iPhone, saved in \(place).")
        case .ask(let askID, let question):
            answer(question, id: askID, on: channel)
        case .ping:
            channel.send(.pong)
        default:
            break
        }
    }

    private func note(_ line: String) {
        activity.insert("\(Date().formatted(date: .omitted, time: .shortened))  \(line)", at: 0)
        if activity.count > 30 { activity.removeLast(activity.count - 30) }
    }

    // MARK: Captures

    static var capturesFolder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("11am Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Saves the files beside your documents and makes a note that links to them. Returns where it went.
    private func file(_ capture: LinkCapture) -> String {
        var links: [String] = []
        for attachment in capture.attachments {
            let url = Self.uniqueURL(in: Self.capturesFolder, name: attachment.name)
            do {
                try attachment.data.write(to: url, options: .atomic)
                links.append("[\(url.lastPathComponent)](\(url.absoluteString))")
            } catch {
                links.append("\(attachment.name) couldn't be saved: \(error.localizedDescription)")
            }
        }
        let folder: String
        var tags = "#capture"
        switch capture.destination {
        case .receipt:
            folder = "Receipts"
            tags += " #receipt"
        case .pdf, .notes:
            folder = "Captures"
        }
        var body = "# \(capture.title)\n\n"
        if capture.kind == .link, let first = capture.text.split(separator: "\n").first {
            body += "<\(first)>\n\n" + capture.text.split(separator: "\n").dropFirst().joined(separator: "\n")
        } else if !capture.text.isEmpty {
            body += capture.text
        }
        if !links.isEmpty { body += "\n\n" + links.joined(separator: "\n") }
        body += "\n\n\(tags) · from the iPhone, \(capture.created.formatted(date: .abbreviated, time: .shortened))"
        _ = notes.newNote(text: body, folder: folder)
        if capture.destination == .pdf, capture.attachments.contains(where: { $0.kind == "pdf" }) {
            return "Notes › \(folder) and 11am Captures"
        }
        return "Notes › \(folder)"
    }

    private static func uniqueURL(in folder: URL, name: String) -> URL {
        let clean = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        var url = folder.appendingPathComponent(clean)
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(number)").appendingPathExtension(ext)
            number += 1
        }
        return url
    }

    // MARK: Brief and Ask

    func brief() -> LinkBrief {
        let events = today.shownEvents.map { event in
            LinkEvent(title: event.title, start: event.start, end: event.end, location: event.location, isAllDay: event.isAllDay)
        }
        let text = today.briefRun?.status == .done ? (today.briefRun?.text ?? "") : ""
        return LinkBrief(macName: macName, written: text.isEmpty ? nil : today.briefDate, text: text, events: events)
    }

    /// Sends the brief to every connected iPhone, after Leo writes it.
    func briefChanged() {
        let current = brief()
        for (id, channel) in channels where greeted.contains(id) { channel.send(.brief(current)) }
    }

    private func answer(_ question: String, id: UUID, on channel: LinkChannel) {
        note("Asked from the iPhone: \(question)")
        let run = brain.run(BrainRequest(
            system: "You are Leo, the chief of staff inside 11am, answering a question asked from the user's iPhone. Be brief: two or three sentences.",
            prompt: question + (energyFacts.map { "\n\n(Energy today: \($0))" } ?? ""),
            weight: .quick))
        Task {
            await run.finished()
            if case .failed(let message) = run.status {
                channel.send(.answer(id: id, text: "Your Mac couldn't answer: \(message)", done: true))
            } else {
                channel.send(.answer(id: id, text: run.text, done: true))
            }
        }
    }

    // MARK: Energy

    var latest: (today: DayEnergy?, yesterday: DayEnergy?, baseline: EnergyBaseline) { EnergyInsight.latest(energy) }

    /// For Leo's brief.
    var energyFacts: String? {
        let latest = self.latest
        guard latest.today != nil || latest.yesterday != nil else { return nil }
        return EnergyInsight.briefFacts(today: latest.today, yesterday: latest.yesterday, baseline: latest.baseline)
    }

    /// Sample days, to see Energy on the Mac before pairing (and for screenshots).
    func useSampleEnergy() {
        energy = EnergySample.days(35)
    }

    // MARK: Network

    /// This Mac's IPv4 addresses on Wi-Fi and Ethernet, for when Bonjour can't be used.
    static func localAddresses() -> [String] {
        var addresses: [String] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = entry.pointee
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en"), (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0, (interface.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                addresses.append(String(cString: host))
            }
        }
        return addresses
    }
}
