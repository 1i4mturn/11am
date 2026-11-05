import Foundation

// Marc's toolkit: snippets with fill-in fields, times to send later, and noticing what an email is
// (a receipt for Money, a meeting request for Leo, an agreement to sign). Foundation only, so it's tested on its own.

struct MailSnippet: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var body: String
}

enum Snippets {
    /// Filled in for you: the recipient's first name, your name, today's date and your free times from Calendar.
    static let automatic: Set<String> = ["first name", "my name", "today", "free times"]

    static let builtIns: [MailSnippet] = [
        MailSnippet(name: "Times that work", body: "Hi {{first name}},\n\nHere are some times that work for me:\n\n{{free times}}\n\nHappy to fit around you if none of those suit.\n\n{{my name}}"),
        MailSnippet(name: "Following up", body: "Hi {{first name}},\n\nJust following up on {{what}}. Is there anything you need from me to move it forward?\n\nThanks,\n{{my name}}"),
        MailSnippet(name: "Introduction", body: "Hi {{first name}},\n\nI'd like to introduce you to {{who}}, who {{why they should talk}}. I'll let you two take it from here.\n\n{{my name}}"),
        MailSnippet(name: "Invoice reminder", body: "Hi {{first name}},\n\nA quick reminder that invoice {{invoice number}} for {{amount}} was due on {{due date}}. Could you let me know when it'll be paid?\n\nThanks,\n{{my name}}"),
        MailSnippet(name: "Not right now", body: "Hi {{first name}},\n\nThanks for thinking of me. It's not something I can take on right now, but I'd be glad to hear from you again in a few months.\n\n{{my name}}"),
        MailSnippet(name: "Thank you", body: "Hi {{first name}},\n\nThank you for {{what}}. It made a real difference.\n\n{{my name}}"),
    ]

    /// The fields in a snippet, in order, once each: "{{invoice number}}" → "invoice number".
    static func fields(in body: String) -> [String] {
        var found: [String] = []
        var rest = Substring(body)
        while let open = rest.range(of: "{{"), let close = rest.range(of: "}}", range: open.upperBound..<rest.endIndex) {
            let name = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
            if !name.isEmpty, !found.contains(name) { found.append(name) }
            rest = rest[close.upperBound...]
        }
        return found
    }

    /// The fields you fill in yourself.
    static func blanks(in body: String) -> [String] {
        fields(in: body).filter { !automatic.contains($0) }
    }

    /// Puts the values in. Fields without a value are left for you to see.
    static func fill(_ body: String, values: [String: String]) -> String {
        var result = ""
        var rest = Substring(body)
        let lowered = Dictionary(values.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        while let open = rest.range(of: "{{"), let close = rest.range(of: "}}", range: open.upperBound..<rest.endIndex) {
            result += rest[rest.startIndex..<open.lowerBound]
            let name = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
            if let value = lowered[name], !value.isEmpty {
                result += value
            } else {
                result += rest[open.lowerBound..<close.upperBound]
            }
            rest = rest[close.upperBound...]
        }
        return result + rest
    }

    /// "Tom Baker <tom@acme.co>, rita@acme.co" → "Tom".
    static func firstName(fromRecipients to: String) -> String {
        guard let first = to.split(separator: ",").first.map({ $0.trimmingCharacters(in: .whitespaces) }), !first.isEmpty else { return "" }
        if let open = first.firstIndex(of: "<") {
            let name = first[..<open].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'")))
            if let word = name.split(separator: " ").first { return String(word) }
        }
        let local = first.split(separator: "@").first.map(String.init) ?? first
        let word = local.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" }).first.map(String.init) ?? local
        guard word.count > 1, word.allSatisfy(\.isLetter) else { return "" }
        return word.prefix(1).uppercased() + word.dropFirst().lowercased()
    }
}

enum SendLater {
    /// Sensible times to send: in an hour, this afternoon, tomorrow morning, Monday morning.
    static func options(now: Date, calendar: Calendar) -> [(title: String, date: Date)] {
        var options: [(String, Date)] = []
        let today = calendar.startOfDay(for: now)
        func at(_ hour: Int, on day: Date) -> Date { calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day }
        let hour = calendar.component(.hour, from: now)
        let nextHour = calendar.dateInterval(of: .hour, for: now.addingTimeInterval(3_600))?.start ?? now.addingTimeInterval(3_600)
        options.append(("In an hour", nextHour))
        if hour < 13 { options.append(("This afternoon", at(14, on: today))) }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let weekday = calendar.component(.weekday, from: tomorrow)
        if weekday != 7 && weekday != 1 { options.append(("Tomorrow morning", at(8, on: tomorrow))) }
        let ahead = (2 - calendar.component(.weekday, from: today) + 7) % 7
        let monday = calendar.date(byAdding: .day, value: ahead == 0 ? 7 : ahead, to: today) ?? today
        if !calendar.isDate(monday, inSameDayAs: tomorrow) || weekday == 7 || weekday == 1 {
            options.append(("Monday morning", at(8, on: monday)))
        }
        return options.map { (title: $0.0, date: $0.1) }
    }
}

enum MailRouter {
    enum Route: Equatable, Sendable {
        /// A receipt or invoice, with who it's from and the total if one was found.
        case receipt(vendor: String, total: Double?)
        /// They're asking to meet.
        case meeting
        /// An agreement or contract to read or sign.
        case agreement
    }

