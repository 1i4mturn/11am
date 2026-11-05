import Foundation

// Conner's contacts: one person and one organisation everywhere, found from the mail you actually exchange,
// with what's happened (emails, meetings, notes) gathered for each deal, a forecast by month, and the deals going quiet.
// Foundation only, so it's tested on its own.

struct CRMPerson: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    /// Lower case.
    var email: String
    var title = ""
    var phone = ""
    var organisationID: UUID?
    var notes = ""
    var created = Date()

    init(id: UUID = UUID(), name: String, email: String, title: String = "", phone: String = "", organisationID: UUID? = nil, notes: String = "", created: Date = Date()) {
        self.id = id
        self.name = name
        self.email = email.lowercased()
        self.title = title
        self.phone = phone
        self.organisationID = organisationID
        self.notes = notes
        self.created = created
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        email = (try c.decodeIfPresent(String.self, forKey: .email) ?? "").lowercased()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        organisationID = try c.decodeIfPresent(UUID.self, forKey: .organisationID)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
    }

    private enum CodingKeys: String, CodingKey { case id, name, email, title, phone, organisationID, notes, created }
}

struct CRMOrganisation: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    /// "acme.co", lower case.
    var domain: String?
    var notes = ""
    var created = Date()

    init(id: UUID = UUID(), name: String, domain: String? = nil, notes: String = "", created: Date = Date()) {
        self.id = id
        self.name = name
        self.domain = domain?.lowercased()
        self.notes = notes
        self.created = created
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        domain = try c.decodeIfPresent(String.self, forKey: .domain)?.lowercased()
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
    }

    private enum CodingKeys: String, CodingKey { case id, name, domain, notes, created }
}

/// Something that happened with a person or company.
struct CRMActivity: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case received, sent, meeting, note, logged

        var symbol: String {
            switch self {
            case .received: return "envelope"
            case .sent: return "paperplane"
            case .meeting: return "person.2"
            case .note: return "note.text"
            case .logged: return "text.bubble"
            }
        }
    }

    /// Stable, so the same email isn't counted twice: "mail:<id>", "event:<id>".
    var id: String
    var kind: Kind
    var date: Date
    var title: String
    var detail = ""
    /// Addresses involved, lower case.
    var people: [String] = []
}

/// One email, without the mail app's types.
struct CRMMail: Sendable {
    var id: String
    var from: String
    var fromName: String
    var to: [String]
    var subject: String
    var snippet: String
    var date: Date
    var outgoing: Bool
}

/// One calendar event, without the calendar's types.
struct CRMMeeting: Sendable {
    var id: String
    var title: String
    var start: Date
    var attendees: [(name: String, email: String)]
}

enum CRMMatch {
    /// Free mail providers: an address there says nothing about a company.
    static let personalDomains: Set<String> = [
        "gmail.com", "googlemail.com", "outlook.com", "hotmail.com", "live.com", "msn.com", "icloud.com", "me.com", "mac.com",
        "yahoo.com", "yahoo.com.au", "ymail.com", "aol.com", "proton.me", "protonmail.com", "fastmail.com", "fastmail.fm",
        "bigpond.com", "bigpond.net.au", "optusnet.com.au", "tpg.com.au", "iinet.net.au", "gmx.com", "hey.com", "zoho.com",
    ]

    /// "Tom Baker <TOM@acme.co>" → "tom@acme.co".
    static func address(_ text: String) -> String {
        var value = text
        if let open = value.firstIndex(of: "<"), let close = value.lastIndex(of: ">"), open < close {
            value = String(value[value.index(after: open)..<close])
        }
        return value.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'"))).lowercased()
    }

