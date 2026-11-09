import Charts
import SwiftUI

/// George's forecast: cash for the year ahead as things are, and with the changes you're trying.
struct ForecastPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    @State private var sentence = ""
    @State private var openMonth: Date?

    var body: some View {
        let tried = ledger.forecast
        let plain = ledger.baseline
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForecastTile(label: "Cash now", value: LedgerMoney.text(tried.opening),
                                 detail: "In the bank, with lines not reconciled yet")
                    ForecastTile(label: "In \(ledger.forecastMonths) months", value: LedgerMoney.text(tried.closing),
                                 detail: ledger.hasChanges ? "\(LedgerMoney.text(plain.closing)) as things are" : "As things are")
                    ForecastTile(label: "Lowest", value: LedgerMoney.text(tried.lowest?.closing ?? tried.opening),
                                 detail: (tried.lowest?.start ?? ledger.today).formatted(.dateTime.month(.wide).year()))
                    ForecastTile(label: "Runway", value: tried.runsOut.map { $0.formatted(.dateTime.month(.abbreviated).year()) } ?? "The year",
                                 detail: tried.runsOut == nil ? "Cash lasts the whole forecast" : "When the cash runs out", warning: tried.runsOut != nil)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionLabel(text: "What if…")
                        Spacer()
                        Text("Usually \(LedgerMoney.text(plain.usualIn)) in and \(LedgerMoney.text(plain.usualOut)) out a month, from the last \(plain.history) \(plain.history == 1 ? "month" : "months")")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.inkTertiary(scheme))
                            .lineLimit(1)
                    }
                    AskField(placeholder: "Hire at $8k a month from March · lose a client in May · a $3,000 laptop in February", text: $sentence) {
                        if withAnimation(theme.spring, { ledger.tryWhatIf(sentence) }) { sentence = "" }
                    }
                    if ledger.whatIfs.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(examples, id: \.self) { example in
                                Button(example) {
                                    withAnimation(theme.spring) { _ = ledger.tryWhatIf(example) }
                                }
                                .buttonStyle(.vellumSecondary)
                                .controlSize(.small)
                            }
                        }
                    } else {
                        FlowChips(changes: ledger.whatIfs)
                    }
                }
                .padding(16)
                .vellum(level: 3, radius: max(theme.radius - 4, 8))

                ForecastChart(plain: plain, tried: ledger.hasChanges ? tried : nil)

                HStack(alignment: .top, spacing: 12) {
                    ForecastTable(forecast: tried, openMonth: $openMonth)
                        .frame(maxWidth: .infinity)
                    GeorgeOnForecast()
                        .frame(width: 280)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
    }

    private var examples: [String] {
        var list = ["Hire at $8k a month from March", "Prices up 10% from July", "A $3,000 laptop in February"]
        if let biggest = ledger.book.invoices.filter({ $0.kind == .sale && $0.status != .void }).reduce(into: [UUID: Cents](), { $0[$1.contact, default: 0] += $1.total })
            .max(by: { $0.value < $1.value }), let name = ledger.book.contact(biggest.key)?.name {
            list.insert("Lose \(name) in April", at: 1)
        }
        return list
    }
}

private struct ForecastTile: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var label: String
    var value: String
    var detail: String
    var warning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.inkTertiary(scheme))
            HStack(spacing: 6) {
                if warning { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13)) }
                Text(value)
                    .font(theme.display(24))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(theme.ink(scheme))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(theme.inkSecondary(scheme))
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .vellum(level: 3, radius: max(theme.radius - 4, 8))
    }
}

/// The changes being tried, each one on or off.
private struct FlowChips: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    var changes: [WhatIf]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(changes) { change in
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(get: { change.on }, set: { _ in withAnimation(theme.spring) { ledger.toggle(change) } }))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .tint(theme.ink(scheme))
                        .labelsHidden()
                    Image(systemName: symbol(change))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .frame(width: 16)
                    Text(change.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(change.on ? theme.ink(scheme) : theme.inkTertiary(scheme))
                        .strikethrough(!change.on, color: theme.inkTertiary(scheme))
                    Spacer()
                    Button { withAnimation(theme.spring) { ledger.remove(change) } } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .help("Remove")
                }
            }
        }
    }

    private func symbol(_ change: WhatIf) -> String {
        switch change.kind {
        case .cost: return change.amount >= 0 ? "arrow.up.right" : "scissors"
        case .income: return "arrow.down.left"
        case .oneOff: return change.amount >= 0 ? "plus.circle" : "minus.circle"
        case .loseClient: return "person.crop.circle.badge.minus"
        case .prices: return "tag"
        }
    }
}

