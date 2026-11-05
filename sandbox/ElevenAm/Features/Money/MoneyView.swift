import Charts
import SwiftUI
import UniformTypeIdentifiers

/// George's app: where the money is, where it's going, and what happens next.
struct MoneyView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var money: MoneyModel
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "money", subtitle: subtitle) {
                HStack(spacing: 8) {
                    Menu {
                        Section("Books") {
                            Button("Import a bank statement…") { ledger.importStatement() }
                            Button("Your business and GST…") { ledger.showsSettings = true }
                        }
                        Section("Overview") {
                            Button("Sample transactions") { money.useSample() }
                            Button("Import bank CSV for the overview…") { importing = true }
                        }
                    } label: {
                        Label(ledger.book.settings.businessName, systemImage: "building.columns")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .foregroundStyle(theme.inkSecondary(scheme))
                    Button {
                        ledger.newInvoice(.sale)
                    } label: {
                        Label("New invoice", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.vellumPrimary)
                }
            }

            Picker("", selection: $ledger.tab) {
                ForEach(MoneyTab.allCases) { tab in
                    Text(tab == .bank && !ledger.book.unreconciled.isEmpty ? "Bank · \(ledger.book.unreconciled.count)" : tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 720)

            if let notice = ledger.notice ?? money.notice {
                HStack(spacing: 10) {
                    AgentLogo(code: "ge", size: 18, color: theme.inkSecondary(scheme))
                    Text(notice).font(.system(size: 12.5)).foregroundStyle(theme.ink(scheme)).lineLimit(2)
                    Spacer()
                    Button {
                        ledger.notice = nil
                        money.notice = nil
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkTertiary(scheme))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .vellum(level: 3, radius: max(theme.radius - 4, 8))
                .transition(.rise(theme.rise))
            }

            Group {
                switch ledger.tab {
                case .overview: MoneyOverview()
                case .bank: BankPanel()
                case .invoices: InvoicesPanel(kind: .sale)
                case .quotes: QuotesPanel()
                case .bills: InvoicesPanel(kind: .bill)
                case .contacts: ContactsPanel()
                case .reports: ReportsPanel()
                case .gst: GSTPanel()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
        .animation(theme.spring, value: ledger.tab)
        .animation(theme.spring, value: ledger.notice)
        .task(id: ledger.notice) {
            guard ledger.notice != nil, (try? await Task.sleep(for: .seconds(10))) != nil else { return }
            ledger.notice = nil
        }
        .sheet(item: $ledger.editing) { invoice in
            InvoiceEditor(invoice: invoice)
                .environmentObject(ledger)
                .environmentObject(theme)
        }
        .sheet(item: $ledger.editingQuote) { quote in
            QuoteEditor(quote: quote)
                .environmentObject(ledger)
                .environmentObject(theme)
        }
        .sheet(item: $ledger.editingSchedule) { schedule in
            ScheduleEditor(schedule: schedule)
                .environmentObject(ledger)
                .environmentObject(theme)
        }
        .sheet(item: $ledger.reviewing) { review in
            ReminderSheet(review: review)
                .environmentObject(ledger)
                .environmentObject(theme)
        }
        .sheet(isPresented: $ledger.showsSettings) {
            LedgerSettingsView(settings: ledger.book.settings)
                .environmentObject(ledger)
                .environmentObject(theme)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText, .data]) { result in
            if case .success(let url) = result { withAnimation(theme.spring) { money.importCSV(url) } }
        }
    }

    private var subtitle: String {
        let open = ledger.book.unreconciled.count
        return "George · never invents a number" + (open > 0 ? " · \(open) bank \(open == 1 ? "line" : "lines") to reconcile" : "")
    }
}

/// Cash, burn and runway, with what the books say is owed.
private struct MoneyOverview: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var money: MoneyModel
    @EnvironmentObject private var ledger: LedgerModel

    var body: some View {
        let quarter = ledger.book.quarter(containing: ledger.today)
        let gst = ledger.book.bas(from: quarter.start, to: quarter.end)
        let overdue = ledger.book.overdue(.sale, on: ledger.today)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    CashTile().entrance(0)
                    StatTile(label: "Net burn / month", value: Money.short(money.netBurn), detail: "\(Money.short(money.grossBurn)) out, \(Money.short(money.monthlyRevenue)) in").entrance(1)
                    StatTile(label: "Revenue / month", value: Money.short(money.monthlyRevenue), detail: "Average of the last 3 months").entrance(2)
                    StatTile(label: "Runway", value: money.runwayMonths.map { String(format: "%.1f mo", $0) } ?? "∞", detail: money.runwayMonths == nil ? "Not burning cash" : "At the current net burn").entrance(3)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    Button { ledger.tab = .invoices } label: {
                        StatTile(label: "Owed to you", value: LedgerMoney.text(ledger.book.owedToYou),
                                 detail: overdue.isEmpty ? "Nothing overdue" : "\(LedgerMoney.text(overdue.reduce(0) { $0 + $1.owing })) overdue on \(overdue.count)")
                    }
                    .buttonStyle(.plain)
                    Button { ledger.tab = .bills } label: {
                        StatTile(label: "You owe", value: LedgerMoney.text(ledger.book.youOwe), detail: "On bills you've approved")
                    }
                    .buttonStyle(.plain)
                    Button { ledger.tab = .gst } label: {
                        StatTile(label: "GST this quarter", value: LedgerMoney.text(abs(gst.net)), detail: gst.net >= 0 ? "To pay so far" : "Refund so far")
                    }
                    .buttonStyle(.plain)
                    Button { ledger.tab = .bank } label: {
                        StatTile(label: "To reconcile", value: "\(ledger.book.unreconciled.count)", detail: "Bank lines George needs you for")
                    }
                    .buttonStyle(.plain)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        MonthChart().frame(minWidth: 340)
                        CategoryBreakdown().frame(width: 260)
                    }
                    VStack(spacing: 12) {
                        MonthChart()
                        CategoryBreakdown()
                    }
                }

                AskGeorge()

                TransactionList()
            }
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
    }
}

