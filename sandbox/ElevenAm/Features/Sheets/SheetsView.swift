import AppKit
import Charts
import SwiftUI

/// George's spreadsheets: workbooks down the side, the grid with its formula bar and tabs, charts beside it.
struct SheetsView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var sheets: SheetsModel
    @Environment(\.colorScheme) private var scheme
    @State private var asking = false
    @State private var summarising = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "sheets", subtitle: subtitle) {
                HStack(spacing: 8) {
                    Button {
                        asking = true
                    } label: {
                        Label("Ask George", systemImage: "sparkle")
                    }
                    .buttonStyle(.vellumSecondary)
                    .help("Write a formula, explain one, ask about the numbers or make a sheet")
                    .popover(isPresented: $asking, arrowEdge: .bottom) {
                        AskSheetsView()
                            .environmentObject(sheets)
                            .environmentObject(theme)
                    }
                    Button {
                        summarising = true
                    } label: {
                        Label("Summarise", systemImage: "sum")
                    }
                    .buttonStyle(.vellumSecondary)
                    .help("A live summary of this table, grouped by one column")
                    .disabled(sheets.tableHeaders.count < 2)
                    .popover(isPresented: $summarising, arrowEdge: .bottom) {
                        SummariseView(done: { summarising = false })
                            .environmentObject(sheets)
                            .environmentObject(theme)
                    }
                    moreMenu
                    Button {
                        withAnimation(theme.spring) { sheets.newWorkbook() }
                    } label: {
                        Label("New workbook", systemImage: "plus.square.on.square")
                    }
                    .buttonStyle(.vellumPrimary)
                }
            }

            if let notice = sheets.notice {
                SheetsBanner(text: notice) { sheets.notice = nil }
                    .transition(.rise(theme.rise))
            }

            HStack(alignment: .top, spacing: 14) {
                WorkbookList()
                    .frame(width: 170)
                if sheets.book != nil {
                    VStack(spacing: 8) {
                        SheetsFormatBar()
                        FormulaBar()
                        GridCanvas(model: sheets, style: GridStyle.from(theme, scheme))
                            .clipShape(RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous)
                                    .strokeBorder(theme.edge(scheme), lineWidth: 0.5)
                            }
                        SheetTabs()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if sheets.showsCharts, let sheet = sheets.sheet, !sheet.charts.isEmpty {
                        ChartsPanel()
                            .frame(width: 290)
                            .transition(.rise(theme.rise))
                    }
                } else {
                    VStack(spacing: 10) {
                        AgentLogo(code: "ge", size: 44, color: theme.inkTertiary(scheme))
                        Text("No workbook open. Start one, or import an Excel file.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(24)
        .animation(theme.spring, value: sheets.notice)
        .animation(theme.spring, value: sheets.showsCharts)
        .task(id: sheets.notice) {
            guard sheets.notice != nil, (try? await Task.sleep(for: .seconds(10))) != nil else { return }
            sheets.notice = nil
        }
        .onDisappear { sheets.flushSave() }
    }

    private var subtitle: String {
        guard let book = sheets.book else { return "Spreadsheets with live formulas, on this Mac" }
        let count = book.sheets.count
        return "\(book.name) · \(count) \(count == 1 ? "sheet" : "sheets") · opens and saves Excel files"
    }

    private var moreMenu: some View {
        Menu {
            Section("Import") {
                Button("Excel or CSV files…") { sheets.importFiles() }
            }
            Section("Export") {
                ForEach(SheetsModel.Export.allCases) { kind in
                    Button(kind.title + "…") { sheets.export(kind) }
                }
            }
            Divider()
            Button("Show the workbooks folder in Finder") {
                sheets.flushSave()
                NSWorkspace.shared.activateFileViewerSelecting([sheets.root])
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(theme.inkSecondary(scheme))
        .help("Import and export")
    }
}

private struct SheetsBanner: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var text: String
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AgentLogo(code: "ge", size: 18, color: theme.inkSecondary(scheme))
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.ink(scheme))
                .lineLimit(2)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(theme.inkTertiary(scheme))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).fill(theme.well(scheme))
        }
        .overlay {
            RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5)
        }
    }
}

// MARK: Workbooks

