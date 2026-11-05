import AppKit
import SwiftUI

// George's money in: quotes, repeating invoices, the reminders Marc drafts for late invoices, and the audit trail.

// MARK: Quotes

struct QuotesPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all, open, accepted, invoiced, lost
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "All"
            case .open: return "Waiting"
            case .accepted: return "Accepted"
            case .invoiced: return "Invoiced"
            case .lost: return "Declined or expired"
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            content(narrow: geo.size.width < 800)
        }
    }

    @ViewBuilder
    private func content(narrow: Bool) -> some View {
        let today = ledger.today
        let calendar = ledger.book.calendar
        let all = ledger.quotes
        let shown = all.filter { matches($0, today, calendar) }
        let waiting = ledger.book.openQuotes(on: today)
        let accepted = all.filter { $0.status == .accepted }
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if narrow {
                        Picker("", selection: $filter) {
                            ForEach(Filter.allCases) { item in Text(item.title).tag(item) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                    } else {
                        Picker("", selection: $filter) {
                            ForEach(Filter.allCases) { item in Text(item.title).tag(item) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 460)
                    }
                    Spacer(minLength: 8)
                    Button {
                        ledger.newQuote()
                    } label: {
                        Label("New quote", systemImage: "plus")
                    }
                    .buttonStyle(.vellumPrimary)
                    .fixedSize()
                }
                Text("Waiting on \(waiting.count) \(waiting.count == 1 ? "answer" : "answers") worth \(LedgerMoney.text(waiting.reduce(0) { $0 + $1.total }))"
                     + (accepted.isEmpty ? "" : " · \(accepted.count) accepted, still to invoice in full"))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkSecondary(scheme))
                LedgerCard {
                    if shown.isEmpty {
                        Text("No quotes here. Write one, and when they say yes it becomes an invoice in a click.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.inkTertiary(scheme))
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(shown) { quote in row(quote, today, calendar) }
                            }
                        }
                    }
                }
            }
            .frame(minWidth: narrow ? 250 : 360, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if let id = ledger.selectedQuote, let quote = ledger.book.quote(id) {
                QuoteDetail(quote: quote)
                    .frame(width: narrow ? 270 : 320)
                    .transition(.rise(theme.rise))
            }
        }
        .animation(theme.spring, value: ledger.selectedQuote)
    }

    private func matches(_ quote: Quote, _ today: Date, _ calendar: Calendar) -> Bool {
        let expired = quote.isExpired(on: today, calendar: calendar)
        switch filter {
        case .all: return true
        case .open: return quote.isOpen && !expired
        case .accepted: return quote.status == .accepted
        case .invoiced: return quote.status == .invoiced
        case .lost: return quote.status == .declined || expired
        }
    }

    private func row(_ quote: Quote, _ today: Date, _ calendar: Calendar) -> some View {
        let selected = ledger.selectedQuote == quote.id
        let expired = quote.isExpired(on: today, calendar: calendar)
        let status = quote.statusText(on: today, calendar: calendar)
        let when = expired ? "lapsed \(quote.expires.shortDay)" : quote.isOpen ? "good until \(quote.expires.shortDay)" : "written \(quote.issued.shortDay)"
        return Button {
            ledger.selectedQuote = selected ? nil : quote.id
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(quote.number)
                            .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(theme.ink(scheme))
                            .fixedSize()
                        Text(ledger.book.contact(quote.contact)?.name ?? "")
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.ink(scheme))
                            .lineLimit(1)
                    }
                    Text([quote.title, "\(status) · \(when)"].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 11, weight: quote.status == .accepted ? .semibold : .regular))
                        .foregroundStyle(quote.status == .accepted ? theme.ink(scheme) : theme.inkTertiary(scheme))
                        .lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                LedgerAmount(cents: quote.total, bold: quote.status == .accepted, width: 96)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .opacity(expired || quote.status == .declined ? 0.6 : 1)
            .background {
                if selected { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(theme.raised(scheme)) }
            }
            .overlay(alignment: .bottom) { Rectangle().fill(theme.edge(scheme)).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct QuoteDetail: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    var quote: Quote
    @State private var parting = false
    @State private var percent = 50.0
    @State private var deleting = false

    var body: some View {
        let today = ledger.today
        let calendar = ledger.book.calendar
        let expired = quote.isExpired(on: today, calendar: calendar)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(quote.number)
                        .font(theme.display(22))
                        .foregroundStyle(theme.ink(scheme))
                    Spacer()
                    Chip(text: quote.statusText(on: today, calendar: calendar), filled: quote.status == .accepted || quote.status == .invoiced)
                }
                VStack(alignment: .leading, spacing: 3) {
                    if !quote.title.isEmpty {
                        Text(quote.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.ink(scheme))
                    }
                    Text(ledger.book.contact(quote.contact)?.name ?? "").font(.system(size: 12.5)).foregroundStyle(theme.ink(scheme))
                    Text("Written \(quote.issued.fullDay) · good until \(quote.expires.fullDay)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                    if let sent = quote.sentAt {
                        Text("Sent \(sent.formatted(.relative(presentation: .named)))")
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                }
                LedgerCard {
                    ForEach(quote.lines) { line in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(line.description).font(.system(size: 12.5)).foregroundStyle(theme.ink(scheme))
                                Text("\(line.quantity == line.quantity.rounded() ? String(Int(line.quantity)) : String(format: "%.2f", line.quantity)) × \(LedgerMoney.text(line.unitPrice))")
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(theme.inkTertiary(scheme))
                            }
                            Spacer()
                            LedgerAmount(cents: line.net, width: 90)
                        }
                    }
                    Divider()
                    ReportRow(label: "Subtotal", cents: quote.subtotal)
                    ReportRow(label: "GST", cents: quote.tax)
                    ReportRow(label: "Total", cents: quote.total, bold: true)
                    ForEach(quote.invoices.indices, id: \.self) { index in
                        if let invoice = ledger.book.invoice(quote.invoices[index]) {
                            Button {
                                open(invoice)
                            } label: {
                                ReportRow(label: "\(invoice.number), \(share(index))% · \(invoice.status.title.lowercased())", cents: invoice.total)
                            }
                            .buttonStyle(.plain)
                            .help("Open \(invoice.number)")
                        }
                    }
                }
                actions(expired: expired)
            }
            .padding(14)
        }
        .vellum(level: 2, radius: max(theme.radius - 2, 10))
        .confirmationDialog("Delete \(quote.number)?", isPresented: $deleting) {
            Button("Delete", role: .destructive) { ledger.deleteQuote(quote.id) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func share(_ index: Int) -> Int {
        index < quote.parts.count ? Int((quote.parts[index] * 100).rounded()) : 0
    }

    @ViewBuilder
    private func actions(expired: Bool) -> some View {
        let remaining = Int((quote.remainingPart * 100).rounded())
        VStack(alignment: .leading, spacing: 8) {
            if expired {
                Text("It lapsed on \(quote.expires.fullDay).").font(.system(size: 12)).foregroundStyle(theme.inkSecondary(scheme))
                HStack {
                    Button("Extend \(ledger.book.settings.quoteDays) days") { ledger.extendQuote(quote.id) }.buttonStyle(.vellumPrimary)
                    Button("They said no") { ledger.markQuote(quote.id, .declined) }.buttonStyle(.vellumSecondary)
                }
            } else {
                switch quote.status {
                case .draft:
                    HStack {
                        Button("Email") { ledger.emailQuote(quote) }.buttonStyle(.vellumPrimary)
                        Button("Edit") { ledger.editQuote(quote.id) }.buttonStyle(.vellumSecondary)
                        Spacer(minLength: 0)
                        Menu {
                            Button("Save as PDF…") { ledger.saveQuotePDF(quote) }
                            Button("Delete…", role: .destructive) { deleting = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.button)
                        .buttonStyle(.borderless)
                        .fixedSize()
                    }
                    Button("Mark as sent") { ledger.markQuote(quote.id, .sent) }
                        .buttonStyle(.borderless)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.inkSecondary(scheme))
                case .sent:
                    HStack {
                        Button("They said yes") { ledger.markQuote(quote.id, .accepted) }.buttonStyle(.vellumPrimary)
                        Button("No") { ledger.markQuote(quote.id, .declined) }.buttonStyle(.vellumSecondary)
                        Spacer(minLength: 0)
                        Menu {
                            Button("Email again") { ledger.emailQuote(quote) }
                            Button("Save as PDF…") { ledger.saveQuotePDF(quote) }
                            if quote.invoices.isEmpty { Button("Edit") { ledger.editQuote(quote.id) } }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.button)
                        .buttonStyle(.borderless)
                        .fixedSize()
                    }
                case .accepted:
                    HStack {
                        Button(quote.parts.isEmpty ? "Invoice it all" : "Invoice the balance, \(remaining)%") { ledger.invoiceQuote(quote.id) }
                            .buttonStyle(.vellumPrimary)
                        Spacer(minLength: 0)
                        Menu {
                            Button("Save as PDF…") { ledger.saveQuotePDF(quote) }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.button)
                        .buttonStyle(.borderless)
                        .fixedSize()
                    }
                    if remaining > 10 {
                        Button(quote.parts.isEmpty ? "Deposit first…" : "Another part…") {
                            percent = quote.parts.isEmpty ? 50 : Double(min(50, remaining - 5))
                            parting = true
                        }
                        .buttonStyle(.vellumSecondary)
                        .popover(isPresented: $parting, arrowEdge: .bottom) { partForm(remaining: remaining) }
                    }
                    Text("The invoice is a draft with the quote's lines, for you to check before it goes.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                case .invoiced:
                    Text("Invoiced in full.").font(.system(size: 12)).foregroundStyle(theme.inkSecondary(scheme))
                case .declined:
                    HStack {
                        Text("They said no.").font(.system(size: 12)).foregroundStyle(theme.inkSecondary(scheme))
                        Spacer()
                        Button("Reopen") { ledger.extendQuote(quote.id) }.buttonStyle(.vellumSecondary)
                    }
                }
            }
        }
    }

    private func partForm(remaining: Int) -> some View {
        let upper = quote.parts.isEmpty ? 90.0 : Double(max(10, remaining - 5))
        return VStack(alignment: .leading, spacing: 10) {
            Text(quote.parts.isEmpty ? "A deposit first" : "Another part").font(.system(size: 13, weight: .semibold))
            Slider(value: $percent, in: 5...max(10, upper), step: 5)
            Text("\(Int(percent))% of \(quote.number): \(LedgerMoney.text(Int((Double(quote.total) * percent / 100).rounded())))")
                .font(.system(size: 12).monospacedDigit())
            Text("Each line is invoiced in the same share. The balance makes it up to the cent.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Make the invoice") {
                    parting = false
                    ledger.invoiceQuote(quote.id, part: percent / 100)
                }
                .buttonStyle(.vellumPrimary)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func open(_ invoice: Invoice) {
        ledger.salesFilter = .all
        ledger.selectedInvoice = invoice.id
        ledger.tab = .invoices
    }
}

/// Writing a quote.
struct QuoteEditor: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    @State var quote: Quote
    @State private var newContact = ""

    var body: some View {
        let gst = ledger.book.settings.gstRegistered
        VStack(alignment: .leading, spacing: 14) {
            Text(quote.number.isEmpty ? "New quote" : "Edit \(quote.number)")
                .font(theme.display(24))
                .foregroundStyle(theme.ink(scheme))
            HStack(spacing: 10) {
                Picker("For", selection: $quote.contact) {
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
                TextField("What it's for, like \"Annual report design\"", text: $quote.title)
                    .frame(width: 300)
                DatePicker("Date", selection: $quote.issued, displayedComponents: .date)
                DatePicker("Good until", selection: $quote.expires, displayedComponents: .date)
            }
            LineItemsEditor(lines: $quote.lines, sale: true)
            HStack(alignment: .top) {
                TextField("Notes on the quote: what's included, what isn't, how long it takes", text: $quote.notes, axis: .vertical)
                    .lineLimit(2...4)
                    .frame(maxWidth: 380)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    ReportRow(label: "Subtotal", cents: quote.subtotal)
                    ReportRow(label: "GST", cents: gst ? quote.tax : 0)
                    ReportRow(label: "Total", cents: quote.subtotal + (gst ? quote.tax : 0), bold: true)
                }
                .frame(width: 260)
            }
            HStack {
                Text("When they say yes, it becomes an invoice in a click, all at once or a deposit first.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
                Spacer()
                Button("Cancel") { ledger.editingQuote = nil }
                    .buttonStyle(.vellumSecondary)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { ledger.saveQuote(quote) }
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
        quote.contact = ledger.addContact(named: name)
        newContact = ""
    }
}

// MARK: Repeating invoices

struct RepeatingList: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let schedules = ledger.schedules
        let active = schedules.filter { !$0.paused && $0.next(calendar: ledger.book.calendar) != nil }
        let monthly = active.reduce(0.0) { $0 + perMonth($1) }
        VStack(alignment: .leading, spacing: 10) {
            Text("\(active.count) repeating · about \(LedgerMoney.text(Int(monthly.rounded()))) a month · George makes each one on its day")
                .font(.system(size: 12))
                .foregroundStyle(theme.inkSecondary(scheme))
            LedgerCard {
                if schedules.isEmpty {
                    Text("Nothing repeats yet. Set up a retainer or a care plan, or choose Repeat on any invoice.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(schedules) { schedule in row(schedule) }
                        }
                    }
                }
            }
        }
    }

    private func perMonth(_ schedule: RepeatingInvoice) -> Double {
        let total = Double(schedule.total) / Double(max(1, schedule.every))
        switch schedule.unit {
        case .week: return total * 52 / 12
        case .month: return total
        case .year: return total / 12
        }
    }

    private func row(_ schedule: RepeatingInvoice) -> some View {
        let calendar = ledger.book.calendar
        let selected = ledger.selectedSchedule == schedule.id
        let next = schedule.next(calendar: calendar)
        let when = schedule.paused ? "Paused" : next.map { "\(schedule.summary) · next \($0.shortDay)" } ?? "Ended"
        return Button {
            ledger.selectedSchedule = selected ? nil : schedule.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: schedule.paused ? "pause.circle" : "repeat")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(ledger.book.contact(schedule.contact)?.name ?? "")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(theme.ink(scheme))
                            .lineLimit(1)
                        Text(next.map { RepeatingInvoice.fill(schedule.lines.first?.description ?? "", on: $0, calendar: calendar) } ?? schedule.lines.first?.description ?? "")
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.inkSecondary(scheme))
                            .lineLimit(1)
                    }
                    Text(when)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                LedgerAmount(cents: schedule.total, width: 96)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .opacity(schedule.paused || next == nil ? 0.6 : 1)
            .background {
                if selected { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(theme.raised(scheme)) }
            }
            .overlay(alignment: .bottom) { Rectangle().fill(theme.edge(scheme)).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct RepeatingDetail: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    var schedule: RepeatingInvoice
    @State private var stopping = false

    var body: some View {
        let calendar = ledger.book.calendar
        let next = schedule.next(calendar: calendar)
        let after: [Date] = next == nil ? [] : (1...2).map { schedule.occurrence(schedule.made + $0, calendar: calendar) }
            .filter { date in schedule.end.map { calendar.startOfDay(for: date) <= calendar.startOfDay(for: $0) } ?? true }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ledger.book.contact(schedule.contact)?.name ?? "")
                        .font(theme.display(20))
                        .foregroundStyle(theme.ink(scheme))
                        .lineLimit(2)
                    Spacer()
                    Chip(text: schedule.paused ? "Paused" : next == nil ? "Ended" : schedule.summary, filled: !schedule.paused && next != nil)
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let next, !schedule.paused {
                        Text("Next on \(next.fullDay)").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.ink(scheme))
                        if !after.isEmpty {
                            Text("Then \(after.map(\.shortDay).joined(separator: ", "))")
                                .font(.system(size: 11.5))
                                .foregroundStyle(theme.inkTertiary(scheme))
                        }
                    }
                    Text("Due \(schedule.dueDays) days after · \(schedule.approve ? "approved straight into the books" : "left as a draft for you to check")")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    if schedule.made > 0 {
                        Text("\(schedule.made) made so far")
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                }
                LedgerCard {
                    ForEach(schedule.lines) { line in
                        HStack(alignment: .firstTextBaseline) {
                            Text(next.map { RepeatingInvoice.fill(line.description, on: $0, calendar: calendar) } ?? line.description)
                                .font(.system(size: 12.5))
                                .foregroundStyle(theme.ink(scheme))
                            Spacer()
                            LedgerAmount(cents: line.net, width: 90)
                        }
                    }
                    Divider()
                    ReportRow(label: "Each time", cents: schedule.total, bold: true)
                }
                HStack {
                    Button("Edit") { ledger.editingSchedule = schedule }.buttonStyle(.vellumSecondary)
                    Button(schedule.paused ? "Resume" : "Pause") { ledger.togglePause(schedule.id) }.buttonStyle(.vellumSecondary)
                    Spacer()
                    Button("Stop") { stopping = true }.buttonStyle(.vellumSecondary)
                }
                if let id = schedule.lastInvoice, let last = ledger.book.invoice(id) {
                    Button {
                        ledger.salesFilter = .all
                        ledger.selectedInvoice = last.id
                    } label: {
                        Label("The last one: \(last.number), \(last.issued.shortDay)", systemImage: "arrow.right.circle")
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkSecondary(scheme))
                }
            }
            .padding(14)
        }
        .vellum(level: 2, radius: max(theme.radius - 2, 10))
        .confirmationDialog("Stop this repeating invoice?", isPresented: $stopping) {
            Button("Stop", role: .destructive) { ledger.deleteSchedule(schedule.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Invoices it already made stay in the books.")
        }
    }
}

/// Setting up an invoice that repeats.
struct ScheduleEditor: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    @State var schedule: RepeatingInvoice
    @State private var newContact = ""

    var body: some View {
        let isNew = ledger.book.schedule(schedule.id) == nil
        let plural = schedule.every != 1
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New repeating invoice" : "Edit repeating invoice")
                .font(theme.display(24))
                .foregroundStyle(theme.ink(scheme))
            HStack(spacing: 10) {
                Picker("To", selection: $schedule.contact) {
                    ForEach(ledger.book.contacts) { contact in Text(contact.name).tag(contact.id) }
                }
                .frame(maxWidth: 280)
                TextField("Or a new contact", text: $newContact)
                    .frame(width: 180)
                    .onSubmit(addContact)
                Button("Add", action: addContact)
                    .disabled(newContact.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: 12) {
                Text("Every")
                Stepper(value: $schedule.every, in: 1...24) {
                    Text("\(schedule.every)").monospacedDigit().frame(minWidth: 18)
                }
                .fixedSize()
                Picker("", selection: $schedule.unit) {
                    Text(plural ? "weeks" : "week").tag(RepeatingInvoice.Unit.week)
                    Text(plural ? "months" : "month").tag(RepeatingInvoice.Unit.month)
                    Text(plural ? "years" : "year").tag(RepeatingInvoice.Unit.year)
                }
                .labelsHidden()
                .fixedSize()
                DatePicker("from", selection: $schedule.start, displayedComponents: .date)
                    .fixedSize()
                Toggle("Ends", isOn: Binding(get: { schedule.end != nil }, set: { on in
                    schedule.end = on ? Calendar.current.date(byAdding: .year, value: 1, to: schedule.start) : nil
                }))
                if schedule.end != nil {
                    DatePicker("on", selection: Binding(get: { schedule.end ?? schedule.start }, set: { schedule.end = $0 }), displayedComponents: .date)
                        .fixedSize()
                }
                Spacer()
            }
            HStack(spacing: 12) {
                Text("Due")
                TextField("", value: $schedule.dueDays, format: .number).frame(width: 50)
                Text("days after")
                Toggle("Approve each one straight into the books", isOn: $schedule.approve)
                Spacer()
                TextField("Reference (their PO)", text: $schedule.reference).frame(width: 180)
            }
            LineItemsEditor(lines: $schedule.lines, sale: true)
            HStack {
                Text("Descriptions can say [month] and [year]: \"Retainer, [month]\" becomes \"Retainer, November\".")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
                Spacer()
                Button("Cancel") { ledger.editingSchedule = nil }
                    .buttonStyle(.vellumSecondary)
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Start it" : "Save") { ledger.saveSchedule(schedule) }
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
        schedule.contact = ledger.addContact(named: name)
        newContact = ""
    }
}

// MARK: Marc's reminders

private struct WaitingPayment: Identifiable {
    var invoice: Invoice
    var line: BankLine
    var id: UUID { invoice.id }
}

/// Late invoices with Marc's reminder ready to read, and late ones whose payment is already in the bank.
struct MarcRemindersCard: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let due = ledger.remindersDue
        let waiting = ledger.book.latePaymentsWaiting(on: ledger.today).map { WaitingPayment(invoice: $0.invoice, line: $0.line) }
        if !due.isEmpty || !waiting.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    AgentLogo(code: "mc", size: 16, color: theme.inkSecondary(scheme))
                    Text(due.isEmpty ? "Marc isn't chasing anyone" : "Marc drafted \(due.count) \(due.count == 1 ? "reminder" : "reminders") for you to approve")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.ink(scheme))
                    Spacer()
                }
                ForEach(due) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(item.number) · \(item.contact)")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(theme.ink(scheme))
                                .lineLimit(1)
                            Text(detail(item))
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(theme.inkTertiary(scheme))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 8) {
                            Spacer(minLength: 0)
                            if ledger.sending.contains(item.invoice) {
                                Text("Sending…").font(.system(size: 11.5)).foregroundStyle(theme.inkTertiary(scheme))
                            } else {
                                Button("Skip") { ledger.skip(item) }.buttonStyle(.vellumSecondary)
                                Button("Read and send…") { ledger.review(item) }.buttonStyle(.vellumPrimary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                ForEach(waiting) { pair in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(ledger.book.contact(pair.invoice.contact)?.name ?? "Their") \(LedgerMoney.text(pair.invoice.owing)) for \(pair.invoice.number) looks like it's in the bank (\(pair.line.date.shortDay)), so Marc isn't chasing it.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.inkSecondary(scheme))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Spacer(minLength: 0)
                            Button("Reconcile") { ledger.reconcileWaiting(pair.invoice, line: pair.line) }.buttonStyle(.vellumSecondary)
                        }
                    }
                    .padding(.top, 2)
                    .overlay(alignment: .top) { Rectangle().fill(theme.edge(scheme)).frame(height: 0.5).offset(y: -4) }
                }
            }
            .padding(12)
            .vellum(level: 3, radius: max(theme.radius - 4, 8))
            .transition(.rise(theme.rise))
        }
    }

    private func detail(_ item: OverdueReminder) -> String {
        let tone: String
        switch item.tone {
        case .friendly: tone = "a friendly reminder"
        case .firm: tone = "a firmer reminder"
        case .final: tone = "the final reminder"
        }
        let last = item.lastSent.map { " · last chased \($0.shortDay)" } ?? ""
        return "\(item.daysLate) days late · \(LedgerMoney.text(item.owing)) · \(tone)\(last)"
    }
}

