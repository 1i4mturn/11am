import Foundation

// George's money in, finished: quotes that become invoices (whole, or a deposit then the balance), invoices that
// repeat on a schedule, reminders Marc drafts when an invoice is late, and the audit trail behind every change.
// Plain data and arithmetic, tested with the rest of the books.

// MARK: Quotes

struct Quote: Codable, Identifiable, Hashable, Sendable {
    enum Status: String, Codable, CaseIterable, Sendable {
        case draft, sent, accepted, declined, invoiced

        var title: String {
            switch self {
            case .draft: return "Draft"
            case .sent: return "Sent"
            case .accepted: return "Accepted"
            case .declined: return "Declined"
            case .invoiced: return "Invoiced"
            }
        }
    }

    var id = UUID()
    var number: String
    var contact: UUID
    /// What it's for, in a few words: "Annual report design".
    var title = ""
    var issued: Date
    var expires: Date
    var lines: [InvoiceLine]
    var status: Status = .draft
    var notes = ""
    var sentAt: Date?
    /// The share of the quote invoiced each time: [0.5] after a 50% deposit.
    var parts: [Double] = []
    /// The invoices made from it.
    var invoices: [UUID] = []

    var subtotal: Cents { lines.reduce(0) { $0 + $1.net } }
    var tax: Cents { lines.reduce(0) { $0 + $1.tax } }
    var total: Cents { subtotal + tax }
    var invoicedPart: Double { parts.reduce(0, +) }
    var remainingPart: Double { max(0, 1 - invoicedPart) }
    var isOpen: Bool { status == .draft || status == .sent }

    func isExpired(on date: Date, calendar: Calendar) -> Bool {
        isOpen && calendar.startOfDay(for: expires) < calendar.startOfDay(for: date)
    }

    /// "Sent", "Expired", "50% invoiced".
    func statusText(on date: Date, calendar: Calendar) -> String {
        if isExpired(on: date, calendar: calendar) { return "Expired" }
        if status == .accepted, !parts.isEmpty { return "\(Int((invoicedPart * 100).rounded()))% invoiced" }
        return status.title
    }
}

extension LedgerBook {
    func quote(_ id: UUID) -> Quote? { quotes.first { $0.id == id } }

    /// The next quote number, like QU-0007.
    mutating func takeQuoteNumber() -> String {
        let number = settings.nextQuote
        settings.nextQuote += 1
        let digits = String(number)
        return settings.quotePrefix + String(repeating: "0", count: max(0, 4 - digits.count)) + digits
    }

    /// Adds or updates a quote, numbering a new one.
    @discardableResult
    mutating func saveQuote(_ draft: Quote) -> UUID {
        var quote = draft
        if quote.number.isEmpty { quote.number = takeQuoteNumber() }
        let name = contact(quote.contact)?.name ?? ""
        if let index = quotes.firstIndex(where: { $0.id == quote.id }) {
            quotes[index] = quote
            log("Edited quote \(quote.number)", name, amount: quote.total)
        } else {
            quotes.append(quote)
            log("Wrote quote \(quote.number)", name, amount: quote.total)
        }
        return quote.id
    }

    mutating func setQuote(_ id: UUID, status: Quote.Status) {
        guard let index = quotes.firstIndex(where: { $0.id == id }), quotes[index].status != status, quotes[index].status != .invoiced else { return }
        quotes[index].status = status
        if status == .sent, quotes[index].sentAt == nil { quotes[index].sentAt = clock ?? Date() }
        log("Marked quote \(quotes[index].number) \(status.title.lowercased())", contact(quotes[index].contact)?.name ?? "", amount: quotes[index].total)
    }

    mutating func deleteQuote(_ id: UUID) {
        guard let gone = self.quote(id), gone.invoices.isEmpty else { return }
        quotes.removeAll { $0.id == id }
        log("Deleted quote \(gone.number)", contact(gone.contact)?.name ?? "", amount: gone.total)
    }

