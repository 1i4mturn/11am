import AppKit
import SwiftUI

// MARK: Pieces

/// An amount in the books' own style: tabular figures, money in shown plainly, money out with a minus.
struct LedgerAmount: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var cents: Cents
    var bold = false
    var width: CGFloat? = 110

    var body: some View {
        Text(LedgerMoney.text(cents))
            .font(.system(size: 12.5, weight: bold ? .semibold : .regular).monospacedDigit())
            .foregroundStyle(cents < 0 ? theme.inkSecondary(scheme) : theme.ink(scheme))
            .frame(width: width, alignment: .trailing)
            .lineLimit(1)
    }
}

/// A sheet-like card for the ledger panels.
struct LedgerCard<Content: View>: View {
    @EnvironmentObject private var theme: Theme
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .vellum(level: 3, radius: max(theme.radius - 4, 8))
    }
}

struct ReportRow: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var label: String
    var cents: Cents?
    var bold = false
    var indent: CGFloat = 0
    var second: Cents?

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12.5, weight: bold ? .semibold : .regular))
                .foregroundStyle(theme.ink(scheme))
                .padding(.leading, indent)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let second { LedgerAmount(cents: second, bold: bold) }
            if let cents { LedgerAmount(cents: cents, bold: bold) }
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            if bold { Rectangle().fill(theme.edge(scheme)).frame(height: 0.5) }
        }
    }
}

extension Date {
    var shortDay: String { formatted(.dateTime.day().month(.abbreviated)) }
    var fullDay: String { formatted(.dateTime.day().month(.wide).year()) }
}

/// A dollars-and-cents field over a cents value.
struct MoneyField: View {
    var title: String
    @Binding var cents: Cents

    var body: some View {
        TextField(title, value: Binding(get: { LedgerMoney.dollars(cents) }, set: { cents = LedgerMoney.cents($0) }),
                  format: .number.precision(.fractionLength(2)))
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
    }
}

// MARK: Bank

