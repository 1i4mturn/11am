import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// The places inside Money.
enum MoneyTab: String, CaseIterable, Identifiable {
    case overview, bank, invoices, bills, contacts, reports, gst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .bank: return "Bank"
        case .invoices: return "Invoices"
        case .bills: return "Bills"
        case .contacts: return "Contacts"
        case .reports: return "Reports"
        case .gst: return "GST"
        }
    }
}

/// Report periods, Australian financial years and quarters.
enum LedgerPeriod: String, CaseIterable, Identifiable {
    case thisMonth, lastMonth, thisQuarter, lastQuarter, thisYear, lastYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thisMonth: return "This month"
        case .lastMonth: return "Last month"
        case .thisQuarter: return "This quarter"
        case .lastQuarter: return "Last quarter"
        case .thisYear: return "This financial year"
        case .lastYear: return "Last financial year"
        }
    }
}

/// George's books in the app: the ledger, saved on this Mac, with the panels and sharing that go with it.
@MainActor
final class LedgerModel: ObservableObject {
    @Published var tab: MoneyTab = .overview
    @Published private(set) var book: LedgerBook
    @Published var notice: String?
    /// The invoice or bill open in the editor.
    @Published var editing: Invoice?
    @Published var selectedInvoice: UUID?
    @Published var selectedContact: UUID?
    @Published var bankAccount = "090"
    @Published var period: LedgerPeriod = .thisYear
    @Published var showsSettings = false

    init() {
        if let saved = JSONStore.load(LedgerBook.self, from: "ledger") {
            book = saved
        } else {
            book = LedgerSamples.book()
        }
    }

    // MARK: Changing the books

    /// Every change goes through here, so a failed one leaves the books as they were.
    func change(_ edit: (inout LedgerBook) throws -> Void) {
        var copy = book
        do {
            try edit(&copy)
            book = copy
            save()
        } catch {
            notice = error.localizedDescription
        }
    }

    private func save() {
        JSONStore.save(book, to: "ledger")
    }

    func useSample() {
        book = LedgerSamples.book()
        save()
        notice = "Back to the sample books."
    }

    /// Empty books with your settings and chart of accounts kept.
    func startFresh() {
        var fresh = LedgerBook()
        fresh.settings = book.settings
        fresh.settings.nextInvoice = 1
        fresh.accounts = book.accounts
        book = fresh
        save()
        notice = "Fresh books. Import a bank statement to start."
    }

    func updateSettings(_ settings: LedgerSettings) {
        change { $0.settings = settings }
    }

    // MARK: Dates

    var today: Date { Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date() }

