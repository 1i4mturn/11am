import Foundation

/// George's books: double-entry, in cents, with Australian GST. Everything here is plain data and arithmetic,
/// so it can be tested without the app.
typealias Cents = Int

// MARK: Money

enum LedgerMoney {
    static func cents(_ dollars: Double) -> Cents { Int((dollars * 100).rounded(.toNearestOrAwayFromZero)) }
    static func dollars(_ cents: Cents) -> Double { Double(cents) / 100 }

    /// "$1,234.50" and "−$80.00".
    static func text(_ cents: Cents, symbol: Bool = true) -> String {
        let magnitude = abs(cents)
        let whole = String(magnitude / 100)
        var grouped = ""
        for (index, character) in whole.reversed().enumerated() {
            if index > 0 && index % 3 == 0 { grouped.append(",") }
            grouped.append(character)
        }
        let fraction = magnitude % 100
        let body = String(grouped.reversed()) + "." + (fraction < 10 ? "0" : "") + String(fraction)
        return (cents < 0 ? "−" : "") + (symbol ? "$" : "") + body
    }

    /// Whole dollars, as the BAS wants them (cents dropped).
    static func wholeDollars(_ cents: Cents) -> Int { cents / 100 }

    /// "$1,234.50", "-12", "(45.00)", "45.00 DR", "1 234,50".
    static func parse(_ text: String) -> Cents? {
        var value = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard !value.isEmpty else { return nil }
        var negative = false
        if value.hasSuffix("DR") { negative = true; value = String(value.dropLast(2)) }
        if value.hasSuffix("CR") { value = String(value.dropLast(2)) }
        value = value.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("(") && value.hasSuffix(")") { negative.toggle(); value = String(value.dropFirst().dropLast()) }
        if value.hasPrefix("-") || value.hasPrefix("−") { negative.toggle(); value = String(value.dropFirst()) }
        if value.hasSuffix("-") { negative.toggle(); value = String(value.dropLast()) }
        // "1 234,50" (comma as the decimal point, no dot) becomes 1234.50.
        if !value.contains("."), let comma = value.lastIndex(of: ","), value.distance(from: comma, to: value.endIndex) == 3 {
            value.replaceSubrange(comma...comma, with: ".")
        }
        value = value.filter { $0.isNumber || $0 == "." }
        guard !value.isEmpty, let number = Double(value) else { return nil }
        return cents(negative ? -number : number)
    }
}

// MARK: GST

enum GSTCode: String, Codable, CaseIterable, Identifiable, Sendable {
    /// 10% GST on sales or purchases.
    case gst
    /// GST-free: most food, health, education, exports, bank fees.
    case free
    /// Input-taxed: residential rent, interest and other financial supplies.
    case input
    /// A purchase of equipment or other capital, with GST.
    case capital
    /// Not on the BAS at all: wages, super, transfers, owner's money.
    case excluded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gst: return "GST 10%"
        case .free: return "GST free"
        case .input: return "Input taxed"
        case .capital: return "Capital, GST"
        case .excluded: return "BAS excluded"
        }
    }

    var hasTax: Bool { self == .gst || self == .capital }
}

enum GST {
    /// The GST inside a GST-inclusive amount: one eleventh, to the nearest cent.
    static func included(in gross: Cents, _ code: GSTCode) -> Cents { code.hasTax ? divide(gross, 11) : 0 }

    /// The GST on top of a GST-exclusive amount.
    static func added(to net: Cents, _ code: GSTCode) -> Cents { code.hasTax ? divide(net, 10) : 0 }

    private static func divide(_ value: Int, _ by: Int) -> Int {
        Int((Double(value) / Double(by)).rounded(.toNearestOrAwayFromZero))
    }
}

// MARK: Accounts

enum AccountType: String, Codable, CaseIterable, Identifiable, Sendable {
    case asset, liability, equity, income, expense

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    /// Assets and expenses grow with debits; the rest with credits.
    var debitNormal: Bool { self == .asset || self == .expense }
}

struct LedgerAccount: Codable, Identifiable, Hashable, Sendable {
    enum Role: String, Codable, Sendable { case receivables, payables, gst, equity }

    var code: String
    var name: String
    var type: AccountType
    /// The GST code new transactions in this account start with.
    var gst: GSTCode
    var isBank = false
    var role: Role?

    var id: String { code }
    var label: String { "\(code) · \(name)" }
}

extension LedgerAccount {
    private static func make(_ code: String, _ name: String, _ type: AccountType, _ gst: GSTCode, bank: Bool = false, role: Role? = nil) -> LedgerAccount {
        LedgerAccount(code: code, name: name, type: type, gst: gst, isBank: bank, role: role)
    }

    /// A small business chart of accounts for Australia.
    static let australian: [LedgerAccount] = [
        make("090", "Business account", .asset, .excluded, bank: true),
        make("091", "Savings account", .asset, .excluded, bank: true),
        make("610", "Accounts receivable", .asset, .excluded, role: .receivables),
        make("620", "Prepayments", .asset, .excluded),
        make("710", "Office equipment", .asset, .capital),
        make("720", "Computer equipment", .asset, .capital),
        make("800", "Accounts payable", .liability, .excluded, role: .payables),
        make("810", "Business credit card", .liability, .excluded, bank: true),
        make("820", "GST", .liability, .excluded, role: .gst),
        make("825", "PAYG withholding payable", .liability, .excluded),
        make("826", "Superannuation payable", .liability, .excluded),
        make("880", "Owner funds introduced", .equity, .excluded, role: .equity),
        make("881", "Owner drawings", .equity, .excluded),
        make("960", "Retained earnings", .equity, .excluded),
        make("200", "Sales", .income, .gst),
        make("260", "Other income", .income, .gst),
        make("270", "Interest income", .income, .input),
        make("310", "Cost of goods sold", .expense, .gst),
        make("400", "Advertising", .expense, .gst),
        make("404", "Bank fees", .expense, .free),
        make("408", "Cleaning", .expense, .gst),
        make("410", "Contractors", .expense, .gst),
        make("412", "Accounting and legal", .expense, .gst),
        make("420", "Entertainment", .expense, .gst),
        make("429", "General expenses", .expense, .gst),
        make("433", "Insurance", .expense, .gst),
        make("445", "Electricity and gas", .expense, .gst),
        make("449", "Motor vehicle", .expense, .gst),
        make("453", "Office supplies", .expense, .gst),
        make("469", "Rent", .expense, .gst),
        make("473", "Repairs and maintenance", .expense, .gst),
        make("477", "Wages and salaries", .expense, .excluded),
        make("478", "Superannuation", .expense, .excluded),
        make("485", "Software and subscriptions", .expense, .gst),
        make("489", "Phone and internet", .expense, .gst),
        make("493", "Travel, domestic", .expense, .gst),
        make("494", "Travel, overseas", .expense, .free),
    ]
}

// MARK: The journal

struct JournalLine: Codable, Hashable, Sendable {
    var account: String
    /// Debits are positive, credits negative.
    var amount: Cents
    var tax: GSTCode?
    /// The GST that belongs with this line, signed like `amount` (so a sale's GST is negative too).
    var taxAmount: Cents = 0
    var memo = ""
}

struct JournalEntry: Codable, Identifiable, Hashable, Sendable {
    enum Source: String, Codable, Sendable { case bank, invoice, bill, payment, manual, transfer, opening }

    var id = UUID()
    var date: Date
    var memo: String
    var source: Source
    /// The invoice, bill or bank line it came from.
    var reference: UUID?
    var lines: [JournalLine]

