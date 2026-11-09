import Foundation

// George's forecast and the move from Xero: cash for the months ahead from what's already known (invoices and bills
// due, repeating invoices) and what usually happens; "what if" changes typed as a sentence; any report line explained
// from the transactions behind it; contacts, accounts, invoices and bills from Xero's own exports; a pay-online link.

// MARK: - The forecast

struct ForecastItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case invoice, bill, repeating, usualIn, usualOut, whatIf }

    var id = UUID()
    var date: Date
    var description: String
    /// Money in is positive.
    var amount: Cents
    var kind: Kind
    var contact: UUID?
}

struct ForecastMonth: Identifiable, Hashable, Sendable {
    var start: Date
    var opening: Cents
    var items: [ForecastItem]

    var id: Date { start }
    var moneyIn: Cents { items.reduce(0) { $0 + max(0, $1.amount) } }
    var moneyOut: Cents { items.reduce(0) { $0 + max(0, -$1.amount) } }
    var closing: Cents { opening + moneyIn - moneyOut }
}

struct Forecast: Sendable {
    var today: Date
    /// Cash now: the bank accounts in the books plus statement lines not reconciled yet.
    var opening: Cents
    var months: [ForecastMonth]
    /// What usually comes in and goes out in a month (the last six full months), and from how many months.
    var usualIn: Cents
    var usualOut: Cents
    var history: Int

    /// The first month that ends below zero.
    var runsOut: Date? { months.first { $0.closing < 0 }?.start }
    var lowest: ForecastMonth? { months.min { $0.closing < $1.closing } }
    var closing: Cents { months.last?.closing ?? opening }
}

/// A change to try: hire someone, lose a client, put prices up, a one-off cost or windfall.
struct WhatIf: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// Monthly money out (negative saves money).
        case cost
        /// Monthly money in.
        case income
        /// A single amount on a day: positive in, negative out.
        case oneOff
        /// A client stops paying.
        case loseClient
        /// Prices change by a percentage.
        case prices
    }

    var id = UUID()
    var kind: Kind
    var name: String
    var amount: Cents = 0
    var percent: Double = 0
    var from: Date
    var until: Date?
    var contact: UUID?
    var on = true
}

extension LedgerBook {
    /// The 12% super guarantee on wages, from 1 July 2025.
    static let superRate = 0.12