/// Cash at the end of each month: as things are, and with your changes as a second line.
private struct ForecastChart: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var plain: Forecast
    var tried: Forecast?

    private struct Point: Identifiable {
        var month: Date
        var cash: Double
        var series: String
        var id: String { "\(series)\(month.timeIntervalSince1970)" }
    }

    private var points: [Point] {
        var list = plain.months.map { Point(month: $0.start, cash: LedgerMoney.dollars($0.closing), series: "As things are") }
        if let tried {
            list += tried.months.map { Point(month: $0.start, cash: LedgerMoney.dollars($0.closing), series: "With your changes") }
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Cash at the end of each month")
                Spacer()
                LegendSwatch(color: theme.ink(scheme).opacity(tried == nil ? 1 : 0.35), label: "As things are")
                if tried != nil { LegendSwatch(color: theme.ink(scheme), label: "With your changes") }
            }
            Chart {
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                ForEach(points) { point in
                    LineMark(x: .value("Month", point.month, unit: .month), y: .value("Cash", point.cash))
                        .foregroundStyle(by: .value("Series", point.series))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: point.series == "With your changes" ? 2.5 : 2))
                    if tried == nil || point.series == "With your changes" {
                        AreaMark(x: .value("Month", point.month, unit: .month), y: .value("Cash", point.cash))
                            .foregroundStyle(theme.ink(scheme).opacity(0.06))
                            .interpolationMethod(.monotone)
                    }
                }
            }
            .chartForegroundStyleScale(["As things are": theme.ink(scheme).opacity(tried == nil ? 1 : 0.35), "With your changes": theme.ink(scheme)])
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
            .frame(height: 200)
        }
        .padding(16)
        .vellum(level: 3, radius: max(theme.radius - 4, 8))
    }
}

private struct LegendSwatch: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var color: Color
    var label: String

    var body: some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 14, height: 3)
            Text(label).font(.system(size: 11)).foregroundStyle(theme.inkSecondary(scheme))
        }
    }
}

/// Month by month: what comes in, what goes out, and where it ends; open a month to see why.
private struct ForecastTable: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var forecast: Forecast
    @Binding var openMonth: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Month").frame(maxWidth: .infinity, alignment: .leading)
                Text("In").frame(width: 100, alignment: .trailing)
                Text("Out").frame(width: 100, alignment: .trailing)
                Text("Cash at the end").frame(width: 120, alignment: .trailing)
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(theme.inkTertiary(scheme))
            .padding(.bottom, 6)
            ForEach(forecast.months) { month in
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(theme.spring) { openMonth = openMonth == month.start ? nil : month.start }
                    } label: {
                        HStack {
                            Image(systemName: openMonth == month.start ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(theme.inkTertiary(scheme))
                                .frame(width: 12)
                            Text(month.start.formatted(.dateTime.month(.wide).year()))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(LedgerMoney.text(month.moneyIn)).frame(width: 100, alignment: .trailing)
                            Text(LedgerMoney.text(-month.moneyOut)).frame(width: 100, alignment: .trailing)
                            Text(LedgerMoney.text(month.closing))
                                .fontWeight(.semibold)
                                .frame(width: 120, alignment: .trailing)
                        }
                        .font(.system(size: 12.5).monospacedDigit())
                        .foregroundStyle(month.closing < 0 ? Color.red : theme.ink(scheme))
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if openMonth == month.start {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(month.items) { item in
                                HStack {
                                    Text(item.date.shortDay)
                                        .frame(width: 52, alignment: .leading)
                                        .foregroundStyle(theme.inkTertiary(scheme))
                                    Text(item.description)
                                        .foregroundStyle(item.kind == .whatIf ? theme.ink(scheme) : theme.inkSecondary(scheme))
                                        .fontWeight(item.kind == .whatIf ? .semibold : .regular)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(LedgerMoney.text(item.amount))
                                        .monospacedDigit()
                                        .foregroundStyle(theme.inkSecondary(scheme))
                                }
                                .font(.system(size: 11.5))
                            }
                        }
                        .padding(.leading, 20)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                    }
                    Rectangle().fill(theme.edge(scheme)).frame(height: 0.5)
                }
            }
        }
        .padding(16)
        .vellum(level: 3, radius: max(theme.radius - 4, 8))
    }
}

/// George reads the forecast out to you.
private struct GeorgeOnForecast: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AgentLogo(code: "ge", size: 20)
                Text("George")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.ink(scheme))
            }
            Text("The forecast counts invoices and bills by their due dates, repeating invoices on their schedule, and your usual money in and out for the rest. Late invoices are counted in the next two weeks. Hiring includes 12% super.")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.inkSecondary(scheme))
                .fixedSize(horizontal: false, vertical: true)
            if let run = ledger.forecastRun {
                RunView(run: run)
            } else {
                Button("What does this mean?") { ledger.explainForecast() }
                    .buttonStyle(.vellumSecondary)
                    .disabled(brain.isBusy)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .vellum(level: 3, radius: max(theme.radius - 4, 8))
    }
}

