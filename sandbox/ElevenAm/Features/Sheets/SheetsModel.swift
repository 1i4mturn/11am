import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A workbook as listed down the side, without loading its cells.
struct SheetsEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var modified: Date
    var sheets: Int
}

/// Cells copied inside 11am, so formulas move with them when pasted.
struct GridClip {
    var range: CellRange
    var cells: [[GridCell]]
    var isCut: Bool
    var sheetID: UUID
    var text: String
}

/// What George was asked to do in Sheets.
enum SheetsAsk: String, CaseIterable, Identifiable {
    case formula, explain, question, build

    var id: String { rawValue }

    var title: String {
        switch self {
        case .formula: return "Write a formula"
        case .explain: return "Explain this formula"
        case .question: return "Ask about this sheet"
        case .build: return "Make a sheet"
        }
    }

    var placeholder: String {
        switch self {
        case .formula: return "e.g. total of Amount where Region is North"
        case .explain: return "Select a cell with a formula, then ask"
        case .question: return "e.g. which month cost the most?"
        case .build: return "e.g. a 12-month cash flow with income, costs and running balance"
        }
    }
}

/// George's spreadsheets: workbooks of sheets on this Mac, with live formulas, undo, and Excel and CSV in and out.
@MainActor
final class SheetsModel: ObservableObject {
    @Published private(set) var entries: [SheetsEntry] = []
    @Published private(set) var book: Workbook?
    @Published var sheetIndex = 0
    /// The cell the cursor is on; typing goes here.
    @Published var active = CellAddress(row: 0, column: 0)
    /// The far corner of the selection; the other corner is `active`.
    @Published var extent = CellAddress(row: 0, column: 0)
    /// Bumped on every change so the grid redraws.
    @Published private(set) var revision = 0
    @Published var notice: String?
    @Published var askRun: BrainRun?
    @Published var askKind: SheetsAsk = .formula
    @Published var suggestedFormula: String?
    @Published var showsCharts = true
    @Published var search = ""
    /// Set to start typing in the active cell (from the formula bar's Return, or a menu).
    @Published var editRequest = 0
    /// Bumped to hand the keyboard back to the grid (after the formula bar).
    @Published var focusRequest = 0

    private(set) var engine = GridEngine(Workbook(name: "Empty"))
    private var undoStack: [Workbook] = []
    private var redoStack: [Workbook] = []
    private var saveTask: Task<Void, Never>?
    private let brain: Brain
    var clip: GridClip?

    let root: URL = JSONStore.folder.appendingPathComponent("Sheets", isDirectory: true)

    init(brain: Brain) {
        self.brain = brain
    }

    // MARK: Loading and saving