    /// Cash now, as the bank sees it.
    func cashNow(_ today: Date) -> Cents {
        let books = bankAccounts.reduce(0) { $0 + bankBalance($1.code, asOf: today) }
        let last = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today)) ?? today
        let waiting = bank.filter { !$0.isReconciled && $0.date < last }.reduce(0) { $0 + $1.amount }
        return books + waiting
    }

    func monthStart(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    /// Money that moved in and out of the bank each month (transfers between your own accounts left out).
    func cashMovements(from start: Date, to end: Date) -> [(month: Date, moneyIn: Cents, moneyOut: Cents)] {
        var byMonth: [Date: (Cents, Cents)] = [:]
        func add(_ date: Date, _ amount: Cents) {
            guard date >= start && date < end else { return }
            let month = monthStart(date)
            var value = byMonth[month] ?? (0, 0)
            if amount > 0 { value.0 += amount } else { value.1 -= amount }
            byMonth[month] = value
        }
        let banks = Set(bankAccounts.map(\.code))
        for entry in entries where entry.source != .transfer && entry.source != .opening {
            for line in entry.lines where banks.contains(line.account) { add(entry.date, line.amount) }
        }
        for line in bank where !line.isReconciled && !line.description.lowercased().contains("transfer") {
            add(line.date, line.amount)
        }
        var months: [(month: Date, moneyIn: Cents, moneyOut: Cents)] = []
        var month = monthStart(start)
        while month < end {
            let value = byMonth[month] ?? (0, 0)
            months.append((month: month, moneyIn: value.0, moneyOut: value.1))
            month = calendar.date(byAdding: .month, value: 1, to: month) ?? end
        }
        return months
    }

    /// What each client paid on average a month over the same months.
    func clientAverages(from start: Date, to end: Date, months: Int) -> [UUID: Cents] {
        var totals: [UUID: Cents] = [:]
        for invoice in invoices where invoice.kind == .sale {
            for payment in invoice.payments where payment.date >= start && payment.date < end {
                totals[invoice.contact, default: 0] += payment.amount
            }
        }
        return totals.mapValues { $0 / max(1, months) }
    }

    /// Cash for the months ahead, as things stand and with the changes you're trying.
    func forecast(from today: Date, months count: Int = 12, whatIfs: [WhatIf] = []) -> Forecast {
        let thisMonth = monthStart(today)
        let historyStart = calendar.date(byAdding: .month, value: -6, to: thisMonth) ?? thisMonth
        // Only months the books cover count towards "usual".
        let firstRecord = (entries.map(\.date) + bank.map(\.date)).min() ?? today
        let past = cashMovements(from: max(historyStart, monthStart(firstRecord)), to: thisMonth)
        let history = past.count
        let usualIn = history == 0 ? 0 : past.reduce(0) { $0 + $1.moneyIn } / history
        let usualOut = history == 0 ? 0 : past.reduce(0) { $0 + $1.moneyOut } / history
        let clients = clientAverages(from: historyStart, to: thisMonth, months: max(1, history))
        let horizon = calendar.date(byAdding: .month, value: count, to: thisMonth) ?? thisMonth
        let soon = calendar.date(byAdding: .day, value: 14, to: today) ?? today

        // What's already known.
        var known: [ForecastItem] = []
        for invoice in invoices where invoice.owing > 0 && invoice.status == .approved {
            let name = contact(invoice.contact)?.name ?? ""
            let late = invoice.due < calendar.startOfDay(for: today)
            let date = invoice.kind == .sale ? (late ? soon : invoice.due) : max(invoice.due, today)
            guard date < horizon else { continue }
            known.append(ForecastItem(date: date, description: "\(invoice.number) · \(name)\(late ? " (late)" : "")",
                                      amount: invoice.kind == .sale ? invoice.owing : -invoice.owing,
                                      kind: invoice.kind == .sale ? .invoice : .bill, contact: invoice.contact))
        }
        for schedule in repeating where !schedule.paused {
            var n = schedule.made
            while true {
                let made = schedule.occurrence(n, calendar: calendar)
                if let end = schedule.end, calendar.startOfDay(for: made) > calendar.startOfDay(for: end) { break }
                let paid = calendar.date(byAdding: .day, value: schedule.dueDays, to: made) ?? made
                if paid >= horizon || n > schedule.made + 400 { break }
                if paid >= calendar.startOfDay(for: today) {
                    known.append(ForecastItem(date: paid, description: "Repeating · \(contact(schedule.contact)?.name ?? "")",
                                              amount: schedule.total, kind: .repeating, contact: schedule.contact))
                }
                n += 1
            }
        }

        // The changes being tried.
        let active = whatIfs.filter(\.on)
        let lost = active.filter { $0.kind == .loseClient && $0.contact != nil }
        func isLost(_ item: ForecastItem) -> Bool {
            lost.contains { change in item.contact == change.contact && item.date >= change.from }
        }

        var months: [ForecastMonth] = []
        var opening = cashNow(today)
        let startingCash = opening
        var month = thisMonth
        while month < horizon {
            let next = calendar.date(byAdding: .month, value: 1, to: month) ?? horizon
            // The rest of this month, then whole months.
            let days = Double(calendar.range(of: .day, in: .month, for: month)?.count ?? 30)
            let share = month == thisMonth ? max(0, Double(calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: next).day ?? 0) / days) : 1
            var items = known.filter { $0.date >= month && $0.date < next && !isLost($0) }
            let knownIn = items.reduce(0) { $0 + max(0, $1.amount) }
            let knownOut = items.reduce(0) { $0 + max(0, -$1.amount) }
            let middle = calendar.date(byAdding: .day, value: 14, to: month) ?? month
            let usualInHere = Cents((Double(usualIn) * share).rounded())
            let usualOutHere = Cents((Double(usualOut) * share).rounded())
            if usualInHere > knownIn {
                items.append(ForecastItem(date: max(middle, today), description: "Usual money in, beyond what's invoiced",
                                          amount: usualInHere - knownIn, kind: .usualIn))
            }
            if usualOutHere > knownOut {
                items.append(ForecastItem(date: max(middle, today), description: "Usual spending, beyond bills entered",
                                          amount: -(usualOutHere - knownOut), kind: .usualOut))
            }
            for change in active {
                let started = monthStart(change.from) <= month
                let ended = change.until.map { monthStart($0) < month } ?? false
                let fraction = change.from > month && change.from < next
                    ? Double(calendar.dateComponents([.day], from: calendar.startOfDay(for: change.from), to: next).day ?? 0) / days : share
                switch change.kind {
                case .cost, .income:
                    guard started && !ended else { continue }
                    let amount = Cents((Double(change.amount) * fraction).rounded())
                    items.append(ForecastItem(date: max(change.from, max(middle, today)), description: change.name,
                                              amount: change.kind == .cost ? -amount : amount, kind: .whatIf))
                case .oneOff:
                    if change.from >= month && change.from < next && change.from >= calendar.startOfDay(for: today) {
                        items.append(ForecastItem(date: change.from, description: change.name, amount: change.amount, kind: .whatIf))
                    }
                case .loseClient:
                    guard started, let id = change.contact, let average = clients[id], average > 0 else { continue }
                    // Their usual payments stop too, as far as the usual money in included them.
                    let usualShare = min(Cents((Double(average) * fraction).rounded()), max(0, usualInHere - knownIn))
                    if usualShare > 0 {
                        items.append(ForecastItem(date: max(middle, today), description: change.name, amount: -usualShare, kind: .whatIf))
                    }
                case .prices:
                    guard started && !ended else { continue }
                    let sales = items.filter { [.invoice, .repeating, .usualIn].contains($0.kind) && $0.date >= change.from }
                        .reduce(0) { $0 + $1.amount }
                    let amount = Cents((Double(sales) * change.percent / 100).rounded())
                    if amount != 0 {
                        items.append(ForecastItem(date: max(middle, today), description: change.name, amount: amount, kind: .whatIf))
                    }
                }
            }
            items.sort { $0.date < $1.date }
            let row = ForecastMonth(start: month, opening: opening, items: items)
            months.append(row)
            opening = row.closing
            month = next
        }
        return Forecast(today: today, opening: startingCash, months: months, usualIn: usualIn, usualOut: usualOut, history: history)
    }
}