    private static let receiptWords = ["receipt", "tax invoice", "invoice", "order confirmation", "your order", "payment received",
                                       "payment confirmation", "thanks for your payment", "thank you for your payment", "subscription renewed"]
    private static let meetingWords = ["can we meet", "could we meet", "find a time", "are you free", "are you available", "catch up",
                                       "grab a coffee", "set up a call", "schedule a call", "book a time", "jump on a call", "hop on a call",
                                       "time to chat", "quick call", "meet next week", "meeting request", "what times work", "when suits"]
    private static let agreementWords = ["agreement", "contract", "please sign", "for signature", "docusign", "statement of work",
                                         "terms of engagement", "e-sign", "esign", "countersign", "signed copy"]

    /// What an email is, if it's one of the things Marc hands on.
    static func route(subject: String, body: String, fromName: String, fromAddress: String) -> Route? {
        let head = (subject + "\n" + String(body.prefix(1_500))).lowercased()
        if receiptWords.contains(where: { head.contains($0) }), let total = total(in: subject + "\n" + body) {
            return .receipt(vendor: vendor(fromSubject: subject) ?? vendor(name: fromName, address: fromAddress), total: total)
        }
        if meetingWords.contains(where: { head.contains($0) }) { return .meeting }
        if agreementWords.contains(where: { head.contains($0) }) { return .agreement }
        return nil
    }

    /// The total in a receipt: an amount on a line saying total, amount due or paid, else the largest amount.
    static func total(in text: String) -> Double? {
        var labelled: [Double] = []
        var all: [Double] = []
        for line in text.components(separatedBy: .newlines) {
            let amounts = self.amounts(in: line)
            all += amounts
            let lower = line.lowercased()
            if ["total", "amount due", "amount paid", "paid", "balance due", "charged"].contains(where: { lower.contains($0) }) {
                labelled += amounts
            }
        }
        return labelled.last ?? all.max()
    }

    /// "$1,234.56", "A$42", "AUD 12.00", "12.00 AUD".
    static func amounts(in line: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: #"(?:(?:A|AU|US|NZ)?\$|AUD\s?|USD\s?)\s?(\d{1,3}(?:,\d{3})*(?:\.\d{2})?|\d+(?:\.\d{2})?)|(\d{1,3}(?:,\d{3})*\.\d{2}|\d+\.\d{2})\s?(?:AUD|USD)"#,
                                              options: [.caseInsensitive]) else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            for group in [1, 2] {
                if let swift = Range(match.range(at: group), in: line) {
                    return Double(line[swift].replacingOccurrences(of: ",", with: ""))
                }
            }
            return nil
        }
    }

    /// "Your receipt from Vercel Inc." → "Vercel Inc.": payment services send receipts for others.
    static func vendor(fromSubject subject: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?:receipt|invoice|order|payment)\s+(?:from|to)\s+(.+?)(?:\s*[#:(\[|]|\s+-\s+|$)"#,
                                                   options: [.caseInsensitive]),
              let match = regex.firstMatch(in: subject, range: NSRange(subject.startIndex..., in: subject)),
              let range = Range(match.range(at: 1), in: subject) else { return nil }
        let name = subject[range].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".,")))
        return name.isEmpty ? nil : name
    }

    /// "Lumen Coffee" or, for "receipts@lumen.coffee" with no name, "Lumen".
    static func vendor(name: String, address: String) -> String {
        var cleaned = name
        for prefix in ["Receipts from ", "Receipt from ", "Invoice from ", "Billing at ", "Payments at "] where cleaned.hasPrefix(prefix) {
            cleaned = String(cleaned.dropFirst(prefix.count))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        let generic: Set<String> = ["no-reply", "noreply", "billing", "receipts", "accounts", "invoices", "support", ""]
        if !generic.contains(cleaned.lowercased()) { return cleaned }
        let domain = address.split(separator: "@").last.map(String.init) ?? address
        let label = domain.split(separator: ".").first.map(String.init) ?? domain
        return label.prefix(1).uppercased() + label.dropFirst()
    }
}