private struct WorkbookList: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var sheets: SheetsModel
    @Environment(\.colorScheme) private var scheme
    @State private var renaming: SheetsEntry?
    @State private var newName = ""
    @State private var deleting: SheetsEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Workbooks")
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(sheets.entries) { entry in
                        row(entry)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .alert("Rename workbook", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let entry = renaming {
                    if sheets.book?.id != entry.id { sheets.open(entry.id) }
                    sheets.rename(newName)
                    sheets.flushSave()
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Move \u{201C}\(deleting?.name ?? "")\u{201D} to the Trash?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { entry in
            Button("Move to Trash", role: .destructive) { withAnimation(theme.spring) { sheets.delete(entry.id) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It goes to the Mac's Trash, so you can still put it back.")
        }
    }

    private func row(_ entry: SheetsEntry) -> some View {
        let selected = sheets.book?.id == entry.id
        let name = selected ? (sheets.book?.name ?? entry.name) : entry.name
        return Button {
            withAnimation(theme.spring) { sheets.open(entry.id) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(theme.ink(scheme))
                    .lineLimit(1)
                Text("\(entry.modified.formatted(.relative(presentation: .named))) · \(entry.sheets) \(entry.sheets == 1 ? "sheet" : "sheets")")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.raised(scheme))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename…") {
                newName = name
                renaming = entry
            }
            Button("Move to Trash…") { deleting = entry }
        }
    }
}

// MARK: Formatting

private struct SheetsFormatBar: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var sheets: SheetsModel
    @Environment(\.colorScheme) private var scheme

    private static let fills: [Swatch] = [
        Swatch("None", nil), Swatch("Butter", "#FFF4C2"), Swatch("Mint", "#DDF3E4"), Swatch("Sky", "#DCEBFA"),
        Swatch("Blush", "#FBE0E0"), Swatch("Lilac", "#ECE3F7"), Swatch("Stone", "#ECEAE6"),
    ]
    private static let inks: [Swatch] = [
        Swatch("Automatic", nil), Swatch("Grey", "#7A7A7A"), Swatch("Red", "#C0392B"), Swatch("Green", "#2E7D4F"), Swatch("Blue", "#2463A6"),
    ]

    var body: some View {
        let format = sheets.activeFormat
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 2) {
            ToolButton(symbol: "arrow.uturn.backward", help: "Undo (⌘Z)") { sheets.undo() }
                .disabled(!sheets.canUndo)
            ToolButton(symbol: "arrow.uturn.forward", help: "Redo (⇧⌘Z)") { sheets.redo() }
                .disabled(!sheets.canRedo)
            divider
            numberMenu
            TextToolButton(text: "$", help: "Currency") { sheets.setNumberFormat(.currency(2)) }
            TextToolButton(text: "%", help: "Percent") { sheets.setNumberFormat(.percent(0)) }
            TextToolButton(text: "−.0", help: "Fewer decimal places") { sheets.adjustDecimals(-1) }
            TextToolButton(text: "+.0", help: "More decimal places") { sheets.adjustDecimals(1) }
            divider
            ToolButton(symbol: "bold", help: "Bold (⌘B)", on: format.bold) { sheets.toggleBold() }
                .keyboardShortcut("b", modifiers: .command)
            ToolButton(symbol: "italic", help: "Italic (⌘I)", on: format.italic) { sheets.toggleItalic() }
                .keyboardShortcut("i", modifiers: .command)
            ToolButton(symbol: "text.alignleft", help: "Align left", on: format.alignment == .left) { sheets.setAlignment(format.alignment == .left ? nil : .left) }
            ToolButton(symbol: "text.aligncenter", help: "Centre", on: format.alignment == .center) { sheets.setAlignment(format.alignment == .center ? nil : .center) }
            ToolButton(symbol: "text.alignright", help: "Align right", on: format.alignment == .right) { sheets.setAlignment(format.alignment == .right ? nil : .right) }
            colourMenu(symbol: "paintbrush", help: "Fill colour", options: Self.fills) { sheets.setFill($0) }
            colourMenu(symbol: "character", help: "Text colour", options: Self.inks) { sheets.setColor($0) }
            divider
            ToolButton(symbol: "arrow.up.arrow.down", help: "Sort the table by this column, A to Z") { sheets.sort(ascending: true) }
            ToolButton(symbol: "pin", help: (sheets.sheet?.frozenRows ?? 0) > 0 ? "Unfreeze the top rows" : "Keep the top rows in view",
                       on: (sheets.sheet?.frozenRows ?? 0) > 0) {
                sheets.freezeRows((sheets.sheet?.frozenRows ?? 0) > 0 ? 0 : max(1, sheets.active.row + 1))
            }
            insertMenu
            chartMenu
            if let sheet = sheets.sheet, !sheet.charts.isEmpty {
                divider
                ToolButton(symbol: "sidebar.right", help: sheets.showsCharts ? "Hide charts" : "Show charts", on: sheets.showsCharts) {
                    sheets.showsCharts.toggle()
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.well(scheme))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5)
        }
    }

    private var divider: some View {
        Rectangle().fill(theme.edge(scheme)).frame(width: 1, height: 16).padding(.horizontal, 4)
    }

    private var numberMenu: some View {
        Menu {
            let options: [NumberFormat] = [.general, .number(0), .number(2), .currency(2), .currency(0), .percent(0), .percent(1), .date, .shortDate, .time, .dateTime, .text]
            ForEach(options, id: \.self) { option in
                Button(option.title) { sheets.setNumberFormat(option) }
            }
        } label: {
            Text(shortTitle(sheets.activeNumberFormat))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(theme.inkSecondary(scheme))
                .frame(minWidth: 70, alignment: .leading)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .help("Number format")
        .padding(.horizontal, 4)
    }

    private func shortTitle(_ format: NumberFormat) -> String {
        switch format {
        case .general: return "Automatic"
        case .number: return "Number"
        case .currency: return "Currency"
        case .percent: return "Percent"
        case .date, .shortDate: return "Date"
        case .time: return "Time"
        case .dateTime: return "Date & time"
        case .text: return "Text"
        case .custom: return "Custom"
        }
    }

    private func colourMenu(symbol: String, help: String, options: [Swatch], apply: @escaping (String?) -> Void) -> some View {
        Menu {
            ForEach(options) { option in
                Button {
                    apply(option.hex)
                } label: {
                    if let color = GridColor.swiftUI(option.hex) {
                        Label { Text(option.name) } icon: { Image(systemName: "circle.fill").foregroundStyle(color) }
                    } else {
                        Text(option.name)
                    }
                }
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.inkSecondary(scheme))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 26, height: 24)
        .help(help)
    }

    private var insertMenu: some View {
        Menu {
            Button("Rows above") { sheets.insertRows() }
            Button("Rows below") { sheets.insertRows(below: true) }
            Button("Columns left") { sheets.insertColumns() }
            Button("Columns right") { sheets.insertColumns(right: true) }
            Divider()
            Button("Delete rows") { sheets.deleteRows() }
            Button("Delete columns") { sheets.deleteColumns() }
        } label: {
            Image(systemName: "plus.rectangle.on.rectangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.inkSecondary(scheme))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 26, height: 24)
        .help("Insert or delete rows and columns")
    }

    private var chartMenu: some View {
        Menu {
            ForEach(GridChart.Kind.allCases) { kind in
                Button(kind.title) { sheets.addChart(kind) }
            }
        } label: {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.inkSecondary(scheme))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 26, height: 24)
        .help("Chart the selection (or the whole table)")
    }
}

/// A named colour for the fill, text and tab menus.
struct Swatch: Identifiable, Hashable {
    var name: String
    var hex: String?
    var id: String { name }

    init(_ name: String, _ hex: String?) {
        self.name = name
        self.hex = hex
    }
}

struct TextToolButton: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var text: String
    var help: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(theme.inkSecondary(scheme))
                .padding(.horizontal, 5)
                .frame(minWidth: 24, minHeight: 24)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering ? theme.well(scheme) : Color.clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: Formula bar

private struct FormulaBar: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var sheets: SheetsModel
    @Environment(\.colorScheme) private var scheme
    @State private var text = ""
    @State private var address = ""
    @FocusState private var editing: Bool
    @FocusState private var naming: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("", text: $address)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(theme.ink(scheme))
                .frame(width: 74)
                .focused($naming)
                .onSubmit(jump)
                .help("Type a cell or range, like B12 or A1:D20, to go there")
            Rectangle().fill(theme.edge(scheme)).frame(width: 1, height: 16)
            Text("fx")
                .font(.system(size: 12, weight: .semibold, design: .serif).italic())
                .foregroundStyle(theme.inkTertiary(scheme))
            TextField("", text: $text, prompt: Text("Type a value, or = for a formula"))
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, design: text.hasPrefix("=") ? .monospaced : .default))
                .foregroundStyle(theme.ink(scheme))
                .focused($editing)
                .onSubmit {
                    sheets.setInput(text, at: sheets.active)
                    sheets.move(rows: 1, columns: 0, extend: false, jump: false)
                    sheets.focusRequest += 1
                }
                .onExitCommand {
                    text = sheets.input(sheets.active)
                    sheets.focusRequest += 1
                }
            if let formula = sheets.input(sheets.active).nilIfEmpty, formula.hasPrefix("=") {
                Text("= " + sheets.display(sheets.active))
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.well(scheme))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5)
        }
        .onAppear(perform: refresh)
        .onChange(of: sheets.active) { _, _ in refresh() }
        .onChange(of: sheets.extent) { _, _ in if !naming { address = sheets.selection.a1 } }
        .onChange(of: sheets.revision) { _, _ in if !editing { refresh() } }
        .onChange(of: sheets.sheetIndex) { _, _ in refresh() }
    }

    private func refresh() {
        text = sheets.input(sheets.active)
        if !naming { address = sheets.selection.a1 }
    }

    private func jump() {
        let typed = address.trimmingCharacters(in: .whitespaces).uppercased()
        if let range = CellRange(typed) {
            sheets.select(range)
        } else if let cell = CellAddress(typed) {
            sheets.select(cell)
        } else if let book = sheets.book, let named = book.names[typed] ?? book.names.first(where: { $0.key.uppercased() == typed })?.value,
                  let range = CellRange(named.components(separatedBy: "!").last?.replacingOccurrences(of: "$", with: "") ?? "") {
            sheets.select(range)
        }
        address = sheets.selection.a1
        sheets.focusRequest += 1
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: Tabs

private struct SheetTabs: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var sheets: SheetsModel
    @Environment(\.colorScheme) private var scheme
    @State private var renaming: Int?
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private static let colours: [Swatch] = [
        Swatch("None", nil), Swatch("Red", "#D9534F"), Swatch("Orange", "#E8964A"), Swatch("Yellow", "#E9C46A"),
        Swatch("Green", "#5BA36F"), Swatch("Blue", "#4A86C8"), Swatch("Purple", "#8E6CC0"),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    let list = sheets.book?.sheets ?? []
                    ForEach(list.indices, id: \.self) { index in
                        tab(index: index, sheet: list[index])
                    }
                    Button {
                        withAnimation(theme.spring) { sheets.addSheet() }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.inkSecondary(scheme))
                            .frame(width: 24, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Add a sheet")
                }
            }
            Spacer(minLength: 8)
            if let stats = sheets.selectionStats {
                HStack(spacing: 12) {
                    if !stats.sum.isEmpty {
                        stat("Sum", stats.sum)
                        stat("Average", stats.average)
                    }
                    stat("Count", "\(stats.count)")
                }
                .transition(.opacity)
            }
        }
        .frame(height: 26)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(theme.inkTertiary(scheme))
            Text(value).foregroundStyle(theme.ink(scheme)).monospacedDigit()
        }
        .font(.system(size: 11.5))
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func tab(index: Int, sheet: GridSheet) -> some View {
        let selected = index == sheets.sheetIndex
        if renaming == index {
            TextField("", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: max(70, CGFloat(name.count) * 7.5 + 20))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(theme.raised(scheme)) }
                .focused($nameFocused)
                .onAppear { nameFocused = true }
                .onSubmit {
                    sheets.renameSheet(index, to: name)
                    renaming = nil
                    sheets.focusRequest += 1
                }
                .onExitCommand { renaming = nil }
        } else {
            Button {
                sheets.showSheet(index)
            } label: {
                HStack(spacing: 6) {
                    if let colour = GridColor.swiftUI(sheet.color) {
                        Circle().fill(colour).frame(width: 7, height: 7)
                    }
                    Text(sheet.name)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? theme.ink(scheme) : theme.inkSecondary(scheme))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(theme.raised(scheme))
                            .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5) }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture(count: 2).onEnded { startRenaming(index, sheet) })
            .contextMenu {
                Button("Rename…") { startRenaming(index, sheet) }
                Button("Duplicate") { sheets.duplicateSheet(index) }
                Button("Move left") { sheets.moveSheet(index, by: -1) }.disabled(index == 0)
                Button("Move right") { sheets.moveSheet(index, by: 1) }.disabled(index >= (sheets.book?.sheets.count ?? 1) - 1)
                Menu("Colour") {
                    ForEach(Self.colours) { option in
                        Button(option.name) { sheets.setSheetColor(index, option.hex) }
                    }
                }
                Divider()
                Button("Delete sheet", role: .destructive) { sheets.deleteSheet(index) }
                    .disabled((sheets.book?.sheets.count ?? 1) <= 1)
            }
        }
    }

    private func startRenaming(_ index: Int, _ sheet: GridSheet) {
        name = sheet.name
        renaming = index
    }
}

