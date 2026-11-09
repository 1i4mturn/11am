import SwiftUI

/// A chart's link to Sheets: pick a sheet and George finds the columns; it updates when you open or present.
struct ChartLinkBox: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var decks: DecksModel
    @EnvironmentObject private var sheets: SheetsModel
    @Environment(\.colorScheme) private var scheme
    @State private var labels = ""
    @State private var values = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Numbers from Sheets")
            if let link = decks.slide?.content.link {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkSecondary(scheme))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(link.workbook) › \(link.sheet)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.ink(scheme))
                        Text(link.updated.map { "Updated \($0.formatted(.relative(presentation: .named)))" } ?? "Not updated yet")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                }
                HStack(spacing: 6) {
                    TextField("Labels", text: $labels)
                    TextField("Numbers", text: $values)
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5, design: .monospaced))
                .onSubmit {
                    var changed = link
                    changed.labels = labels.trimmingCharacters(in: .whitespaces)
                    changed.values = values.trimmingCharacters(in: .whitespaces)
                    decks.linkChart(changed)
                }
                HStack(spacing: 6) {
                    Button("Refresh") { decks.refreshCharts() }
                        .buttonStyle(.vellumSecondary)
                    Button("Unlink") { decks.unlinkChart() }
                        .buttonStyle(.vellumSecondary)
                }
                .controlSize(.small)
                .onAppear {
                    labels = link.labels
                    values = link.values
                }
                .onChange(of: link) { _, now in
                    labels = now.labels
                    values = now.values
                }
            } else {
                Menu {
                    ForEach(sheets.entries) { entry in
                        Menu(entry.name) {
                            ForEach(sheetNames(entry.name), id: \.self) { name in
                                Button(name) { decks.linkChart(workbook: entry.name, sheet: name) }
                            }
                        }
                    }
                } label: {
                    Label("Link to a sheet", systemImage: "tablecells")
                }
                .menuStyle(.button)
                .buttonStyle(.vellumSecondary)
                .fixedSize()
                .disabled(sheets.entries.isEmpty)
                Text("Or type the bars below. A linked chart takes its numbers from the sheet each time you open or present the deck.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sheetNames(_ workbook: String) -> [String] {
        sheets.workbook(named: workbook)?.sheets.map(\.name) ?? []
    }
}

/// How the rehearsal went: the total against your target and the last run, and each slide's time.
struct RehearsalView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var decks: DecksModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    var run: Rehearsal
    @State private var target = ""

    var body: some View {
        let deck = decks.deck ?? SlideDeck(name: "", theme: .paper, slides: [])
        let previous = decks.previousRehearsal(before: run)
        let minutes = deck.targetMinutes
        let rows = RehearsalReport.rows(deck, run, previous: previous, targetMinutes: minutes)
        let longest = max(rows.map(\.seconds).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "stopwatch")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.ink(scheme))
                VStack(alignment: .leading, spacing: 2) {
                    Text(RehearsalReport.clock(run.total))
                        .font(theme.display(28))
                        .monospacedDigit()
                        .foregroundStyle(theme.ink(scheme))
                    Text(RehearsalReport.summary(deck, run, previous: previous, targetMinutes: minutes))
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.inkSecondary(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Text("Aiming for")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkSecondary(scheme))
                TextField("minutes", text: $target)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .onSubmit { decks.setTarget(minutes: Double(target)) }
                Text("minutes")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkSecondary(scheme))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rows) { row in
                        HStack(spacing: 10) {
                            Text("\(row.number)")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(theme.inkTertiary(scheme))
                                .frame(width: 18, alignment: .trailing)
                            Text(row.title)
                                .font(.system(size: 12.5, weight: row.long ? .semibold : .regular))
                                .foregroundStyle(theme.ink(scheme))
                                .lineLimit(1)
                                .frame(width: 200, alignment: .leading)
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(row.long ? Color.orange : theme.ink(scheme).opacity(0.75))
                                    .frame(width: max(4, proxy.size.width * row.seconds / longest), height: 8)
                                    .frame(maxHeight: .infinity, alignment: .center)
                            }
                            .frame(height: 16)
                            Text(RehearsalReport.clock(row.seconds))
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(theme.ink(scheme))
                                .frame(width: 44, alignment: .trailing)
                            if let before = row.previous {
                                Text(before > row.seconds ? "−\(RehearsalReport.clock(before - row.seconds))" : "+\(RehearsalReport.clock(row.seconds - before))")
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(theme.inkTertiary(scheme))
                                    .frame(width: 48, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 320)
            HStack {
                Text("Orange slides took more than half again their share of the time.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkTertiary(scheme))
                Spacer()
                Button("Rehearse again") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { decks.rehearse() }
                }
                .buttonStyle(.vellumSecondary)
                Button("Done") { dismiss() }
                    .buttonStyle(.vellumPrimary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 620)
        .onAppear { target = deck.targetMinutes.map { $0 == $0.rounded() ? String(Int($0)) : String($0) } ?? "" }
    }
}
