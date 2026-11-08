import AppKit
import SwiftUI
import UniformTypeIdentifiers

// George's money out: his checks, receipts to match, purchases that need their tax invoice, and expense claims.

struct SpendPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    @State private var claiming: Set<UUID> = []
    @State private var dropping = false
    @State private var showsMatched = false

    var body: some View {
        let book = ledger.book
        let unmatched = book.receipts.filter { !$0.isMatched }.sorted { $0.date > $1.date }
        let matched = book.receipts.filter(\.isMatched).sorted { $0.date > $1.date }
        let yearStart = book.financialYearStart(for: ledger.today)
        let missing = book.missingReceipts(from: yearStart, to: ledger.today)
        let checks = ledger.checks
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !checks.isEmpty { checksCard(checks) }

                // Receipts
                HStack(spacing: 10) {
                    SectionLabel(text: unmatched.isEmpty ? "Receipts" : "Receipts to match · \(unmatched.count)")
                    Spacer()
                    if !unmatched.isEmpty {
                        Button("Match the sure ones") { withAnimation(theme.spring) { ledger.matchReceipts() } }
                            .buttonStyle(.vellumSecondary)
                    }
                    Button {
                        ledger.chooseReceipts()
                    } label: {
                        Label("Add receipts…", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.vellumPrimary)
                }
                LedgerCard {
                    if unmatched.isEmpty {
                        Text(book.receipts.isEmpty ? "Drop receipts here: PDFs, photos or scans. George reads them on this Mac and matches them to the bank."
                             : "Every receipt is matched. Drop more here, or forward them from Mail.")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.inkTertiary(scheme))
                            .frame(maxWidth: .infinity, minHeight: 54)
                    } else {
                        ForEach(unmatched) { receipt in
                            ReceiptRow(receipt: receipt, claiming: Binding(get: { claiming.contains(receipt.id) }, set: { on in
                                if on { claiming.insert(receipt.id) } else { claiming.remove(receipt.id) }
                            }))
                        }
                        HStack {
                            Text(claiming.isEmpty ? "Paid for something yourself? Tick it and put it on a claim." : "\(claiming.count) ticked · \(LedgerMoney.text(claimTotal))")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.inkTertiary(scheme))
                            Spacer()
                            Button("Put on an expense claim") {
                                ledger.claim(Array(claiming))
                                claiming = []
                            }
                            .buttonStyle(.vellumSecondary)
                            .disabled(claiming.isEmpty)
                        }
                        .padding(.top, 4)
                    }
                    if !matched.isEmpty {
                        Button {
                            withAnimation(theme.spring) { showsMatched.toggle() }
                        } label: {
                            Label("\(matched.count) matched", systemImage: showsMatched ? "chevron.down" : "chevron.right")
                                .font(.system(size: 11.5))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.inkSecondary(scheme))
                        if showsMatched {
                            ForEach(matched.prefix(60)) { receipt in matchedRow(receipt) }
                        }
                    }
                }
                .overlay {
                    if dropping {
                        RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous)
                            .strokeBorder(theme.ink(scheme), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    }
                }
                .dropDestination(for: URL.self) { urls, _ in
                    ledger.addReceiptFiles(urls)
                    return true
                } isTargeted: { dropping = $0 }

                // Purchases that need their tax invoice
                if !missing.isEmpty {
                    HStack {
                        SectionLabel(text: "Need their tax invoice · \(missing.count)")
                        Spacer()
                        Text("\(LedgerMoney.text(book.gstWaitingOnReceipts(from: yearStart, to: ledger.today))) of GST credits this financial year")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                    LedgerCard {
                        ForEach(missing.prefix(40)) { line in missingRow(line) }
                        Text("The ATO asks for a tax invoice for any purchase over $82.50 (GST included) before you claim its GST. Bills you've entered already count.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(theme.inkTertiary(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ClaimsCard()
            }
            .padding(.bottom, 20)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .animation(theme.spring, value: unmatched.count)
    }

    private var claimTotal: Cents {
        claiming.compactMap { ledger.book.receipt($0)?.total }.reduce(0, +)
    }

    private func checksCard(_ checks: [LedgerCheck]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AgentLogo(code: "ge", size: 16, color: theme.inkSecondary(scheme))
                Text(checks.count == 1 ? "George found one thing to look at" : "George found \(checks.count) things to look at")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.ink(scheme))
            }
            ForEach(checks) { check in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(theme.ink(scheme))
                        Text(check.detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.inkSecondary(scheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button("Look") { withAnimation(theme.spring) { ledger.open(check) } }
                        .buttonStyle(.vellumSecondary)
                    Button {
                        withAnimation(theme.spring) { ledger.dismiss(check) }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .help("It's fine; don't show this again")
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .vellum(level: 3, radius: max(theme.radius - 4, 8))
    }

    private func matchedRow(_ receipt: LedgerReceipt) -> some View {
        let line = receipt.bankLine.flatMap { id in ledger.book.bank.first { $0.id == id } }
        let bill = receipt.bill.flatMap { ledger.book.invoice($0) }
        return HStack(spacing: 10) {
            Image(systemName: "paperclip")
                .font(.system(size: 11))
                .foregroundStyle(theme.inkTertiary(scheme))
            Text(receipt.vendor)
                .font(.system(size: 12))
                .foregroundStyle(theme.ink(scheme))
                .lineLimit(1)
            Text(line.map { "\($0.description) · \($0.date.shortDay)" } ?? bill.map { "\($0.number)" } ?? "")
                .font(.system(size: 11))
                .foregroundStyle(theme.inkTertiary(scheme))
                .lineLimit(1)
            Spacer(minLength: 8)
            LedgerAmount(cents: -receipt.total, width: 90)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Open the receipt") { ledger.openReceipt(receipt) }.disabled(receipt.file.isEmpty)
            Button("Unmatch") { ledger.detachReceipt(receipt.id) }.disabled(receipt.bill != nil)
            Button("Delete receipt", role: .destructive) { ledger.deleteReceipt(receipt.id) }
        }
    }

    private func missingRow(_ line: BankLine) -> some View {
        HStack(spacing: 10) {
            Text(line.date.shortDay)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(theme.inkTertiary(scheme))
                .frame(width: 52, alignment: .leading)
            Text(line.description)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.ink(scheme))
                .lineLimit(1)
            Spacer(minLength: 8)
            LedgerAmount(cents: line.amount, width: 96)
            Button("I have it…") { ledger.addReceipt(for: line) }
                .buttonStyle(.vellumSecondary)
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.edge(scheme)).frame(height: 0.5) }
    }
}

/// An unmatched receipt: what it says, and the bank line George thinks it is.
private struct ReceiptRow: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    var receipt: LedgerReceipt
    @Binding var claiming: Bool
    @State private var editing = false

    var body: some View {
        let candidates = ledger.book.candidates(for: receipt)
        HStack(alignment: .center, spacing: 10) {
            Toggle("", isOn: $claiming)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help("Paid for it yourself: tick to put it on an expense claim")
            Image(systemName: receipt.source == .mail ? "envelope" : "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(theme.inkTertiary(scheme))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.vendor)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(theme.ink(scheme))
                    .lineLimit(1)
                Text(detail(candidates.first?.line))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            LedgerAmount(cents: -receipt.total, bold: receipt.total == 0, width: 90)
            if let best = candidates.first {
                Button("Match") { withAnimation(theme.spring) { ledger.attachReceipt(receipt.id, to: best.line.id) } }
                    .buttonStyle(.vellumPrimary)
                    .help("\(best.line.description), \(best.line.date.shortDay)")
            }
            Menu {
                Button("Edit…") { editing = true }
                Button("Open the receipt") { ledger.openReceipt(receipt) }.disabled(receipt.file.isEmpty)
                if candidates.count > 1 {
                    Section("Or match it to") {
                        ForEach(Array(candidates.dropFirst().prefix(4).map { $0.line })) { other in
                            Button("\(other.description), \(other.date.shortDay)") { ledger.attachReceipt(receipt.id, to: other.id) }
                        }
                    }
                }
                Divider()
                Button("Delete", role: .destructive) { ledger.deleteReceipt(receipt.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .popover(isPresented: $editing, arrowEdge: .bottom) { ReceiptEditor(receipt: receipt, done: { editing = false }) }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.edge(scheme)).frame(height: 0.5) }
    }

    private func detail(_ line: BankLine?) -> String {
        var parts = [receipt.date.shortDay]
        if let gst = receipt.gst, gst > 0 { parts.append("GST \(LedgerMoney.text(gst))") }
        if receipt.total == 0 {
            parts.append("no total read: edit it")
        } else if let line {
            parts.append("probably \(line.description), \(line.date.shortDay)")
        } else {
            parts.append("no bank line yet")
        }
        return parts.joined(separator: " · ")
    }
}

private struct ReceiptEditor: View {
    @EnvironmentObject private var ledger: LedgerModel
    @State var receipt: LedgerReceipt
    var done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Receipt").font(.system(size: 13, weight: .semibold))
            TextField("Who from", text: $receipt.vendor)
            HStack {
                Text("Total")
                MoneyField(title: "0.00", cents: $receipt.total).frame(width: 110)
            }
            DatePicker("Date", selection: $receipt.date, displayedComponents: .date)
            TextField("Note", text: $receipt.note)
            HStack {
                Spacer()
                Button("Save") {
                    ledger.updateReceipt(receipt)
                    done()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(16)
        .frame(width: 300)
    }
}

/// Expense claims: what the business owes you for things you paid.
private struct ClaimsCard: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let claims = ledger.book.claims
        HStack {
            SectionLabel(text: "Expense claims")
            Spacer()
            if ledger.book.owedOnClaims > 0 {
                Text("Owed to you \(LedgerMoney.text(ledger.book.owedOnClaims))")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(theme.inkSecondary(scheme))
            }
        }
        LedgerCard {
            if claims.isEmpty {
                Text("Paid for something for the business yourself? Tick its receipt above and put it on a claim. It's paid back like a bill.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(claims) { claim in
                    Button {
                        ledger.selectedInvoice = claim.id
                        ledger.tab = .bills
                    } label: {
                        HStack(spacing: 10) {
                            Text(claim.number)
                                .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(theme.ink(scheme))
                            Text("\(ledger.book.contact(claim.contact)?.name ?? "") · \(claim.lines.count) \(claim.lines.count == 1 ? "item" : "items") · \(claim.issued.shortDay)")
                                .font(.system(size: 11.5))
                                .foregroundStyle(theme.inkTertiary(scheme))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Chip(text: claim.owing > 0 ? "To pay back" : claim.status.title, filled: claim.owing == 0)
                            LedgerAmount(cents: claim.total, width: 90)
                        }
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: Budget against actual

struct BudgetReport: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    var dates: (start: Date, end: Date)
    @State private var editing = false

    var body: some View {
        let end = min(dates.end, ledger.today)
        let rows = ledger.book.budgetReport(from: dates.start, to: end)
        let income = rows.filter { $0.account.type == .income }
        let costs = rows.filter { $0.account.type == .expense }
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Budget to \(end.fullDay), against what happened")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                Spacer()
                Button("Edit budgets…") { editing = true }
                    .buttonStyle(.vellumSecondary)
            }
            if ledger.book.budgets.isEmpty {
                Text("No budgets yet. Set a monthly figure for the accounts that matter, or start from last year's.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .padding(.vertical, 8)
            }
            header
            if !income.isEmpty {
                section("Income", income)
            }
            if !costs.isEmpty {
                section("Spending", costs)
            }
            BudgetLine(label: "Profit", budget: Self.total(income, \.budget) - Self.total(costs, \.budget),
                       actual: Self.total(income, \.actual) - Self.total(costs, \.actual),
                       variance: Self.total(income, \.variance) + Self.total(costs, \.variance), used: nil, bold: true)
        }
        .sheet(isPresented: $editing) {
            BudgetEditor(done: { editing = false })
                .environmentObject(ledger)
                .environmentObject(theme)
        }
    }

    static func total(_ rows: [BudgetRow], _ key: KeyPath<BudgetRow, Cents>) -> Cents {
        var sum = 0
        for row in rows { sum += row[keyPath: key] }
        return sum
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("").frame(maxWidth: .infinity, alignment: .leading)
            Text("Budget").frame(width: 100, alignment: .trailing)
            Text("Actual").frame(width: 100, alignment: .trailing)
            Text("Better or worse").frame(width: 110, alignment: .trailing)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(theme.inkTertiary(scheme))
        .padding(.top, 8)
    }

    @ViewBuilder
    private func section(_ title: String, _ rows: [BudgetRow]) -> some View {
        SectionLabel(text: title).padding(.top, 8)
        ForEach(rows) { row in
            BudgetLine(label: row.account.name, budget: row.budget, actual: row.actual, variance: row.variance, used: row.used)
        }
        BudgetLine(label: "Total \(title.lowercased())", budget: Self.total(rows, \.budget), actual: Self.total(rows, \.actual),
                   variance: Self.total(rows, \.variance), used: nil, bold: true)
    }
}

private struct BudgetLine: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var label: String
    var budget: Cents
    var actual: Cents
    var variance: Cents
    var used: Double?
    var bold = false

    private var varianceText: String {
        if variance == 0 { return "–" }
        return (variance > 0 ? "+" : "−") + LedgerMoney.text(abs(variance))
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 12.5, weight: bold ? .semibold : .regular))
                    .foregroundStyle(theme.ink(scheme))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LedgerAmount(cents: budget, bold: bold, width: 100)
                LedgerAmount(cents: actual, bold: bold, width: 100)
                Text(varianceText)
                    .font(.system(size: 12.5, weight: variance < 0 ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(variance < 0 ? theme.ink(scheme) : theme.inkSecondary(scheme))
                    .frame(width: 110, alignment: .trailing)
            }
            if let used {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.edge(scheme))
                        Capsule().fill(used > 1 ? theme.ink(scheme) : theme.inkTertiary(scheme))
                            .frame(width: proxy.size.width * min(1, max(0, used)))
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            if bold { Rectangle().fill(theme.edge(scheme)).frame(height: 0.5) }
        }
    }
}

/// Monthly budgets, account by account.
private struct BudgetEditor: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    var done: () -> Void
    @State private var amounts: [String: Cents] = [:]

    var body: some View {
        let accounts = ledger.book.accounts.filter { $0.type == .income || $0.type == .expense }
        VStack(alignment: .leading, spacing: 12) {
            Text("Monthly budgets").font(theme.display(22)).foregroundStyle(theme.ink(scheme))
            Text("A figure a month for each account. Reports spread it over the days of each month, so part of a month counts in part.")
                .font(.system(size: 12))
                .foregroundStyle(theme.inkSecondary(scheme))
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(accounts) { account in
                        HStack {
                            Text(account.label).font(.system(size: 12.5)).lineLimit(1)
                            Spacer()
                            MoneyField(title: "0.00", cents: Binding(get: { amounts[account.code] ?? 0 }, set: { amounts[account.code] = $0 }))
                                .frame(width: 120)
                        }
                        .padding(.vertical, 4)
                        .overlay(alignment: .bottom) { Rectangle().fill(theme.edge(scheme)).frame(height: 0.5) }
                    }
                }
            }
            .frame(height: 360)
            HStack {
                Button("Start from last year") {
                    ledger.startBudgetsFromLastYear()
                    amounts = ledger.book.budgets
                }
                .buttonStyle(.vellumSecondary)
                Spacer()
                Button("Cancel", action: done)
                    .buttonStyle(.vellumSecondary)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    for account in accounts where (amounts[account.code] ?? 0) != (ledger.book.budgets[account.code] ?? 0) {
                        ledger.setBudget(account.code, monthly: amounts[account.code] ?? 0)
                    }
                    done()
                }
                .buttonStyle(.vellumPrimary)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520)
        .textFieldStyle(.roundedBorder)
        .onAppear { amounts = ledger.book.budgets }
    }
}