// MARK: Charts

private struct ChartsPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var sheets: SheetsModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Charts")
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(sheets.sheet?.charts ?? []) { chart in
                        ChartCard(chart: chart)
                    }
                }
            }
        }
    }
}

private struct ChartCard: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var sheets: SheetsModel
    @Environment(\.colorScheme) private var scheme
    var chart: GridChart

    var body: some View {
        let data = sheets.series(for: chart)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(chart.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.ink(scheme))
                    .lineLimit(1)
                Spacer()
                Menu {
                    ForEach(GridChart.Kind.allCases) { kind in
                        Button(kind.title) {
                            var updated = chart
                            updated.kind = kind
                            sheets.updateChart(updated)
                        }
                    }
                    Divider()
                    Button("Use the selection (\(sheets.selection.a1))") {
                        var updated = chart
                        updated.range = sheets.effectiveSelection
                        sheets.updateChart(updated)
                    }
                    Button("Select its data") { sheets.select(chart.range) }
                    Divider()
                    Button("Remove chart", role: .destructive) { sheets.removeChart(chart.id) }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(theme.inkTertiary(scheme))
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            if data.points.isEmpty {
                Text("No numbers in \(chart.range.a1) to chart.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                GridChartView(kind: chart.kind, data: data, ink: theme.ink(scheme))
                    .frame(height: 180)
            }
            Text(chart.range.a1)
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(theme.inkTertiary(scheme))
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).fill(theme.well(scheme))
        }
        .overlay {
            RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5)
        }
    }
}