    /// Turns a quote into an invoice: all of it, or a share (a 50% deposit, say), with the balance worked out to the cent
    /// when the last share is invoiced.
    @discardableResult
    mutating func invoice(fromQuote id: UUID, part: Double? = nil, issued: Date, approve: Bool = false) throws -> UUID {
        guard let index = quotes.firstIndex(where: { $0.id == id }) else { throw LedgerError.notFound }
        var quote = quotes[index]
        let remaining = quote.remainingPart
        guard quote.status != .declined, remaining > 0.0001 else { throw LedgerError.alreadyInvoiced }
        let share = min(max(part ?? remaining, 0.01), remaining)
        let last = share >= remaining - 0.0001
        let percent = Int((share * 100).rounded())
        var lines: [InvoiceLine] = []
        if quote.parts.isEmpty && last {
            lines = quote.lines.map { line in
                var copy = line
                copy.id = UUID()
                return copy
            }
        } else {
            for line in quote.lines {
                let before = quote.parts.reduce(0) { $0 + Self.share(of: line.net, $1) }
                let amount = last ? line.net - before : Self.share(of: line.net, share)
                let description = last ? "\(line.description) (balance of \(quote.number))" : "\(line.description) (\(percent)% of \(quote.number))"
                lines.append(InvoiceLine(description: description, quantity: 1, unitPrice: amount, account: line.account, gst: line.gst))
            }
        }
        let due = calendar.date(byAdding: .day, value: settings.paymentDays, to: issued) ?? issued
        let invoice = Invoice(kind: .sale, number: takeInvoiceNumber(), contact: quote.contact, issued: issued, due: due,
                              reference: quote.title.isEmpty ? quote.number : "\(quote.number) · \(quote.title)", lines: lines)
        invoices.append(invoice)
        quote.parts.append(share)
        quote.invoices.append(invoice.id)
        quote.status = last ? .invoiced : .accepted
        quotes[index] = quote
        log("Invoiced quote \(quote.number)", "\(invoice.number)\(last && quote.parts.count == 1 ? "" : ", \(last ? "the balance" : "\(percent)%")")",
            amount: invoice.total)
        if approve { try self.approve(invoice.id) }
        return invoice.id
    }

    private static func share(of cents: Cents, _ part: Double) -> Cents {
        Int((Double(cents) * part).rounded(.toNearestOrAwayFromZero))
    }

    /// Quotes still waiting on an answer, and what they're worth.
    func openQuotes(on date: Date) -> [Quote] {
        quotes.filter { $0.isOpen && $0.status == .sent && !$0.isExpired(on: date, calendar: calendar) }
    }
}

enum QuoteDocument {
    /// The quote as Markdown, for the PDF.
    static func markdown(_ quote: Quote, contact: Contact?, settings: LedgerSettings) -> String {
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_AU")
        date.dateFormat = "d MMMM yyyy"
        var parts: [String] = ["# Quote \(quote.number)"]
        if !quote.title.isEmpty { parts.append("## \(quote.title)") }
        var from = "**\(settings.businessName)**"
        if !settings.abn.isEmpty { from += "  \nABN \(settings.abn)" }
        if !settings.address.isEmpty { from += "  \n" + settings.address.replacingOccurrences(of: "\n", with: "  \n") }
        if !settings.email.isEmpty { from += "  \n\(settings.email)" }
        parts.append(from)
        var to = "**For:** \(contact?.name ?? "")"
        if let address = contact?.address, !address.isEmpty { to += "  \n" + address.replacingOccurrences(of: "\n", with: "  \n") }
        parts.append(to)
        parts.append("**Date:** \(date.string(from: quote.issued))  \n**Valid until:** \(date.string(from: quote.expires))")
        var table = ["| Description | Qty | Unit price | Amount |", "| --- | ---: | ---: | ---: |"]
        for line in quote.lines {
            let quantity = line.quantity == line.quantity.rounded() ? String(Int(line.quantity)) : String(format: "%.2f", line.quantity)
            table.append("| \(line.description.replacingOccurrences(of: "|", with: "/")) | \(quantity) | \(LedgerMoney.text(line.unitPrice)) | \(LedgerMoney.text(line.net)) |")
        }
        parts.append(table.joined(separator: "\n"))
        var totals = "**Subtotal:** \(LedgerMoney.text(quote.subtotal))  \n"
        if settings.gstRegistered { totals += "**GST:** \(LedgerMoney.text(quote.tax))  \n" }
        totals += "**Total:** \(LedgerMoney.text(quote.total))"
        parts.append(totals)
        if !quote.notes.isEmpty { parts.append(quote.notes) }
        parts.append("To go ahead, reply to say yes and we'll get started.")
        return parts.joined(separator: "\n\n")
    }
}