/// Marc's draft, to read, change and send.
struct ReminderSheet: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    @State var review: ReminderReview

    var body: some View {
        let reminder = review.reminder
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                AgentLogo(code: "mc", size: 22, color: theme.ink(scheme))
                VStack(alignment: .leading, spacing: 2) {
                    Text("A reminder for \(reminder.number)")
                        .font(theme.display(22))
                        .foregroundStyle(theme.ink(scheme))
                    Text("\(reminder.contact) · \(reminder.daysLate) days late · \(LedgerMoney.text(reminder.owing)) owing")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.inkSecondary(scheme))
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("To").font(.system(size: 12)).foregroundStyle(theme.inkSecondary(scheme))
                    TextField("Their email", text: $review.to)
                }
                GridRow {
                    Text("Subject").font(.system(size: 12)).foregroundStyle(theme.inkSecondary(scheme))
                    TextField("", text: $review.subject)
                }
            }
            TextEditor(text: $review.body)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 230)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.raised(scheme)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5))
            Text(ledger.reminderSender.map { "Marc sends it from \($0), with a few seconds to undo. The bank details are in the email." }
                 ?? "There's no mail account in 11am yet, so your mail app opens with it, and the invoice attached.")
                .font(.system(size: 11))
                .foregroundStyle(theme.inkTertiary(scheme))
            HStack {
                Button("Not now") { ledger.reviewing = nil }
                    .buttonStyle(.vellumSecondary)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if ledger.reminderSender != nil {
                    Button("Change it in Mail") { ledger.openInMail(review) }.buttonStyle(.vellumSecondary)
                }
                Button("Send") { ledger.send(review) }
                    .buttonStyle(.vellumPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(ledger.reminderSender != nil && review.to.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 600)
        .textFieldStyle(.roundedBorder)
    }
}

