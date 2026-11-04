import Foundation
import Security
import SwiftUI
import UIKit

/// Something captured, waiting to go to the Mac or already there.
struct OutboxItem: Codable, Identifiable, Hashable {
    enum Status: Codable, Hashable {
        case waiting
        case sent(String)
    }

    var capture: LinkCapture
    var status: Status = .waiting

    var id: UUID { capture.id }
}

struct AskExchange: Identifiable, Hashable {
    let id: UUID
    let question: String
    var answer: String
    var done: Bool
}

enum LinkStatus: Equatable {
    case unpaired
    case searching
    case connected(String)
    case unreachable(String)

    var isConnected: Bool { if case .connected = self { return true } else { return false } }
}

/// The iPhone app's state: Health, what you've captured, and the link to your Mac.
@MainActor
final class PhoneModel: ObservableObject {
    @Published private(set) var energy: [DayEnergy] = []
    @Published private(set) var healthState: HealthReader.State = .unknown
    @Published private(set) var usingSample = false
    @Published private(set) var outbox: [OutboxItem] = []
    @Published private(set) var brief: LinkBrief?
    @Published private(set) var link: LinkStatus = .unpaired
    @Published private(set) var pairing: LinkPairing?
    @Published private(set) var exchanges: [AskExchange] = []
    @Published var notice: String?
    @Published var tab: PhoneTab = .today

    private let health = HealthReader()
    private var client: LinkClient?
    private var channel: LinkChannel?
    private var sentEnergyDays: [DayEnergy] = []

    init() {
        pairing = PhoneKeychain.loadPairing()
        outbox = PhoneStore.load([OutboxItem].self, "outbox") ?? []
        brief = PhoneStore.load(LinkBrief.self, "brief")
        energy = PhoneStore.load([DayEnergy].self, "energy") ?? []
        if pairing != nil { link = .searching }
        healthState = health.state
    }

    // MARK: Energy

    var reading: (today: DayEnergy?, yesterday: DayEnergy?, baseline: EnergyBaseline) { EnergyInsight.latest(energy) }

    func refreshHealth() async {
        guard !usingSample else { return }
        healthState = health.state
        guard healthState == .allowed else { return }
        let days = await health.days(35)
        guard !days.isEmpty else { return }
        energy = days
        PhoneStore.save(days, "energy")
        sendEnergyIfChanged()
    }

    func connectHealth() async {
        do {
            try await health.requestAccess()
            healthState = health.state
            await refreshHealth()
            if energy.isEmpty { notice = "Health didn't share anything yet. Check Settings › Health › Data Access › 11am." }
        } catch {
            notice = error.localizedDescription
        }
    }

    func useSample(_ on: Bool) {
        usingSample = on
        if on {
            energy = EnergySample.days(35)
        } else {
            energy = PhoneStore.load([DayEnergy].self, "energy") ?? []
            Task { await refreshHealth() }
        }
    }

    // MARK: Capture

    func add(_ capture: LinkCapture) {
        outbox.insert(OutboxItem(capture: capture), at: 0)
        saveOutbox()
        if let channel, link.isConnected {
            channel.send(.capture(capture))
            notice = "Sending to \(pairing?.macName ?? "your Mac")…"
        } else {
            notice = pairing == nil ? "Saved here. Pair with your Mac to send it." : "Saved here. It goes to your Mac next time they're on the same Wi-Fi."
        }
    }

    func remove(_ item: OutboxItem) {
        outbox.removeAll { $0.id == item.id }
        saveOutbox()
    }

    private func saveOutbox() {
        // Keep the last 60; sent items lose their attachments, which are safely on the Mac.
        var trimmed = Array(outbox.prefix(60))
        for index in trimmed.indices where trimmed[index].status != .waiting { trimmed[index].capture.attachments = [] }
        PhoneStore.save(trimmed, "outbox")
    }

    // MARK: Ask