    /// "Tom Baker <tom@acme.co>" → "Tom Baker"; just an address → a name made from it.
    static func displayName(_ text: String) -> String {
        if let open = text.firstIndex(of: "<") {
            let name = text[..<open].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'")))
            if !name.isEmpty { return name }
        }
        let local = Self.address(text).split(separator: "@").first.map(String.init) ?? text
        return local.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// The company domain of an address, or nil for gmail.com and the like.
    static func domain(of email: String) -> String? {
        let normalized = Self.address(email)
        guard let at = normalized.lastIndex(of: "@") else { return nil }
        let domain = String(normalized[normalized.index(after: at)...])
        guard domain.contains("."), !personalDomains.contains(domain) else { return nil }
        return domain
    }

    /// "acme.co" → "Acme"; "mail.harbourhealth.org" → "Harbourhealth".
    static func organisationName(fromDomain domain: String) -> String {
        let labels = domain.lowercased().split(separator: ".").map(String.init)
        let skip: Set<String> = ["mail", "email", "www", "m", "corp", "team"]
        let suffixes: Set<String> = ["com", "co", "org", "net", "io", "au", "uk", "nz", "app", "ai", "dev", "gov", "edu", "studio", "vc", "coffee", "agency", "design", "health"]
        let meaningful = labels.filter { !skip.contains($0) }
        // The label before the public suffix.
        var index = meaningful.count - 1
        while index > 0 && suffixes.contains(meaningful[index]) { index -= 1 }
        let name = meaningful.isEmpty ? domain : meaningful[max(0, index)]
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Whether an address belongs to an organisation or one of its people.
    static func belongs(_ email: String, to organisation: CRMOrganisation, people: [CRMPerson]) -> Bool {
        let normalized = Self.address(email)
        if let domain = organisation.domain, normalized.hasSuffix("@" + domain) || normalized.hasSuffix("." + domain) { return true }
        return people.contains { $0.organisationID == organisation.id && $0.email == normalized }
    }
}

enum CRMDirectory {
    struct Result: Equatable {
        var people: [CRMPerson]
        var organisations: [CRMOrganisation]
        var added: Int
    }

    /// People you've actually exchanged mail with (you wrote to them at least once), and their companies.
    /// Existing people and organisations are kept as they are; only new ones are added.
    static func update(people: [CRMPerson], organisations: [CRMOrganisation], mail: [CRMMail], wroteTo: [String: Int], me: Set<String>) -> Result {
        var people = people
        var organisations = organisations
        var added = 0
        var known = Set(people.map(\.email))
        let mine = Set(me.map { $0.lowercased() })
        let wrote = Dictionary(wroteTo.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: +)

        // Who's in the mail, with the best name seen for each.
        var names: [String: String] = [:]
        var outgoing: [String: Int] = wrote
        for message in mail {
            let from = CRMMatch.address(message.from)
            if !message.fromName.isEmpty, !message.fromName.contains("@") { names[from] = message.fromName }
            if message.outgoing {
                for recipient in message.to { outgoing[CRMMatch.address(recipient), default: 0] += 1 }
            }
            for recipient in message.to where names[CRMMatch.address(recipient)] == nil {
                let name = CRMMatch.displayName(recipient)
                if recipient.contains("<") { names[CRMMatch.address(recipient)] = name }
            }
        }
        for (address, count) in outgoing.sorted(by: { $0.key < $1.key }) where count > 0 && !mine.contains(address) && !known.contains(address) {
            guard address.contains("@"), !address.hasPrefix("noreply"), !address.hasPrefix("no-reply") else { continue }
            var organisationID: UUID?
            if let domain = CRMMatch.domain(of: address) {
                if let existing = organisations.first(where: { $0.domain == domain }) {
                    organisationID = existing.id
                } else {
                    let organisation = CRMOrganisation(name: CRMMatch.organisationName(fromDomain: domain), domain: domain)
                    organisations.append(organisation)
                    organisationID = organisation.id
                }
            }
            people.append(CRMPerson(name: names[address] ?? CRMMatch.displayName(address), email: address, organisationID: organisationID))
            known.insert(address)
            added += 1
        }
        return Result(people: people, organisations: organisations, added: added)
    }
}

enum CRMTimeline {
    /// Everything that's happened with these addresses or this domain, newest first.
    static func activities(addresses: Set<String>, domain: String?, mail: [CRMMail], meetings: [CRMMeeting], logged: [CRMActivity] = []) -> [CRMActivity] {
        let wanted = Set(addresses.map { $0.lowercased() })
        func matches(_ email: String) -> Bool {
            let address = CRMMatch.address(email)
            if wanted.contains(address) { return true }
            if let domain, address.hasSuffix("@" + domain) { return true }
            return false
        }
        var result: [CRMActivity] = logged
        for message in mail {
            let involved = ([message.from] + message.to).filter(matches).map(CRMMatch.address)
            guard !involved.isEmpty else { continue }
            result.append(CRMActivity(id: "mail:\(message.id)", kind: message.outgoing ? .sent : .received, date: message.date,
                                      title: message.subject.isEmpty ? "(no subject)" : message.subject,
                                      detail: String(message.snippet.prefix(160)), people: involved))
        }
        for meeting in meetings {
            let involved = meeting.attendees.map { $0.email }.filter(matches).map(CRMMatch.address)
            guard !involved.isEmpty else { continue }
            result.append(CRMActivity(id: "event:\(meeting.id)", kind: .meeting, date: meeting.start, title: meeting.title, people: involved))
        }
        var seen = Set<String>()
        return result.sorted { $0.date > $1.date }.filter { seen.insert($0.id).inserted }
    }

    /// The last time anything happened, if anything has.
    static func lastTouch(_ activities: [CRMActivity], now: Date) -> Date? {
        activities.map(\.date).filter { $0 <= now }.max()
    }
}

enum CRMForecast {
    struct Month: Equatable {
        var month: Date
        var total: Double
        var weighted: Double
        var count: Int
    }

    /// Open deals with a close date, by the month they're expected to close. Overdue ones count in this month.
    static func byMonth(_ deals: [(value: Double, likelihood: Double, close: Date?)], now: Date, calendar: Calendar) -> [Month] {
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        var months: [Date: Month] = [:]
        for deal in deals {
            guard let close = deal.close else { continue }
            var month = calendar.date(from: calendar.dateComponents([.year, .month], from: close)) ?? close
            if month < thisMonth { month = thisMonth }
            var entry = months[month] ?? Month(month: month, total: 0, weighted: 0, count: 0)
            entry.total += deal.value
            entry.weighted += deal.value * deal.likelihood
            entry.count += 1
            months[month] = entry
        }
        return months.values.sorted { $0.month < $1.month }
    }
}

enum CRMNudge {
    /// How long since anything happened, in whole days.
    static func daysQuiet(lastTouch: Date, now: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: lastTouch), to: calendar.startOfDay(for: now)).day ?? 0
    }