    func range(_ period: LedgerPeriod) -> (start: Date, end: Date) {
        let calendar = book.calendar
        let now = today
        switch period {
        case .thisMonth, .lastMonth:
            let base = period == .thisMonth ? now : (calendar.date(byAdding: .month, value: -1, to: now) ?? now)
            let start = calendar.dateInterval(of: .month, for: base)?.start ?? base
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? base
            return (start, end)
        case .thisQuarter:
            return book.quarter(containing: now)
        case .lastQuarter:
            let previous = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            return book.quarter(containing: previous)
        case .thisYear, .lastYear:
            var start = book.financialYearStart(for: now)
            if period == .lastYear { start = calendar.date(byAdding: .year, value: -1, to: start) ?? start }
            let end = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: start) ?? now
            return (start, end)
        }
    }

    /// When the BAS for a quarter is due: the 28th of the month after, except October–December, due 28 February.
    func basDue(for quarterEnd: Date) -> Date {
        let calendar = book.calendar
        let month = calendar.component(.month, from: quarterEnd)
        let months = month == 12 ? 2 : 1
        let next = calendar.date(byAdding: .month, value: months, to: quarterEnd) ?? quarterEnd
        var parts = calendar.dateComponents([.year, .month], from: next)
        parts.day = 28
        return calendar.date(from: parts) ?? next
    }

    // MARK: Bank

    var bankLines: [BankLine] { book.bank.filter { $0.account == bankAccount } }

    func importStatement() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["csv", "ofx", "qfx", "qif", "txt"].compactMap { UTType(filenameExtension: $0) }
        panel.message = "Choose a statement exported from your bank (CSV, OFX or QIF)."
        guard panel.runModal() == .OK else { return }
        var added = 0, duplicates = 0, unreadable: [String] = []
        let account = bankAccount
        for url in panel.urls {
            guard let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else {
                unreadable.append(url.lastPathComponent)
                continue
            }
            let lines = StatementParser.parse(text, fileExtension: url.pathExtension, account: account)
            if lines.isEmpty { unreadable.append(url.lastPathComponent); continue }
            change { book in
                let result = book.importStatement(lines)
                added += result.added
                duplicates += result.duplicates
            }
        }
        var parts: [String] = []
        if added > 0 || duplicates > 0 { parts.append("Added \(added) bank \(added == 1 ? "line" : "lines")\(duplicates > 0 ? ", skipped \(duplicates) already here" : "").") }
        if !unreadable.isEmpty { parts.append("Couldn't read \(unreadable.joined(separator: ", ")).") }
        notice = parts.joined(separator: " ")
        tab = .bank
    }

    func suggestion(for line: BankLine) -> BankSuggestion? { book.suggestion(for: line) }

    func accept(_ line: BankLine) {
        guard let suggestion = book.suggestion(for: line) else { return }
        switch suggestion {
        case .invoice(let id): match(line, invoice: id)
        case .rule(let account, let gst, _): code(line, account: account, gst: gst)
        case .transfer(let account): transfer(line, to: account)
        }
    }

    func code(_ line: BankLine, account: String, gst: GSTCode) {
        change { try $0.code(line.id, account: account, gst: gst) }
    }

    func match(_ line: BankLine, invoice: UUID) {
        change { try $0.match(line.id, invoice: invoice) }
    }

    func transfer(_ line: BankLine, to account: String) {
        change { try $0.transfer(line.id, to: account) }
    }

    func unreconcile(_ line: BankLine) {
        change { try $0.unreconcile(line.id) }
    }

    /// Accepts every suggestion that matches an invoice exactly or a payee coded at least twice.
    func acceptConfident() {
        var count = 0
        change { book in
            for line in book.unreconciled {
                switch book.suggestion(for: line) {
                case .invoice(let id)?:
                    try book.match(line.id, invoice: id)
                    count += 1
                case .rule(let account, let gst, let times)? where times >= 2:
                    try book.code(line.id, account: account, gst: gst)
                    count += 1
                default:
                    break
                }
            }
        }
        notice = count == 0 ? "Nothing George is sure enough about. Code the rest by hand." : "Reconciled \(count) \(count == 1 ? "line" : "lines") George was sure of."
    }

    /// Invoices or bills a bank line could pay: same direction, still owing.
    func candidates(for line: BankLine) -> [Invoice] {
        let kind: Invoice.Kind = line.amount > 0 ? .sale : .bill
        return book.invoices.filter { $0.kind == kind && $0.owing > 0 }.sorted { abs($0.owing - abs(line.amount)) < abs($1.owing - abs(line.amount)) }
    }

    // MARK: Invoices and bills

    func invoices(_ kind: Invoice.Kind) -> [Invoice] {
        book.invoices.filter { $0.kind == kind }.sorted { $0.issued > $1.issued }
    }

    func newInvoice(_ kind: Invoice.Kind, for contact: UUID? = nil) {
        let issued = today
        let due = Calendar.current.date(byAdding: .day, value: book.settings.paymentDays, to: issued) ?? issued
        let account = kind == .sale ? "200" : "429"
        editing = Invoice(kind: kind, number: "", contact: contact ?? book.contacts.first?.id ?? UUID(), issued: issued, due: due,
                          lines: [InvoiceLine(description: "", unitPrice: 0, account: account, gst: book.settings.gstRegistered ? .gst : .excluded)])
    }

    func edit(_ id: UUID) {
        guard let invoice = book.invoice(id), invoice.status == .draft else { return }
        editing = invoice
    }

    /// Saves the editor's invoice, numbering a new one, and approves it if asked.
    func save(_ draft: Invoice, approve: Bool) {
        var invoice = draft
        invoice.lines = invoice.lines.filter { !$0.description.isEmpty || $0.unitPrice != 0 }
        guard !invoice.lines.isEmpty else {
            notice = "Add at least one line."
            return
        }
        guard book.contact(invoice.contact) != nil else {
            notice = "Pick who it's \(invoice.kind == .sale ? "for" : "from")."
            return
        }
        change { book in
            if invoice.number.isEmpty {
                invoice.number = invoice.kind == .sale ? book.takeInvoiceNumber() : "BILL-\(book.invoices.filter { $0.kind == .bill }.count + 1)"
            }
            if let index = book.invoices.firstIndex(where: { $0.id == invoice.id }) { book.invoices[index] = invoice } else { book.invoices.append(invoice) }
            if approve { try book.approve(invoice.id) }
        }
        selectedInvoice = invoice.id
        editing = nil
    }

    func approve(_ id: UUID) { change { try $0.approve(id) } }

    /// Marc found a receipt or invoice in your mail: a draft bill to check and approve, with GST worked out.
    func draftBill(from vendor: String, total: Cents, description: String, date: Date, reference: String) {
        let contact = book.contacts.first { $0.name.caseInsensitiveCompare(vendor) == .orderedSame }?.id ?? addContact(named: vendor)
        let gst: GSTCode = book.settings.gstRegistered ? .gst : .excluded
        let net = total - GST.included(in: total, gst)
        let bill = Invoice(kind: .bill, number: "", contact: contact, issued: date, due: date, reference: reference,
                           lines: [InvoiceLine(description: description, unitPrice: net, account: "429", gst: gst)])
        save(bill, approve: false)
        tab = .bills
        notice = "A draft bill from \(vendor) for \(LedgerMoney.text(total)) is ready to check and approve."
    }

    func void(_ id: UUID) { change { try $0.void(id) } }

    func deleteDraft(_ id: UUID) {
        change { book in book.invoices.removeAll { $0.id == id && $0.status == .draft } }
        if selectedInvoice == id { selectedInvoice = nil }
    }

    func recordPayment(_ id: UUID, amount: Cents, date: Date) {
        let account = bankAccount
        change { try $0.recordPayment(id, amount: amount, date: date, bankAccount: account) }
    }

    func pdf(for invoice: Invoice) -> Data {
        let markdown = InvoiceDocument.markdown(invoice, contact: book.contact(invoice.contact), settings: book.settings)
        var setup = PageSetup()
        setup.showsTitle = false
        setup.margin = 56
        return DocPDF.data(markdown, title: invoice.number, setup: setup, baseURL: nil)
    }

    func savePDF(_ invoice: Invoice) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(invoice.number) \(book.contact(invoice.contact)?.name ?? "").pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try pdf(for: invoice).write(to: url, options: .atomic)
            notice = "Saved \(url.lastPathComponent)."
        } catch {
            notice = "Couldn't save: \(error.localizedDescription)"
        }
    }

    /// Opens a new email in your mail app with the PDF attached and a short note.
    func email(_ invoice: Invoice) {
        let contact = book.contact(invoice.contact)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("11am-invoices", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(invoice.number).pdf")
        do {
            try pdf(for: invoice).write(to: file, options: .atomic)
        } catch {
            notice = "Couldn't make the PDF: \(error.localizedDescription)"
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM"
        let greeting = contact.map { "Hi \($0.name)," } ?? "Hi,"
        let body = """
        \(greeting)

        Please find \(invoice.kind == .sale ? "invoice" : "bill") \(invoice.number) attached for \(LedgerMoney.text(invoice.total)), due \(formatter.string(from: invoice.due)).

        Thanks,
        \(book.settings.businessName)
        """
        guard let service = NSSharingService(named: .composeEmail) else {
            notice = "No mail app is set up on this Mac."
            return
        }
        if let email = contact?.email, !email.isEmpty { service.recipients = [email] }
        service.subject = "\(invoice.kind == .sale ? "Invoice" : "Bill") \(invoice.number) from \(book.settings.businessName)"
        guard service.canPerform(withItems: [body, file]) else {
            notice = "Your mail app can't take attachments this way. Save the PDF and attach it."
            return
        }
        service.perform(withItems: [body, file])
        change { book in
            if let index = book.invoices.firstIndex(where: { $0.id == invoice.id }) { book.invoices[index].sentAt = Date() }
        }
    }

    // MARK: Contacts

    func addContact(named name: String) -> UUID {
        let contact = Contact(name: name.trimmingCharacters(in: .whitespaces))
        change { $0.contacts.append(contact) }
        return contact.id
    }

    func update(_ contact: Contact) {
        change { book in
            if let index = book.contacts.firstIndex(where: { $0.id == contact.id }) { book.contacts[index] = contact }
        }
    }

    func deleteContact(_ id: UUID) {
        guard !book.invoices.contains(where: { $0.contact == id }) else {
            notice = "That contact has invoices or bills, so it stays."
            return
        }
        change { $0.contacts.removeAll { $0.id == id } }
        if selectedContact == id { selectedContact = nil }
    }

    // MARK: Reports

    /// The accountant's pack for a period as an Excel workbook.
    func accountantPack() -> Workbook {
        let dates = range(period)
        return LedgerExport.workbook(book, from: dates.start, to: dates.end)
    }

    func exportPack() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(book.settings.businessName) accounts, \(period.title.lowercased()).xlsx"
        if let type = UTType(filenameExtension: "xlsx") { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try GridXLSX.data(accountantPack()).write(to: url, options: .atomic)
            notice = "Saved \(url.lastPathComponent) for your accountant."
        } catch {
            notice = "Couldn't save: \(error.localizedDescription)"
        }
    }

    // MARK: For George

    /// What George knows about the books when you ask him something.
    var georgeFacts: String {
        let year = range(.thisYear)
        let pnl = book.profitAndLoss(from: year.start, to: today)
        let quarter = book.quarter(containing: today)
        let gst = book.bas(from: quarter.start, to: quarter.end)
        let overdue = book.overdue(.sale)
        let topExpenses = pnl.expenses.sorted { $0.amount > $1.amount }.prefix(5).map { "\($0.account.name) \(LedgerMoney.text($0.amount))" }
        return """
        From the books (\(book.settings.cashBasis ? "cash" : "accrual") basis):
        This financial year so far: income \(LedgerMoney.text(pnl.totalIncome)), expenses \(LedgerMoney.text(pnl.totalExpenses)), profit \(LedgerMoney.text(pnl.net)).
        Biggest expenses: \(topExpenses.joined(separator: ", ")).
        Owed to you: \(LedgerMoney.text(book.owedToYou)), of which overdue: \(LedgerMoney.text(overdue.reduce(0) { $0 + $1.owing })) on \(overdue.count) invoices.
        You owe on bills: \(LedgerMoney.text(book.youOwe)).
        GST this quarter so far: on sales \(LedgerMoney.text(gst.gstOnSales)), on purchases \(LedgerMoney.text(gst.gstOnPurchases)), net \(LedgerMoney.text(gst.net)).
        Bank lines still to reconcile: \(book.unreconciled.count).
        """
    }
}