// MARK: Repeating invoices

struct RepeatingInvoice: Codable, Identifiable, Hashable, Sendable {
    enum Unit: String, Codable, CaseIterable, Sendable { case week, month, year }

    var id = UUID()
    var contact: UUID
    /// Descriptions can say [month] and [year]: "Retainer, [month]" becomes "Retainer, November".
    var lines: [InvoiceLine]
    var reference = ""
    var every = 1
    var unit: Unit = .month
    /// The first invoice's date. Later ones count from it, so the 31st stays the end of the month.
    var start: Date
    var end: Date?
    var dueDays = 14
    /// Approved straight into the books, or left as a draft for you to check.
    var approve = true
    var paused = false
    /// How many it has made.
    var made = 0
    var lastInvoice: UUID?

    var subtotal: Cents { lines.reduce(0) { $0 + $1.net } }
    var total: Cents { subtotal + lines.reduce(0) { $0 + $1.tax } }

    func occurrence(_ n: Int, calendar: Calendar) -> Date {
        let component: Calendar.Component = unit == .week ? .weekOfYear : unit == .month ? .month : .year
        return calendar.date(byAdding: component, value: n * max(1, every), to: start) ?? start
    }

    /// When the next one is made, unless the schedule has ended.
    func next(calendar: Calendar) -> Date? {
        let date = occurrence(made, calendar: calendar)
        if let end, calendar.startOfDay(for: date) > calendar.startOfDay(for: end) { return nil }
        return date
    }

    /// "Every month", "Every 2 weeks".
    var summary: String {
        let name = unit.rawValue
        return every <= 1 ? "Every \(name)" : "Every \(every) \(name)s"
    }

    /// Fills [month], [year] and [week] for the invoice's date.
    static func fill(_ text: String, on date: Date, calendar: Calendar) -> String {
        guard text.contains("[") else { return text }
        let month = DateFormatter()
        month.locale = Locale(identifier: "en_AU")
        month.calendar = calendar
        month.timeZone = calendar.timeZone
        month.dateFormat = "MMMM"
        var result = text
        result = result.replacingOccurrences(of: "[month]", with: month.string(from: date), options: .caseInsensitive)
        result = result.replacingOccurrences(of: "[year]", with: String(calendar.component(.year, from: date)), options: .caseInsensitive)
        result = result.replacingOccurrences(of: "[week]", with: String(calendar.component(.weekOfYear, from: date)), options: .caseInsensitive)
        return result
    }
}

extension LedgerBook {
    func schedule(_ id: UUID) -> RepeatingInvoice? { repeating.first { $0.id == id } }

    @discardableResult
    mutating func saveSchedule(_ schedule: RepeatingInvoice) -> UUID {
        let name = contact(schedule.contact)?.name ?? ""
        if let index = repeating.firstIndex(where: { $0.id == schedule.id }) {
            repeating[index] = schedule
            log("Changed a repeating invoice", "\(name) · \(schedule.summary.lowercased())", amount: schedule.total)
        } else {
            repeating.append(schedule)
            log("Set up a repeating invoice", "\(name) · \(schedule.summary.lowercased())", amount: schedule.total)
        }
        return schedule.id
    }

    mutating func deleteSchedule(_ id: UUID) {
        guard let gone = self.schedule(id) else { return }
        repeating.removeAll { $0.id == id }
        log("Stopped a repeating invoice", contact(gone.contact)?.name ?? "", amount: gone.total)
    }