    /// Open deals worth a nudge: quiet for longer than their stage allows (a proposal goes cold faster than a lead).
    static func isQuiet(stage: String, lastTouch: Date, now: Date, calendar: Calendar) -> Bool {
        let allowed: Int
        switch stage {
        case "proposal": allowed = 5
        case "talking": allowed = 7
        case "lead": allowed = 14
        default: return false
        }
        return daysQuiet(lastTouch: lastTouch, now: now, calendar: calendar) > allowed
    }

    /// "Quiet for 11 days" / "Last touch yesterday".
    static func text(lastTouch: Date, now: Date, calendar: Calendar) -> String {
        let days = daysQuiet(lastTouch: lastTouch, now: now, calendar: calendar)
        switch days {
        case ..<1: return "Touched today"
        case 1: return "Last touch yesterday"
        default: return "Quiet for \(days) days"
        }
    }
}

enum CRMProposal {
    /// Fills the proposal template's blanks from a deal, leaving the rest for William and you.
    static func fill(_ template: String, project: String, client: String, contact: String, organisation: String, value: Double, currency: (Double) -> String) -> String {
        template
            .replacingOccurrences(of: "[project]", with: project)
            .replacingOccurrences(of: "[client]", with: client)
            .replacingOccurrences(of: "[name]", with: contact)
            .replacingOccurrences(of: "[organisation]", with: organisation)
            .replacingOccurrences(of: "| [Item] | $[0] |", with: "| \(project) | \(currency(value)) |")
            .replacingOccurrences(of: "**$[0]**", with: "**\(currency(value))**")
    }
}