    func load() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: root.appendingPathComponent("index.json")),
           let saved = try? Self.decoder.decode([SheetsEntry].self, from: data) {
            entries = saved.filter { FileManager.default.fileExists(atPath: url(for: $0.id).path) }
        }
        if entries.isEmpty && !UserDefaults.standard.bool(forKey: "sheets.seeded") {
            for sample in SheetsSamples.all { write(sample) }
            UserDefaults.standard.set(true, forKey: "sheets.seeded")
        }
        sortEntries()
        if book == nil, let first = entries.first { open(first.id) }
    }

    func open(_ id: UUID) {
        flushSave()
        guard let data = try? Data(contentsOf: url(for: id)), let loaded = try? Self.decoder.decode(Workbook.self, from: data) else {
            notice = "That workbook couldn't be read."
            return
        }
        undoStack.removeAll()
        redoStack.removeAll()
        book = loaded
        engine = GridEngine(loaded)
        sheetIndex = 0
        select(CellAddress(row: 0, column: 0))
        revision += 1
    }

    /// Opens a workbook by name (launch flags, links from other apps).
    func open(named name: String) {
        if let entry = entries.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) { open(entry.id) }
    }

    func newWorkbook() {
        var names = Set(entries.map(\.name))
        var name = "Untitled"
        var number = 2
        while names.contains(name) { name = "Untitled \(number)"; number += 1 }
        names.insert(name)
        let fresh = Workbook(name: name)
        write(fresh)
        sortEntries()
        open(fresh.id)
    }

    func delete(_ id: UUID) {
        let target = url(for: id)
        NSWorkspace.shared.recycle([target]) { _, _ in }
        entries.removeAll { $0.id == id }
        saveIndex()
        if book?.id == id {
            book = nil
            if let first = entries.first { open(first.id) }
        }
    }

    func rename(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        change { $0.name = trimmed }
    }

    private func url(for id: UUID) -> URL { root.appendingPathComponent("\(id.uuidString).json") }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func write(_ workbook: Workbook) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let data = try? Self.encoder.encode(workbook) { try? data.write(to: url(for: workbook.id), options: .atomic) }
        let entry = SheetsEntry(id: workbook.id, name: workbook.name, modified: workbook.modified, sheets: workbook.sheets.count)
        if let index = entries.firstIndex(where: { $0.id == workbook.id }) { entries[index] = entry } else { entries.append(entry) }
        saveIndex()
    }

    private func saveIndex() {
        if let data = try? Self.encoder.encode(entries) { try? data.write(to: root.appendingPathComponent("index.json"), options: .atomic) }
    }

    private func sortEntries() {
        entries.sort { $0.modified > $1.modified }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            guard (try? await Task.sleep(for: .milliseconds(700))) != nil else { return }
            self?.flushSave()
        }
    }

    /// Writes the open workbook now (before switching, quitting or exporting).
    func flushSave() {
        saveTask?.cancel()
        saveTask = nil
        if let book { write(book) }
    }

    // MARK: Changing

    var sheet: GridSheet? {
        guard let book, book.sheets.indices.contains(sheetIndex) else { return nil }
        return book.sheets[sheetIndex]
    }

    var selection: CellRange { CellRange(active, extent) }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Every edit goes through here: one undo step, a fresh engine, a redraw and a save.
    func change(_ edit: (inout Workbook) -> Void) {
        guard var current = book else { return }
        let before = current
        edit(&current)
        guard current != before else { return }
        current.modified = Date()
        undoStack.append(before)
        if undoStack.count > 80 { undoStack.removeFirst(undoStack.count - 80) }
        redoStack.removeAll()
        apply(current)
    }

    private func apply(_ current: Workbook) {
        book = current
        engine = GridEngine(current)
        if sheetIndex >= current.sheets.count { sheetIndex = max(0, current.sheets.count - 1) }
        revision += 1
        scheduleSave()
    }

    func undo() {
        guard let previous = undoStack.popLast(), let book else { return }
        redoStack.append(book)
        apply(previous)
    }

    func redo() {
        guard let next = redoStack.popLast(), let book else { return }
        undoStack.append(book)
        apply(next)
    }

    /// Changes the cells of the current sheet.
    func changeSheet(_ edit: (inout GridSheet) -> Void) {
        let index = sheetIndex
        change { book in
            guard book.sheets.indices.contains(index) else { return }
            edit(&book.sheets[index])
        }
    }

    // MARK: Selection

    func select(_ address: CellAddress, extend: Bool = false) {
        let clamped = CellAddress(row: max(0, address.row), column: max(0, address.column))
        if extend {
            extent = clamped
        } else {
            active = clamped
            extent = clamped
        }
    }

    func select(_ range: CellRange) {
        active = range.start
        extent = range.end
    }

    /// Moves the cursor like the arrow keys: ⌘ jumps to the edge of the data.
    func move(rows: Int, columns: Int, extend: Bool, jump: Bool) {
        let from = extend ? extent : active
        var target = from.offset(rows: rows, columns: columns)
        if jump, let sheet {
            target = edge(of: sheet, from: from, rows: rows, columns: columns)
        }
        target = CellAddress(row: max(0, target.row), column: max(0, target.column))
        select(target, extend: extend)
    }

    private func edge(of sheet: GridSheet, from start: CellAddress, rows: Int, columns: Int) -> CellAddress {
        let step = (rows: rows.signum(), columns: columns.signum())
        let limit = (sheet.usedRange?.end ?? start)
        func filled(_ address: CellAddress) -> Bool { !sheet.input(address).isEmpty }
        var current = start
        let next = current.offset(rows: step.rows, columns: step.columns)
        let startingInData = filled(current) && filled(next)
        while true {
            let candidate = current.offset(rows: step.rows, columns: step.columns)
            if candidate.row < 0 || candidate.column < 0 { break }
            if candidate.row > limit.row + 1 && step.rows > 0 { break }
            if candidate.column > limit.column + 1 && step.columns > 0 { break }
            if startingInData {
                if !filled(candidate) { break }
                current = candidate
            } else {
                current = candidate
                if filled(candidate) { break }
            }
        }
        return current
    }

    func selectAll() {
        let end = sheet?.usedRange?.end ?? CellAddress(row: 0, column: 0)
        select(CellRange(CellAddress(row: 0, column: 0), end))
    }

    func selectColumn(_ column: Int, extend: Bool = false) {
        let rows = max((sheet?.usedRange?.end.row ?? 0), 99)
        if extend {
            active = CellAddress(row: 0, column: active.column)
            extent = CellAddress(row: rows, column: column)
        } else {
            active = CellAddress(row: 0, column: column)
            extent = CellAddress(row: rows, column: column)
        }
    }

    func selectRow(_ row: Int, extend: Bool = false) {
        let columns = max((sheet?.usedRange?.end.column ?? 0), 12)
        if extend {
            active = CellAddress(row: active.row, column: 0)
            extent = CellAddress(row: row, column: columns)
        } else {
            active = CellAddress(row: row, column: 0)
            extent = CellAddress(row: row, column: columns)
        }
    }

    /// The selection, trimmed to cells that hold something (so a whole column doesn't mean a million cells).
    var effectiveSelection: CellRange {
        let range = selection
        guard let used = sheet?.usedRange else { return range }
        let end = CellAddress(row: min(range.end.row, max(used.end.row, range.start.row)), column: min(range.end.column, max(used.end.column, range.start.column)))
        return CellRange(range.start, end)
    }

    // MARK: Cells

    func input(_ address: CellAddress) -> String { sheet?.input(address) ?? "" }

    func display(_ address: CellAddress) -> String { engine.display(sheet: sheetIndex, address) }

    func setInput(_ text: String, at address: CellAddress) {
        changeSheet { sheet in
            var cell = sheet[address]
            cell.input = Self.normalised(text)
            sheet[address] = cell
        }
    }

    /// Formulas typed in lower case become upper case outside quotes, so `=sum(a1:a3)` reads like Excel.
    static func normalised(_ text: String) -> String {
        guard text.hasPrefix("=") else { return text }
        var result = ""
        var quoted = false
        for character in text {
            if character == "\"" { quoted.toggle() }
            result.append(quoted ? character : Character(character.uppercased()))
        }
        return result
    }

    func clearContents() {
        let range = effectiveSelection
        changeSheet { sheet in
            for address in range.cells { sheet[address].input = "" }
        }
    }

    func clearFormats() {
        let range = effectiveSelection
        changeSheet { sheet in
            for address in range.cells { sheet[address].format = nil }
        }
    }

    // MARK: Formatting

    var activeFormat: CellFormat { sheet?[active].format ?? CellFormat() }

    /// The number format the active cell shows in, whether set or worked out.
    var activeNumberFormat: NumberFormat { engine.format(sheet: sheetIndex, active) }

    func format(_ transform: (inout CellFormat) -> Void) {
        let range = effectiveSelection
        changeSheet { sheet in
            for address in range.cells {
                var format = sheet[address].format ?? CellFormat()
                transform(&format)
                sheet[address].format = format.isPlain ? nil : format
            }
        }
    }

    func toggleBold() {
        let on = !activeFormat.bold
        format { $0.bold = on }
    }

    func toggleItalic() {
        let on = !activeFormat.italic
        format { $0.italic = on }
    }

    func toggleWrap() {
        let on = !activeFormat.wrap
        format { $0.wrap = on }
    }

    func setAlignment(_ alignment: CellFormat.Alignment?) {
        format { $0.alignment = alignment }
    }

    func setNumberFormat(_ number: NumberFormat) {
        format { $0.number = number }
    }

    func setFill(_ hex: String?) { format { $0.fill = hex } }
    func setColor(_ hex: String?) { format { $0.color = hex } }

    /// One more or one fewer decimal place, starting from what the cell shows now.
    func adjustDecimals(_ step: Int) {
        let current = activeNumberFormat
        let updated: NumberFormat
        switch current {
        case .number(let places): updated = .number(max(0, min(10, places + step)))
        case .currency(let places): updated = .currency(max(0, min(10, places + step)))
        case .percent(let places): updated = .percent(max(0, min(10, places + step)))
        default:
            let text = display(active)
            let places = text.split(separator: ".").last.map { $0.filter(\.isNumber).count } ?? 0
            updated = .number(max(0, (text.contains(".") ? places : 0) + step))
        }
        setNumberFormat(updated)
    }

    // MARK: Rows, columns and sheets

    func insertRows(below: Bool = false) {
        let range = selection
        let index = below ? range.end.row + 1 : range.start.row
        let sheet = sheetIndex
        change { GridEdit.insert(&$0, sheet: sheet, rows: true, at: index, count: range.rowCount) }
        if below { select(CellRange(CellAddress(row: index, column: range.start.column), CellAddress(row: index + range.rowCount - 1, column: range.end.column))) }
    }

    func insertColumns(right: Bool = false) {
        let range = selection
        let index = right ? range.end.column + 1 : range.start.column
        let sheet = sheetIndex
        change { GridEdit.insert(&$0, sheet: sheet, rows: false, at: index, count: range.columnCount) }
        if right { select(CellRange(CellAddress(row: range.start.row, column: index), CellAddress(row: range.end.row, column: index + range.columnCount - 1))) }
    }

    func deleteRows() {
        let range = selection
        let sheet = sheetIndex
        change { GridEdit.insert(&$0, sheet: sheet, rows: true, at: range.start.row, count: -range.rowCount) }
        select(CellAddress(row: range.start.row, column: active.column))
    }

    func deleteColumns() {
        let range = selection
        let sheet = sheetIndex
        change { GridEdit.insert(&$0, sheet: sheet, rows: false, at: range.start.column, count: -range.columnCount) }
        select(CellAddress(row: active.row, column: range.start.column))
    }

    func setColumnWidth(_ column: Int, _ width: Double) {
        changeSheet { $0.columnWidths[column] = max(28, min(800, width.rounded())) }
    }

    /// Fits a column to what it shows.
    func autoFit(_ column: Int) {
        guard let sheet, let used = sheet.usedRange else { return }
        var widest: CGFloat = 40
        for row in 0...min(used.end.row, 2000) {
            let address = CellAddress(row: row, column: column)
            let text = display(address)
            guard !text.isEmpty else { continue }
            let bold = sheet[address].format?.bold ?? false
            let font = NSFont.systemFont(ofSize: 12, weight: bold ? .semibold : .regular)
            widest = max(widest, (text as NSString).size(withAttributes: [.font: font]).width + 18)
        }
        setColumnWidth(column, Double(widest))
    }

    func freezeRows(_ count: Int) {
        changeSheet { $0.frozenRows = max(0, count) }
    }

    func sort(ascending: Bool) {
        guard let sheet else { return }
        var range = effectiveSelection
        // A single cell sorts the table around it, keeping the header.
        if range.isSingleCell, let used = sheet.usedRange {
            range = CellRange(CellAddress(row: 0, column: 0), used.end)
        }
        let header = range.start.row == 0 && sheet.frozenRows > 0 || looksLikeHeader(range)
        let column = active.column
        let index = sheetIndex
        change { GridEdit.sort(&$0, sheet: index, range: range, by: column, ascending: ascending, header: header) }
    }

    private func looksLikeHeader(_ range: CellRange) -> Bool {
        guard range.rowCount > 1 else { return false }
        let first = range.columns.map { engine.value(sheet: sheetIndex, CellAddress(row: range.start.row, column: $0)) }
        let second = range.columns.map { engine.value(sheet: sheetIndex, CellAddress(row: range.start.row + 1, column: $0)) }
        let firstAllText = first.allSatisfy { if case .text = $0 { return true }; return $0 == .empty }
        let secondHasNumber = second.contains { if case .number = $0 { return true }; return false }
        return firstAllText && secondHasNumber
    }

    func fill(to target: CellRange) {
        let source = selection
        guard target != source else { return }
        changeSheet { GridEdit.fill(&$0, from: source, to: target) }
        select(target)
    }

    func fillDown() {
        let range = selection
        guard range.rowCount > 1 else { return }
        let source = CellRange(range.start, CellAddress(row: range.start.row, column: range.end.column))
        changeSheet { GridEdit.fill(&$0, from: source, to: range) }
    }

    func fillRight() {
        let range = selection
        guard range.columnCount > 1 else { return }
        let source = CellRange(range.start, CellAddress(row: range.end.row, column: range.start.column))
        changeSheet { GridEdit.fill(&$0, from: source, to: range) }
    }

    func addSheet() {
        guard let book else { return }
        var number = book.sheets.count + 1
        while book.sheetIndex(named: "Sheet \(number)") != nil { number += 1 }
        let name = "Sheet \(number)"
        change { $0.sheets.append(GridSheet(name: name)) }
        sheetIndex = (self.book?.sheets.count ?? 1) - 1
        select(CellAddress(row: 0, column: 0))
    }

    func showSheet(_ index: Int) {
        guard let book, book.sheets.indices.contains(index), index != sheetIndex else { return }
        sheetIndex = index
        select(CellAddress(row: 0, column: 0))
        revision += 1
    }

    func renameSheet(_ index: Int, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "!", with: "")
        guard !trimmed.isEmpty, let book, book.sheets.indices.contains(index) else { return }
        let old = book.sheets[index].name
        guard trimmed != old, book.sheetIndex(named: trimmed) == nil else { return }
        change { workbook in
            workbook.sheets[index].name = trimmed
            // Formulas elsewhere that name the old sheet follow it.
            for sheet in workbook.sheets.indices {
                for (address, cell) in workbook.sheets[sheet].cells where cell.input.hasPrefix("=") && cell.input.localizedCaseInsensitiveContains(old) {
                    workbook.sheets[sheet].cells[address]?.input = Self.renaming(sheet: old, to: trimmed, in: cell.input)
                }
            }
        }
    }

    static func renaming(sheet old: String, to new: String, in formula: String) -> String {
        let quotedNew = new.contains(where: { !$0.isLetter && !$0.isNumber && $0 != "_" }) ? "'" + new.replacingOccurrences(of: "'", with: "''") + "'" : new
        var result = formula
        let quotedOld = "'" + old.replacingOccurrences(of: "'", with: "''") + "'!"
        result = result.replacingOccurrences(of: quotedOld, with: quotedNew + "!", options: .caseInsensitive)
        if !old.contains(" ") {
            result = result.replacingOccurrences(of: old + "!", with: quotedNew + "!", options: .caseInsensitive)
        }
        return result
    }

    func duplicateSheet(_ index: Int) {
        guard let book, book.sheets.indices.contains(index) else { return }
        var copy = book.sheets[index]
        copy.id = UUID()
        var name = copy.name + " copy"
        var number = 2
        while book.sheetIndex(named: name) != nil { name = copy.name + " copy \(number)"; number += 1 }
        copy.name = name
        copy.charts = copy.charts.map { chart in
            var fresh = chart
            fresh.id = UUID()
            return fresh
        }
        change { $0.sheets.insert(copy, at: index + 1) }
        sheetIndex = index + 1
    }

    func deleteSheet(_ index: Int) {
        guard let book, book.sheets.count > 1, book.sheets.indices.contains(index) else { return }
        change { $0.sheets.remove(at: index) }
        sheetIndex = min(sheetIndex, (self.book?.sheets.count ?? 1) - 1)
        select(CellAddress(row: 0, column: 0))
    }

    func moveSheet(_ index: Int, by offset: Int) {
        guard let book, book.sheets.indices.contains(index), book.sheets.indices.contains(index + offset) else { return }
        change { $0.sheets.swapAt(index, index + offset) }
        sheetIndex = index + offset
    }

    func setSheetColor(_ index: Int, _ hex: String?) {
        change { workbook in
            guard workbook.sheets.indices.contains(index) else { return }
            workbook.sheets[index].color = hex
        }
    }

    // MARK: Copy and paste

    func copy(cut: Bool = false) {
        guard let sheet else { return }
        let range = effectiveSelection
        let cells = range.rows.map { row in range.columns.map { sheet[CellAddress(row: row, column: $0)] } }
        let text = GridEdit.tsv(engine, sheet: sheetIndex, range: range)
        clip = GridClip(range: range, cells: cells, isCut: cut, sheetID: sheet.id, text: text)
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }

    func paste() {
        let board = NSPasteboard.general.string(forType: .string) ?? ""
        let destination = selection.start
        if let clip, clip.text == board {
            let index = sheetIndex
            let originSheet = book?.sheets.firstIndex { $0.id == clip.sheetID }
            change { workbook in
                if clip.isCut, let origin = originSheet {
                    for address in clip.range.cells { workbook.sheets[origin][address] = GridCell() }
                }
                GridEdit.paste(clip.cells, from: clip.range.start, into: &workbook.sheets[index], at: destination)
            }
            select(CellRange(destination, destination.offset(rows: clip.range.rowCount - 1, columns: clip.range.columnCount - 1)))
            if clip.isCut { self.clip = nil }
            return
        }
        guard !board.isEmpty else { return }
        var pasted = CellRange(destination)
        changeSheet { sheet in pasted = GridEdit.paste(text: board, into: &sheet, at: destination) }
        select(pasted)
    }

    // MARK: Charts and summaries

    func addChart(_ kind: GridChart.Kind) {
        guard let sheet else { return }
        var range = effectiveSelection
        if range.isSingleCell, let used = sheet.usedRange { range = used }
        let title = sheet.input(range.start).isEmpty ? sheet.name : sheet.input(range.start)
        let chart = GridChart(kind: kind, range: range, title: title)
        changeSheet { $0.charts.append(chart) }
        showsCharts = true
    }

    func removeChart(_ id: UUID) {
        changeSheet { $0.charts.removeAll { $0.id == id } }
    }

    func updateChart(_ chart: GridChart) {
        changeSheet { sheet in
            if let index = sheet.charts.firstIndex(where: { $0.id == chart.id }) { sheet.charts[index] = chart }
        }
    }

    /// Labels and series for a chart: the first column names the rows, the first row names the series.
    func series(for chart: GridChart) -> GridSeries {
        GridSeries.make(engine: engine, sheet: sheetIndex, range: chart.range)
    }

    /// The headers of the table the cursor is in, for the summary picker.
    var tableHeaders: [GridHeader] {
        guard let used = sheet?.usedRange else { return [] }
        return used.columns.compactMap { column in
            let title = display(CellAddress(row: 0, column: column))
            return title.isEmpty ? nil : GridHeader(column: column, title: title)
        }
    }

    func summarise(group: Int, value: Int, summary: GridEdit.Summary) {
        guard let book, let used = sheet?.usedRange else { return }
        let index = sheetIndex
        var result = GridEdit.summarise(book, sheet: index, range: used, group: group, value: value, summary: summary)
        var name = result.name
        var number = 2
        while book.sheetIndex(named: name) != nil { name = result.name + " \(number)"; number += 1 }
        result.name = name
        let rows = result.usedRange?.end.row ?? 1
        if rows > 1 { result.charts = [GridChart(kind: .bar, range: CellRange(CellAddress(row: 0, column: 0), CellAddress(row: rows - 1, column: 1)), title: name)] }
        change { $0.sheets.insert(result, at: index + 1) }
        sheetIndex = index + 1
        select(CellAddress(row: 1, column: 1))
        notice = "Made \u{201C}\(name)\u{201D}. It's live: change the table and it updates."
    }

    // MARK: Status

    /// Sum, average and count of the selection, like the bottom of Excel.
    var selectionStats: (sum: String, average: String, count: Int)? {
        let range = effectiveSelection
        guard !range.isSingleCell, range.rowCount * range.columnCount <= 200_000 else { return nil }
        let values = engine.area(sheet: sheetIndex, range).values
        let numbers = values.compactMap { value -> Double? in if case .number(let n) = value { return n }; return nil }
        let count = values.filter { $0 != .empty }.count
        guard count > 0 else { return nil }
        let format = engine.format(sheet: sheetIndex, range.start)
        guard !numbers.isEmpty else { return ("", "", count) }
        let total = numbers.reduce(0, +)
        let useFormat: NumberFormat = format.isDate || format == .text ? .general : format
        return (GridDisplay.text(total, format: useFormat), GridDisplay.text(total / Double(numbers.count), format: useFormat), count)
    }

    // MARK: Files

    func importFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? UTType.data, UTType.commaSeparatedText, UTType.tabSeparatedText, UTType.plainText]
        guard panel.runModal() == .OK else { return }
        importURLs(panel.urls)
    }

    func importURLs(_ urls: [URL]) {
        var last: UUID?
        var failed: [String] = []
        for url in urls {
            do {
                var workbook: Workbook
                if url.pathExtension.lowercased() == "xlsx" {
                    workbook = try GridXLSX.workbook(from: url)
                } else {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    workbook = Workbook(name: url.deletingPathExtension().lastPathComponent, sheets: [GridCSV.sheet(from: text, name: "Sheet 1")])
                }
                workbook.id = UUID()
                workbook.name = url.deletingPathExtension().lastPathComponent
                workbook.modified = Date()
                write(workbook)
                last = workbook.id
            } catch {
                failed.append(url.lastPathComponent)
            }
        }
        sortEntries()
        if let last { open(last) }
        if !failed.isEmpty { notice = "Couldn't read \(failed.joined(separator: ", "))." }
        else if urls.count > 1 { notice = "Imported \(urls.count) workbooks." }
    }

    /// Saves a workbook made elsewhere (George's reports) and opens it.
    func add(_ workbook: Workbook) {
        var copy = workbook
        copy.id = UUID()
        copy.modified = Date()
        var name = copy.name
        var number = 2
        while entries.contains(where: { $0.name == name }) { name = "\(copy.name) \(number)"; number += 1 }
        copy.name = name
        flushSave()
        write(copy)
        sortEntries()
        open(copy.id)
        notice = "Opened \u{201C}\(name)\u{201D} from Money."
    }

    enum Export: String, CaseIterable, Identifiable {
        case xlsx, csv, pdf
        var id: String { rawValue }
        var title: String {
            switch self {
            case .xlsx: return "Excel workbook (.xlsx)"
            case .csv: return "This sheet as CSV"
            case .pdf: return "This sheet as PDF"
            }
        }
    }

    func export(_ kind: Export) {
        guard let book else { return }
        flushSave()
        let panel = NSSavePanel()
        let base = kind == .xlsx ? book.name : "\(book.name) - \(sheet?.name ?? "Sheet")"
        panel.nameFieldStringValue = base.replacingOccurrences(of: "/", with: "-") + "." + kind.rawValue
        if let type = UTType(filenameExtension: kind.rawValue) { panel.allowedContentTypes = [type] }
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data(for: kind).write(to: url, options: .atomic)
            notice = "Saved \(url.lastPathComponent)."
        } catch {
            notice = "Couldn't save: \(error.localizedDescription)"
        }
    }

    func data(for kind: Export) -> Data {
        guard let book else { return Data() }
        switch kind {
        case .xlsx: return GridXLSX.data(book)
        case .csv: return Data(GridCSV.text(engine, sheet: sheetIndex).utf8)
        case .pdf:
            let markdown = markdownTable()
            var setup = PageSetup()
            setup.landscape = (sheet?.usedRange?.columnCount ?? 0) > 5
            setup.margin = 40
            return DocPDF.data(markdown, title: "\(book.name) · \(sheet?.name ?? "")", setup: setup, baseURL: nil)
        }
    }

    /// The sheet as a Markdown table (for PDF and for George).
    func markdownTable(limit: Int = 2_000) -> String {
        guard let used = sheet?.usedRange else { return "" }
        let rows = Array(used.rows.prefix(limit))
        func cell(_ row: Int, _ column: Int) -> String {
            display(CellAddress(row: row, column: column)).replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
        }
        var lines: [String] = []
        for (offset, row) in rows.enumerated() {
            lines.append("| " + used.columns.map { cell(row, $0) }.joined(separator: " | ") + " |")
            if offset == 0 { lines.append("|" + used.columns.map { _ in " --- " }.joined(separator: "|") + "|") }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: George

    func ask(_ request: String) {
        let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        suggestedFormula = nil
        guard let sheet, let book else { return }
        let headers = describeColumns()
        let cell = active.a1
        let others = book.sheets.enumerated().filter { $0.offset != sheetIndex }.map { $0.element.name }
        let context = """
        Sheet: \(sheet.name)\(others.isEmpty ? "" : " (other sheets: \(others.joined(separator: ", ")))")
        Columns:
        \(headers)
        Data rows: \(sheet.usedRange.map { "2 to \($0.end.row + 1)" } ?? "none")
        Selected cell: \(cell)
        """
        let system: String
        let prompt: String
        switch askKind {
        case .formula:
            guard !request.isEmpty else { return }
            system = """
            You are George, the finance agent inside 11am, writing a spreadsheet formula. Use Excel syntax and only these functions: \
            \(GridFunctions.names.joined(separator: ", ")). Use the real column letters and rows given. \
            Reply with the formula alone on the first line, starting with =, then one short sentence on what it does.
            """
            prompt = "\(context)\n\nWrite a formula for \(cell) that works out: \(request)"
        case .explain:
            let formula = input(active)
            guard formula.hasPrefix("=") else {
                notice = "Pick a cell with a formula first, then ask George to explain it."
                return
            }
            system = "You are George, the finance agent inside 11am. Explain a spreadsheet formula in plain words, in two to four short sentences. Name the columns by their headers."
            prompt = "\(context)\n\nFormula in \(cell): \(formula)\nIt currently shows: \(display(active))\n\(request.isEmpty ? "" : "Question: \(request)")"
        case .question:
            guard !request.isEmpty else { return }
            system = """
            You are George, the finance agent inside 11am. Answer using only the table given. Never invent a number. \
            Show the arithmetic briefly when you calculate. Keep it short and plain. This is not financial or tax advice.
            """
            prompt = "Sheet \u{201C}\(sheet.name)\u{201D}:\n\n\(markdownTable(limit: 300))\n\nQuestion: \(request)"
        case .build:
            guard !request.isEmpty else { return }
            system = """
            You are George, the finance agent inside 11am, making a spreadsheet. Reply with one CSV block in ``` fences and nothing else. \
            The first row is headers. Cells may hold Excel formulas starting with = using A1 references to the rows as they will be \
            placed (headers in row 1). Use only: \(GridFunctions.names.joined(separator: ", ")). Write money as plain numbers. Quote any \
            cell containing a comma. Keep it under 40 rows.
            """
            prompt = "Make a sheet for: \(request)"
        }
        let run = brain.run(BrainRequest(system: system, prompt: prompt, weight: askKind == .build ? .deep : .quick))
        askRun = run
        let kind = askKind
        Task { [weak self] in
            await run.finished()
            guard let self, self.askRun === run, case .done = run.status else { return }
            switch kind {
            case .formula: self.suggestedFormula = Self.formula(in: run.text)
            case .build: self.makeSheet(from: run.text, title: request)
            default: break
            }
        }
    }

    /// The first line that is a formula, from George's reply.
    static func formula(in text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            trimmed = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
            if trimmed.hasPrefix("=") { return trimmed }
        }
        return nil
    }

    func useSuggestedFormula() {
        guard let formula = suggestedFormula else { return }
        setInput(formula, at: active)
        suggestedFormula = nil
        askRun = nil
    }

    private func makeSheet(from text: String, title: String) {
        var csv = text
        if let start = text.range(of: "```") {
            let rest = text[start.upperBound...]
            let body = rest.drop { $0 != "\n" }.dropFirst()
            if let end = body.range(of: "```") { csv = String(body[..<end.lowerBound]) } else { csv = String(body) }
        }
        csv = csv.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !csv.isEmpty, let book else { return }
        var made = GridCSV.sheet(from: csv, name: "")
        let words = title.split(separator: " ").prefix(4).joined(separator: " ")
        var name = words.isEmpty ? "George's sheet" : words.prefix(1).uppercased() + words.dropFirst()
        var number = 2
        let base = name
        while book.sheetIndex(named: name) != nil { name = "\(base) \(number)"; number += 1 }
        made.name = name
        if let used = made.usedRange {
            for column in used.columns { made.columnWidths[column] = column == 0 ? 160 : 110 }
        }
        let index = sheetIndex
        change { $0.sheets.insert(made, at: index + 1) }
        sheetIndex = index + 1
        select(CellAddress(row: 1, column: 0))
        notice = "George made \u{201C}\(name)\u{201D}. Check it before you rely on it."
    }

    private func describeColumns() -> String {
        guard let used = sheet?.usedRange else { return "(empty)" }
        return used.columns.prefix(30).map { column in
            let letter = CellAddress.columnName(column)
            let header = display(CellAddress(row: 0, column: column))
            let sample = display(CellAddress(row: min(1, used.end.row), column: column))
            return "\(letter): \(header.isEmpty ? "(no header)" : header)\(sample.isEmpty ? "" : ", e.g. \(sample)")"
        }.joined(separator: "\n")
    }
}