    /// The same invoice again on a schedule, starting one period after this one.
    @discardableResult
    mutating func repeatInvoice(_ id: UUID, every: Int = 1, unit: RepeatingInvoice.Unit = .month) -> UUID? {
        guard let source = self.invoice(id), source.kind == .sale else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: source.issued), to: calendar.startOfDay(for: source.due)).day ?? settings.paymentDays
        var plan = RepeatingInvoice(contact: source.contact, lines: source.lines.map { line in
            var copy = line
            copy.id = UUID()
            return copy
        }, reference: source.reference, every: every, unit: unit, start: source.issued, dueDays: max(0, days))
        plan.made = 1
        plan.lastInvoice = source.id
        return saveSchedule(plan)
    }

    /// Makes every repeating invoice due by this date, catching up on any missed while the Mac was off. George does it.
    @discardableResult
    mutating func makeRepeatingInvoices(upTo date: Date) -> [UUID] {
        var made: [UUID] = []
        let before = actor
        actor = "George"
        defer { actor = before }
        let last = calendar.startOfDay(for: date)
        for index in repeating.indices where !repeating[index].paused {
            var count = 0
            while let next = repeating[index].next(calendar: calendar), calendar.startOfDay(for: next) <= last, count < 24 {
                let schedule = repeating[index]
                let issued = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: next) ?? next
                let due = calendar.date(byAdding: .day, value: schedule.dueDays, to: issued) ?? issued
                let lines = schedule.lines.map { line in
                    var copy = line
                    copy.id = UUID()
                    copy.description = RepeatingInvoice.fill(line.description, on: issued, calendar: calendar)
                    return copy
                }
                let invoice = Invoice(kind: .sale, number: takeInvoiceNumber(), contact: schedule.contact, issued: issued, due: due,
                                      reference: RepeatingInvoice.fill(schedule.reference, on: issued, calendar: calendar), lines: lines)
                invoices.append(invoice)
                log("Made repeating invoice \(invoice.number)", contact(schedule.contact)?.name ?? "", amount: invoice.total)
                // A locked period leaves it as a draft to look at.
                if schedule.approve { try? approve(invoice.id) }
                repeating[index].made += 1
                repeating[index].lastInvoice = invoice.id
                made.append(invoice.id)
                count += 1
            }
        }
        return made
    }

    /// What's coming in the next few weeks.
    func upcomingRepeats(from date: Date, days: Int) -> [(schedule: RepeatingInvoice, date: Date)] {
        let limit = calendar.date(byAdding: .day, value: days, to: date) ?? date
        return repeating.filter { !$0.paused }.compactMap { schedule in
            schedule.next(calendar: calendar).flatMap { $0 <= limit ? (schedule, $0) : nil }
        }
        .sorted { $0.date < $1.date }
    }
}

// MARK: Overdue reminders

struct ReminderSent: Codable, Hashable, Sendable {
    var invoice: UUID
    var date: Date
    /// Which of the reminder days it answered: 0 is the first, friendly one.
    var stage: Int
    /// You chose not to send it.
    var skipped = false
}

/// A reminder Marc has drafted for an invoice that's late.
struct OverdueReminder: Identifiable, Hashable, Sendable {
    enum Tone: String, Sendable { case friendly, firm, final }

    var invoice: UUID
    var number: String
    var contact: String
    var email: String
    var owing: Cents
    var daysLate: Int
    var stage: Int
    var tone: Tone
    var lastSent: Date?
    var id: UUID { invoice }
}

extension LedgerBook {
    private var reminderStages: [Int] { Array(Set(settings.reminderDays.filter { $0 >= 0 })).sorted() }