/// A report line, opened: the facts behind it and George's plain-English reading.
struct LineExplainerSheet: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    var request: ExplainRequest

    var body: some View {
        let line = request.explanation
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.account.name)
                        .font(theme.display(22))
                        .foregroundStyle(theme.ink(scheme))
                    Text("\(line.from.fullDay) to \(line.to.fullDay) · account \(line.account.code)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(LedgerMoney.text(line.total))
                        .font(theme.display(22))
                        .monospacedDigit()
                        .foregroundStyle(theme.ink(scheme))
                    if line.previous != 0 || line.total != 0 {
                        Text(changeText(line))
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.inkSecondary(scheme))
                    }
                }
            }

            HStack(alignment: .top, spacing: 10) {
                AgentLogo(code: "ge", size: 20)
                if let run = request.run {
                    GeorgeReading(run: run, facts: line.facts(calendar: ledger.book.calendar))
                } else {
                    FactsText(text: line.facts(calendar: ledger.book.calendar))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.well(scheme)))

            if line.months.count > 1 {
                Chart(line.months) { month in
                    BarMark(x: .value("Month", month.month, unit: .month), y: .value("Amount", LedgerMoney.dollars(month.amount)))
                        .foregroundStyle(theme.ink(scheme))
                }
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
                .frame(height: 120)
            }

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Who it was with")
                    ForEach(line.payees.prefix(6)) { payee in
                        HStack {
                            Text(payee.name).lineLimit(1)
                            Text("· \(payee.count)").foregroundStyle(theme.inkTertiary(scheme))
                            Spacer()
                            Text(LedgerMoney.text(payee.amount)).monospacedDigit()
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(theme.ink(scheme))
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Largest entries")
                    ForEach(line.largest) { entry in
                        HStack {
                            Text(entry.date.shortDay).foregroundStyle(theme.inkTertiary(scheme)).frame(width: 46, alignment: .leading)
                            Text(entry.description).lineLimit(1)
                            Spacer()
                            Text(LedgerMoney.text(entry.amount)).monospacedDigit()
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(theme.ink(scheme))
                    }
                }
            }

            if line.isTax {
                Text(LineExplanation.taxNote)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.vellumPrimary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 620)
    }

    private func changeText(_ line: LineExplanation) -> String {
        guard line.previous != 0 else { return "Nothing the period before" }
        let direction = line.change > 0 ? "Up" : (line.change < 0 ? "Down" : "Same as")
        let percent = line.changePercent.map { " (\(Int(abs($0).rounded()))%)" } ?? ""
        return line.change == 0 ? "Same as the period before" : "\(direction) \(LedgerMoney.text(abs(line.change)))\(percent) on the period before"
    }
}

/// George's words, or the plain facts when no brain can answer.
private struct GeorgeReading: View {
    @ObservedObject var run: BrainRun
    var facts: String

    var body: some View {
        if case .failed = run.status {
            FactsText(text: facts)
        } else {
            RunView(run: run)
        }
    }
}

private struct FactsText: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12.5))
            .lineSpacing(2.5)
            .foregroundStyle(theme.ink(scheme))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A report line George can explain: click it.
struct ExplainableRow: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    var label: String
    var cents: Cents
    var account: String
    var dates: (start: Date, end: Date)
    @State private var hovering = false

    var body: some View {
        Button {
            ledger.explain(account: account, from: dates.start, to: dates.end)
        } label: {
            HStack(spacing: 4) {
                ReportRow(label: label, cents: cents, indent: 12)
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .opacity(hovering ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Ask George what's behind \(label)")
    }
}

/// Moving across from Xero: what to export there, and the files to bring in.
struct XeroImportSheet: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var files = XeroFiles()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AgentLogo(code: "ge", size: 24)
                Text("Move across from Xero")
                    .font(theme.display(20))
                    .foregroundStyle(theme.ink(scheme))
            }
            Text("Export these from Xero as CSV files, then choose them here. George brings across your contacts, chart of accounts, and the invoices and bills still owing, so you can run both side by side for a quarter. Bring your bank statements in from the day you switch.")
                .font(.system(size: 12))
                .foregroundStyle(theme.inkSecondary(scheme))
                .fixedSize(horizontal: false, vertical: true)
            fileRow("Contacts", where: "Contacts › All contacts › Export", path: \.contacts)
            fileRow("Chart of accounts", where: "Accounting › Chart of accounts › Export", path: \.accounts)
            fileRow("Sales invoices", where: "Business › Invoices › Export", path: \.invoices)
            fileRow("Bills", where: "Business › Bills to pay › Export", path: \.bills)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.vellumSecondary)
                    .keyboardShortcut(.cancelAction)
                Button("Bring them across") {
                    ledger.importFromXero(files)
                    dismiss()
                }
                .buttonStyle(.vellumPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(files.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 540)
    }

    private func fileRow(_ title: String, where place: String, path: WritableKeyPath<XeroFiles, URL?>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: files[keyPath: path] == nil ? "circle" : "checkmark.circle.fill")
                .foregroundStyle(theme.ink(scheme))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(theme.ink(scheme))
                Text(files[keyPath: path]?.lastPathComponent ?? "In Xero: \(place)")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .lineLimit(1)
            }
            Spacer()
            Button("Choose…") { ledger.chooseXeroFile(path, into: &files) }
                .buttonStyle(.vellumSecondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.well(scheme)))
    }
}