/// A chart in shades of ink, to sit on the vellum.
struct GridChartView: View {
    var kind: GridChart.Kind
    var data: GridSeries
    var ink: Color

    private var domain: [String] { kind == .pie ? data.labels : data.names }

    private var palette: [Color] {
        let steps: [Double] = [1, 0.62, 0.38, 0.22, 0.8, 0.5, 0.3, 0.15]
        return domain.indices.map { ink.opacity(steps[$0 % steps.count]) }
    }

    var body: some View {
        Chart(data.points) { point in
            switch kind {
            case .column:
                BarMark(x: .value("Label", point.label), y: .value("Value", point.value))
                    .foregroundStyle(by: .value("Series", point.series))
                    .position(by: .value("Series", point.series))
            case .bar:
                BarMark(x: .value("Value", point.value), y: .value("Label", point.label))
                    .foregroundStyle(by: .value("Series", point.series))
                    .position(by: .value("Series", point.series))
            case .line:
                LineMark(x: .value("Label", point.label), y: .value("Value", point.value))
                    .foregroundStyle(by: .value("Series", point.series))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Label", point.label), y: .value("Value", point.value))
                    .foregroundStyle(by: .value("Series", point.series))
                    .symbolSize(18)
            case .area:
                AreaMark(x: .value("Label", point.label), y: .value("Value", point.value))
                    .foregroundStyle(by: .value("Series", point.series))
                    .interpolationMethod(.monotone)
            case .pie:
                SectorMark(angle: .value("Value", max(0, point.value)), innerRadius: .ratio(0.55), angularInset: 1.5)
                    .foregroundStyle(by: .value("Label", point.label))
            case .scatter:
                PointMark(x: .value("Row", point.index), y: .value("Value", point.value))
                    .foregroundStyle(by: .value("Series", point.series))
            }
        }
        .chartForegroundStyleScale(domain: domain, range: palette)
        .chartLegend(domain.count > 1 ? .visible : .hidden)
        .font(.system(size: 10))
    }
}