    var isBalanced: Bool { lines.reduce(0) { $0 + $1.amount } == 0 }
}

// MARK: People, invoices and bills

struct Contact: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var email = ""
    var abn = ""
    var address = ""
    var phone = ""
}

struct InvoiceLine: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var description: String
    var quantity: Double = 1
    /// Before GST.
    var unitPrice: Cents
    var account: String
    var gst: GSTCode

    var net: Cents { Int((Double(unitPrice) * quantity).rounded(.toNearestOrAwayFromZero)) }
    var tax: Cents { GST.added(to: net, gst) }
}

struct Payment: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var date: Date
    var amount: Cents
    var bankAccount: String
    var entry: UUID?
}

struct Invoice: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case sale, bill }
    enum Status: String, Codable, Sendable {
        case draft, approved, paid, void

        var title: String {
            switch self {
            case .draft: return "Draft"
            case .approved: return "Awaiting payment"
            case .paid: return "Paid"
            case .void: return "Void"
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var number: String
    var contact: UUID
    var issued: Date
    var due: Date
    var reference = ""
    var lines: [InvoiceLine]
    var status: Status = .draft
    var payments: [Payment] = []
    var notes = ""
    var entry: UUID?
    var sentAt: Date?

    var subtotal: Cents { lines.reduce(0) { $0 + $1.net } }
    var tax: Cents { lines.reduce(0) { $0 + $1.tax } }
    var total: Cents { subtotal + tax }
    var paid: Cents { payments.reduce(0) { $0 + $1.amount } }
    var owing: Cents { status == .void || status == .draft ? 0 : max(0, total - paid) }

    func daysOverdue(on date: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: due), end = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}

// MARK: The bank feed

struct BankLine: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var account: String
    var date: Date
    var description: String
    /// Money in is positive.
    var amount: Cents
    /// The bank's own id for the line (OFX FITID), for spotting duplicates.
    var bankID: String?
    /// The journal entry that accounts for it, once reconciled.
    var entry: UUID?

    var isReconciled: Bool { entry != nil }
}

/// What George learned from how you coded a payee before.
struct CodingRule: Codable, Hashable, Sendable {
    var account: String
    var gst: GSTCode
    var count: Int
}

struct LedgerSettings: Codable, Hashable, Sendable {
    var businessName = "Your business"
    var abn = ""
    var email = ""
    var address = ""
    var bsb = ""
    var accountNumber = ""
    var accountName = ""
    var gstRegistered = true
    /// Cash basis counts GST when money moves; accrual when invoices and bills are dated.
    var cashBasis = false
    var invoicePrefix = "INV-"
    var nextInvoice = 1
    var paymentDays = 14
    var quotePrefix = "QU-"
    var nextQuote = 1
    /// How long a quote stands.
    var quoteDays = 30
    /// Nothing dated on or before this can be added, changed or removed. Lock a quarter once its BAS is in.
    var lockDate: Date?
    /// Days after the due date Marc drafts a reminder: friendly, then firmer, then a final one.
    var reminderDays = [3, 14, 30]

    init() {}
}

extension LedgerSettings {
    /// Tolerant of fields added in later versions.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        businessName = try c.decodeIfPresent(String.self, forKey: .businessName) ?? businessName
        abn = try c.decodeIfPresent(String.self, forKey: .abn) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        bsb = try c.decodeIfPresent(String.self, forKey: .bsb) ?? ""
        accountNumber = try c.decodeIfPresent(String.self, forKey: .accountNumber) ?? ""
        accountName = try c.decodeIfPresent(String.self, forKey: .accountName) ?? ""
        gstRegistered = try c.decodeIfPresent(Bool.self, forKey: .gstRegistered) ?? true
        cashBasis = try c.decodeIfPresent(Bool.self, forKey: .cashBasis) ?? false
        invoicePrefix = try c.decodeIfPresent(String.self, forKey: .invoicePrefix) ?? invoicePrefix
        nextInvoice = try c.decodeIfPresent(Int.self, forKey: .nextInvoice) ?? 1
        paymentDays = try c.decodeIfPresent(Int.self, forKey: .paymentDays) ?? 14
        quotePrefix = try c.decodeIfPresent(String.self, forKey: .quotePrefix) ?? quotePrefix
        nextQuote = try c.decodeIfPresent(Int.self, forKey: .nextQuote) ?? 1
        quoteDays = try c.decodeIfPresent(Int.self, forKey: .quoteDays) ?? 30
        lockDate = try c.decodeIfPresent(Date.self, forKey: .lockDate)
        reminderDays = try c.decodeIfPresent([Int].self, forKey: .reminderDays) ?? reminderDays
    }
}

// MARK: Reports

struct AccountAmount: Identifiable, Hashable, Sendable {
    var account: LedgerAccount
    var amount: Cents
    var id: String { account.code }
}

struct ProfitAndLoss: Sendable {
    var income: [AccountAmount]
    var expenses: [AccountAmount]
    var totalIncome: Cents { income.reduce(0) { $0 + $1.amount } }
    var totalExpenses: Cents { expenses.reduce(0) { $0 + $1.amount } }
    var net: Cents { totalIncome - totalExpenses }
}

struct BalanceSheet: Sendable {
    var assets: [AccountAmount]
    var liabilities: [AccountAmount]
    var equity: [AccountAmount]
    /// Profit since the start of this financial year.
    var currentEarnings: Cents
    /// Profit from earlier years not yet moved into retained earnings.
    var earlierEarnings: Cents
    var totalAssets: Cents { assets.reduce(0) { $0 + $1.amount } }
    var totalLiabilities: Cents { liabilities.reduce(0) { $0 + $1.amount } }
    var totalEquity: Cents { equity.reduce(0) { $0 + $1.amount } + currentEarnings + earlierEarnings }
    var balances: Bool { totalAssets == totalLiabilities + totalEquity }
}

struct TrialBalanceRow: Identifiable, Hashable, Sendable {
    var account: LedgerAccount
    var debit: Cents
    var credit: Cents
    var id: String { account.code }
}

struct AgedRow: Identifiable, Hashable, Sendable {
    var contact: Contact
    /// Current, 1–30, 31–60, 61–90 and over 90 days past due.
    var buckets: [Cents]
    var id: UUID { contact.id }
    var total: Cents { buckets.reduce(0, +) }

    static let titles = ["Current", "1–30 days", "31–60 days", "61–90 days", "Older"]
}

/// The GST figures for a Business Activity Statement.
struct BASFigures: Equatable, Sendable {
    /// G1: total sales, including GST.
    var totalSales: Cents = 0
    /// G3: GST-free sales.
    var gstFreeSales: Cents = 0
    /// G10: capital purchases, including GST.
    var capitalPurchases: Cents = 0
    /// G11: other purchases, including GST.
    var otherPurchases: Cents = 0
    /// 1A: GST on sales.
    var gstOnSales: Cents = 0
    /// 1B: GST on purchases.
    var gstOnPurchases: Cents = 0

    /// Positive means you pay the ATO; negative is a refund.
    var net: Cents { gstOnSales - gstOnPurchases }
}

struct CashRow: Identifiable, Hashable, Sendable {
    var account: LedgerAccount
    var opening: Cents
    var moneyIn: Cents
    var moneyOut: Cents
    var closing: Cents { opening + moneyIn - moneyOut }
    var id: String { account.code }
}

enum LedgerError: LocalizedError, Equatable {
    case unbalanced, missingAccount(String), notFound, alreadyReconciled, nothingOwing, notApproved, locked(Date), alreadyInvoiced