// MARK: Audit trail

private struct AuditDay: Identifiable {
    var day: Date
    var events: [AuditEvent]
    var id: Date { day }
}

/// Every change to the books, who made it and when, newest first.
struct AuditTrailView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var ledger: LedgerModel
    @Environment(\.colorScheme) private var scheme
    @State private var search = ""

    var body: some View {
        let events = ledger.book.auditTrail(matching: search)
        let calendar = ledger.book.calendar
        let days = Dictionary(grouping: events.prefix(500)) { calendar.startOfDay(for: $0.date) }
            .map { AuditDay(day: $0.key, events: $0.value) }
            .sorted { $0.day > $1.day }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Search: an invoice number, a name, Marc…", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                Text("\(events.count) \(events.count == 1 ? "change" : "changes")")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                Spacer(minLength: 8)
                Label(ledger.book.settings.lockDate.map { "Locked up to \($0.fullDay)" } ?? "Not locked",
                      systemImage: ledger.book.settings.lockDate == nil ? "lock.open" : "lock.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkSecondary(scheme))
            }
            ScrollView {
                LedgerCard {
                    if events.isEmpty {
                        Text(search.isEmpty ? "Changes to the books show here as they happen." : "Nothing matches.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.inkTertiary(scheme))
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(days) { group in
                                SectionLabel(text: group.day.fullDay)
                                    .padding(.top, 10)
                                    .padding(.bottom, 2)
                                ForEach(group.events) { event in row(event) }
                            }
                        }
                    }
                }
                .frame(maxWidth: 820, alignment: .leading)
            }
        }
    }

    private func row(_ event: AuditEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(event.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(theme.inkTertiary(scheme))
                .frame(width: 64, alignment: .leading)
            Text(event.by)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(event.by == "You" ? theme.inkSecondary(scheme) : theme.ink(scheme))
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.action)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.ink(scheme))
                    .lineLimit(1)
                if !event.detail.isEmpty {
                    Text(event.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkTertiary(scheme))
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            if let amount = event.amount { LedgerAmount(cents: amount, width: 100) }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.edge(scheme)).frame(height: 0.5) }
    }
}
