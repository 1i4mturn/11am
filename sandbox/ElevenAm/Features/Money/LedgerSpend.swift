import Foundation

// George's money out: receipts kept with the bank lines they explain (and the ones the ATO wants to see), expense claims
// for what you paid yourself, budgets against what really happened, and George's checks for anything odd.
// Plain data and arithmetic, tested with the rest of the books.

// MARK: Receipts

struct LedgerReceipt: Codable, Identifiable, Hashable, Sendable {
    enum Source: String, Codable, Sendable { case file, mail, phone }

    var id = UUID()
    /// The copy kept in Money's receipts folder ("" when there's no file, like a receipt read from an email).
    var file = ""
    var vendor: String
    var date: Date
    /// What was paid, GST included.
    var total: Cents
    /// The GST the receipt shows, when it shows it.
    var gst: Cents?
    var abn = ""
    var source: Source = .file
    var note = ""
    /// The bank line it explains, or the bill or expense claim it supports.
    var bankLine: UUID?
    var bill: UUID?

    var isMatched: Bool { bankLine != nil || bill != nil }
}

enum ReceiptReader {
    struct Reading: Equatable {
        var vendor: String?
        var date: Date?
        var total: Cents?
        var gst: Cents?
        var abn: String?
    }

    /// Reads what a receipt says from its text (from the PDF, or recognised from a photo).
    static func read(_ text: String, calendar: Calendar) -> Reading {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var reading = Reading()
        var labelled: [Cents] = []
        var all: [Cents] = []
        for line in lines {
            let lower = line.lowercased()
            let found = amounts(in: line)
            all += found
            if lower.contains("gst") && !lower.contains("excl") {
                if reading.gst == nil, let tax = found.last, !lower.contains("total") || lower.contains("includes") || lower.contains("incl") {
                    reading.gst = tax
                }
                if !(lower.contains("total") && (lower.contains("includes") || lower.contains("incl"))) { continue }
            }
            if lower.contains("subtotal") || lower.contains("sub-total") || lower.contains("sub total") { continue }
            if ["total", "amount due", "amount paid", "balance due", "paid", "charged", "card"].contains(where: { lower.contains($0) }) {
                labelled += found
            }
        }
        reading.total = labelled.last ?? all.max()
        // "Total includes GST of $1.05" names the GST, not the total.
        if let gst = reading.gst, reading.total == gst, let biggest = all.max(), biggest > gst { reading.total = biggest }
        reading.date = date(in: text, calendar: calendar)
        reading.abn = abn(in: text)
        reading.vendor = vendor(in: lines)
        return reading
    }

    /// Amounts with cents ("$1,234.50", "12.00"), or with a dollar sign ("$12").
    static func amounts(in line: String) -> [Cents] {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![\d/.:-])(?:(?:A|AU|US)?\$\s?)?(\d{1,3}(?:,\d{3})+|\d+)\.(\d{2})(?![\d/.%])|(?:A|AU|US)?\$\s?(\d{1,3}(?:,\d{3})+|\d+)(?![\d.,/%])"#) else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            func group(_ index: Int) -> String? { Range(match.range(at: index), in: line).map { String(line[$0]) } }
            if let whole = group(1), let cents = group(2), let dollars = Int(whole.replacingOccurrences(of: ",", with: "")), let part = Int(cents) {
                return dollars * 100 + part
            }
            if let whole = group(3), let dollars = Int(whole.replacingOccurrences(of: ",", with: "")) { return dollars * 100 }
            return nil
        }
    }

    private static let dateFormats = ["d/M/yyyy", "d/M/yy", "d-M-yyyy", "yyyy-MM-dd", "d MMM yyyy", "d MMMM yyyy", "d MMM yy", "MMM d yyyy",
                                      "MMMM d yyyy", "EEE d MMM yyyy", "EEEE d MMMM yyyy", "d.M.yyyy"]

    static func date(in text: String, calendar: Calendar) -> Date? {
        let patterns = [#"\b\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}\b"#, #"\b\d{4}-\d{2}-\d{2}\b"#,
                        #"\b(?:(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)[a-z]*,?\s+)?\d{1,2}(?:st|nd|rd|th)?\s+[A-Z][a-z]{2,8}\.?,?\s+\d{2,4}\b"#,
                        #"\b[A-Z][a-z]{2,8}\.?\s+\d{1,2}(?:st|nd|rd|th)?,?\s+\d{4}\b"#]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.isLenient = false
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range, in: text) else { continue }
                var found = String(text[range]).replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: pattern.hasPrefix(#"\b\d{1,2}[/.-]"#) ? "/" : "")
                found = found.replacingOccurrences(of: #"(\d)(st|nd|rd|th)"#, with: "$1", options: .regularExpression)
                found = found.replacingOccurrences(of: "Sept ", with: "Sep ").replacingOccurrences(of: "-", with: pattern.hasPrefix(#"\b\d{4}"#) ? "-" : "/")
                for format in dateFormats {
                    formatter.dateFormat = format
                    if let date = formatter.date(from: found) {
                        let year = calendar.component(.year, from: date)
                        guard (2000...2100).contains(year) else { continue }
                        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)
                    }
                }
            }
        }
        return nil
    }

    static func abn(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"ABN[:.\s]*(\d{2}\s?\d{3}\s?\d{3}\s?\d{3})"#, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let digits = text[range].filter(\.isNumber)
        guard digits.count == 11 else { return nil }
        let chars = Array(digits)
        return "\(String(chars[0...1])) \(String(chars[2...4])) \(String(chars[5...7])) \(String(chars[8...10]))"
    }

    /// The business: the first line near the top that's a name, not "Tax invoice", a date, an amount or an address detail.
    static func vendor(in lines: [String]) -> String? {
        let skip = ["tax invoice", "invoice", "receipt", "tax receipt", "order", "abn", "acn", "phone", "tel", "www", "http", "date", "thank",
                    "welcome", "customer copy", "merchant copy", "eftpos", "@"]
        for line in lines.prefix(8) {
            let lower = line.lowercased()
            guard line.count >= 3, line.count <= 48, line.contains(where: \.isLetter) else { continue }
            if lower.contains("@") || skip.contains(where: { lower.hasPrefix($0) || (lower.contains($0) && $0.count > 4) }) { continue }
            if !amounts(in: line).isEmpty { continue }
            let digits = line.filter(\.isNumber).count
            if digits > line.count / 3 { continue }
            return line.trimmingCharacters(in: CharacterSet(charactersIn: "*#-=_ "))
        }
        return nil
    }
}