// MARK: Summaries

private struct SummariseView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var sheets: SheetsModel
    @Environment(\.colorScheme) private var scheme
    var done: () -> Void
    @State private var group = 0
    @State private var value = 1
    @State private var summary: GridEdit.Summary = .sum

    var body: some View {
        let headers = sheets.tableHeaders
        VStack(alignment: .leading, spacing: 12) {
            Text("Summarise \u{201C}\(sheets.sheet?.name ?? "")\u{201D}")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.ink(scheme))
            Text("A new sheet with one row for each value, worked out with live formulas, and a chart.")
                .font(.system(size: 12))
                .foregroundStyle(theme.inkSecondary(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Picker("For each", selection: $group) {
                ForEach(headers) { header in Text(header.title).tag(header.column) }
            }
            Picker("Show the", selection: $summary) {
                ForEach(GridEdit.Summary.allCases) { kind in Text(kind.title).tag(kind) }
            }
            Picker("Of", selection: $value) {
                ForEach(headers) { header in Text(header.title).tag(header.column) }
            }
            HStack {
                Spacer()
                Button("Cancel", action: done)
                    .buttonStyle(.vellumSecondary)
                Button("Make summary") {
                    sheets.summarise(group: group, value: value, summary: summary)
                    done()
                }
                .buttonStyle(.vellumPrimary)
                .disabled(group == value && summary != .count)
            }
        }
        .padding(18)
        .frame(width: 340)
        .onAppear {
            // A sensible start: group by the first text column, total the last number column.
            let sheetIndex = sheets.sheetIndex
            let engine = sheets.engine
            func isNumber(_ column: Int) -> Bool {
                if case .number = engine.value(sheet: sheetIndex, CellAddress(row: 1, column: column)) { return true }
                return false
            }
            if let text = headers.first(where: { !isNumber($0.column) }) { group = text.column }
            if let number = headers.last(where: { isNumber($0.column) }) { value = number.column }
        }
    }
}