    func ask(_ question: String) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        guard let channel, link.isConnected else {
            notice = "Ask goes to your Mac, which isn't connected right now."
            return
        }
        let id = UUID()
        exchanges.insert(AskExchange(id: id, question: question, answer: "", done: false), at: 0)
        channel.send(.ask(id: id, question: question))
    }

    // MARK: Pairing and the link

    func pair(with text: String) -> Bool {
        guard let pairing = LinkPairing(text: text) else {
            notice = "That isn't a pairing code from 11am on the Mac."
            return false
        }
        PhoneKeychain.savePairing(pairing)
        self.pairing = pairing
        disconnect()
        connect()
        return true
    }

    func unpair() {
        disconnect()
        PhoneKeychain.deletePairing()
        pairing = nil
        link = .unpaired
        brief = nil
        PhoneStore.delete("brief")
    }

    func connect() {
        guard let pairing, channel == nil else { return }
        link = .searching
        let client = LinkClient(pairing: pairing)
        client.onChannel = { [weak self] channel in self?.attach(channel) }
        client.onFailure = { [weak self] message in
            self?.link = .unreachable(message)
            self?.client = nil
        }
        self.client = client
        client.connect()
    }

    func disconnect() {
        client?.cancel()
        client = nil
        channel?.close()
        channel = nil
        if pairing != nil { link = .unreachable("Not connected.") }
    }

    private func attach(_ channel: LinkChannel) {
        self.channel = channel
        channel.onState = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                channel.send(.hello(device: UIDevice.current.name, pairing: self.pairing?.id ?? UUID()))
            case .closed(let reason):
                self.channel = nil
                self.client = nil
                self.link = .unreachable(reason ?? "Disconnected.")
            case .connecting:
                break
            }
        }
        channel.onMessage = { [weak self] message in self?.handle(message) }
    }

    private func handle(_ message: LinkMessage) {
        switch message {
        case .welcome(let macName):
            link = .connected(macName)
            sentEnergyDays = []
            sendEnergyIfChanged()
            for item in outbox where item.status == .waiting { channel?.send(.capture(item.capture)) }
        case .brief(let brief):
            self.brief = brief
            PhoneStore.save(brief, "brief")
        case .received(let id, let place):
            if let index = outbox.firstIndex(where: { $0.id == id }) {
                outbox[index].status = .sent(place)
                saveOutbox()
                notice = "On your Mac, in \(place)."
            }
        case .answer(let id, let text, let done):
            if let index = exchanges.firstIndex(where: { $0.id == id }) {
                exchanges[index].answer = text
                exchanges[index].done = done
            }
        case .ping:
            channel?.send(.pong)
        default:
            break
        }
    }

    /// Sends the last five weeks of Energy when they've changed since the last send.
    private func sendEnergyIfChanged() {
        guard let channel, link.isConnected, !usingSample, !energy.isEmpty, energy != sentEnergyDays else { return }
        channel.send(.energy(energy))
        sentEnergyDays = energy
    }

    func sendEnergyNow() {
        sentEnergyDays = []
        if usingSample {
            notice = "That's sample data, so it stays here. Connect Apple Health to share your own."
            return
        }
        sendEnergyIfChanged()
        notice = link.isConnected ? "Energy sent to \(pairing?.macName ?? "your Mac")." : "Your Mac isn't connected right now."
    }

    // MARK: Sample

    /// For screenshots and trying the app out without Health or a Mac.
    func loadSample() {
        usingSample = true
        energy = EnergySample.days(35)
        let calendar = Calendar.current
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        }
        brief = LinkBrief(macName: "MacBook Air", written: at(6, 2), text: """
            Short night, so the Acme pricing review moves to 2pm and the morning stays clear for the board deck. \
            Tom needs the pilot numbers before go-live on Thursday. Two hours of focus from 10 if you keep the inbox closed.
            """, events: [
            LinkEvent(title: "Stand-up", start: at(9, 30), end: at(9, 45), location: "Zoom"),
            LinkEvent(title: "Board deck: focus", start: at(10), end: at(12)),
            LinkEvent(title: "Lunch with Sam", start: at(12, 30), end: at(13, 30), location: "Lune"),
            LinkEvent(title: "Acme pricing review", start: at(14), end: at(15), location: "Acme, Level 4"),
        ])
        pairing = LinkPairing.make(macName: "MacBook Air")
        link = .connected("MacBook Air")
        outbox = [
            OutboxItem(capture: LinkCapture(kind: .scan, destination: .receipt, title: "Receipt · Cafe Lune", text: "Cafe Lune\nFlat white 5.50\nTotal $14.50 incl. GST",
                                            created: at(8, 12)), status: .sent("Notes › Receipts")),
            OutboxItem(capture: LinkCapture(kind: .voice, title: "Voice note", text: "Ask Tom whether the pilot can start with two teams instead of five.",
                                            created: at(7, 48)), status: .sent("Notes")),
            OutboxItem(capture: LinkCapture(kind: .link, title: "Pricing pages that work", text: "https://example.com/pricing-pages",
                                            created: at(7, 20)), status: .waiting),
        ]
        exchanges = [AskExchange(id: UUID(), question: "What do I need for the Acme review?",
                                 answer: "The pilot numbers from Tom's sheet and last month's usage export. Both are in Files.", done: true)]
    }
}

enum PhoneTab: String, CaseIterable, Identifiable {
    case today, energy, capture, mac

    var id: String { rawValue }
}

/// Small JSON files in the app's own folder.
enum PhoneStore {
    static var folder: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("11am", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("\(name).json")) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, _ name: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: folder.appendingPathComponent("\(name).json"), options: [.atomic, .completeFileProtection])
    }

    static func delete(_ name: String) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(name).json"))
    }
}

/// The pairing key lives in the Keychain, on this device only.
enum PhoneKeychain {
    private static let service = "au.elevenam.phone"
    private static let account = "mac-pairing"

    static func savePairing(_ pairing: LinkPairing) {
        guard let data = try? JSONEncoder().encode(pairing) else { return }
        deletePairing()
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func loadPairing() -> LinkPairing? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(LinkPairing.self, from: data)
    }

    static func deletePairing() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