extension LedgerBook {
    /// The ATO wants a tax invoice before you claim the GST on anything over $82.50 (GST included).
    static let taxInvoiceThreshold: Cents = 8_250

    func receipt(_ id: UUID) -> LedgerReceipt? { receipts.first { $0.id == id } }

    func receipts(forLine id: UUID) -> [LedgerReceipt] { receipts.filter { $0.bankLine == id } }

    func receipts(forBill id: UUID) -> [LedgerReceipt] { receipts.filter { $0.bill == id } }

    /// Money-out bank lines a receipt could explain: the same amount (or within a cent or two for card rounding), from a few
    /// days before the receipt to ten days after, best first. Lines that already have a receipt are left out.
    func candidates(for receipt: LedgerReceipt) -> [(line: BankLine, score: Double)] {
        let explained = Set(receipts.compactMap { $0.id == receipt.id ? nil : $0.bankLine })
        return bank.compactMap { line -> (line: BankLine, score: Double)? in
            guard line.amount < 0, !explained.contains(line.id) else { return nil }
            let difference = abs(abs(line.amount) - receipt.total)
            guard difference <= 2 else { return nil }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: receipt.date), to: calendar.startOfDay(for: line.date)).day ?? 99
            guard days >= -3, days <= 10 else { return nil }
            var score = difference == 0 ? 1.0 : 0.6
            score += 1 - Double(abs(days)) / 11
            if names(receipt, line) { score += 1 }
            return (line, score)
        }
        .sorted { $0.score > $1.score }
    }

    /// The bank line George is sure a receipt belongs to: exactly the amount, within five days, and either the only one or named.
    func confidentMatch(for receipt: LedgerReceipt) -> BankLine? {
        let found = candidates(for: receipt)
        guard let best = found.first, abs(best.line.amount) == receipt.total else { return nil }
        let days = abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: receipt.date), to: calendar.startOfDay(for: best.line.date)).day ?? 99)
        guard days <= 5 else { return nil }
        if found.count == 1 { return best.line }
        // Several for the same amount: only when the receipt's name is in exactly one of them.
        let named = found.filter { names(receipt, $0.line) }
        if named.count == 1, named[0].line.id == best.line.id { return best.line }
        return nil
    }

    /// Whether a bank line's description carries the receipt's business name.
    func names(_ receipt: LedgerReceipt, _ line: BankLine) -> Bool {
        let words = Self.payeeKey(receipt.vendor).split(separator: " ").map(String.init)
        let text = line.description.lowercased()
        return !words.isEmpty && words.contains { text.contains($0) }
    }

    /// Keeps a receipt, matched to its bank line straight away when George is sure.
    @discardableResult
    mutating func addReceipt(_ receipt: LedgerReceipt) -> UUID {
        var kept = receipt
        if kept.bankLine == nil, kept.bill == nil, let line = confidentMatch(for: kept) { kept.bankLine = line.id }
        receipts.append(kept)
        log("Kept a receipt from \(kept.vendor)", kept.bankLine == nil ? "Not matched yet" : "Matched to the bank", amount: kept.total)
        return kept.id
    }

    mutating func attachReceipt(_ id: UUID, toLine line: UUID) {
        guard let index = receipts.firstIndex(where: { $0.id == id }) else { return }
        receipts[index].bankLine = line
        receipts[index].bill = nil
        log("Matched a receipt", receipts[index].vendor, amount: receipts[index].total)
    }

    mutating func detachReceipt(_ id: UUID) {
        guard let index = receipts.firstIndex(where: { $0.id == id }) else { return }
        receipts[index].bankLine = nil
        receipts[index].bill = nil
    }

    mutating func deleteReceipt(_ id: UUID) {
        guard let gone = receipt(id) else { return }
        receipts.removeAll { $0.id == id }
        log("Deleted a receipt", gone.vendor, amount: gone.total)
    }

    /// Matches every receipt George is sure of. Returns how many.
    @discardableResult
    mutating func matchReceipts() -> Int {
        var count = 0
        for index in receipts.indices where !receipts[index].isMatched {
            if let line = confidentMatch(for: receipts[index]) {
                receipts[index].bankLine = line.id
                count += 1
            }
        }
        if count > 0 { log("Matched \(count) \(count == 1 ? "receipt" : "receipts")") }
        return count
    }

    /// Purchases coded straight from the bank with GST, over $82.50, with no receipt: their GST credits need a tax invoice.
    /// (Bills don't count: the bill is the tax invoice.)
    func missingReceipts(from start: Date, to end: Date) -> [BankLine] {
        let explained = Set(receipts.compactMap(\.bankLine))
        let first = calendar.startOfDay(for: start), last = calendar.startOfDay(for: end)
        return bank.filter { line in
            guard line.amount < 0, -line.amount > Self.taxInvoiceThreshold, !explained.contains(line.id), let entryID = line.entry,
                  let entry = entries.first(where: { $0.id == entryID }), entry.source == .bank else { return false }
            let day = calendar.startOfDay(for: line.date)
            guard day >= first, day <= last else { return false }
            return entry.lines.contains { $0.tax?.hasTax == true && $0.taxAmount != 0 }
        }
        .sorted { $0.date > $1.date }
    }

    /// The GST credits waiting on those receipts.
    func gstWaitingOnReceipts(from start: Date, to end: Date) -> Cents {
        missingReceipts(from: start, to: end).reduce(0) { total, line in
            guard let entry = entries.first(where: { $0.id == line.entry }) else { return total }
            return total + entry.lines.filter { $0.tax?.hasTax == true }.reduce(0) { $0 + abs($1.taxAmount) }
        }
    }
}