    var errorDescription: String? {
        switch self {
        case .unbalanced: return "The entry doesn't balance."
        case .missingAccount(let code): return "There's no account \(code)."
        case .notFound: return "That couldn't be found."
        case .alreadyReconciled: return "That bank line is already reconciled."
        case .nothingOwing: return "Nothing is owing on it."
        case .notApproved: return "Approve it first."
        case .locked(let date):
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMMM yyyy"
            return "The books are locked up to \(formatter.string(from: date)). Change the lock date in Settings to change anything before it."
        case .alreadyInvoiced: return "That quote has been invoiced in full."
        }
    }
}

/// What George suggests for an unreconciled bank line.
enum BankSuggestion: Equatable {
    /// A payment against this invoice or bill.
    case invoice(UUID)
    /// Code it the way this payee was coded before.
    case rule(account: String, gst: GSTCode, times: Int)
    /// A transfer between your own accounts.
    case transfer(account: String)
}

// MARK: The book

struct LedgerBook: Codable, Sendable {
    var settings = LedgerSettings()
    var accounts: [LedgerAccount] = LedgerAccount.australian
    var contacts: [Contact] = []
    var entries: [JournalEntry] = []
    var bank: [BankLine] = []
    var invoices: [Invoice] = []
    var rules: [String: CodingRule] = [:]
    var quotes: [Quote] = []
    var repeating: [RepeatingInvoice] = []
    var reminders: [ReminderSent] = []
    /// Every change, newest last: who, what and when.
    var audit: [AuditEvent] = []
    var receipts: [LedgerReceipt] = []
    /// Monthly budgets by account code.
    var budgets: [String: Cents] = [:]
    /// George's checks you've said are fine.
    var dismissedChecks: Set<String> = []
    /// Who's making changes right now, for the audit trail. Not saved.
    var actor = "You"
    /// The time changes are stamped with; nil is now. Not saved (the samples use it to backdate).
    var clock: Date?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case settings, accounts, contacts, entries, bank, invoices, rules, quotes, repeating, reminders, audit, receipts, budgets, dismissedChecks
    }

    /// Tolerant of parts added in later versions.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = try c.decodeIfPresent(LedgerSettings.self, forKey: .settings) ?? LedgerSettings()
        accounts = try c.decodeIfPresent([LedgerAccount].self, forKey: .accounts) ?? LedgerAccount.australian
        contacts = try c.decodeIfPresent([Contact].self, forKey: .contacts) ?? []
        entries = try c.decodeIfPresent([JournalEntry].self, forKey: .entries) ?? []
        bank = try c.decodeIfPresent([BankLine].self, forKey: .bank) ?? []
        invoices = try c.decodeIfPresent([Invoice].self, forKey: .invoices) ?? []
        rules = try c.decodeIfPresent([String: CodingRule].self, forKey: .rules) ?? [:]
        quotes = (try? c.decodeIfPresent([Quote].self, forKey: .quotes)) ?? []
        repeating = (try? c.decodeIfPresent([RepeatingInvoice].self, forKey: .repeating)) ?? []
        reminders = (try? c.decodeIfPresent([ReminderSent].self, forKey: .reminders)) ?? []
        audit = (try? c.decodeIfPresent([AuditEvent].self, forKey: .audit)) ?? []
        receipts = (try? c.decodeIfPresent([LedgerReceipt].self, forKey: .receipts)) ?? []
        budgets = (try? c.decodeIfPresent([String: Cents].self, forKey: .budgets)) ?? [:]
        dismissedChecks = (try? c.decodeIfPresent(Set<String>.self, forKey: .dismissedChecks)) ?? []
    }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    func account(_ code: String) -> LedgerAccount? { accounts.first { $0.code == code } }
    func contact(_ id: UUID) -> Contact? { contacts.first { $0.id == id } }
    func invoice(_ id: UUID) -> Invoice? { invoices.first { $0.id == id } }

    func code(for role: LedgerAccount.Role) -> String {
        accounts.first { $0.role == role }?.code ?? {
            switch role {
            case .receivables: return "610"
            case .payables: return "800"
            case .gst: return "820"
            case .equity: return "880"
            }
        }()
    }

    var bankAccounts: [LedgerAccount] { accounts.filter(\.isBank) }

    // MARK: Posting

    @discardableResult
    mutating func post(_ entry: JournalEntry) throws -> UUID {
        guard entry.isBalanced else { throw LedgerError.unbalanced }
        if let lock = settings.lockDate, isLocked(entry.date) { throw LedgerError.locked(lock) }
        for line in entry.lines where account(line.account) == nil { throw LedgerError.missingAccount(line.account) }
        entries.append(entry)
        return entry.id
    }

    mutating func removeEntry(_ id: UUID?) {
        guard let id else { return }
        entries.removeAll { $0.id == id }
    }

    // MARK: Lock date and audit trail

    /// On or before the lock date.
    func isLocked(_ date: Date) -> Bool {
        guard let lock = settings.lockDate else { return false }
        return calendar.startOfDay(for: date) <= calendar.startOfDay(for: lock)
    }

    private func checkUnlocked(_ entryIDs: [UUID?]) throws {
        guard let lock = settings.lockDate else { return }
        for id in entryIDs.compactMap({ $0 }) {
            if let entry = entries.first(where: { $0.id == id }), isLocked(entry.date) { throw LedgerError.locked(lock) }
        }
    }

    /// Locks the books up to a date (nil unlocks them), and notes it.
    mutating func setLockDate(_ date: Date?) {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM yyyy"
        settings.lockDate = date.map { calendar.date(bySettingHour: 12, minute: 0, second: 0, of: $0) ?? $0 }
        log(date == nil ? "Unlocked the books" : "Locked the books", date.map { "Up to \(formatter.string(from: $0))" } ?? "")
    }

    mutating func log(_ action: String, _ detail: String = "", amount: Cents? = nil) {
        audit.append(AuditEvent(date: clock ?? Date(), by: actor, action: action, detail: detail, amount: amount))
    }

    /// The next invoice number, like INV-0042.
    mutating func takeInvoiceNumber() -> String {
        let number = settings.nextInvoice
        settings.nextInvoice += 1
        let digits = String(number)
        return settings.invoicePrefix + String(repeating: "0", count: max(0, 4 - digits.count)) + digits
    }

    /// Approving an invoice or bill puts it in the books: what's owed, the income or expense, and the GST.
    mutating func approve(_ id: UUID) throws {
        guard let index = invoices.firstIndex(where: { $0.id == id }) else { throw LedgerError.notFound }
        var invoice = invoices[index]
        guard invoice.status == .draft else { return }
        let sale = invoice.kind == .sale
        let gstAccount = code(for: .gst)
        var lines: [JournalLine] = []
        let control = JournalLine(account: code(for: sale ? .receivables : .payables), amount: sale ? invoice.total : -invoice.total,
                                  memo: invoice.number)
        lines.append(control)
        var gstTotal = 0
        for item in invoice.lines {
            let tax = settings.gstRegistered ? item.tax : 0
            let taxCode: GSTCode = settings.gstRegistered ? item.gst : .excluded
            gstTotal += tax
            lines.append(JournalLine(account: item.account, amount: sale ? -item.net : item.net, tax: taxCode, taxAmount: sale ? -tax : tax,
                                     memo: item.description))
        }
        // Without GST registration the totals still include no GST.
        if gstTotal != 0 { lines.append(JournalLine(account: gstAccount, amount: sale ? -gstTotal : gstTotal, memo: "GST \(invoice.number)")) }
        let difference = lines.reduce(0) { $0 + $1.amount }
        if difference != 0 { lines[0].amount -= difference }
        let entry = JournalEntry(date: invoice.issued, memo: "\(sale ? "Invoice" : "Bill") \(invoice.number) · \(contact(invoice.contact)?.name ?? "")",
                                 source: sale ? .invoice : .bill, reference: invoice.id, lines: lines)
        invoice.entry = try post(entry)
        invoice.status = .approved
        invoices[index] = invoice
        log("Approved \(sale ? "invoice" : "bill") \(invoice.number)", contact(invoice.contact)?.name ?? "", amount: invoice.total)
    }

    /// Voiding takes it back out of the books (and any payments with it).
    mutating func void(_ id: UUID) throws {
        guard let index = invoices.firstIndex(where: { $0.id == id }) else { return }
        try checkUnlocked([invoices[index].entry] + invoices[index].payments.map(\.entry))
        let total = invoices[index].total
        log("Voided \(invoices[index].kind == .sale ? "invoice" : "bill") \(invoices[index].number)", contact(invoices[index].contact)?.name ?? "", amount: total)
        removeEntry(invoices[index].entry)
        for payment in invoices[index].payments {
            removeEntry(payment.entry)
            for line in bank.indices where bank[line].entry == payment.entry { bank[line].entry = nil }
        }
        invoices[index].payments = []
        invoices[index].entry = nil
        invoices[index].status = .void
    }

    /// Money received for an invoice, or paid on a bill.
    @discardableResult
    mutating func recordPayment(_ id: UUID, amount: Cents, date: Date, bankAccount: String, bankLine: UUID? = nil) throws -> UUID {
        guard let index = invoices.firstIndex(where: { $0.id == id }) else { throw LedgerError.notFound }
        guard invoices[index].status == .approved else { throw invoices[index].status == .draft ? LedgerError.notApproved : LedgerError.nothingOwing }
        guard amount > 0, amount <= invoices[index].owing else { throw LedgerError.nothingOwing }
        let invoice = invoices[index]
        let sale = invoice.kind == .sale
        let control = code(for: sale ? .receivables : .payables)
        let entry = JournalEntry(date: date, memo: "\(sale ? "Payment for" : "Paid") \(invoice.number) · \(contact(invoice.contact)?.name ?? "")",
                                 source: .payment, reference: bankLine ?? invoice.id, lines: [
                                    JournalLine(account: bankAccount, amount: sale ? amount : -amount),
                                    JournalLine(account: control, amount: sale ? -amount : amount),
                                 ])
        let entryID = try post(entry)
        invoices[index].payments.append(Payment(date: date, amount: amount, bankAccount: bankAccount, entry: entryID))
        if invoices[index].owing == 0 { invoices[index].status = .paid }
        log("\(sale ? "Payment received for" : "Paid") \(invoice.number)", contact(invoice.contact)?.name ?? "", amount: amount)
        return entryID
    }

    // MARK: Bank reconciliation

    /// Adds statement lines, skipping ones already here. Returns how many were new.
    @discardableResult
    mutating func importStatement(_ lines: [BankLine]) -> (added: Int, duplicates: Int) {
        var added = 0, duplicates = 0
        var seenIDs = Set(bank.compactMap(\.bankID))
        var seenKeys = Set(bank.map(Self.duplicateKey))
        for line in lines {
            if let id = line.bankID, seenIDs.contains(id) { duplicates += 1; continue }
            let key = Self.duplicateKey(line)
            if line.bankID == nil && seenKeys.contains(key) { duplicates += 1; continue }
            bank.append(line)
            if let id = line.bankID { seenIDs.insert(id) }
            seenKeys.insert(key)
            added += 1
        }
        bank.sort { $0.date < $1.date }
        if added > 0 { log("Imported a bank statement", "\(added) new \(added == 1 ? "line" : "lines")\(duplicates > 0 ? ", \(duplicates) already here" : "")") }
        return (added, duplicates)
    }

    private static func duplicateKey(_ line: BankLine) -> String {
        "\(line.account)|\(Int(line.date.timeIntervalSince1970 / 86_400))|\(line.amount)|\(line.description.lowercased())"
    }

    /// Codes a bank line straight to an account, splitting out the GST, and remembers it for that payee.
    @discardableResult
    mutating func code(_ lineID: UUID, account code: String, gst: GSTCode, memo: String? = nil, learn: Bool = true) throws -> UUID {
        guard let index = bank.firstIndex(where: { $0.id == lineID }) else { throw LedgerError.notFound }
        guard !bank[index].isReconciled else { throw LedgerError.alreadyReconciled }
        guard account(code) != nil else { throw LedgerError.missingAccount(code) }
        let line = bank[index]
        let taxCode: GSTCode = settings.gstRegistered ? gst : .excluded
        let gross = line.amount
        let tax = GST.included(in: abs(gross), taxCode) * (gross < 0 ? 1 : -1)
        // Money out: debit the expense (net) and GST, credit the bank. Money in: the reverse.
        let net = -gross - tax
        var lines = [JournalLine(account: line.account, amount: gross)]
        lines.append(JournalLine(account: code, amount: net, tax: taxCode, taxAmount: tax, memo: memo ?? line.description))
        if tax != 0 { lines.append(JournalLine(account: self.code(for: .gst), amount: tax, memo: "GST")) }
        let entry = JournalEntry(date: line.date, memo: memo ?? line.description, source: .bank, reference: line.id, lines: lines)
        let id = try post(entry)
        bank[index].entry = id
        log("Coded a bank line to \(account(code)?.name ?? code)", line.description, amount: gross)
        if learn {
            let key = Self.payeeKey(line.description)
            if !key.isEmpty {
                let count = (rules[key]?.account == code ? rules[key]?.count ?? 0 : 0) + 1
                rules[key] = CodingRule(account: code, gst: gst, count: count)
            }
        }
        return id
    }

    /// Reconciles a bank line as the payment of an invoice or bill.
    @discardableResult
    mutating func match(_ lineID: UUID, invoice invoiceID: UUID) throws -> UUID {
        guard let index = bank.firstIndex(where: { $0.id == lineID }) else { throw LedgerError.notFound }
        guard !bank[index].isReconciled else { throw LedgerError.alreadyReconciled }
        let line = bank[index]
        let id = try recordPayment(invoiceID, amount: abs(line.amount), date: line.date, bankAccount: line.account, bankLine: line.id)
        bank[index].entry = id
        return id
    }

    /// Money moved between two of your own accounts.
    @discardableResult
    mutating func transfer(_ lineID: UUID, to other: String) throws -> UUID {
        guard let index = bank.firstIndex(where: { $0.id == lineID }) else { throw LedgerError.notFound }
        guard !bank[index].isReconciled else { throw LedgerError.alreadyReconciled }
        let line = bank[index]
        let entry = JournalEntry(date: line.date, memo: "Transfer · \(line.description)", source: .transfer, reference: line.id, lines: [
            JournalLine(account: line.account, amount: line.amount),
            JournalLine(account: other, amount: -line.amount),
        ])
        let id = try post(entry)
        bank[index].entry = id
        log("Recorded a transfer to \(account(other)?.name ?? other)", line.description, amount: line.amount)
        // The same transfer seen from the other account reconciles against the same entry.
        if let twin = bank.firstIndex(where: { $0.account == other && !$0.isReconciled && $0.amount == -line.amount
            && abs($0.date.timeIntervalSince(line.date)) < 4 * 86_400 }) {
            bank[twin].entry = id
        }
        return id
    }

    /// Takes a bank line's entry back out, so it can be coded again.
    mutating func unreconcile(_ lineID: UUID) throws {
        guard let index = bank.firstIndex(where: { $0.id == lineID }), let entryID = bank[index].entry else { return }
        try checkUnlocked([entryID])
        log("Undid a reconciliation", bank[index].description, amount: bank[index].amount)
        for invoice in invoices.indices {
            if let payment = invoices[invoice].payments.firstIndex(where: { $0.entry == entryID }) {
                invoices[invoice].payments.remove(at: payment)
                if invoices[invoice].status == .paid { invoices[invoice].status = .approved }
            }
        }
        removeEntry(entryID)
        for other in bank.indices where bank[other].entry == entryID { bank[other].entry = nil }
    }

    /// The two words that identify a payee: "AWS EMEA 1234 Sydney" and "AWS EMEA 9876" both become "aws emea".
    static func payeeKey(_ description: String) -> String {
        description.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && $0.rangeOfCharacter(from: .decimalDigits) == nil && !["pty", "ltd", "the", "card", "visa", "eftpos", "pos", "aus", "au"].contains($0) }
            .prefix(2)
            .joined(separator: " ")
    }

    func suggestion(for line: BankLine) -> BankSuggestion? {
        guard !line.isReconciled else { return nil }
        let wanted: Invoice.Kind = line.amount > 0 ? .sale : .bill
        let open = invoices.filter { $0.kind == wanted && $0.status == .approved && $0.owing == abs(line.amount) }
        let text = line.description.lowercased()
        if let named = open.first(where: { invoice in
            if text.contains(invoice.number.lowercased()) { return true }
            guard let name = contact(invoice.contact).map({ Self.payeeKey($0.name) }), let word = name.components(separatedBy: " ").first,
                  !word.isEmpty else { return false }
            return text.contains(word)
        }) {
            return .invoice(named.id)
        }
        if open.count == 1, let only = open.first { return .invoice(only.id) }
        if let rule = rules[Self.payeeKey(line.description)] { return .rule(account: rule.account, gst: rule.gst, times: rule.count) }
        if text.contains("transfer"), let other = bank.first(where: { $0.account != line.account && $0.amount == -line.amount
            && abs($0.date.timeIntervalSince(line.date)) < 4 * 86_400 }) {
            return .transfer(account: other.account)
        }
        return nil
    }

    // MARK: Balances

    /// Each account's balance from its entries, debit-positive, between two dates (inclusive of whole days).
    func balances(from start: Date? = nil, to end: Date) -> [String: Cents] {
        let last = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        let first = start.map { calendar.startOfDay(for: $0) }
        var totals: [String: Cents] = [:]
        for entry in entries where entry.date < last && (first.map { entry.date >= $0 } ?? true) {
            for line in entry.lines { totals[line.account, default: 0] += line.amount }
        }
        return totals
    }

    /// 1 July before (or on) the date: the Australian financial year.
    func financialYearStart(for date: Date) -> Date {
        let parts = calendar.dateComponents([.year, .month], from: date)
        let year = (parts.month ?? 1) >= 7 ? (parts.year ?? 2000) : (parts.year ?? 2000) - 1
        return calendar.date(from: DateComponents(year: year, month: 7, day: 1)) ?? date
    }

    func profitAndLoss(from start: Date, to end: Date) -> ProfitAndLoss {
        let totals = balances(from: start, to: end)
        let income = accounts.filter { $0.type == .income }.compactMap { account -> AccountAmount? in
            let amount = -(totals[account.code] ?? 0)
            return amount == 0 ? nil : AccountAmount(account: account, amount: amount)
        }
        let expenses = accounts.filter { $0.type == .expense }.compactMap { account -> AccountAmount? in
            let amount = totals[account.code] ?? 0
            return amount == 0 ? nil : AccountAmount(account: account, amount: amount)
        }
        return ProfitAndLoss(income: income, expenses: expenses)
    }

    func balanceSheet(asOf date: Date) -> BalanceSheet {
        let totals = balances(to: date)
        func amounts(_ type: AccountType) -> [AccountAmount] {
            accounts.filter { $0.type == type }.compactMap { account in
                let raw = totals[account.code] ?? 0
                let amount = type.debitNormal ? raw : -raw
                return amount == 0 ? nil : AccountAmount(account: account, amount: amount)
            }
        }
        let yearStart = financialYearStart(for: date)
        let current = profitAndLoss(from: yearStart, to: date).net
        let before = calendar.date(byAdding: .day, value: -1, to: yearStart) ?? yearStart
        let earlierTotals = balances(to: before)
        let earlier = accounts.filter { $0.type == .income || $0.type == .expense }.reduce(0) { $0 - (earlierTotals[$1.code] ?? 0) }
        return BalanceSheet(assets: amounts(.asset), liabilities: amounts(.liability), equity: amounts(.equity),
                            currentEarnings: current, earlierEarnings: earlier)
    }

    func trialBalance(asOf date: Date) -> [TrialBalanceRow] {
        let totals = balances(to: date)
        return accounts.compactMap { account in
            let amount = totals[account.code] ?? 0
            guard amount != 0 else { return nil }
            return TrialBalanceRow(account: account, debit: max(0, amount), credit: max(0, -amount))
        }
    }

    func cashSummary(from start: Date, to end: Date) -> [CashRow] {
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        let opening = balances(to: dayBefore)
        let last = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        let first = calendar.startOfDay(for: start)
        return bankAccounts.map { account in
            var moneyIn = 0, moneyOut = 0
            for entry in entries where entry.date >= first && entry.date < last {
                for line in entry.lines where line.account == account.code {
                    if line.amount > 0 { moneyIn += line.amount } else { moneyOut -= line.amount }
                }
            }
            return CashRow(account: account, opening: opening[account.code] ?? 0, moneyIn: moneyIn, moneyOut: moneyOut)
        }
    }

    /// Who owes what (sales) or what you owe (bills), by how late it is.
    func aged(_ kind: Invoice.Kind, asOf date: Date) -> [AgedRow] {
        var rows: [UUID: [Cents]] = [:]
        for invoice in invoices where invoice.kind == kind && invoice.owing > 0 && invoice.issued <= date {
            let days = invoice.daysOverdue(on: date, calendar: calendar)
            let bucket = days <= 0 ? 0 : (days <= 30 ? 1 : (days <= 60 ? 2 : (days <= 90 ? 3 : 4)))
            var buckets = rows[invoice.contact] ?? Array(repeating: 0, count: 5)
            buckets[bucket] += invoice.owing
            rows[invoice.contact] = buckets
        }
        return rows.compactMap { id, buckets in contact(id).map { AgedRow(contact: $0, buckets: buckets) } }
            .sorted { $0.total > $1.total }
    }

    // MARK: GST

    /// G1, G3, G10, G11, 1A and 1B for a period, on the basis in the settings.
    func bas(from start: Date, to end: Date) -> BASFigures {
        let first = calendar.startOfDay(for: start)
        let last = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        var figures = BASFigures()
        func add(account code: String, amount: Cents, tax: GSTCode?, taxAmount: Cents) {
            guard let tax, tax != .excluded, let found = self.account(code) else { return }
            switch found.type {
            case .income:
                let sales = -(amount + taxAmount)
                figures.totalSales += sales
                if tax == .free { figures.gstFreeSales += sales }
                figures.gstOnSales -= taxAmount
            case .expense, .asset:
                let purchase = amount + taxAmount
                if tax == .capital || found.type == .asset { figures.capitalPurchases += purchase } else { figures.otherPurchases += purchase }
                figures.gstOnPurchases += taxAmount
            default:
                break
            }
        }
        for entry in entries where entry.date >= first && entry.date < last {
            if settings.cashBasis && (entry.source == .invoice || entry.source == .bill) { continue }
            for line in entry.lines { add(account: line.account, amount: line.amount, tax: line.tax, taxAmount: line.taxAmount) }
        }
        if settings.cashBasis {
            // Invoices and bills count when they're paid, in proportion to what was paid.
            for invoice in invoices where invoice.total > 0 {
                for payment in invoice.payments where payment.date >= first && payment.date < last {
                    let share = Double(payment.amount) / Double(invoice.total)
                    let sale = invoice.kind == .sale
                    for item in invoice.lines {
                        let net = Int((Double(item.net) * share).rounded(.toNearestOrAwayFromZero))
                        let tax = Int((Double(item.tax) * share).rounded(.toNearestOrAwayFromZero))
                        add(account: item.account, amount: sale ? -net : net, tax: settings.gstRegistered ? item.gst : .excluded, taxAmount: sale ? -tax : tax)
                    }
                }
            }
        }
        return figures
    }

    /// The quarter (July–September and so on) a date falls in.
    func quarter(containing date: Date) -> (start: Date, end: Date) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        let month = parts.month ?? 1
        let startMonth = ((month - 1) / 3) * 3 + 1
        let start = calendar.date(from: DateComponents(year: parts.year, month: startMonth, day: 1)) ?? date
        let next = calendar.date(byAdding: .month, value: 3, to: start) ?? date
        return (start, calendar.date(byAdding: .day, value: -1, to: next) ?? date)
    }

    // MARK: Lookups for the app

    var unreconciled: [BankLine] { bank.filter { !$0.isReconciled } }

    func bankBalance(_ account: String, asOf date: Date = Date()) -> Cents { balances(to: date)[account] ?? 0 }

    /// What the statement says, which can differ from the books until everything is reconciled.
    func statementBalance(_ account: String, opening: Cents = 0) -> Cents {
        opening + bank.filter { $0.account == account }.reduce(0) { $0 + $1.amount }
    }

    var owedToYou: Cents { invoices.filter { $0.kind == .sale }.reduce(0) { $0 + $1.owing } }
    var youOwe: Cents { invoices.filter { $0.kind == .bill }.reduce(0) { $0 + $1.owing } }

    func overdue(_ kind: Invoice.Kind, on date: Date = Date()) -> [Invoice] {
        invoices.filter { $0.kind == kind && $0.owing > 0 && $0.daysOverdue(on: date, calendar: calendar) > 0 }
    }

    /// Every line of the journal in a period, for the general ledger report.
    func generalLedger(from start: Date, to end: Date) -> [(entry: JournalEntry, line: JournalLine)] {
        let first = calendar.startOfDay(for: start)
        let last = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        return entries.filter { $0.date >= first && $0.date < last }.sorted { $0.date < $1.date }.flatMap { entry in
            entry.lines.map { (entry: entry, line: $0) }
        }
    }
}