struct GridHeader: Identifiable, Hashable {
    var column: Int
    var title: String
    var id: Int { column }
}

/// A chart's data, read from the grid.
struct GridSeries {
    struct Point: Identifiable {
        var id: String { "\(series)-\(index)" }
        var index: Int
        var label: String
        var series: String
        var value: Double
    }

    var points: [Point]
    var names: [String]
    var labels: [String]

    static func make(engine: GridEngine, sheet: Int, range: CellRange) -> GridSeries {
        guard range.columnCount >= 1 else { return GridSeries(points: [], names: [], labels: []) }
        let firstRow = range.columns.map { engine.value(sheet: sheet, CellAddress(row: range.start.row, column: $0)) }
        func isText(_ value: CellValue) -> Bool {
            if case .text = value { return true }
            return false
        }
        let hasHeader = range.rowCount > 1 && (range.columnCount == 1 ? isText(firstRow[0]) : firstRow.dropFirst().contains(where: isText))
        let firstColumnIsLabels = range.columnCount > 1 && range.rows.dropFirst(hasHeader ? 1 : 0).contains { row in
            if case .number = engine.value(sheet: sheet, CellAddress(row: row, column: range.start.column)),
               !engine.format(sheet: sheet, CellAddress(row: row, column: range.start.column)).isDate { return false }
            return true
        }
        let valueColumns = Array(range.columns.dropFirst(firstColumnIsLabels ? 1 : 0))
        let rows = Array(range.rows.dropFirst(hasHeader ? 1 : 0))
        var names: [String] = []
        for column in valueColumns {
            let name = hasHeader ? engine.display(sheet: sheet, CellAddress(row: range.start.row, column: column)) : CellAddress.columnName(column)
            names.append(name.isEmpty ? CellAddress.columnName(column) : name)
        }
        var labels: [String] = []
        var points: [Point] = []
        for (index, row) in rows.enumerated() {
            let label = firstColumnIsLabels ? engine.display(sheet: sheet, CellAddress(row: row, column: range.start.column)) : "\(row + 1)"
            // Total rows would dwarf the rest; leave them out.
            if label.lowercased().hasPrefix("total") { continue }
            labels.append(label)
            for (offset, column) in valueColumns.enumerated() {
                if case .number(let value) = engine.value(sheet: sheet, CellAddress(row: row, column: column)) {
                    points.append(Point(index: index, label: label, series: names[offset], value: value))
                }
            }
        }
        return GridSeries(points: points, names: names, labels: labels)
    }
}