// MARK: - What if, from a sentence

enum WhatIfParser {
    static let monthNames = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]

    /// "hire at 10k a month from March", "lose Acme in May", "put prices up 10% from July", "buy a laptop for $3,000 in February",
    /// "a $20k grant in May", "win a $4,000 a month retainer from January", "cut software by $500 a month".
    static func parse(_ sentence: String, today: Date, contacts: [Contact], calendar: Calendar) -> WhatIf? {
        let text = sentence.lowercased().replacingOccurrences(of: "’", with: "'")
        let from = startDate(in: text, today: today, calendar: calendar)
        let until = endDate(in: text, from: from, calendar: calendar)
        let when = describe(from, today: today, calendar: calendar)

        // Prices.
        if text.contains("price") || text.contains("rates") && text.contains("%"), let found = Self.percent(in: text) {
            let down = ["cut", "lower", "drop", "reduce", "discount", "down"].contains { text.contains($0) }
            let value = down ? -abs(found) : abs(found)
            return WhatIf(kind: .prices, name: "Prices \(value >= 0 ? "up" : "down") \(number(abs(value)))% \(when)", percent: value, from: from, until: until)
        }

        // Losing a client.
        if ["lose", "losing", "lost", "drop", "goes quiet", "leaves", "stop paying"].contains(where: { text.contains($0) }),
           let client = contacts.first(where: { mentions(text, $0.name) }) {
            return WhatIf(kind: .loseClient, name: "Lose \(client.name) \(when)", from: from, contact: client.id)
        }

        guard let amount = money(in: text) else { return nil }
        let monthly = ["a month", "per month", "/month", "monthly", " pm", "p.m.", "a mth", "/mth", "each month", "every month"].contains { text.contains($0) }
        let weekly = ["a week", "per week", "/week", "weekly", " pw"].contains { text.contains($0) }
        let yearly = ["a year", "per year", "/year", "yearly", "annual", " pa", "p.a."].contains { text.contains($0) }

        if ["hire", "employ", "take on", "staff", "salary", "wage", "contractor", "assistant", "developer", "designer"].contains(where: { text.contains($0) })
            && (monthly || weekly || yearly) {
            let base = perMonth(amount, weekly: weekly, yearly: yearly)
            let wages = text.contains("contractor") ? base : Cents((Double(base) * (1 + LedgerBook.superRate)).rounded())
            let extra = wages - base
            return WhatIf(kind: .cost, name: "Hire at \(dollars(base)) a month \(when)" + (extra > 0 ? " (+ \(dollars(extra)) super)" : ""),
                          amount: wages, from: from, until: until)
        }

        let incomeWords = ["client", "retainer", "win", "new contract", "revenue", "income", "sales", "earn", "customer", "grant", "receive",
                           "refund", "invest", "funding", "raise", "get paid", "comes in", "loan of"]
        let savingWords = ["cut", "save", "saving", "reduce", "cancel", "less on", "drop", "stop"]
        let isIncome = incomeWords.contains { text.contains($0) }
        let isSaving = savingWords.contains { text.contains($0) }

        if monthly || weekly || yearly {
            let value = perMonth(amount, weekly: weekly, yearly: yearly)
            if isIncome && !isSaving {
                return WhatIf(kind: .income, name: "\(dollars(value)) a month more coming in \(when)", amount: value, from: from, until: until)
            }
            if isSaving {
                return WhatIf(kind: .cost, name: "Spend \(dollars(value)) a month less \(when)", amount: -value, from: from, until: until)
            }
            return WhatIf(kind: .cost, name: "\(dollars(value)) a month more going out \(when)", amount: value, from: from, until: until)
        }

        let on = oneOffDate(in: text, today: today, calendar: calendar) ?? from
        let label = describe(on, today: today, calendar: calendar, exact: true)
        if isIncome {
            return WhatIf(kind: .oneOff, name: "\(dollars(amount)) in \(label)", amount: amount, from: on)
        }
        return WhatIf(kind: .oneOff, name: "\(dollars(amount)) out \(label)", amount: -amount, from: on)
    }

    /// "$10,000", or "$10,000.50" when there are cents.
    static func dollars(_ cents: Cents) -> String {
        let text = LedgerMoney.text(cents)
        return text.hasSuffix(".00") ? String(text.dropLast(3)) : text
    }

    static func mentions(_ text: String, _ name: String) -> Bool {
        let lowered = name.lowercased()
        if text.contains(lowered) { return true }
        let first = lowered.split(separator: " ").first.map(String.init) ?? lowered
        return first.count >= 3 && text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: first))\\b", options: .regularExpression) != nil
    }

    static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    static func perMonth(_ amount: Cents, weekly: Bool, yearly: Bool) -> Cents {
        if weekly { return Cents((Double(amount) * 52 / 12).rounded()) }
        if yearly { return Cents((Double(amount) / 12).rounded()) }
        return amount
    }

    /// "$10k", "10,000", "$1.5m", "20 thousand"; not a percentage, a year or a day of the month.
    static func money(in text: String) -> Cents? {
        guard let regex = try? NSRegularExpression(pattern: #"(\$)?\s?(\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?)\s?(k\b|m\b|thousand|million|grand)?(\s?%|\s?percent)?"#) else { return nil }
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard match.range(at: 4).location == NSNotFound else { continue }
            let dollar = match.range(at: 1).location != NSNotFound
            let suffix = match.range(at: 3).location != NSNotFound ? ns.substring(with: match.range(at: 3)) : ""
            guard let value = Double(ns.substring(with: match.range(at: 2)).replacingOccurrences(of: ",", with: "")) else { continue }
            // A bare number is money only with a dollar sign or a size ("10k"), unless it's big enough not to be a date.
            if !dollar && suffix.isEmpty && (value < 100 || (value >= 1900 && value <= 2100)) { continue }
            var multiplier = 1.0
            if suffix.hasPrefix("k") || suffix == "thousand" || suffix == "grand" { multiplier = 1_000 }
            if suffix.hasPrefix("m") || suffix == "million" { multiplier = 1_000_000 }
            return LedgerMoney.cents(value * multiplier)
        }
        return nil
    }

    static func percent(in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s?(%|percent|per cent)"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range])
    }

    static func month(in text: String, after words: [String]) -> (month: Int, year: Int?, day: Int?)? {
        let names = monthNames.map { "\($0)|\($0.prefix(3))" }.joined(separator: "|")
        let pattern = #"\b(?:"# + words.joined(separator: "|") + #")\s+(?:the\s+)?(?:(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?)?("# + names + #")\b\.?(?:\s+(\d{4}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let ns = text as NSString
        let name = ns.substring(with: match.range(at: 2))
        guard let index = monthNames.firstIndex(where: { $0.hasPrefix(name) }) else { return nil }
        let year = match.range(at: 3).location == NSNotFound ? nil : Int(ns.substring(with: match.range(at: 3)))
        let day = match.range(at: 1).location == NSNotFound ? nil : Int(ns.substring(with: match.range(at: 1)))
        return (index + 1, year, day)
    }

    /// The next time that month starts (this month counts if it's the one named).
    static func date(month: Int, year: Int?, day: Int?, today: Date, calendar: Calendar) -> Date {
        let now = calendar.dateComponents([.year, .month], from: today)
        var chosen = year ?? (now.year ?? 2026)
        if year == nil, month < (now.month ?? 1) { chosen += 1 }
        return calendar.date(from: DateComponents(year: chosen, month: month, day: day ?? 1, hour: 12)) ?? today
    }

    static func startDate(in text: String, today: Date, calendar: Calendar) -> Date {
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        if let found = month(in: text, after: ["from", "in", "starting", "start", "starts", "on", "by", "after", "at the start of", "beginning", "until"].filter { $0 != "until" }) {
            return date(month: found.month, year: found.year, day: found.day, today: today, calendar: calendar)
        }
        if let regex = try? NSRegularExpression(pattern: #"in (\d+|a|one|two|three|six) months?"#),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            let words = ["a": 1, "one": 1, "two": 2, "three": 3, "six": 6]
            let count = Int(text[range]) ?? words[String(text[range])] ?? 1
            return calendar.date(byAdding: .month, value: count, to: thisMonth).map { calendar.date(bySettingHour: 12, minute: 0, second: 0, of: $0) ?? $0 } ?? today
        }
        if text.contains("now") || text.contains("today") || text.contains("this month") || text.contains("straight away") {
            return today
        }
        // "Next month" and anything without a date start next month.
        let next = calendar.date(byAdding: .month, value: 1, to: thisMonth) ?? today
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: next) ?? next
    }

    static func oneOffDate(in text: String, today: Date, calendar: Calendar) -> Date? {
        guard let found = month(in: text, after: ["in", "on", "by", "from", "around", "early", "late", "mid", "end of"]) else { return nil }
        return date(month: found.month, year: found.year, day: found.day ?? 15, today: today, calendar: calendar)
    }

    static func endDate(in text: String, from: Date, calendar: Calendar) -> Date? {
        if let found = month(in: text, after: ["until", "till", "to", "through"]) {
            let year = found.year ?? {
                let start = calendar.dateComponents([.year, .month], from: from)
                return found.month < (start.month ?? 1) ? (start.year ?? 2026) + 1 : (start.year ?? 2026)
            }()
            return calendar.date(from: DateComponents(year: year, month: found.month, day: 1, hour: 12))
        }
        if let regex = try? NSRegularExpression(pattern: #"for (\d+|a|one|two|three|six|twelve) (months?|years?)"#),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let countRange = Range(match.range(at: 1), in: text), let unitRange = Range(match.range(at: 2), in: text) {
            let words = ["a": 1, "one": 1, "two": 2, "three": 3, "six": 6, "twelve": 12]
            let count = Int(text[countRange]) ?? words[String(text[countRange])] ?? 1
            let months = text[unitRange].hasPrefix("year") ? count * 12 : count
            // The last month it runs in.
            return calendar.date(byAdding: .month, value: months - 1, to: from)
        }
        return nil
    }

    static func describe(_ date: Date, today: Date, calendar: Calendar, exact: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_AU")
        formatter.timeZone = calendar.timeZone
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: today)
        if exact {
            formatter.dateFormat = sameYear ? "'on' d MMMM" : "'on' d MMMM yyyy"
        } else {
            formatter.dateFormat = sameYear ? "'from' MMMM" : "'from' MMMM yyyy"
        }
        return formatter.string(from: date)
    }
}