private struct StatTile: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var label: String
    var value: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: label)
            Text(value)
                .font(theme.display(30))
                .foregroundStyle(theme.ink(scheme))
                .contentTransition(.numericText())
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
}

/// Cash is the one number George can't read from transactions, so you set it.
private struct CashTile: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var money: MoneyModel
    @Environment(\.colorScheme) private var scheme
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SectionLabel(text: "Cash")
                Spacer()
                Button("Edit") { editing.toggle() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .popover(isPresented: $editing, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Cash in the bank").font(.system(size: 12.5, weight: .semibold))
                            TextField("Cash", value: $money.cash, format: .currency(code: Money.currencyCode).precision(.fractionLength(0)))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 180)
                        }
                        .padding(14)
                    }
            }
            Text(Money.short(money.cash))
                .font(theme.display(30))
                .foregroundStyle(theme.ink(scheme))
                .contentTransition(.numericText())
            Text("In the bank today")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.inkTertiary(scheme))
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .vellum(level: 3, radius: max(theme.radius - 4, 8))
    }
}

private struct MonthChart: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var money: MoneyModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "In and out · 6 months")
                Spacer()
                LegendDot(color: theme.ink(scheme), label: "In")
                LegendDot(color: theme.ink(scheme).opacity(0.3), label: "Out")
            }
            Chart {
                ForEach(money.months) { month in
                    BarMark(x: .value("Month", month.month, unit: .month), y: .value("Amount", month.income))
                        .foregroundStyle(by: .value("Flow", "In"))
                        .position(by: .value("Flow", "In"))
                    BarMark(x: .value("Month", month.month, unit: .month), y: .value("Amount", month.spend))
                        .foregroundStyle(by: .value("Flow", "Out"))
                        .position(by: .value("Flow", "Out"))
                }
            }
            .chartForegroundStyleScale(["In": theme.ink(scheme), "Out": theme.ink(scheme).opacity(0.3)])
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(theme.edge(scheme))
                    AxisValueLabel {
                        if let amount = value.as(Double.self) { Text(Money.short(amount)) }
                    }
                }
            }
            .frame(height: 190)
        }
        .padding(16)
        .vellum(level: 3, radius: max(theme.radius - 4, 8))
    }
}