// MARK: Statements

/// Bank statements in the three formats Australian banks export: CSV, OFX (also QFX) and QIF.
enum StatementParser {
    static func parse(_ text: String, fileExtension: String, account: String) -> [BankLine] {
        switch fileExtension.lowercased() {
        case "ofx", "qfx": return ofx(text, account: account)
        case "qif": return qif(text, account: account)
        default:
            if text.contains("<STMTTRN>") || text.contains("<stmttrn>") { return ofx(text, account: account) }
            if text.hasPrefix("!Type") { return qif(text, account: account) }
            return csv(text, account: account)
        }
    }

    static func ofx(_ text: String, account: String) -> [BankLine] {
        var lines: [BankLine] = []
        let blocks = text.components(separatedBy: "<STMTTRN>").dropFirst()
        for block in blocks {
            let body = block.components(separatedBy: "</STMTTRN>").first ?? block
            func tag(_ name: String) -> String? {
                guard let range = body.range(of: "<\(name)>", options: .caseInsensitive) else { return nil }
                let rest = body[range.upperBound...]
                let value = rest.prefix { $0 != "<" && $0 != "\n" && $0 != "\r" }
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? nil : decode(trimmed)
            }
            guard let posted = tag("DTPOSTED"), let date = Self.date(String(posted.prefix(8)), formats: ["yyyyMMdd"]),
                  let amountText = tag("TRNAMT"), let amount = LedgerMoney.parse(amountText) else { continue }
            let name = tag("NAME") ?? ""
            let memo = tag("MEMO") ?? ""
            let description = [name, memo].filter { !$0.isEmpty }.joined(separator: name.isEmpty || memo.isEmpty || memo.hasPrefix(name) ? "" : " · ")
            lines.append(BankLine(account: account, date: date, description: memo.hasPrefix(name) && !memo.isEmpty ? memo : description,
                                  amount: amount, bankID: tag("FITID")))
        }
        return lines
    }