// MARK: - Explaining a report line

struct MonthAmount: Identifiable, Hashable, Sendable {
    var month: Date
    var amount: Cents
    var id: Date { month }
}

struct PayeeAmount: Identifiable, Hashable, Sendable {
    var name: String
    var amount: Cents
    var count: Int
    var id: String { name }
}

struct ExplainedLine: Identifiable, Hashable, Sendable {
    var id = UUID()
    var date: Date
    var description: String
    var amount: Cents
}

struct LineExplanation: Sendable {
    var account: LedgerAccount
    var from: Date
    var to: Date
    var total: Cents
    /// The same length of time just before.
    var previous: Cents
    var months: [MonthAmount]
    var payees: [PayeeAmount]
    var lines: [ExplainedLine]

    var change: Cents { total - previous }
    var changePercent: Double? { previous == 0 ? nil : Double(change) / Double(abs(previous)) * 100 }
    var largest: [ExplainedLine] { Array(lines.sorted { abs($0.amount) > abs($1.amount) }.prefix(5)) }
    var isTax: Bool { account.role == .gst || account.name.lowercased().contains("tax") || account.name.lowercased().contains("gst") }
}

extension LedgerBook {
    /// Who a journal entry was with: the contact for invoices and payments, the payee for a bank line.
    func counterparty(of entry: JournalEntry) -> String {
        if let reference = entry.reference {
            if let sale = self.invoice(reference), let name = contact(sale.contact)?.name { return name }
            if let paid = invoices.first(where: { $0.payments.contains { $0.entry == entry.id } }), let name = contact(paid.contact)?.name { return name }
            if let line = bank.first(where: { $0.id == reference }) {
                // The payee's words as the bank wrote them: "AWS EMEA", not "aws emea".
                let key = Self.payeeKey(line.description).split(separator: " ").map(String.init)
                guard !key.isEmpty else { return line.description }
                let words = line.description.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
                return key.map { part in words.first { $0.lowercased() == part } ?? part }.joined(separator: " ")
            }
        }
        return entry.memo.isEmpty ? "Other" : entry.memo
    }

