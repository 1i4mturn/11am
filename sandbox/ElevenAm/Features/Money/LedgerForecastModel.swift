import AppKit
import Foundation
import UniformTypeIdentifiers

/// A report line George is explaining, with his words once he's written them.
struct ExplainRequest: Identifiable {
    let id = UUID()
    var explanation: LineExplanation
    var run: BrainRun?
}

/// The files from Xero for the move, picked one by one.
struct XeroFiles {
    var contacts: URL?
    var accounts: URL?
    var invoices: URL?
    var bills: URL?

    var isEmpty: Bool { contacts == nil && accounts == nil && invoices == nil && bills == nil }
}

extension LedgerModel {
    static let georgeSystem = """
    You are George, the finance agent inside 11am. Use only the figures given; never invent one. Explain plainly, \
    in two to four short sentences, what's behind the numbers and what to look at. Not financial advice. \
    If tax or GST is involved, end with: General information, not tax advice.
    """

    // MARK: The forecast

    var forecast: Forecast { book.forecast(from: today, months: forecastMonths, whatIfs: whatIfs) }
    var baseline: Forecast { book.forecast(from: today, months: forecastMonths) }
    var hasChanges: Bool { whatIfs.contains(where: \.on) }

    /// "Hire at 10k a month from March", typed as you'd say it.
    @discardableResult
    func tryWhatIf(_ sentence: String) -> Bool {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        guard let change = WhatIfParser.parse(text, today: today, contacts: book.contacts, calendar: book.calendar) else {
            notice = "George couldn't turn that into numbers. Try \u{201C}hire at $8k a month from March\u{201D}, \u{201C}lose Acme in May\u{201D} or \u{201C}a $3,000 laptop in February\u{201D}."
            return false
        }
        whatIfs.append(change)
        forecastRun = nil
        let result = forecast
        notice = result.runsOut.map { "With that, the cash runs out in \($0.formatted(.dateTime.month(.wide).year()))." }
            ?? "With that, the lowest point is \(LedgerMoney.text(result.lowest?.closing ?? result.opening)) in \((result.lowest?.start ?? today).formatted(.dateTime.month(.wide).year()))."
        return true
    }

    func toggle(_ change: WhatIf) {
        guard let index = whatIfs.firstIndex(where: { $0.id == change.id }) else { return }
        whatIfs[index].on.toggle()
        forecastRun = nil
    }

    func remove(_ change: WhatIf) {
        whatIfs.removeAll { $0.id == change.id }
        forecastRun = nil
    }

    /// The forecast in words George can talk about.
    var forecastFacts: String {
        let plain = baseline
        var lines = ["Cash now: \(LedgerMoney.text(plain.opening)). Usually \(LedgerMoney.text(plain.usualIn)) comes in and \(LedgerMoney.text(plain.usualOut)) goes out a month (average of the last \(plain.history) months)."]
        lines.append("As things are, in \(forecastMonths) months the cash is \(LedgerMoney.text(plain.closing))" + (plain.runsOut.map { "; it runs out in \($0.formatted(.dateTime.month(.wide).year()))" } ?? "") + ".")
        if hasChanges {
            let tried = forecast
            lines.append("Trying: " + whatIfs.filter(\.on).map(\.name).joined(separator: "; ") + ".")
            lines.append("With those, in \(forecastMonths) months the cash is \(LedgerMoney.text(tried.closing))" + (tried.runsOut.map { "; it runs out in \($0.formatted(.dateTime.month(.wide).year()))" } ?? "")
                         + "; the lowest month is \((tried.lowest?.start ?? today).formatted(.dateTime.month(.wide).year())) at \(LedgerMoney.text(tried.lowest?.closing ?? tried.opening)).")
        }
        return lines.joined(separator: "\n")
    }

    func explainForecast() {
        guard let brain else { return }
        forecastRun = brain.run(BrainRequest(system: Self.georgeSystem, prompt: "\(forecastFacts)\n\nWhat does this forecast mean for the business, and what should I watch?", weight: .quick))
    }

    // MARK: Explaining a report line

    func explain(account code: String, from start: Date, to end: Date) {
        guard let explanation = book.explain(account: code, from: start, to: end) else { return }
        var request = ExplainRequest(explanation: explanation)
        if let brain {
            let facts = explanation.facts(calendar: book.calendar)
            request.run = brain.run(BrainRequest(system: Self.georgeSystem, prompt: "\(facts)\n\nExplain this line of the report in plain English.", weight: .quick))
        }
        explaining = request
    }

    // MARK: The move from Xero

    func chooseXeroFile(_ kind: WritableKeyPath<XeroFiles, URL?>, into files: inout XeroFiles) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.message = "Choose the CSV file you exported from Xero."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        files[keyPath: kind] = url
    }

    /// Contacts and accounts first, then invoices and bills still owing, all in one change.
    func importFromXero(_ files: XeroFiles) {
        var summary: [String] = []
        change { book in
            if let url = files.contacts, let text = try? String(contentsOf: url, encoding: .utf8) {
                var added = 0
                for contact in XeroImport.contacts(text) where !book.contacts.contains(where: { $0.name.caseInsensitiveCompare(contact.name) == .orderedSame }) {
                    book.contacts.append(contact)
                    added += 1
                }
                summary.append("\(added) contacts")
            }
            if let url = files.accounts, let text = try? String(contentsOf: url, encoding: .utf8) {
                var added = 0
                for account in XeroImport.accounts(text) where book.account(account.code) == nil {
                    book.accounts.append(account)
                    added += 1
                }
                book.accounts.sort { $0.code < $1.code }
                summary.append("\(added) new accounts")
            }
            if let url = files.invoices, let text = try? String(contentsOf: url, encoding: .utf8) {
                let result = XeroImport.invoices(text, kind: .sale, book: &book)
                summary.append("\(result.imported.count) invoices still owing")
            }
            if let url = files.bills, let text = try? String(contentsOf: url, encoding: .utf8) {
                let result = XeroImport.invoices(text, kind: .bill, book: &book)
                summary.append("\(result.imported.count) bills to pay")
            }
            book.log("Moved across from Xero", summary.joined(separator: ", "))
        }
        notice = summary.isEmpty ? "Nothing came across. Choose the CSV files you exported from Xero."
            : "From Xero: " + summary.joined(separator: ", ") + ". Now bring in your bank statements from the day you switch."
    }
}