    private static func decode(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
    }

    static func qif(_ text: String, account: String) -> [BankLine] {
        var lines: [BankLine] = []
        var date: Date?
        var amount: Cents?
        var payee = ""
        var memo = ""
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let code = line.first else { continue }
            let value = String(line.dropFirst())
            switch code {
            case "D": date = self.date(value.replacingOccurrences(of: "'", with: "/").replacingOccurrences(of: " ", with: ""),
                                       formats: ["d/M/yyyy", "d/M/yy", "yyyy-MM-dd", "d-M-yyyy"])
            case "T", "U": amount = LedgerMoney.parse(value)
            case "P": payee = value
            case "M": memo = value
            case "^":
                if let date, let amount {
                    lines.append(BankLine(account: account, date: date, description: payee.isEmpty ? memo : payee, amount: amount))
                }
                date = nil; amount = nil; payee = ""; memo = ""
            default: break
            }
        }
        return lines
    }

    /// Finds the date, description and amount (or debit and credit) columns by their headers; headerless exports
    /// in the common date, amount, description order work too.
    static func csv(_ text: String, account: String) -> [BankLine] {
        let rows = GridCSV.parse(text)
        guard let first = rows.first else { return [] }
        let header = first.map { $0.lowercased() }
        func column(_ names: [String]) -> Int? { header.firstIndex { cell in names.contains { cell.contains($0) } } }
        var dateColumn = column(["date"])
        var descriptionColumn = column(["description", "details", "narrative", "transaction", "payee", "memo", "particulars", "name"])
        var amountColumn = column(["amount", "value"])
        let debitColumn = column(["debit", "withdrawal", "money out", "paid out"])
        let creditColumn = column(["credit", "deposit", "money in", "paid in"])
        var body = Array(rows.dropFirst())
        if dateColumn == nil, let guess = guessColumns(first) {
            // No header row (CommBank's export): date, amount, description, balance.
            dateColumn = guess.date
            amountColumn = guess.amount
            descriptionColumn = guess.description
            body = rows
        }
        guard let dateIndex = dateColumn, let descriptionIndex = descriptionColumn else { return [] }
        var lines: [BankLine] = []
        for row in body {
            func cell(_ index: Int?) -> String { index.flatMap { $0 < row.count ? row[$0] : nil } ?? "" }
            guard let date = Self.date(cell(dateIndex)) else { continue }
            var amount: Cents?
            if amountColumn != nil, let value = LedgerMoney.parse(cell(amountColumn)) {
                amount = value
            } else {
                let debit = LedgerMoney.parse(cell(debitColumn)) ?? 0
                let credit = LedgerMoney.parse(cell(creditColumn)) ?? 0
                if debit != 0 || credit != 0 { amount = abs(credit) - abs(debit) }
            }
            guard let amount, amount != 0 else { continue }
            lines.append(BankLine(account: account, date: date, description: cell(descriptionIndex).trimmingCharacters(in: .whitespaces), amount: amount))
        }
        return lines
    }

    private static func guessColumns(_ row: [String]) -> (date: Int, amount: Int, description: Int)? {
        guard let date = row.firstIndex(where: { self.date($0) != nil }) else { return nil }
        guard let amount = row.indices.first(where: { $0 != date && LedgerMoney.parse(row[$0]) != nil && row[$0].contains(".") }) else { return nil }
        guard let description = row.indices.first(where: { $0 != date && $0 != amount && LedgerMoney.parse(row[$0]) == nil && !row[$0].isEmpty }) else { return nil }
        return (date, amount, description)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.isLenient = false
        return formatter
    }()

    private static let lock = NSLock()

    /// Day-first, as Australian banks write dates.
    static func date(_ text: String, formats: [String] = ["d/M/yyyy", "d/M/yy", "yyyy-MM-dd", "d MMM yyyy", "d-MMM-yyyy", "d MMM yy", "d-M-yyyy", "yyyyMMdd", "yyyy/MM/dd"]) -> Date? {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        for format in formats {
            formatter.dateFormat = format
            if var date = formatter.date(from: value) {
                // "16/10/26" read with a four-digit year pattern is the year 26.
                let year = Calendar.current.component(.year, from: date)
                if year < 100 { date = Calendar.current.date(byAdding: .year, value: 2000, to: date) ?? date }
                // Noon, so time zones never push a line into the next or previous day.
                return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
            }
        }
        return nil
    }
}