// MARK: Expense claims

/// Something you paid for yourself, to be paid back.
struct ClaimItem: Equatable, Sendable {
    var description: String
    /// What you paid, GST included.
    var total: Cents
    var account: String
    var gst: GSTCode
    var date: Date
    var receipt: UUID?
}

extension LedgerBook {
    /// Expense claims are bills from you to the business, numbered CLAIM-0001, so paying them back is like paying any bill.
    static let claimPrefix = "CLAIM-"

    func isClaim(_ invoice: Invoice) -> Bool { invoice.kind == .bill && invoice.number.hasPrefix(Self.claimPrefix) }

    var claims: [Invoice] { invoices.filter(isClaim).sorted { $0.issued > $1.issued } }

    /// What the business owes you for claims.
    var owedOnClaims: Cents { claims.reduce(0) { $0 + $1.owing } }

    /// A line that adds back up to exactly what was paid once GST is added.
    static func line(for item: ClaimItem, registered: Bool) -> InvoiceLine {
        let code: GSTCode = registered ? item.gst : .excluded
        var net = item.total - GST.included(in: item.total, code)
        for candidate in [net, net - 1, net + 1] where candidate + GST.added(to: candidate, code) == item.total {
            net = candidate
            break
        }
        return InvoiceLine(description: item.description, unitPrice: net, account: item.account, gst: code)
    }