private struct LegendDot: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var color: Color
    var label: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(label).font(.system(size: 11)).foregroundStyle(theme.inkTertiary(scheme))
        }
    }
}

private struct CategoryBreakdown: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var money: MoneyModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let rows = money.spendByCategory
        let top = rows.first?.amount ?? 1
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: "Where it goes · 3 months")
            ForEach(rows, id: \.category) { row in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(row.category).font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(Money.short(row.amount)).font(.system(size: 11.5).monospacedDigit())
                            .foregroundStyle(theme.inkSecondary(scheme))
                    }
                    .foregroundStyle(theme.ink(scheme))
                    GeometryReader { proxy in
                        Capsule()
                            .fill(theme.ink(scheme).opacity(0.75))
                            .frame(width: max(3, proxy.size.width * row.amount / top))
                    }
                    .frame(height: 4)
                }
            }
            if rows.isEmpty {
                Text("No spending yet.").font(.system(size: 12)).foregroundStyle(theme.inkTertiary(scheme))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .vellum(level: 3, radius: max(theme.radius - 4, 8))
    }
}

private struct AskGeorge: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var money: MoneyModel
    @Environment(\.colorScheme) private var scheme
    @State private var question = ""

    private let examples = ["What happens if we hire one more engineer at 10k a month?", "Where could we cut 2k a month?", "When do we hit break-even at this growth?"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AgentLogo(code: "ge", size: 24)
                SectionLabel(text: "Ask George about your numbers")
            }
            AskField(placeholder: "Ask about runway, burn, a hire, a cut…", text: $question) {
                money.ask(question)
            }
            FlowLayout(spacing: 6) {
                ForEach(examples, id: \.self) { example in
                    Button(example) {
                        question = example
                        money.ask(example)
                    }
                    .buttonStyle(.vellumSecondary)
                }
            }
            if let run = money.askRun {
                RunView(run: run)
                    .transition(.rise(theme.rise))
            }
        }
        .padding(16)
        .vellum(level: 3, radius: max(theme.radius - 4, 8))
        .animation(theme.spring, value: money.askRun?.id)
    }
}

private struct TransactionList: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var money: MoneyModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel(text: "Transactions")
                Spacer()
                Text("Change a category and George remembers that payee")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
            .padding(.bottom, 8)
            LazyVStack(spacing: 0) {
                ForEach(money.recent) { item in
                    HStack(spacing: 12) {
                        Text(item.date.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(theme.inkTertiary(scheme))
                            .frame(width: 52, alignment: .leading)
                        Text(item.description)
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.ink(scheme))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Menu {
                            ForEach(MoneyModel.categories, id: \.self) { category in
                                Button(category) { withAnimation(theme.spring) { money.setCategory(category, for: item) } }
                            }
                        } label: {
                            Text(item.category).font(.system(size: 11, weight: .medium))
                        }
                        .menuStyle(.button)
                        .buttonStyle(.borderless)
                        .fixedSize()
                        .foregroundStyle(theme.inkSecondary(scheme))
                        Text(Money.format(item.amount, cents: true))
                            .font(.system(size: 12.5, weight: item.amount > 0 ? .semibold : .regular).monospacedDigit())
                            .foregroundStyle(theme.ink(scheme))
                            .frame(width: 110, alignment: .trailing)
                    }
                    .padding(.vertical, 7)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(theme.edge(scheme)).frame(height: 0.5)
                    }
                }
            }
        }
        .padding(16)
        .vellum(level: 3, radius: max(theme.radius - 4, 8))
    }
}