// MARK: Documents

enum InvoiceDocument {
    /// The invoice as Markdown, for the PDF and the email body.
    static func markdown(_ invoice: Invoice, contact: Contact?, settings: LedgerSettings) -> String {
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_AU")
        date.dateFormat = "d MMMM yyyy"
        var parts: [String] = []
        let title = invoice.kind == .sale ? (settings.gstRegistered ? "Tax invoice" : "Invoice") : "Bill"
        parts.append("# \(title) \(invoice.number)")
        var from = "**\(settings.businessName)**"
        if !settings.abn.isEmpty { from += "  \nABN \(settings.abn)" }
        if !settings.address.isEmpty { from += "  \n" + settings.address.replacingOccurrences(of: "\n", with: "  \n") }
        if !settings.email.isEmpty { from += "  \n\(settings.email)" }
        parts.append(from)
        var to = "**To:** \(contact?.name ?? "")"
        if let abn = contact?.abn, !abn.isEmpty { to += "  \nABN \(abn)" }
        if let address = contact?.address, !address.isEmpty { to += "  \n" + address.replacingOccurrences(of: "\n", with: "  \n") }
        parts.append(to)
        var dates = "**Issued:** \(date.string(from: invoice.issued))  \n**Due:** \(date.string(from: invoice.due))"
        if !invoice.reference.isEmpty { dates += "  \n**Reference:** \(invoice.reference)" }
        parts.append(dates)
        var table = ["| Description | Qty | Unit price | GST | Amount |", "| --- | ---: | ---: | ---: | ---: |"]
        for line in invoice.lines {
            let quantity = line.quantity == line.quantity.rounded() ? String(Int(line.quantity)) : String(format: "%.2f", line.quantity)
            table.append("| \(line.description.replacingOccurrences(of: "|", with: "/")) | \(quantity) | \(LedgerMoney.text(line.unitPrice)) | \(LedgerMoney.text(line.tax)) | \(LedgerMoney.text(line.net)) |")
        }
        parts.append(table.joined(separator: "\n"))
        var totals = "**Subtotal:** \(LedgerMoney.text(invoice.subtotal))  \n"
        if settings.gstRegistered { totals += "**GST:** \(LedgerMoney.text(invoice.tax))  \n" }
        totals += "**Total:** \(LedgerMoney.text(invoice.total))"
        if invoice.paid > 0 { totals += "  \n**Paid:** \(LedgerMoney.text(invoice.paid))  \n**Owing:** \(LedgerMoney.text(invoice.total - invoice.paid))" }
        parts.append(totals)
        if invoice.kind == .sale && (!settings.bsb.isEmpty || !settings.accountNumber.isEmpty) {
            parts.append("## How to pay\n\nBank transfer to **\(settings.accountName.isEmpty ? settings.businessName : settings.accountName)**  \nBSB \(settings.bsb) · Account \(settings.accountNumber)  \nPlease use \(invoice.number) as the reference.")
        }
        if !invoice.notes.isEmpty { parts.append(invoice.notes) }
        return parts.joined(separator: "\n\n")
    }
}