    /// Puts claim items on a claim from the person who paid, approves it into the books, and ties the receipts to it.
    @discardableResult
    mutating func makeClaim(_ items: [ClaimItem], by person: UUID, date: Date) throws -> UUID {
        guard !items.isEmpty else { throw LedgerError.nothingOwing }
        let number = Self.claimPrefix + String(format: "%04d", claims.count + 1)
        let lines = items.map { Self.line(for: $0, registered: settings.gstRegistered) }
        let due = calendar.date(byAdding: .day, value: 7, to: date) ?? date
        let claim = Invoice(kind: .bill, number: number, contact: person, issued: date, due: due, reference: "Expense claim", lines: lines)
        invoices.append(claim)
        do {
            try approve(claim.id)
        } catch {
            invoices.removeAll { $0.id == claim.id }
            throw error
        }
        for item in items {
            if let receiptID = item.receipt, let index = receipts.firstIndex(where: { $0.id == receiptID }) {
                receipts[index].bill = claim.id
                receipts[index].bankLine = nil
            }
        }
        return claim.id
    }
}

// MARK: Budgets

struct BudgetRow: Identifiable, Hashable, Sendable {
    var account: LedgerAccount
    var budget: Cents
    var actual: Cents
    var id: String { account.code }
    /// Positive is better than planned: under on costs, over on income.
    var variance: Cents { account.type == .income ? actual - budget : budget - actual }
    /// How much of the budget has gone (or been earned).
    var used: Double? { budget == 0 ? nil : Double(actual) / Double(budget) }
}

extension LedgerBook {
    /// The budget for an account over some dates: its monthly figure, in proportion to the days of each month covered.
    func budget(for code: String, from start: Date, to end: Date) -> Cents {
        guard let monthly = budgets[code], monthly != 0 else { return 0 }
        let first = calendar.startOfDay(for: start), last = calendar.startOfDay(for: end)
        guard first <= last else { return 0 }
        var total = 0.0
        var month = calendar.dateInterval(of: .month, for: first)?.start ?? first
        while month <= last {
            guard let interval = calendar.dateInterval(of: .month, for: month) else { break }
            let monthEnd = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            let from = max(first, interval.start), to = min(last, calendar.startOfDay(for: monthEnd))
            let days = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
            let covered = (calendar.dateComponents([.day], from: from, to: to).day ?? 0) + 1
            if covered > 0 { total += Double(monthly) * Double(covered) / Double(days) }
            month = interval.end
        }
        return Int(total.rounded())
    }

    /// Budget against actual for every account with a budget or with activity.
    func budgetReport(from start: Date, to end: Date) -> [BudgetRow] {
        let pnl = profitAndLoss(from: start, to: end)
        var actuals: [String: Cents] = [:]
        for item in pnl.income + pnl.expenses { actuals[item.account.code] = item.amount }
        return accounts.filter { $0.type == .income || $0.type == .expense }.compactMap { account in
            let budget = self.budget(for: account.code, from: start, to: end)
            let actual = actuals[account.code] ?? 0
            guard budget != 0 || actual != 0 else { return nil }
            return BudgetRow(account: account, budget: budget, actual: actual)
        }
    }

    mutating func setBudget(_ code: String, monthly: Cents) {
        let before = budgets[code] ?? 0
        guard before != monthly else { return }
        budgets[code] = monthly == 0 ? nil : monthly
        log("Set the budget for \(account(code)?.name ?? code)", "\(LedgerMoney.text(monthly)) a month", amount: monthly)
    }

    /// A starting budget from the year before a date: each account's monthly average, to the dollar.
    func suggestedBudgets(before date: Date) -> [String: Cents] {
        let end = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)) ?? date
        let start = calendar.date(byAdding: .year, value: -1, to: date) ?? date
        let pnl = profitAndLoss(from: start, to: end)
        // Average over the months the books actually cover, so four months of history isn't spread over twelve.
        let firstEntry = entries.map(\.date).min() ?? start
        let from = max(start, firstEntry)
        let days = max(28, calendar.dateComponents([.day], from: from, to: end).day ?? 365)
        let months = max(1, Double(days) / 30.44)
        var result: [String: Cents] = [:]
        for item in pnl.income + pnl.expenses {
            let monthly = (Double(item.amount) / months / 100).rounded() * 100
            if monthly > 0 { result[item.account.code] = Int(monthly) }
        }
        return result
    }
}

// MARK: George's checks

struct LedgerCheck: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case duplicateBill, unusualAmount, gstOnWages, missingReceipts, staleBankLines }

    /// Stable, so a dismissed check stays dismissed.
    var id: String
    var kind: Kind
    var title: String
    var detail: String
    /// The bill, bank line or entry it's about, to open.
    var reference: UUID?
}