struct BankPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let lines = ledger.bankLines.sorted { $0.date > $1.date }
        let open = lines.filter { !$0.isReconciled }
        let done = lines.filter(\.isReconciled)
        let needing = Set(ledger.book.missingReceipts(from: .distantPast, to: ledger.today).map(\.id))
        let kept = Set(ledger.book.receipts.compactMap(\.bankLine))
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Accounts")
                ForEach(ledger.book.bankAccounts) { account in
                    accountRow(account)
                }
                Button {
                    ledger.importStatement()
                } label: {
                    Label("Import statement…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.vellumSecondary)
                .padding(.top, 4)
                Text("CSV, OFX or QIF from your bank. Lines already here are skipped.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 180)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionLabel(text: open.isEmpty ? "All reconciled" : "To reconcile · \(open.count)")
                        Spacer()
                        if !open.isEmpty {
                            Button("Accept the sure ones") { withAnimation(theme.spring) { ledger.acceptConfident() } }
                                .buttonStyle(.vellumSecondary)
                                .help("Payments that match an invoice exactly, and payees you've coded the same way at least twice")
                        }
                    }
                    ForEach(open) { line in
                        ReconcileRow(line: line)
                            .transition(.rise(theme.rise))
                    }
                    if !done.isEmpty {
                        SectionLabel(text: "Reconciled")
                            .padding(.top, 8)
                        LedgerCard {
                            LazyVStack(spacing: 0) {
                                ForEach(done.prefix(80)) { line in
                                    reconciledRow(line, receipt: kept.contains(line.id), needsReceipt: needing.contains(line.id))
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .animation(theme.spring, value: open.count)
    }

    private func accountRow(_ account: LedgerAccount) -> some View {
        let selected = account.code == ledger.bankAccount
        let waiting = ledger.book.bank.filter { $0.account == account.code && !$0.isReconciled }.count
        return Button {
            withAnimation(theme.spring) { ledger.bankAccount = account.code }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(account.name)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(theme.ink(scheme))
                Text(LedgerMoney.text(ledger.book.bankBalance(account.code)))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(theme.inkSecondary(scheme))
                if waiting > 0 {
                    Text("\(waiting) to reconcile")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selected { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.raised(scheme)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func reconciledRow(_ line: BankLine, receipt: Bool, needsReceipt: Bool) -> some View {
        let entry = ledger.book.entries.first { $0.id == line.entry }
        let coded = entry?.lines.first { $0.account != line.account && $0.account != ledger.book.code(for: .gst) }
        let account = coded.flatMap { ledger.book.account($0.account) }
        return HStack(spacing: 10) {
            Text(line.date.shortDay)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(theme.inkTertiary(scheme))
                .frame(width: 52, alignment: .leading)
            Text(line.description)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.ink(scheme))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(account?.name ?? entry?.memo ?? "")
                .font(.system(size: 11))
                .foregroundStyle(theme.inkTertiary(scheme))
                .lineLimit(1)
            if let tax = coded?.tax, tax != .excluded {
                Chip(text: tax.title)
            }
            Group {
                if receipt {
                    Image(systemName: "paperclip").help("Receipt kept")
                } else if needsReceipt {
                    Image(systemName: "exclamationmark.circle").help("Over $82.50 with GST claimed: keep its tax invoice")
                } else {
                    Color.clear
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(needsReceipt ? theme.ink(scheme) : theme.inkTertiary(scheme))
            .frame(width: 14)
            LedgerAmount(cents: line.amount)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.edge(scheme)).frame(height: 0.5) }
        .contextMenu {
            Button("Undo reconciliation") { withAnimation(theme.spring) { ledger.unreconcile(line) } }
            if line.amount < 0 {
                Button("Add its receipt…") { ledger.addReceipt(for: line) }
            }
        }
    }
}

private struct ReconcileRow: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    var line: BankLine
    @State private var account = ""
    @State private var gst: GSTCode = .gst

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(line.date.shortDay)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .frame(width: 52, alignment: .leading)
                Text(line.description)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.ink(scheme))
                    .lineLimit(1)
                Spacer(minLength: 8)
                LedgerAmount(cents: line.amount, bold: true)
            }
            if let suggestion = ledger.suggestion(for: line) {
                HStack(spacing: 8) {
                    AgentLogo(code: "ge", size: 14, color: theme.inkSecondary(scheme))
                    Text(describe(suggestion))
                        .font(.system(size: 12))
                        .foregroundStyle(theme.inkSecondary(scheme))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button("OK") { withAnimation(theme.spring) { ledger.accept(line) } }
                        .buttonStyle(.vellumPrimary)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    accountMenu
                    gstPicker
                    codeButton
                    Spacer(minLength: 0)
                    matchMenu
                    transferMenu
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        accountMenu
                        gstPicker
                        codeButton
                    }
                    HStack(spacing: 8) {
                        matchMenu
                        transferMenu
                    }
                }
            }
        }
        .padding(14)
        .vellum(level: 3, radius: max(theme.radius - 4, 8))
    }

    private var groups: [AccountType] { line.amount > 0 ? [.income, .liability, .equity, .asset] : [.expense, .asset, .liability, .equity] }

    private var accountMenu: some View {
        Menu {
            ForEach(groups, id: \.self) { type in
                Section(type.title) {
                    ForEach(ledger.book.accounts.filter { $0.type == type && !$0.isBank && $0.role == nil }) { item in
                        Button(item.label) {
                            account = item.code
                            gst = ledger.book.settings.gstRegistered ? item.gst : .excluded
                        }
                    }
                }
            }
        } label: {
            Text(ledger.book.account(account)?.label ?? "Choose an account")
                .font(.system(size: 12))
                .lineLimit(1)
        }
        .menuStyle(.button)
        .frame(maxWidth: 230)
    }

    private var gstPicker: some View {
        Picker("", selection: $gst) {
            ForEach(GSTCode.allCases) { code in Text(code.title).tag(code) }
        }
        .labelsHidden()
        .frame(width: 130)
    }

    private var codeButton: some View {
        Button(account.isEmpty ? "Code" : "Code · \(gstPreview)") { withAnimation(theme.spring) { ledger.code(line, account: account, gst: gst) } }
            .buttonStyle(.vellumSecondary)
            .disabled(account.isEmpty)
            .fixedSize()
    }

    @ViewBuilder
    private var matchMenu: some View {
        let candidates = ledger.candidates(for: line)
        if !candidates.isEmpty {
            Menu("Match") {
                ForEach(candidates.prefix(12)) { invoice in
                    Button("\(invoice.number) · \(ledger.book.contact(invoice.contact)?.name ?? "") · \(LedgerMoney.text(invoice.owing))") {
                        withAnimation(theme.spring) { ledger.match(line, invoice: invoice.id) }
                    }
                    .disabled(invoice.owing < abs(line.amount))
                }
            }
            .menuStyle(.button)
            .fixedSize()
            .help(line.amount > 0 ? "A payment for one of your invoices" : "Paying one of your bills")
        }
    }

    @ViewBuilder
    private var transferMenu: some View {
        let others = ledger.book.bankAccounts.filter { $0.code != line.account }
        if !others.isEmpty {
            Menu("Transfer") {
                ForEach(others) { other in
                    Button("\(line.amount < 0 ? "To" : "From") \(other.name)") { withAnimation(theme.spring) { ledger.transfer(line, to: other.code) } }
                }
            }
            .menuStyle(.button)
            .fixedSize()
        }
    }

    private var gstPreview: String {
        let tax = GST.included(in: abs(line.amount), ledger.book.settings.gstRegistered ? gst : .excluded)
        return tax == 0 ? "No GST" : "GST \(LedgerMoney.text(tax))"
    }

    private func describe(_ suggestion: BankSuggestion) -> String {
        switch suggestion {
        case .invoice(let id):
            guard let invoice = ledger.book.invoice(id) else { return "" }
            let name = ledger.book.contact(invoice.contact)?.name ?? ""
            return invoice.kind == .sale ? "Payment for \(invoice.number) from \(name)" : "Pays bill \(invoice.number) from \(name)"
        case .rule(let code, let gst, let times):
            let name = ledger.book.account(code)?.label ?? code
            return "\(name), \(gst.title) · coded this way \(times == 1 ? "once" : "\(times) times") before"
        case .transfer(let code):
            return "A transfer \(line.amount < 0 ? "to" : "from") \(ledger.book.account(code)?.name ?? code)"
        }
    }
}

// MARK: Invoices and bills

struct InvoicesPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    var kind: Invoice.Kind
    @State private var billFilter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all, draft, owing, overdue, paid, repeating
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "All"
            case .draft: return "Drafts"
            case .owing: return "Owing"
            case .overdue: return "Overdue"
            case .paid: return "Paid"
            case .repeating: return "Repeating"
            }
        }
    }

    private var filter: Filter { kind == .sale ? ledger.salesFilter : billFilter }
    private var filterBinding: Binding<Filter> { kind == .sale ? $ledger.salesFilter : $billFilter }

    var body: some View {
        GeometryReader { geo in
            content(narrow: geo.size.width < 800)
        }
    }

    @ViewBuilder
    private func content(narrow: Bool) -> some View {
        let all = ledger.invoices(kind)
        let shown = all.filter(matches)
        let owing = all.reduce(0) { $0 + $1.owing }
        let overdue = ledger.book.overdue(kind, on: ledger.today).reduce(0) { $0 + $1.owing }
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if narrow {
                        Picker("", selection: filterBinding) {
                            ForEach(Filter.allCases.filter { kind == .sale || $0 != .repeating }) { item in Text(item.title).tag(item) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                    } else {
                        Picker("", selection: filterBinding) {
                            ForEach(Filter.allCases.filter { kind == .sale || $0 != .repeating }) { item in Text(item.title).tag(item) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: kind == .sale ? 460 : 360)
                    }
                    Spacer(minLength: 8)
                    Button {
                        if filter == .repeating { ledger.newSchedule() } else { ledger.newInvoice(kind) }
                    } label: {
                        Label(kind == .sale ? (filter == .repeating ? "New repeating" : "New invoice") : "New bill", systemImage: "plus")
                    }
                    .buttonStyle(.vellumPrimary)
                    .fixedSize()
                }
                if filter == .repeating {
                    RepeatingList()
                } else {
                    Text("\(kind == .sale ? "Owed to you" : "You owe") \(LedgerMoney.text(owing))\(overdue > 0 ? " · \(LedgerMoney.text(overdue)) overdue" : "")")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.inkSecondary(scheme))
                    if kind == .sale { MarcRemindersCard() }
                    LedgerCard {
                        if shown.isEmpty {
                            Text(kind == .sale ? "No invoices here." : "No bills here.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(theme.inkTertiary(scheme))
                                .frame(maxWidth: .infinity, minHeight: 80)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(shown) { invoice in row(invoice) }
                                }
                            }
                        }
                    }
                }
            }
            .frame(minWidth: narrow ? 250 : 360, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if filter == .repeating {
                if let id = ledger.selectedSchedule, let schedule = ledger.book.schedule(id) {
                    RepeatingDetail(schedule: schedule)
                        .frame(width: narrow ? 270 : 320)
                        .transition(.rise(theme.rise))
                }
            } else if let id = ledger.selectedInvoice, let invoice = ledger.book.invoice(id), invoice.kind == kind {
                InvoiceDetail(invoice: invoice)
                    .frame(width: narrow ? 270 : 320)
                    .transition(.rise(theme.rise))
            }
        }
        .animation(theme.spring, value: ledger.selectedInvoice)
        .animation(theme.spring, value: ledger.selectedSchedule)
        .animation(theme.spring, value: filter)
    }

    private func matches(_ invoice: Invoice) -> Bool {
        switch filter {
        case .all: return invoice.status != .void
        case .draft: return invoice.status == .draft
        case .owing: return invoice.owing > 0
        case .overdue: return invoice.owing > 0 && invoice.daysOverdue(on: ledger.today) > 0
        case .paid: return invoice.status == .paid
        case .repeating: return false
        }
    }

    private func row(_ invoice: Invoice) -> some View {
        let selected = ledger.selectedInvoice == invoice.id
        let late = invoice.owing > 0 ? invoice.daysOverdue(on: ledger.today) : 0
        return Button {
            ledger.selectedInvoice = selected ? nil : invoice.id
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(invoice.number)
                            .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(theme.ink(scheme))
                            .fixedSize()
                        Text(ledger.book.contact(invoice.contact)?.name ?? "")
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.ink(scheme))
                            .lineLimit(1)
                    }
                    Text(late > 0 ? "\(late) \(late == 1 ? "day" : "days") late · \(invoice.status.title.lowercased())" : "\(invoice.status.title) · due \(invoice.due.shortDay)")
                        .font(.system(size: 11, weight: late > 0 ? .semibold : .regular))
                        .foregroundStyle(late > 0 ? theme.ink(scheme) : theme.inkTertiary(scheme))
                        .lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                LedgerAmount(cents: invoice.total, bold: invoice.owing > 0, width: 96)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background {
                if selected { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(theme.raised(scheme)) }
            }
            .overlay(alignment: .bottom) { Rectangle().fill(theme.edge(scheme)).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct InvoiceDetail: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    var invoice: Invoice
    @State private var paying = false
    @State private var payment: Cents = 0
    @State private var paidOn = Date()
    @State private var voiding = false

    var body: some View {
        let contact = ledger.book.contact(invoice.contact)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(invoice.number)
                        .font(theme.display(22))
                        .foregroundStyle(theme.ink(scheme))
                    Spacer()
                    Chip(text: invoice.status.title, filled: invoice.status == .paid)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(contact?.name ?? "").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.ink(scheme))
                    Text("Issued \(invoice.issued.fullDay) · due \(invoice.due.fullDay)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                    if let sent = invoice.sentAt {
                        Text("Emailed \(sent.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                }
                LedgerCard {
                    ForEach(invoice.lines) { line in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.description).font(.system(size: 12.5)).foregroundStyle(theme.ink(scheme))
                                Text("\(line.quantity == line.quantity.rounded() ? String(Int(line.quantity)) : String(format: "%.2f", line.quantity)) × \(LedgerMoney.text(line.unitPrice)) · \(line.gst.title)")
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(theme.inkTertiary(scheme))
                            }
                            Spacer()
                            LedgerAmount(cents: line.net, width: 90)
                        }
                    }
                    Divider()
                    ReportRow(label: "Subtotal", cents: invoice.subtotal)
                    ReportRow(label: "GST", cents: invoice.tax)
                    ReportRow(label: "Total", cents: invoice.total, bold: true)
                    ForEach(invoice.payments) { item in
                        ReportRow(label: "Paid \(item.date.shortDay)", cents: -item.amount)
                    }
                    if invoice.owing > 0 && !invoice.payments.isEmpty {
                        ReportRow(label: "Owing", cents: invoice.owing, bold: true)
                    }
                }
                actions
            }
            .padding(14)
        }
        .vellum(level: 2, radius: max(theme.radius - 2, 10))
        .confirmationDialog("Void \(invoice.number)?", isPresented: $voiding) {
            Button("Void", role: .destructive) { ledger.void(invoice.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It comes out of the books, along with any payments recorded against it.")
        }
    }

    @ViewBuilder
    private var actions: some View {
        let sale = invoice.kind == .sale
        VStack(alignment: .leading, spacing: 8) {
            switch invoice.status {
            case .draft:
                HStack {
                    Button("Edit") { ledger.edit(invoice.id) }.buttonStyle(.vellumSecondary)
                    Button(sale ? "Approve" : "Approve bill") { ledger.approve(invoice.id) }.buttonStyle(.vellumPrimary)
                    Spacer()
                    Button("Delete") { ledger.deleteDraft(invoice.id) }.buttonStyle(.vellumSecondary)
                }
            case .approved, .paid:
                HStack {
                    if invoice.owing > 0 {
                        Button(sale ? "Record payment…" : "Pay…") {
                            payment = invoice.owing
                            paidOn = ledger.today
                            paying = true
                        }
                        .buttonStyle(.vellumPrimary)
                        .popover(isPresented: $paying, arrowEdge: .bottom) { paymentForm }
                    }
                    if sale {
                        Button("Email") { ledger.email(invoice) }.buttonStyle(.vellumSecondary)
                    } else {
                        Button("PDF") { ledger.savePDF(invoice) }.buttonStyle(.vellumSecondary)
                    }
                    Spacer(minLength: 0)
                    Menu {
                        if sale { Button("Save as PDF…") { ledger.savePDF(invoice) } }
                        Button("Void…", role: .destructive) { voiding = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .help("More")
                }
                if sale {
                    let reminders = ledger.book.remindersSent(for: invoice.id)
                    if !reminders.isEmpty {
                        Text("Marc has sent \(reminders.count) \(reminders.count == 1 ? "reminder" : "reminders"), last on \(reminders.last?.date.shortDay ?? "").")
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                    Menu {
                        Button("Every month") { ledger.repeatInvoice(invoice.id, every: 1, unit: .month) }
                        Button("Every 3 months") { ledger.repeatInvoice(invoice.id, every: 3, unit: .month) }
                        Button("Every year") { ledger.repeatInvoice(invoice.id, every: 1, unit: .year) }
                        Button("Every week") { ledger.repeatInvoice(invoice.id, every: 1, unit: .week) }
                    } label: {
                        Label("Repeat this invoice", systemImage: "repeat")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkSecondary(scheme))
                }
                if invoice.owing > 0 {
                    Text("Or import the bank statement and George matches the payment for you.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
            case .void:
                Text("Void. It's out of the books.").font(.system(size: 12)).foregroundStyle(theme.inkTertiary(scheme))
            }
        }
    }

    private var paymentForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(invoice.kind == .sale ? "Payment received" : "Payment made").font(.system(size: 13, weight: .semibold))
            HStack {
                Text("Amount")
                MoneyField(title: "Amount", cents: $payment).frame(width: 120)
            }
            DatePicker("Date", selection: $paidOn, displayedComponents: .date)
            Picker("Account", selection: $ledger.bankAccount) {
                ForEach(ledger.book.bankAccounts) { account in Text(account.name).tag(account.code) }
            }
            HStack {
                Spacer()
                Button("Record") {
                    ledger.recordPayment(invoice.id, amount: payment, date: paidOn)
                    paying = false
                }
                .buttonStyle(.vellumPrimary)
                .disabled(payment <= 0 || payment > invoice.owing)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

/// Writing an invoice or a bill.
struct InvoiceEditor: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    @State var invoice: Invoice
    @State private var newContact = ""

    var body: some View {
        let sale = invoice.kind == .sale
        VStack(alignment: .leading, spacing: 14) {
            Text(invoice.number.isEmpty ? (sale ? "New invoice" : "New bill") : "Edit \(invoice.number)")
                .font(theme.display(24))
                .foregroundStyle(theme.ink(scheme))
            HStack(spacing: 10) {
                Picker(sale ? "To" : "From", selection: $invoice.contact) {
                    ForEach(ledger.book.contacts) { contact in Text(contact.name).tag(contact.id) }
                }
                .frame(maxWidth: 280)
                TextField("Or a new contact", text: $newContact)
                    .frame(width: 180)
                    .onSubmit(addContact)
                Button("Add", action: addContact)
                    .disabled(newContact.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 16) {
                DatePicker("Issued", selection: $invoice.issued, displayedComponents: .date)
                DatePicker("Due", selection: $invoice.due, displayedComponents: .date)
                TextField(sale ? "Reference (their PO)" : "Their invoice number", text: $invoice.reference)
                    .frame(width: 200)
            }
            LineItemsEditor(lines: $invoice.lines, sale: sale)
            HStack(alignment: .top) {
                TextField("Notes on the invoice (optional)", text: $invoice.notes, axis: .vertical)
                    .lineLimit(2...4)
                    .frame(maxWidth: 360)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    ReportRow(label: "Subtotal", cents: invoice.subtotal)
                    ReportRow(label: "GST", cents: ledger.book.settings.gstRegistered ? invoice.tax : 0)
                    ReportRow(label: "Total", cents: invoice.subtotal + (ledger.book.settings.gstRegistered ? invoice.tax : 0), bold: true)
                }
                .frame(width: 260)
            }
            HStack {
                Spacer()
                Button("Cancel") { ledger.editing = nil }
                    .buttonStyle(.vellumSecondary)
                    .keyboardShortcut(.cancelAction)
                Button("Save draft") { ledger.save(invoice, approve: false) }
                    .buttonStyle(.vellumSecondary)
                Button(sale ? "Approve" : "Approve bill") { ledger.save(invoice, approve: true) }
                    .buttonStyle(.vellumPrimary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 860)
        .textFieldStyle(.roundedBorder)
    }

    private func addContact() {
        let name = newContact.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        invoice.contact = ledger.addContact(named: name)
        newContact = ""
    }
}

/// The lines of an invoice, bill, quote or repeating invoice: what, how many, the price, the account and the GST.
struct LineItemsEditor: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    @Binding var lines: [InvoiceLine]
    var sale = true

    var body: some View {
        let accounts = ledger.book.accounts.filter { sale ? $0.type == .income : ($0.type == .expense || ($0.type == .asset && $0.gst == .capital)) }
        VStack(spacing: 6) {
            HStack {
                Text("Description").frame(maxWidth: .infinity, alignment: .leading)
                Text("Qty").frame(width: 56, alignment: .trailing)
                Text("Price ex GST").frame(width: 100, alignment: .trailing)
                Text("Account").frame(width: 190, alignment: .leading)
                Text("GST").frame(width: 120, alignment: .leading)
                Text("Amount").frame(width: 90, alignment: .trailing)
                Spacer().frame(width: 20)
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(theme.inkTertiary(scheme))
            ForEach($lines) { $line in
                HStack {
                    TextField("What it's for", text: $line.description)
                        .frame(maxWidth: .infinity)
                    TextField("1", value: $line.quantity, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                    MoneyField(title: "0.00", cents: $line.unitPrice)
                        .frame(width: 100)
                    Picker("", selection: $line.account) {
                        ForEach(accounts) { account in Text(account.label).tag(account.code) }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                    .onChange(of: line.account) { _, code in
                        if let account = ledger.book.account(code), ledger.book.settings.gstRegistered { line.gst = account.gst == .excluded ? .gst : account.gst }
                    }
                    Picker("", selection: $line.gst) {
                        ForEach(GSTCode.allCases) { code in Text(code.title).tag(code) }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                    LedgerAmount(cents: line.net, width: 90)
                    Button {
                        lines.removeAll { $0.id == line.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .frame(width: 20)
                    .disabled(lines.count <= 1)
                }
            }
            HStack {
                Button {
                    let last = lines.last
                    lines.append(InvoiceLine(description: "", unitPrice: 0, account: last?.account ?? (sale ? "200" : "429"), gst: last?.gst ?? .gst))
                } label: {
                    Label("Add a line", systemImage: "plus")
                }
                .buttonStyle(.vellumSecondary)
                Spacer()
            }
        }
    }
}

// MARK: Contacts

struct ContactsPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    @State private var newName = ""

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("New contact", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(add)
                    Button("Add", action: add).buttonStyle(.vellumSecondary)
                }
                LedgerCard {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(ledger.book.contacts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { contact in
                                row(contact)
                            }
                        }
                    }
                }
            }
            .frame(width: 320)
            if let id = ledger.selectedContact, let contact = ledger.book.contact(id) {
                ContactDetail(contact: contact)
                    .id(contact.id)
            } else {
                Text("Pick a contact to see their details and what's owing.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        ledger.selectedContact = ledger.addContact(named: name)
        newName = ""
    }

    private func row(_ contact: Contact) -> some View {
        let selected = ledger.selectedContact == contact.id
        let owesYou = ledger.book.invoices.filter { $0.contact == contact.id && $0.kind == .sale }.reduce(0) { $0 + $1.owing }
        let youOwe = ledger.book.invoices.filter { $0.contact == contact.id && $0.kind == .bill }.reduce(0) { $0 + $1.owing }
        return Button {
            ledger.selectedContact = contact.id
        } label: {
            HStack {
                Text(contact.name).font(.system(size: 12.5, weight: selected ? .semibold : .regular)).foregroundStyle(theme.ink(scheme))
                Spacer()
                if owesYou > 0 { LedgerAmount(cents: owesYou, width: 90) }
                if youOwe > 0 { LedgerAmount(cents: -youOwe, width: 90) }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background { if selected { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(theme.raised(scheme)) } }
            .overlay(alignment: .bottom) { Rectangle().fill(theme.edge(scheme)).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ContactDetail: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    @State var contact: Contact

    var body: some View {
        let invoices = ledger.book.invoices.filter { $0.contact == contact.id && $0.status != .void }.sorted { $0.issued > $1.issued }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Name", text: $contact.name).font(theme.display(22)).textFieldStyle(.plain)
                LedgerCard {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow { label("Email"); TextField("", text: $contact.email) }
                        GridRow { label("Phone"); TextField("", text: $contact.phone) }
                        GridRow { label("ABN"); TextField("", text: $contact.abn) }
                        GridRow { label("Address"); TextField("", text: $contact.address, axis: .vertical).lineLimit(2...4) }
                    }
                    .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Button("New invoice") { ledger.newInvoice(.sale, for: contact.id) }.buttonStyle(.vellumPrimary)
                    Button("New bill") { ledger.newInvoice(.bill, for: contact.id) }.buttonStyle(.vellumSecondary)
                    Spacer()
                    Button("Delete") { ledger.deleteContact(contact.id) }.buttonStyle(.vellumSecondary)
                }
                if !invoices.isEmpty {
                    SectionLabel(text: "Invoices and bills")
                    LedgerCard {
                        ForEach(invoices) { invoice in
                            HStack {
                                Text(invoice.number).font(.system(size: 12.5).monospacedDigit())
                                Text(invoice.kind == .sale ? "Invoice" : "Bill").font(.system(size: 11)).foregroundStyle(theme.inkTertiary(scheme))
                                Spacer()
                                Text(invoice.status.title).font(.system(size: 11)).foregroundStyle(theme.inkSecondary(scheme))
                                LedgerAmount(cents: invoice.total)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                ledger.selectedInvoice = invoice.id
                                ledger.tab = invoice.kind == .sale ? .invoices : .bills
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
        .vellum(level: 2, radius: max(theme.radius - 2, 10))
        .onChange(of: contact) { _, updated in ledger.update(updated) }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(theme.inkTertiary(scheme)).frame(width: 60, alignment: .leading)
    }
}

// MARK: Reports

struct ReportsPanel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    private var report: Report { ledger.report }

    enum Report: String, CaseIterable, Identifiable {
        case profit, balance, cash, trial, receivables, payables, budget, audit
        var id: String { rawValue }
        var title: String {
            switch self {
            case .profit: return "Profit and loss"
            case .balance: return "Balance sheet"
            case .cash: return "Cash"
            case .trial: return "Trial balance"
            case .receivables: return "Owed to you"
            case .payables: return "You owe"
            case .budget: return "Budget"
            case .audit: return "Audit trail"
            }
        }
    }

    var body: some View {
        let dates = ledger.range(ledger.period)
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $ledger.report) {
                ForEach(Report.allCases) { item in Text(item.title).tag(item) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 780)
            if report == .audit {
                AuditTrailView()
            } else {
                HStack(spacing: 10) {
                    Picker("", selection: $ledger.period) {
                        ForEach(LedgerPeriod.allCases) { item in Text(item.title).tag(item) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Text(caption(dates))
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button("Open in Sheets") {
                        model.sheets.add(ledger.accountantPack())
                        model.go(to: .sheets)
                    }
                    .buttonStyle(.vellumSecondary)
                    .help("Every report as a workbook in Sheets, with live totals")
                    Button("Accountant's pack…") { ledger.exportPack() }
                        .buttonStyle(.vellumPrimary)
                        .help("Profit and loss, balance sheet, trial balance, general ledger, GST and aged lists as one Excel file")
                }
                ScrollView {
                    LedgerCard {
                        switch report {
                        case .profit: profit(dates)
                        case .balance: balance(dates.end)
                        case .cash: cash(dates)
                        case .trial: trial(dates.end)
                        case .receivables: aged(.sale, dates.end)
                        case .payables: aged(.bill, dates.end)
                        case .budget: BudgetReport(dates: dates)
                    case .audit: EmptyView()
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                }
            }
        }
    }

    private func caption(_ dates: (start: Date, end: Date)) -> String {
        switch report {
        case .balance, .trial, .receivables, .payables: return "At \(min(dates.end, ledger.today).fullDay)"
        default: return "\(dates.start.fullDay) to \(dates.end.fullDay)"
        }
    }

    @ViewBuilder
    private func profit(_ dates: (start: Date, end: Date)) -> some View {
        let report = ledger.book.profitAndLoss(from: dates.start, to: dates.end)
        ReportRow(label: "Income", cents: nil, bold: true)
        ForEach(report.income) { line in ReportRow(label: line.account.name, cents: line.amount, indent: 12) }
        ReportRow(label: "Total income", cents: report.totalIncome, bold: true)
        ReportRow(label: "Expenses", cents: nil, bold: true).padding(.top, 8)
        ForEach(report.expenses.sorted { $0.amount > $1.amount }) { line in ReportRow(label: line.account.name, cents: line.amount, indent: 12) }
        ReportRow(label: "Total expenses", cents: report.totalExpenses, bold: true)
        ReportRow(label: report.net >= 0 ? "Net profit" : "Net loss", cents: report.net, bold: true).padding(.top, 8)
    }

    @ViewBuilder
    private func balance(_ date: Date) -> some View {
        let sheet = ledger.book.balanceSheet(asOf: min(date, ledger.today))
        ReportRow(label: "Assets", cents: nil, bold: true)
        ForEach(sheet.assets) { line in ReportRow(label: line.account.name, cents: line.amount, indent: 12) }
        ReportRow(label: "Total assets", cents: sheet.totalAssets, bold: true)
        ReportRow(label: "Liabilities", cents: nil, bold: true).padding(.top, 8)
        ForEach(sheet.liabilities) { line in ReportRow(label: line.account.name, cents: line.amount, indent: 12) }
        ReportRow(label: "Total liabilities", cents: sheet.totalLiabilities, bold: true)
        ReportRow(label: "Net assets", cents: sheet.totalAssets - sheet.totalLiabilities, bold: true).padding(.top, 8)
        ReportRow(label: "Equity", cents: nil, bold: true).padding(.top, 8)
        ForEach(sheet.equity) { line in ReportRow(label: line.account.name, cents: line.amount, indent: 12) }
        if sheet.earlierEarnings != 0 { ReportRow(label: "Earlier years' earnings", cents: sheet.earlierEarnings, indent: 12) }
        ReportRow(label: "This year's earnings", cents: sheet.currentEarnings, indent: 12)
        ReportRow(label: "Total equity", cents: sheet.totalEquity, bold: true)
        if !sheet.balances {
            Text("This doesn't balance, which means an entry is wrong. Tell George.")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.inkSecondary(scheme))
        }
    }

    @ViewBuilder
    private func cash(_ dates: (start: Date, end: Date)) -> some View {
        let rows = ledger.book.cashSummary(from: dates.start, to: dates.end)
        ForEach(rows) { row in
            ReportRow(label: row.account.name, cents: nil, bold: true)
            ReportRow(label: "Opening balance", cents: row.opening, indent: 12)
            ReportRow(label: "Money in", cents: row.moneyIn, indent: 12)
            ReportRow(label: "Money out", cents: -row.moneyOut, indent: 12)
            ReportRow(label: "Closing balance", cents: row.closing, bold: true)
        }
    }

    @ViewBuilder
    private func trial(_ date: Date) -> some View {
        let rows = ledger.book.trialBalance(asOf: min(date, ledger.today))
        HStack {
            Text("Account").frame(maxWidth: .infinity, alignment: .leading)
            Text("Debit").frame(width: 110, alignment: .trailing)
            Text("Credit").frame(width: 110, alignment: .trailing)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(theme.inkTertiary(scheme))
        ForEach(rows) { row in
            HStack {
                Text(row.account.label).font(.system(size: 12.5)).foregroundStyle(theme.ink(scheme)).frame(maxWidth: .infinity, alignment: .leading)
                Text(row.debit == 0 ? "" : LedgerMoney.text(row.debit)).font(.system(size: 12.5).monospacedDigit()).frame(width: 110, alignment: .trailing)
                Text(row.credit == 0 ? "" : LedgerMoney.text(row.credit)).font(.system(size: 12.5).monospacedDigit()).frame(width: 110, alignment: .trailing)
            }
            .foregroundStyle(theme.ink(scheme))
            .padding(.vertical, 3)
        }
        HStack {
            Text("Total").font(.system(size: 12.5, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
            Text(LedgerMoney.text(rows.reduce(0) { $0 + $1.debit })).font(.system(size: 12.5, weight: .semibold).monospacedDigit()).frame(width: 110, alignment: .trailing)
            Text(LedgerMoney.text(rows.reduce(0) { $0 + $1.credit })).font(.system(size: 12.5, weight: .semibold).monospacedDigit()).frame(width: 110, alignment: .trailing)
        }
        .foregroundStyle(theme.ink(scheme))
        .padding(.top, 6)
    }

    @ViewBuilder
    private func aged(_ kind: Invoice.Kind, _ date: Date) -> some View {
        let rows = ledger.book.aged(kind, asOf: min(date, ledger.today))
        if rows.isEmpty {
            Text(kind == .sale ? "Nobody owes you anything." : "You don't owe anyone.")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.inkTertiary(scheme))
        } else {
            HStack {
                Text("Contact").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(AgedRow.titles, id: \.self) { title in Text(title).frame(width: 86, alignment: .trailing) }
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(theme.inkTertiary(scheme))
            ForEach(rows) { row in
                HStack {
                    Text(row.contact.name).font(.system(size: 12.5)).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                    ForEach(Array(row.buckets.enumerated()), id: \.offset) { item in
                        Text(item.element == 0 ? "" : LedgerMoney.text(item.element))
                            .font(.system(size: 12.5, weight: item.offset >= 2 && item.element > 0 ? .semibold : .regular).monospacedDigit())
                            .frame(width: 86, alignment: .trailing)
                    }
                }
                .foregroundStyle(theme.ink(scheme))
                .padding(.vertical, 3)
            }
            ReportRow(label: "Total", cents: rows.reduce(0) { $0 + $1.total }, bold: true)
        }
    }
}

// MARK: GST

struct GSTPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    @State private var back = 0

    var body: some View {
        let calendar = ledger.book.calendar
        let anchor = calendar.date(byAdding: .month, value: -3 * back, to: ledger.today) ?? ledger.today
        let quarter = ledger.book.quarter(containing: anchor)
        let figures = ledger.book.bas(from: quarter.start, to: quarter.end)
        let due = ledger.basDue(for: quarter.end)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Picker("", selection: $back) {
                        Text("This quarter").tag(0)
                        Text("Last quarter").tag(1)
                        Text("Two quarters ago").tag(2)
                        Text("Three quarters ago").tag(3)
                    }
                    .labelsHidden()
                    .fixedSize()
                    Text("\(quarter.start.fullDay) to \(quarter.end.fullDay)")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.inkSecondary(scheme))
                    Spacer()
                    Toggle("Cash basis", isOn: Binding(get: { ledger.book.settings.cashBasis }, set: { value in
                        var settings = ledger.book.settings
                        settings.cashBasis = value
                        ledger.updateSettings(settings)
                    }))
                    .help("Cash basis counts GST when money moves; accrual when invoices and bills are dated. Use the one you're registered for.")
                    Button("Copy figures") { copy(figures, quarter) }
                        .buttonStyle(.vellumSecondary)
                }

                HStack(alignment: .top, spacing: 12) {
                    box(figures.net >= 0 ? "To pay the ATO" : "Refund from the ATO", LedgerMoney.text(abs(figures.net)),
                        "Due \(due.fullDay)" + (back == 0 ? ", once the quarter ends" : ""), big: true)
                    box("1A · GST on sales", LedgerMoney.text(figures.gstOnSales), "From \(LedgerMoney.text(figures.totalSales)) of sales")
                    box("1B · GST on purchases", LedgerMoney.text(figures.gstOnPurchases), "Credits you can claim")
                }

                LedgerCard {
                    SectionLabel(text: "For the activity statement (whole dollars)")
                    basRow("G1", "Total sales, including GST", figures.totalSales)
                    basRow("G3", "GST-free sales", figures.gstFreeSales)
                    basRow("G10", "Capital purchases, including GST", figures.capitalPurchases)
                    basRow("G11", "Other purchases, including GST", figures.otherPurchases)
                    basRow("1A", "GST on sales", figures.gstOnSales)
                    basRow("1B", "GST on purchases", figures.gstOnPurchases)
                }
                .frame(maxWidth: 640, alignment: .leading)

                if !ledger.book.unreconciled.isEmpty {
                    Text("\(ledger.book.unreconciled.count) bank \(ledger.book.unreconciled.count == 1 ? "line isn't" : "lines aren't") reconciled yet, so these figures may change.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.inkSecondary(scheme))
                }
                if back > 0 || quarter.end < ledger.today {
                    if ledger.book.isLocked(quarter.end) {
                        Label("Locked. Nothing in this quarter can change.", systemImage: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.inkSecondary(scheme))
                    } else {
                        HStack(spacing: 10) {
                            Button {
                                ledger.setLockDate(quarter.end)
                            } label: {
                                Label("Lodged? Lock the books up to \(quarter.end.fullDay)", systemImage: "lock")
                            }
                            .buttonStyle(.vellumSecondary)
                            Text("So nothing in a lodged quarter changes by accident. You can unlock it in Settings.")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.inkTertiary(scheme))
                        }
                    }
                }
                Text("George works these out from your books on the \(ledger.book.settings.cashBasis ? "cash" : "accrual") basis. Check them with your tax agent before you lodge. This isn't tax advice.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func box(_ label: String, _ value: String, _ detail: String, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: label)
            Text(value)
                .font(theme.display(big ? 34 : 26))
                .foregroundStyle(theme.ink(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.inkTertiary(scheme))
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .vellum(level: 3, radius: max(theme.radius - 4, 8))
    }

    private func basRow(_ code: String, _ label: String, _ cents: Cents) -> some View {
        HStack(spacing: 12) {
            Text(code)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(theme.ink(scheme))
                .frame(width: 34, alignment: .leading)
            Text(label).font(.system(size: 12.5)).foregroundStyle(theme.ink(scheme))
            Spacer()
            Text("$\(LedgerMoney.wholeDollars(cents).formatted())")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(theme.ink(scheme))
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.edge(scheme)).frame(height: 0.5) }
    }

    private func copy(_ figures: BASFigures, _ quarter: (start: Date, end: Date)) {
        let text = """
        GST \(quarter.start.fullDay) to \(quarter.end.fullDay)
        G1 \(LedgerMoney.wholeDollars(figures.totalSales))
        G3 \(LedgerMoney.wholeDollars(figures.gstFreeSales))
        G10 \(LedgerMoney.wholeDollars(figures.capitalPurchases))
        G11 \(LedgerMoney.wholeDollars(figures.otherPurchases))
        1A \(LedgerMoney.wholeDollars(figures.gstOnSales))
        1B \(LedgerMoney.wholeDollars(figures.gstOnPurchases))
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ledger.notice = "Copied the GST figures."
    }
}

// MARK: Settings

struct LedgerSettingsView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    @State var settings: LedgerSettings
    @State private var reminderText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your business").font(theme.display(24)).foregroundStyle(theme.ink(scheme))
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
                GridRow { label("Name"); TextField("", text: $settings.businessName) }
                GridRow { label("ABN"); TextField("", text: $settings.abn) }
                GridRow { label("Email"); TextField("", text: $settings.email) }
                GridRow { label("Address"); TextField("", text: $settings.address, axis: .vertical).lineLimit(2...4) }
                GridRow { label("Paid into"); HStack { TextField("BSB", text: $settings.bsb).frame(width: 90); TextField("Account number", text: $settings.accountNumber) } }
                GridRow { label("Account name"); TextField("", text: $settings.accountName) }
                GridRow { label("Invoices"); HStack {
                    TextField("Prefix", text: $settings.invoicePrefix).frame(width: 80)
                    Text("next").foregroundStyle(theme.inkTertiary(scheme))
                    TextField("", value: $settings.nextInvoice, format: .number).frame(width: 60)
                    Text("due in").foregroundStyle(theme.inkTertiary(scheme))
                    TextField("", value: $settings.paymentDays, format: .number).frame(width: 50)
                    Text("days").foregroundStyle(theme.inkTertiary(scheme))
                } }
                GridRow { label("Quotes"); HStack {
                    TextField("Prefix", text: $settings.quotePrefix).frame(width: 80)
                    Text("next").foregroundStyle(theme.inkTertiary(scheme))
                    TextField("", value: $settings.nextQuote, format: .number).frame(width: 60)
                    Text("good for").foregroundStyle(theme.inkTertiary(scheme))
                    TextField("", value: $settings.quoteDays, format: .number).frame(width: 50)
                    Text("days").foregroundStyle(theme.inkTertiary(scheme))
                } }
                GridRow { label("GST"); VStack(alignment: .leading) {
                    Toggle("Registered for GST", isOn: $settings.gstRegistered)
                    Toggle("Report GST on the cash basis", isOn: $settings.cashBasis).disabled(!settings.gstRegistered)
                } }
                GridRow { label("Reminders"); HStack {
                    TextField("3, 14, 30", text: $reminderText).frame(width: 110)
                    Text("days late. Marc drafts a friendly one, a firmer one, then a final one, for you to approve.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                } }
                GridRow { label("Lock date"); VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Toggle("Lock the books", isOn: Binding(get: { settings.lockDate != nil }, set: { on in
                            let quarter = ledger.book.quarter(containing: ledger.today)
                            settings.lockDate = on ? (Calendar.current.date(byAdding: .day, value: -1, to: quarter.start) ?? ledger.today) : nil
                        }))
                        if settings.lockDate != nil {
                            DatePicker("up to", selection: Binding(get: { settings.lockDate ?? ledger.today }, set: { settings.lockDate = $0 }),
                                       displayedComponents: .date)
                                .fixedSize()
                        }
                    }
                    Text("Nothing on or before the lock date can be added, changed or removed. Lock a quarter once its BAS is lodged.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                } }
            }
            .textFieldStyle(.roundedBorder)
            .onAppear { reminderText = settings.reminderDays.map(String.init).joined(separator: ", ") }
            HStack {
                Button("Back to the sample books") {
                    ledger.useSample()
                    ledger.showsSettings = false
                }
                .buttonStyle(.vellumSecondary)
                Button("Start fresh") {
                    ledger.startFresh()
                    ledger.showsSettings = false
                }
                .buttonStyle(.vellumSecondary)
                Spacer()
                Button("Cancel") { ledger.showsSettings = false }
                    .buttonStyle(.vellumSecondary)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let days = reminderText.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.filter { $0 >= 0 && $0 < 400 }
                    settings.reminderDays = Array(Set(days)).sorted()
                    ledger.updateSettings(settings)
                    ledger.showsSettings = false
                }
                .buttonStyle(.vellumPrimary)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 600)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(theme.inkSecondary(scheme)).frame(width: 96, alignment: .leading)
    }
}