// MARK: The accountant's pack

enum LedgerExport {
    /// A workbook with the reports an accountant asks for, totals as live formulas.
    static func workbook(_ book: LedgerBook, from start: Date, to end: Date) -> Workbook {
        let money = CellFormat(number: .currency(2))
        let bold = CellFormat(bold: true)
        let boldMoney = CellFormat(number: .currency(2), bold: true)
        func amount(_ cents: Cents) -> String { String(format: "%.2f", LedgerMoney.dollars(cents)) }
        let dateText = DateFormatter()
        dateText.locale = Locale(identifier: "en_US_POSIX")
        dateText.dateFormat = "d/M/yyyy"

        // Profit and loss
        var pnl = GridSheet(name: "Profit and loss")
        let report = book.profitAndLoss(from: start, to: end)
        var row = 0
        func put(_ sheet: inout GridSheet, _ row: Int, _ column: Int, _ input: String, _ format: CellFormat? = nil) {
            sheet[CellAddress(row: row, column: column)] = GridCell(input: input, format: format)
        }
        put(&pnl, row, 0, "\(book.settings.businessName): profit and loss, \(dateText.string(from: start)) to \(dateText.string(from: end))", bold)
        row += 2
        put(&pnl, row, 0, "Income", bold); row += 1
        let incomeStart = row
        for line in report.income {
            put(&pnl, row, 0, line.account.label)
            put(&pnl, row, 1, amount(line.amount), money)
            row += 1
        }
        let incomeTotalRow = row
        put(&pnl, row, 0, "Total income", bold)
        put(&pnl, row, 1, report.income.isEmpty ? "0" : "=SUM(B\(incomeStart + 1):B\(row))", boldMoney)
        row += 2
        put(&pnl, row, 0, "Expenses", bold); row += 1
        let expenseStart = row
        for line in report.expenses {
            put(&pnl, row, 0, line.account.label)
            put(&pnl, row, 1, amount(line.amount), money)
            row += 1
        }
        let expenseTotalRow = row
        put(&pnl, row, 0, "Total expenses", bold)
        put(&pnl, row, 1, report.expenses.isEmpty ? "0" : "=SUM(B\(expenseStart + 1):B\(row))", boldMoney)
        row += 2
        put(&pnl, row, 0, "Net profit", bold)
        put(&pnl, row, 1, "=B\(incomeTotalRow + 1)-B\(expenseTotalRow + 1)", boldMoney)
        pnl.columnWidths = [0: 280, 1: 120]

        // Balance sheet
        var balance = GridSheet(name: "Balance sheet")
        let sheet = book.balanceSheet(asOf: end)
        row = 0
        put(&balance, row, 0, "Balance sheet at \(dateText.string(from: end))", bold)
        row += 2
        var totals: [Int] = []
        for (title, lines) in [("Assets", sheet.assets), ("Liabilities", sheet.liabilities)] {
            put(&balance, row, 0, title, bold); row += 1
            let first = row
            for line in lines {
                put(&balance, row, 0, line.account.label)
                put(&balance, row, 1, amount(line.amount), money)
                row += 1
            }
            put(&balance, row, 0, "Total \(title.lowercased())", bold)
            put(&balance, row, 1, lines.isEmpty ? "0" : "=SUM(B\(first + 1):B\(row))", boldMoney)
            totals.append(row)
            row += 2
        }
        put(&balance, row, 0, "Equity", bold); row += 1
        let equityStart = row
        for line in sheet.equity {
            put(&balance, row, 0, line.account.label)
            put(&balance, row, 1, amount(line.amount), money)
            row += 1
        }
        put(&balance, row, 0, "Earlier years' earnings"); put(&balance, row, 1, amount(sheet.earlierEarnings), money); row += 1
        put(&balance, row, 0, "This year's earnings"); put(&balance, row, 1, amount(sheet.currentEarnings), money); row += 1
        put(&balance, row, 0, "Total equity", bold)
        put(&balance, row, 1, "=SUM(B\(equityStart + 1):B\(row))", boldMoney)
        let equityRow = row
        row += 2
        put(&balance, row, 0, "Net assets", bold)
        put(&balance, row, 1, "=B\(totals[0] + 1)-B\(totals[1] + 1)", boldMoney)
        put(&balance, row + 1, 0, "Check (should be zero)")
        put(&balance, row + 1, 1, "=B\(row + 1)-B\(equityRow + 1)", money)
        balance.columnWidths = [0: 280, 1: 120]

        // Trial balance
        var trial = GridSheet(name: "Trial balance")
        for (index, title) in ["Code", "Account", "Type", "Debit", "Credit"].enumerated() { put(&trial, 0, index, title, bold) }
        let rows = book.trialBalance(asOf: end)
        for (index, line) in rows.enumerated() {
            put(&trial, index + 1, 0, "'" + line.account.code)
            put(&trial, index + 1, 1, line.account.name)
            put(&trial, index + 1, 2, line.account.type.title)
            if line.debit != 0 { put(&trial, index + 1, 3, amount(line.debit), money) }
            if line.credit != 0 { put(&trial, index + 1, 4, amount(line.credit), money) }
        }
        let trialEnd = rows.count + 1
        put(&trial, trialEnd, 1, "Total", bold)
        put(&trial, trialEnd, 3, "=SUM(D2:D\(trialEnd))", boldMoney)
        put(&trial, trialEnd, 4, "=SUM(E2:E\(trialEnd))", boldMoney)
        trial.frozenRows = 1
        trial.columnWidths = [0: 60, 1: 220, 2: 80, 3: 110, 4: 110]

        // General ledger
        var ledger = GridSheet(name: "General ledger")
        for (index, title) in ["Date", "Account", "Description", "Debit", "Credit", "GST code", "GST"].enumerated() { put(&ledger, 0, index, title, bold) }
        for (index, item) in book.generalLedger(from: start, to: end).enumerated() {
            let r = index + 1
            put(&ledger, r, 0, dateText.string(from: item.entry.date))
            put(&ledger, r, 1, book.account(item.line.account)?.label ?? item.line.account)
            put(&ledger, r, 2, item.line.memo.isEmpty ? item.entry.memo : item.line.memo)
            if item.line.amount > 0 { put(&ledger, r, 3, amount(item.line.amount), money) }
            if item.line.amount < 0 { put(&ledger, r, 4, amount(-item.line.amount), money) }
            if let tax = item.line.tax { put(&ledger, r, 5, tax.title) }
            if item.line.taxAmount != 0 { put(&ledger, r, 6, amount(abs(item.line.taxAmount)), money) }
        }
        ledger.frozenRows = 1
        ledger.columnWidths = [0: 84, 1: 200, 2: 260, 3: 100, 4: 100, 5: 100, 6: 90]

        // GST
        var gst = GridSheet(name: "GST")
        let figures = book.bas(from: start, to: end)
        put(&gst, 0, 0, "GST, \(dateText.string(from: start)) to \(dateText.string(from: end)) (\(book.settings.cashBasis ? "cash" : "accrual") basis)", bold)
        let basRows: [(String, Cents)] = [
            ("G1 Total sales (including GST)", figures.totalSales), ("G3 GST-free sales", figures.gstFreeSales),
            ("G10 Capital purchases", figures.capitalPurchases), ("G11 Other purchases", figures.otherPurchases),
            ("1A GST on sales", figures.gstOnSales), ("1B GST on purchases", figures.gstOnPurchases),
        ]
        for (index, item) in basRows.enumerated() {
            put(&gst, index + 2, 0, item.0)
            put(&gst, index + 2, 1, amount(item.1), money)
        }
        put(&gst, 9, 0, "Net GST (1A − 1B)", bold)
        put(&gst, 9, 1, "=B7-B8", boldMoney)
        gst.columnWidths = [0: 280, 1: 120]

        // Aged receivables and payables
        func agedSheet(_ name: String, _ kind: Invoice.Kind) -> GridSheet {
            var aged = GridSheet(name: name)
            let titles = ["Contact"] + AgedRow.titles + ["Total"]
            for (index, title) in titles.enumerated() { put(&aged, 0, index, title, bold) }
            let rows = book.aged(kind, asOf: end)
            for (index, line) in rows.enumerated() {
                put(&aged, index + 1, 0, line.contact.name)
                for (bucket, value) in line.buckets.enumerated() where value != 0 { put(&aged, index + 1, bucket + 1, amount(value), money) }
                put(&aged, index + 1, 6, "=SUM(B\(index + 2):F\(index + 2))", money)
            }
            aged.frozenRows = 1
            aged.columnWidths = [0: 180, 1: 96, 2: 96, 3: 96, 4: 96, 5: 96, 6: 104]
            return aged
        }

        // Invoices and bills
        var list = GridSheet(name: "Invoices and bills")
        for (index, title) in ["Type", "Number", "Contact", "Issued", "Due", "Status", "Subtotal", "GST", "Total", "Owing"].enumerated() {
            put(&list, 0, index, title, bold)
        }
        let shown = book.invoices.filter { $0.status != .draft && $0.issued <= end }.sorted { $0.issued < $1.issued }
        for (index, invoice) in shown.enumerated() {
            let r = index + 1
            put(&list, r, 0, invoice.kind == .sale ? "Invoice" : "Bill")
            put(&list, r, 1, invoice.number)
            put(&list, r, 2, book.contact(invoice.contact)?.name ?? "")
            put(&list, r, 3, dateText.string(from: invoice.issued))
            put(&list, r, 4, dateText.string(from: invoice.due))
            put(&list, r, 5, invoice.status.title)
            put(&list, r, 6, amount(invoice.subtotal), money)
            put(&list, r, 7, amount(invoice.tax), money)
            put(&list, r, 8, amount(invoice.total), money)
            put(&list, r, 9, amount(invoice.owing), money)
        }
        list.frozenRows = 1
        list.columnWidths = [0: 70, 1: 90, 2: 170, 3: 84, 4: 84, 5: 130, 6: 96, 7: 84, 8: 96, 9: 96]

        return Workbook(name: "\(book.settings.businessName) accounts", sheets: [
            pnl, balance, trial, ledger, gst, agedSheet("Aged receivables", .sale), agedSheet("Aged payables", .bill), list,
        ])
    }
}