    /// The transactions behind one line of a report, compared with the period before.
    func explain(account code: String, from start: Date, to end: Date) -> LineExplanation? {
        guard let ledgerAccount = self.account(code) else { return nil }
        let sign: Cents = ledgerAccount.type.debitNormal ? 1 : -1
        let first = calendar.startOfDay(for: start)
        let last = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        let days = calendar.dateComponents([.day], from: first, to: last).day ?? 30
        let previousStart = calendar.date(byAdding: .day, value: -days, to: first) ?? first
        var total: Cents = 0, previous: Cents = 0
        var months: [Date: Cents] = [:]
        var payees: [String: (Cents, Int)] = [:]
        var lines: [ExplainedLine] = []
        for entry in entries {
            let amount = entry.lines.filter { $0.account == code }.reduce(0) { $0 + $1.amount } * sign
            guard amount != 0 else { continue }
            if entry.date >= first && entry.date < last {
                total += amount
                months[monthStart(entry.date), default: 0] += amount
                let who = counterparty(of: entry)
                let current = payees[who] ?? (0, 0)
                payees[who] = (current.0 + amount, current.1 + 1)
                let said = entry.memo.lowercased().contains(who.lowercased()) ? entry.memo : "\(who) · \(entry.memo)"
                lines.append(ExplainedLine(date: entry.date, description: who == entry.memo ? who : said, amount: amount))
            } else if entry.date >= previousStart && entry.date < first {
                previous += amount
            }
        }
        var monthRows: [MonthAmount] = []
        var month = monthStart(first)
        while month < last {
            monthRows.append(MonthAmount(month: month, amount: months[month] ?? 0))
            month = calendar.date(byAdding: .month, value: 1, to: month) ?? last
        }
        let payeeRows = payees.map { PayeeAmount(name: $0.key, amount: $0.value.0, count: $0.value.1) }.sorted { $0.amount > $1.amount }
        return LineExplanation(account: ledgerAccount, from: first, to: end, total: total, previous: previous, months: monthRows,
                               payees: payeeRows, lines: lines.sorted { $0.date < $1.date })
    }
}