    /// Late invoices that are due a reminder today: the tone follows how late they are, never twice at the same stage,
    /// at least five days apart, and not when the payment looks like it's already in the bank.
    func remindersDue(on date: Date) -> [OverdueReminder] {
        let stages = reminderStages
        guard let first = stages.first else { return [] }
        var due: [OverdueReminder] = []
        for invoice in invoices where invoice.kind == .sale && invoice.status == .approved && invoice.owing > 0 {
            let late = invoice.daysOverdue(on: date, calendar: calendar)
            guard late >= first, let stage = stages.lastIndex(where: { late >= $0 }) else { continue }
            let sent = reminders.filter { $0.invoice == invoice.id }
            if let highest = sent.map(\.stage).max(), highest >= stage { continue }
            let lastSent = sent.filter { !$0.skipped }.map(\.date).max()
            if let last = sent.map(\.date).max(),
               (calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: date)).day ?? 0) < 5 { continue }
            if paymentWaiting(for: invoice) != nil { continue }
            let tone: OverdueReminder.Tone = stages.count >= 2 && stage == stages.count - 1 ? .final : stage == 0 ? .friendly : .firm
            let person = contact(invoice.contact)
            due.append(OverdueReminder(invoice: invoice.id, number: invoice.number, contact: person?.name ?? "", email: person?.email ?? "",
                                       owing: invoice.owing, daysLate: late, stage: stage, tone: tone, lastSent: lastSent))
        }
        return due.sorted { $0.daysLate > $1.daysLate }
    }

    /// A bank line not yet reconciled for exactly what's owing, since the invoice was issued: probably the payment.
    func paymentWaiting(for invoice: Invoice) -> BankLine? {
        let incoming = invoice.kind == .sale
        return unreconciled.first { line in
            (incoming ? line.amount : -line.amount) == invoice.owing && calendar.startOfDay(for: line.date) >= calendar.startOfDay(for: invoice.issued)
        }
    }

    /// Late invoices whose payment seems to have arrived: reconcile, don't chase.
    func latePaymentsWaiting(on date: Date) -> [(invoice: Invoice, line: BankLine)] {
        invoices.filter { $0.kind == .sale && $0.owing > 0 && $0.daysOverdue(on: date, calendar: calendar) > 0 }
            .compactMap { invoice in paymentWaiting(for: invoice).map { (invoice, $0) } }
    }

    /// The email Marc drafts, for you to read, change and send.
    func reminderDraft(_ reminder: OverdueReminder) -> (to: String, subject: String, body: String) {
        guard let item = self.invoice(reminder.invoice) else { return (reminder.email, "Invoice \(reminder.number)", "") }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_AU")
        day.dateFormat = "d MMMM"
        let dueText = day.string(from: item.due)
        let number = item.number
        let owing = LedgerMoney.text(item.owing)
        let what = item.paid > 0 ? "the remaining \(owing) on invoice \(number)" : "invoice \(number) for \(owing)"
        let What = what.prefix(1).uppercased() + what.dropFirst()
        let late = "\(reminder.daysLate) \(reminder.daysLate == 1 ? "day" : "days")"
        let greeting = ReminderText.greeting(name: reminder.contact, email: reminder.email)
        var pay = ""
        if !settings.bsb.isEmpty || !settings.accountNumber.isEmpty {
            let name = settings.accountName.isEmpty ? settings.businessName : settings.accountName
            pay = "\n\nTo pay by bank transfer: \(name), BSB \(settings.bsb), account \(settings.accountNumber), with \(number) as the reference."
        }
        let subject: String
        let message: String
        let signOff: String
        switch reminder.tone {
        case .friendly:
            subject = "Reminder: invoice \(number) from \(settings.businessName)"
            message = "A friendly reminder that \(what) was due on \(dueText). If it's already on its way, thank you, and please ignore this."
            signOff = "Thanks,"
        case .firm:
            subject = "Invoice \(number) is \(late) overdue"
            message = "\(What) was due on \(dueText) and is now \(late) overdue. Could you let me know when it will be paid?"
            signOff = "Thanks,"
        case .final:
            subject = "Final reminder: invoice \(number), \(late) overdue"
            message = "\(What) is now \(late) overdue (it was due on \(dueText)). Please pay it this week, or reply and let me know what's holding it up so we can sort it out."
            signOff = "Kind regards,"
        }
        return (reminder.email, subject, "\(greeting)\n\n\(message)\(pay)\n\n\(signOff)\n\(settings.businessName)")
    }

    /// Marc sent (or you skipped) a reminder.
    mutating func noteReminder(_ invoiceID: UUID, stage: Int, skipped: Bool = false, by who: String = "Marc") {
        guard let item = self.invoice(invoiceID) else { return }
        reminders.append(ReminderSent(invoice: invoiceID, date: clock ?? Date(), stage: stage, skipped: skipped))
        log(skipped ? "Skipped a reminder for \(item.number)" : "Sent a reminder for \(item.number)", contact(item.contact)?.name ?? "",
            amount: item.owing, by: skipped ? actor : who)
    }

    /// The unpaid invoice an email's subject is about: "Reminder: invoice INV-0004" → INV-0004.
    func invoiceMentioned(inSubject subject: String) -> UUID? {
        let lower = subject.lowercased()
        let owing = invoices.filter { $0.kind == .sale && $0.owing > 0 && !$0.number.isEmpty }.sorted { $0.number.count > $1.number.count }
        for invoice in owing {
            guard let range = lower.range(of: invoice.number.lowercased()) else { continue }
            if range.upperBound < lower.endIndex, lower[range.upperBound].isNumber { continue }
            return invoice.id
        }
        return nil
    }

    /// How many reminders have gone for an invoice.
    func remindersSent(for invoiceID: UUID) -> [ReminderSent] {
        reminders.filter { $0.invoice == invoiceID && !$0.skipped }.sorted { $0.date < $1.date }
    }
}