// MARK: George

private struct AskSheetsView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var sheets: SheetsModel
    @Environment(\.colorScheme) private var scheme
    @State private var question = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                AgentLogo(code: "ge", size: 20, color: theme.ink(scheme))
                Text("Ask George")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.ink(scheme))
            }
            Picker("", selection: $sheets.askKind) {
                ForEach(SheetsAsk.allCases) { kind in Text(kind.title).tag(kind) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if sheets.askKind == .explain {
                Text(sheets.input(sheets.active).hasPrefix("=") ? "\(sheets.active.a1): \(sheets.input(sheets.active))" : "Select a cell with a formula first.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .lineLimit(3)
            }
            AskField(placeholder: sheets.askKind.placeholder, text: $question) {
                sheets.ask(question)
            }
            if sheets.askKind == .explain && question.isEmpty {
                Button("Explain it") { sheets.ask("") }
                    .buttonStyle(.vellumSecondary)
                    .disabled(!sheets.input(sheets.active).hasPrefix("="))
            }
            if let run = sheets.askRun {
                RunView(run: run)
            }
            if let formula = sheets.suggestedFormula {
                HStack(spacing: 8) {
                    Text(formula)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.ink(scheme))
                        .textSelection(.enabled)
                        .lineLimit(3)
                    Spacer()
                    Button("Put in \(sheets.active.a1)") { sheets.useSuggestedFormula() }
                        .buttonStyle(.vellumPrimary)
                }
                .padding(10)
                .background { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.well(scheme)) }
            }
            Text("George only sees this workbook's headers and, when you ask about the numbers, this sheet.")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.inkTertiary(scheme))
        }
        .padding(18)
        .frame(width: 440)
    }
}