extension LineExplanation {
    static let taxNote = "General information, not tax advice: check anything you'll lodge with your registered tax or BAS agent."

    /// What George explains from, in plain sentences; never a figure that isn't in the books.
    func facts(calendar: Calendar) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_AU")
        format.timeZone = calendar.timeZone
        format.dateFormat = "d MMM yyyy"
        let monthFormat = DateFormatter()
        monthFormat.locale = Locale(identifier: "en_AU")
        monthFormat.timeZone = calendar.timeZone
        monthFormat.dateFormat = "MMM"
        var lines: [String] = []
        lines.append("\(account.name) (account \(account.code)) was \(LedgerMoney.text(total)) from \(format.string(from: from)) to \(format.string(from: to)).")
        if previous == 0 {
            lines.append(total == 0 ? "Nothing was recorded in the period before either." : "Nothing was recorded in the same length of time before.")
        } else if let percent = changePercent {
            let direction = change > 0 ? "up" : (change < 0 ? "down" : "the same as")
            lines.append(change == 0 ? "That's the same as the period before." :
                "That's \(direction) \(LedgerMoney.text(abs(change))) (\(Int(abs(percent).rounded()))%) on the same length of time before (\(LedgerMoney.text(previous))).")
        }
        if months.count > 1 {
            lines.append("By month: " + months.map { "\(monthFormat.string(from: $0.month)) \(LedgerMoney.text($0.amount))" }.joined(separator: ", ") + ".")
        }
        let top = payees.prefix(4)
        if !top.isEmpty {
            lines.append("Most of it: " + top.map { "\($0.name) \(LedgerMoney.text($0.amount)) (\($0.count) \($0.count == 1 ? "entry" : "entries"))" }.joined(separator: ", ") + ".")
        }
        if let biggest = largest.first, total != 0 {
            lines.append("The largest single entry: \(format.string(from: biggest.date)), \(biggest.description), \(LedgerMoney.text(biggest.amount)).")
        }
        if isTax { lines.append(Self.taxNote) }
        return lines.joined(separator: "\n")
    }
}

// MARK: - The move from Xero

/// Xero's own CSV exports: contacts, the chart of accounts, and sales invoices or bills.
enum XeroImport {
    struct Table {
        var header: [String]
        var rows: [[String]]

        /// A column by name, ignoring Xero's leading "*" on required fields, case and spaces.
        func index(_ names: String...) -> Int? {
            let keys = header.map(Table.key)
            for name in names {
                if let found = keys.firstIndex(of: Table.key(name)) { return found }
            }
            return nil
        }

        func value(_ row: [String], _ index: Int?) -> String {
            guard let index, index < row.count else { return "" }
            return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        static func key(_ name: String) -> String {
            name.lowercased().filter { $0.isLetter || $0.isNumber }
        }
    }