extension LedgerBook {
    /// Things worth a second look, most important first. Nothing here changes the books.
    func checks(on date: Date) -> [LedgerCheck] {
        var found: [LedgerCheck] = []
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_AU")
        day.dateFormat = "d MMM"

        // The same bill twice: same supplier, same amount, within a fortnight.
        let bills = invoices.filter { $0.kind == .bill && $0.status != .void && !isClaim($0) }.sorted { $0.issued < $1.issued }
        for (index, first) in bills.enumerated() {
            for second in bills[(index + 1)...] where second.contact == first.contact && second.total == first.total {
                let gap = calendar.dateComponents([.day], from: first.issued, to: second.issued).day ?? 99
                guard gap <= 14 else { continue }
                let name = contact(first.contact)?.name ?? "a supplier"
                let one = first.number.isEmpty ? "One" : first.number
                let other = second.number.isEmpty ? "another" : second.number
                let detail = "\(one) on \(day.string(from: first.issued)) and \(other) on \(day.string(from: second.issued)). The same bill entered twice?"
                found.append(LedgerCheck(id: "duplicate:\(first.id):\(second.id)", kind: .duplicateBill,
                                         title: "Two bills from \(name) for \(LedgerMoney.text(first.total))", detail: detail, reference: second.id))
            }
        }

        // Much more than usual for a payee.
        var history: [String: [Cents]] = [:]
        for line in bank.sorted(by: { $0.date < $1.date }) where line.amount < 0 {
            let key = Self.payeeKey(line.description)
            guard !key.isEmpty else { continue }
            let earlier = history[key] ?? []
            if earlier.count >= 3 {
                let sorted = earlier.sorted()
                let usual = sorted[sorted.count / 2]
                if -line.amount > usual * 2, -line.amount - usual > 5_000 {
                    let times = String(format: "%.1f", Double(-line.amount) / Double(max(usual, 1)))
                    let detail = "About \(times) times the usual \(LedgerMoney.text(usual)) (\(day.string(from: line.date))). Worth checking it's right."
                    found.append(LedgerCheck(id: "unusual:\(line.id)", kind: .unusualAmount,
                                             title: "\(line.description.capitalized) was \(LedgerMoney.text(-line.amount))", detail: detail, reference: line.id))
                }
            }
            history[key] = earlier + [-line.amount]
        }

        // Wages and super carry no GST.
        var payroll = Set<String>()
        for account in accounts where account.type == .expense {
            let name = account.name.lowercased()
            if account.code == "477" || account.code == "478" || name.contains("wages") || name.contains("superannuation") { payroll.insert(account.code) }
        }
        for entry in entries where entry.lines.contains(where: { payroll.contains($0.account) && $0.tax?.hasTax == true && $0.taxAmount != 0 }) {
            let detail = "\(entry.memo) (\(day.string(from: entry.date))) claims GST, but wages and super are BAS excluded. Recode it so the BAS is right."
            found.append(LedgerCheck(id: "gstwages:\(entry.id)", kind: .gstOnWages, title: "GST on wages or super", detail: detail, reference: entry.id))
        }

        // Receipts the ATO wants for GST credits.
        let quarter = self.quarter(containing: date)
        let yearStart = financialYearStart(for: date)
        let missing = missingReceipts(from: yearStart, to: date)
        if !missing.isEmpty {
            let gst = gstWaitingOnReceipts(from: yearStart, to: date)
            let thisQuarter = missing.filter { $0.date >= quarter.start }.count
            let need = missing.count == 1 ? "purchase needs its" : "purchases need their"
            let recent = thisQuarter > 0 ? " (\(thisQuarter) this quarter)" : ""
            let detail = "Over $82.50 each, with \(LedgerMoney.text(gst)) of GST claimed this year\(recent). Keep the receipts so the credits stand up."
            found.append(LedgerCheck(id: "receipts:\(missing.count):\(gst)", kind: .missingReceipts,
                                     title: "\(missing.count) \(need) tax invoice", detail: detail, reference: nil))
        }

        // Bank lines left a long time.
        let stale = unreconciled.filter { (calendar.dateComponents([.day], from: $0.date, to: date).day ?? 0) > 30 }
        if !stale.isEmpty {
            let waited = stale.count == 1 ? "line has" : "lines have"
            found.append(LedgerCheck(id: "stale:\(stale.count)", kind: .staleBankLines,
                                     title: "\(stale.count) bank \(waited) waited over a month",
                                     detail: "The reports and BAS leave them out until they're reconciled.", reference: stale.first?.id))
        }
        return found.filter { !dismissedChecks.contains($0.id) }
    }

    mutating func dismissCheck(_ id: String) {
        dismissedChecks.insert(id)
    }
}