enum ReminderText {
    private static let shared: Set<String> = ["accounts", "account", "ap", "ar", "billing", "finance", "info", "hello", "admin", "office", "team",
                                              "payables", "invoices", "contact", "enquiries", "sales", "support", "mail", "studio", "receivables"]
    private static let business = ["pty", "ltd", "inc", "llc", "co", "company", "studio", "group", "health", "traders", "trust", "partners",
                                   "accounting", "design", "media", "labs", "agency", "services", "consulting", "holdings", "the"]

    /// "Hi Tom," from tom@acme.co or a person's name; "Hi there," for accounts@ and company names.
    static func greeting(name: String, email: String) -> String {
        let local = email.split(separator: "@").first.map(String.init) ?? ""
        let word = local.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" }).first.map(String.init) ?? ""
        if word.count > 1, word.allSatisfy(\.isLetter), !shared.contains(word.lowercased()) {
            return "Hi \(word.prefix(1).uppercased() + word.dropFirst().lowercased()),"
        }
        let words = name.split(separator: " ").map(String.init)
        if (1...3).contains(words.count), !words.contains(where: { business.contains($0.lowercased().trimmingCharacters(in: .punctuationCharacters)) }),
           let first = words.first, first.count > 1, first.allSatisfy(\.isLetter) {
            return "Hi \(first),"
        }
        return "Hi there,"
    }
}

// MARK: Audit trail

struct AuditEvent: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var date: Date
    /// You, George or Marc.
    var by: String
    var action: String
    var detail = ""
    var amount: Cents?
}

extension LedgerBook {
    /// Notes a change made by someone other than whoever is acting now.
    mutating func log(_ action: String, _ detail: String = "", amount: Cents? = nil, by who: String) {
        audit.append(AuditEvent(date: clock ?? Date(), by: who, action: action, detail: detail, amount: amount))
    }

    /// The trail, newest first, narrowed by words.
    func auditTrail(matching text: String = "") -> [AuditEvent] {
        let words = text.lowercased().split(separator: " ").map(String.init)
        // Newest first; changes made in the same instant keep the order they happened in.
        return audit.enumerated().filter { item in
            let haystack = "\(item.element.by) \(item.element.action) \(item.element.detail)".lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
        .sorted { $0.element.date != $1.element.date ? $0.element.date > $1.element.date : $0.offset > $1.offset }
        .map(\.element)
    }
}