    /// A CSV file read with quotes, commas and line breaks inside quotes.
    static func table(_ text: String) -> Table {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var characters = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        if characters.first == "\u{FEFF}" { characters.removeFirst() }
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if quoted {
                if character == "\"" {
                    if index + 1 < characters.count && characters[index + 1] == "\"" { field.append("\""); index += 1 } else { quoted = false }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                quoted = true
            } else if character == "," {
                row.append(field)
                field = ""
            } else if character == "\n" {
                row.append(field)
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        guard let header = rows.first else { return Table(header: [], rows: []) }
        return Table(header: header, rows: Array(rows.dropFirst()))
    }

    static func contacts(_ text: String) -> [Contact] {
        let csv = Self.table(text)
        guard let name = csv.index("ContactName", "Name") else { return [] }
        let email = csv.index("EmailAddress", "Email")
        let abn = csv.index("TaxNumber", "ABN")
        let phone = csv.index("PhoneNumber", "Phone")
        let address = ["POAddressLine1", "POAddressLine2", "POCity", "PORegion", "POPostalCode"].compactMap { csv.index($0) }
        return csv.rows.compactMap { row in
            let value = csv.value(row, name)
            guard !value.isEmpty else { return nil }
            var contact = Contact(name: value)
            contact.email = csv.value(row, email)
            contact.abn = csv.value(row, abn)
            contact.phone = csv.value(row, phone)
            contact.address = address.map { csv.value(row, $0) }.filter { !$0.isEmpty }.joined(separator: ", ")
            return contact
        }
    }

    static func type(_ xero: String) -> (AccountType, bank: Bool)? {
        let value = xero.lowercased()
        if value == "bank" { return (.asset, true) }
        if value.contains("asset") || value == "inventory" || value == "prepayment" { return (.asset, false) }
        if value.contains("liabilit") { return (.liability, false) }
        if value.contains("equity") { return (.equity, false) }
        if ["revenue", "sales", "other income", "income"].contains(value) { return (.income, false) }
        if ["expense", "direct costs", "overhead", "overheads", "depreciation", "wages and salaries", "superannuation"].contains(value) { return (.expense, false) }
        return nil
    }

    static func gst(_ xero: String) -> GSTCode {
        let value = xero.lowercased()
        if value.contains("capital") && !value.contains("free") { return .capital }
        if value.hasPrefix("gst on") || value == "gst" { return .gst }
        if value.contains("free") || value.contains("export") { return .free }
        if value.contains("input taxed") { return .input }
        return .excluded
    }

    static func accounts(_ text: String) -> [LedgerAccount] {
        let csv = Self.table(text)
        guard let code = csv.index("Code", "AccountCode"), let name = csv.index("Name", "AccountName"), let kind = csv.index("Type", "AccountType") else { return [] }
        let tax = csv.index("TaxCode", "Tax Code", "TaxType")
        return csv.rows.compactMap { row in
            let value = csv.value(row, code)
            guard !value.isEmpty, let mapped = Self.type(csv.value(row, kind)) else { return nil }
            return LedgerAccount(code: value, name: csv.value(row, name), type: mapped.0, gst: Self.gst(csv.value(row, tax)), isBank: mapped.bank)
        }
    }

    /// Invoices or bills, a row per line, grouped by number. Only what's still owing comes across (paid ones stay
    /// in Xero's history); amounts are read as Xero shows them, with or without GST.
    static func invoices(_ text: String, kind: Invoice.Kind, book: inout LedgerBook) -> (imported: [Invoice], skipped: Int) {
        let csv = Self.table(text)
        guard let number = csv.index("InvoiceNumber", "Number"), let name = csv.index("ContactName", "Contact") else { return ([], 0) }
        let issuedColumn = csv.index("InvoiceDate", "Date")
        let dueColumn = csv.index("DueDate")
        let description = csv.index("Description")
        let quantity = csv.index("Quantity")
        let unit = csv.index("UnitAmount", "UnitPrice")
        let lineAmount = csv.index("LineAmount")
        let accountColumn = csv.index("AccountCode", "Account")
        let taxType = csv.index("TaxType")
        let taxAmount = csv.index("TaxAmount")
        let totalColumn = csv.index("Total")
        let dueAmount = csv.index("InvoiceAmountDue", "AmountDue", "Due")
        let paidAmount = csv.index("InvoiceAmountPaid", "AmountPaid", "Paid")
        let statusColumn = csv.index("Status")
        let reference = csv.index("Reference")

        var order: [String] = []
        var groups: [String: [[String]]] = [:]
        for row in csv.rows {
            let key = csv.value(row, number)
            guard !key.isEmpty else { continue }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(row)
        }
        var imported: [Invoice] = []
        var skipped = 0
        let existing = Set(book.invoices.filter { $0.kind == kind }.map(\.number))
        for key in order {
            guard let rows = groups[key], let first = rows.first, !existing.contains(key) else { skipped += 1; continue }
            let status = csv.value(first, statusColumn).uppercased()
            if ["PAID", "VOIDED", "DELETED"].contains(status) { skipped += 1; continue }
            let due = LedgerMoney.parse(csv.value(first, dueAmount))
            if let due, due <= 0 { skipped += 1; continue }

            let contactName = csv.value(first, name)
            let contactID: UUID
            if let found = book.contacts.first(where: { $0.name.caseInsensitiveCompare(contactName) == .orderedSame }) {
                contactID = found.id
            } else {
                let contact = Contact(name: contactName.isEmpty ? "Unknown" : contactName)
                book.contacts.append(contact)
                contactID = contact.id
            }
            let issued = StatementParser.date(csv.value(first, issuedColumn)) ?? Date()
            let dueDate = StatementParser.date(csv.value(first, dueColumn)) ?? issued
            let fallbackAccount = kind == .sale ? "200" : "429"

            // Each line's amount before GST: the line amount less its tax when the total says amounts included GST.
            var drafts: [(text: String, quantity: Double, amount: Cents, tax: Cents, account: String, gst: GSTCode)] = []
            for row in rows {
                let count = Double(csv.value(row, quantity)) ?? 1
                let price = LedgerMoney.parse(csv.value(row, unit)) ?? 0
                let amount = LedgerMoney.parse(csv.value(row, lineAmount)) ?? Cents((Double(price) * count).rounded())
                let tax = LedgerMoney.parse(csv.value(row, taxAmount)) ?? 0
                var account = csv.value(row, accountColumn)
                if book.account(account) == nil { account = fallbackAccount }
                let code = gst(csv.value(row, taxType))
                drafts.append((csv.value(row, description), count, amount, tax, account, book.settings.gstRegistered ? code : .excluded))
            }
            let lineSum = drafts.reduce(0) { $0 + $1.amount }
            let taxSum = drafts.reduce(0) { $0 + $1.tax }
            let total = LedgerMoney.parse(csv.value(first, totalColumn))
            let inclusive = total.map { abs($0 - lineSum) <= drafts.count && taxSum != 0 } ?? false
            let lines = drafts.map { draft -> InvoiceLine in
                let net = inclusive ? draft.amount - draft.tax : draft.amount
                let quantity = draft.quantity == 0 ? 1 : draft.quantity
                return InvoiceLine(description: draft.text.isEmpty ? "Imported from Xero" : draft.text, quantity: quantity,
                                   unitPrice: Cents((Double(net) / quantity).rounded()), account: draft.account, gst: draft.gst)
            }
            var invoice = Invoice(kind: kind, number: key, contact: contactID, issued: issued, due: dueDate,
                                  reference: csv.value(first, reference), lines: lines)
            invoice.notes = "Imported from Xero"
            book.invoices.append(invoice)
            if status != "DRAFT" {
                try? book.approve(invoice.id)
                // Part-paid in Xero: the part already paid is noted against the receivable, so only the rest is owing.
                if let paid = LedgerMoney.parse(csv.value(first, paidAmount)), paid > 0,
                   let index = book.invoices.firstIndex(where: { $0.id == invoice.id }) {
                    book.invoices[index].payments.append(Payment(date: issued, amount: min(paid, book.invoices[index].total), bankAccount: "Xero"))
                }
            }
            if let stored = book.invoice(invoice.id) { imported.append(stored) }
        }
        if !imported.isEmpty {
            book.log("Imported \(kind == .sale ? "invoices" : "bills") from Xero", "\(imported.count) still owing\(skipped > 0 ? ", \(skipped) paid or already here" : "")")
        }
        return (imported, skipped)
    }
}

// MARK: - Paying online

extension InvoiceDocument {
    /// The pay-online link in the settings, with [invoice], [amount] and [email] filled in.
    static func payLink(_ template: String, invoice: Invoice, contact: Contact?) -> String? {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, invoice.kind == .sale, invoice.owing > 0 || invoice.status == .draft else { return nil }
        let amount = String(format: "%.2f", LedgerMoney.dollars(invoice.status == .draft ? invoice.total : invoice.owing))
        func encoded(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value }
        return trimmed.replacingOccurrences(of: "[invoice]", with: encoded(invoice.number))
            .replacingOccurrences(of: "[amount]", with: amount)
            .replacingOccurrences(of: "[email]", with: encoded(contact?.email ?? ""))
    }
}
