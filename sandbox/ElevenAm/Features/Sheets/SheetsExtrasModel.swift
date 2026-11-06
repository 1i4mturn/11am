import AppKit
import Foundation

/// The panel beside the grid.
enum SheetsPanel: String, CaseIterable, Identifiable {
    case rules, validation, clean, comments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rules: return "Conditional formatting"
        case .validation: return "Validation"
        case .clean: return "Clean a column"
        case .comments: return "Comments"
        }
    }

    var symbol: String {
        switch self {
        case .rules: return "paintpalette"
        case .validation: return "checklist"
        case .clean: return "wand.and.stars"
        case .comments: return "text.bubble"
        }
    }
}

/// What the grid paints over the cells: rule colours and bars, cells that break their validation, and comments.
struct SheetDecorations {
    var revision: Int
    var sheet: Int
    var effects: [CellAddress: RuleEffect]
    var invalid: Set<CellAddress>
    var comments: Set<CellAddress>
}

// MARK: Conditional formatting, validation, comments, cleaning and versions

extension SheetsModel {
    var decorations: SheetDecorations {
        if let cached = decorationCache, cached.revision == revision, cached.sheet == sheetIndex { return cached }
        let fresh = SheetDecorations(revision: revision, sheet: sheetIndex,
                                     effects: GridRules.effects(sheet: sheetIndex, engine: engine),
                                     invalid: GridValidation.invalidCells(sheet: sheetIndex, engine: engine),
                                     comments: Set(sheet?.comments.filter { !$0.resolved }.map(\.address) ?? []))
        decorationCache = fresh
        return fresh
    }

    func togglePanel(_ panel: SheetsPanel) {
        self.panel = self.panel == panel ? nil : panel
    }

    /// The range a new rule or validation covers: the selection, or for one cell, its column's data below the header.
    var targetRange: CellRange {
        guard selection.isSingleCell, let sheet else { return selection }
        let column = active.column
        let first = (sheet.frozenRows > 0 || isHeader(sheet)) ? 1 : 0
        // An empty column gets twenty rows to start with; otherwise its data, below any heading.
        let last = sheet.cells.filter { $0.key.column == column && !$0.value.input.isEmpty }.map(\.key.row).max() ?? first + 19
        return CellRange(CellAddress(row: first, column: column), CellAddress(row: max(last, first), column: column))
    }

    /// The first row reads like headings: text, and bold or above numbers.
    private func isHeader(_ sheet: GridSheet) -> Bool {
        guard let used = sheet.usedRange else { return false }
        let firstRow = used.columns.map { engine.value(sheet: sheetIndex, CellAddress(row: 0, column: $0)) }
        let secondRow = used.columns.map { engine.value(sheet: sheetIndex, CellAddress(row: 1, column: $0)) }
        let textAbove = firstRow.filter { if case .text = $0 { return true } else { return false } }.count
        let numbersBelow = secondRow.filter { $0.number != nil }.count
        return textAbove > 0 && (numbersBelow > 0 || used.columns.contains { sheet.cells[CellAddress(row: 0, column: $0)]?.format?.bold == true })
    }

    // MARK: Rules

    var rules: [ConditionalRule] { sheet?.rules ?? [] }

    func addRule(_ kind: ConditionalRule.Kind) {
        let range = targetRange
        var rule = ConditionalRule(range: range, kind: kind)
        let numbers = range.cells.compactMap { engine.value(sheet: sheetIndex, $0).number }
        let middle = numbers.isEmpty ? 0 : numbers.sorted()[numbers.count / 2]
        switch kind {
        case .greaterThan: rule.value1 = GridDisplay.general(middle.rounded())
        case .lessThan: rule.value1 = GridDisplay.general(middle.rounded())
        case .between:
            rule.value1 = GridDisplay.general((numbers.min() ?? 0).rounded())
            rule.value2 = GridDisplay.general(middle.rounded())
        case .equalTo, .notEqualTo, .containsText:
            rule.value1 = display(range.start)
        case .top, .bottom: rule.value1 = "3"
        case .formula: rule.value1 = "=\(range.start.a1)<>\"\""
        case .colorScale: rule.low = "#FFFFFF"; rule.high = "#6E9E78"
        case .dataBar: rule.high = "#8FB59A"
        case .blank, .duplicate:
            rule.style = RuleStyle.presets[2].style
        default: break
        }
        changeSheet { $0.rules.append(rule) }
    }

    func updateRule(_ rule: ConditionalRule) {
        changeSheet { sheet in
            if let index = sheet.rules.firstIndex(where: { $0.id == rule.id }) { sheet.rules[index] = rule }
        }
    }

    func deleteRule(_ id: UUID) {
        changeSheet { $0.rules.removeAll { $0.id == id } }
    }

    /// Earlier rules win, so moving one up gives it priority.
    func moveRule(_ id: UUID, by offset: Int) {
        changeSheet { sheet in
            guard let index = sheet.rules.firstIndex(where: { $0.id == id }) else { return }
            let target = max(0, min(sheet.rules.count - 1, index + offset))
            guard target != index else { return }
            let rule = sheet.rules.remove(at: index)
            sheet.rules.insert(rule, at: target)
        }
    }

    // MARK: Validation

    var validations: [DataValidation] { sheet?.validations ?? [] }

    var activeValidation: DataValidation? { sheet.flatMap { GridValidation.rule(at: active, in: $0) } }

    func choices(for rule: DataValidation) -> [String] { GridValidation.choices(rule, engine: engine, sheet: sheetIndex) }

    func addValidation(_ kind: DataValidation.Kind) {
        let range = targetRange
        var rule = DataValidation(range: range, kind: kind)
        switch kind {
        case .list:
            // Start from what's already in the column.
            var seen = Set<String>()
            rule.choices = range.cells.compactMap { address in
                let text = display(address).trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty, seen.insert(text.lowercased()).inserted else { return nil }
                return text
            }
            if rule.choices.isEmpty || rule.choices.count > 12 { rule.choices = ["Yes", "No"] }
        case .wholeNumber: rule.minimum = "0"
        case .decimal: rule.minimum = "0"
        case .date:
            // From the start of this financial year.
            let year = Calendar.current.component(.year, from: Date())
            let month = Calendar.current.component(.month, from: Date())
            let start = month < 7 ? year - 1 : year
            rule.minimum = "1/7/\(start)"
        case .textLength: rule.maximum = "40"
        case .checkbox: break
        }
        changeSheet { $0.validations.append(rule) }
        if kind == .checkbox {
            notice = "Tick boxes in \(range.a1). Click one to tick it; they count as TRUE in formulas, like =COUNTIF(\(range.a1),TRUE)."
        }
    }

    func updateValidation(_ rule: DataValidation) {
        changeSheet { sheet in
            if let index = sheet.validations.firstIndex(where: { $0.id == rule.id }) { sheet.validations[index] = rule }
        }
    }

    func deleteValidation(_ id: UUID) {
        changeSheet { $0.validations.removeAll { $0.id == id } }
    }

    func toggleCheckbox(_ address: CellAddress) {
        guard let sheet, GridValidation.checkbox(at: address, in: sheet, engine: engine, index: sheetIndex) != nil else { return }
        let ticked = GridValidation.checkbox(at: address, in: sheet, engine: engine, index: sheetIndex) == true
        setInput(ticked ? "FALSE" : "TRUE", at: address)
    }

    // MARK: Comments

    var threads: [(address: CellAddress, comments: [GridComment])] { sheet.map(GridComments.threads) ?? [] }

    func addComment(_ text: String, at address: CellAddress) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let comment = GridComment(address: address, author: "You", text: trimmed, date: Date())
        changeSheet { $0.comments.append(comment) }
        if GridComments.mentionsGeorge(trimmed) { askGeorge(about: address, question: trimmed) }
    }

    func resolveThread(_ address: CellAddress) {
        changeSheet { sheet in
            for index in sheet.comments.indices where sheet.comments[index].address == address { sheet.comments[index].resolved = true }
        }
    }

    func deleteComment(_ id: UUID) {
        changeSheet { $0.comments.removeAll { $0.id == id } }
    }

    /// "@George, is this right?": he answers from the sheet, in the thread.
    private func askGeorge(about address: CellAddress, question: String) {
        guard let sheet else { return }
        let input = sheet.input(address)
        let thread = sheet.comments.filter { $0.address == address && !$0.resolved }.sorted { $0.date < $1.date }
            .map { "\($0.author): \($0.text)" }.joined(separator: "\n")
        let system = """
        You are George, the finance agent inside 11am, answering a comment on a spreadsheet cell. Use only the sheet given. \
        Never invent a number; show the arithmetic briefly if you calculate. Two or three short sentences, plain words. \
        This is not financial or tax advice.
        """
        let prompt = """
        Sheet \u{201C}\(sheet.name)\u{201D}:

        \(markdownTable(limit: 200))

        The comment is on \(address.a1), which shows \(display(address))\(input.hasPrefix("=") ? " from the formula \(input)" : "").

        Thread so far:
        \(thread)
        """
        let run = brain.run(BrainRequest(system: system, prompt: prompt, weight: .quick))
        commentRun = run
        let sheetID = sheet.id
        Task { [weak self] in
            await run.finished()
            guard let self, self.commentRun === run else { return }
            self.commentRun = nil
            guard case .done = run.status else {
                self.notice = "George couldn't answer just now."
                return
            }
            let answer = run.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty, let index = self.book?.sheets.firstIndex(where: { $0.id == sheetID }) else { return }
            let reply = GridComment(address: address, author: "George", text: answer, date: Date())
            self.change { book in
                guard book.sheets.indices.contains(index) else { return }
                book.sheets[index].comments.append(reply)
            }
        }
    }

    // MARK: Cleaning a column

    /// Whether the active column has a heading row to leave alone.
    var cleaningHeader: Bool {
        guard let sheet else { return false }
        return sheet.frozenRows > 0 || isHeader(sheet)
    }

    var columnIssues: [ColumnIssue] {
        guard let sheet else { return [] }
        return ColumnDoctor.diagnose(sheet, column: active.column, header: cleaningHeader)
    }

    var cleaningTitle: String {
        let letter = CellAddress.columnName(active.column)
        let heading = cleaningHeader ? display(CellAddress(row: 0, column: active.column)) : ""
        return heading.isEmpty ? "Column \(letter)" : "Column \(letter) · \(heading)"
    }

    func fix(_ kind: ColumnIssue.Kind) {
        let column = active.column, header = cleaningHeader
        var count = 0
        if kind == .duplicates {
            let index = sheetIndex
            change { count = ColumnDoctor.removeDuplicateRows(&$0, sheet: index, column: column, header: header) }
            notice = "Removed \(count) repeated \(count == 1 ? "row" : "rows"). Undo brings them back."
            return
        }
        changeSheet { count = ColumnDoctor.fix(kind, in: &$0, column: column, header: header) }
        notice = "\(kind.fix): \(count) \(count == 1 ? "cell" : "cells") changed."
    }

    func setCase(_ style: ColumnDoctor.CaseStyle) {
        let column = active.column, header = cleaningHeader
        var count = 0
        changeSheet { count = ColumnDoctor.setCase(style, in: &$0, column: column, header: header) }
        notice = "\(style.title): \(count) \(count == 1 ? "cell" : "cells") changed."
    }

    func split(by separator: String) {
        let column = active.column, header = cleaningHeader, index = sheetIndex
        var made = 0
        change { made = ColumnDoctor.split(&$0, sheet: index, column: column, header: header, separator: separator) }
        notice = made == 0 ? "Nothing in this column has \u{201C}\(separator)\u{201D} in it." : "Split into \(made + 1) columns."
    }

    // MARK: Versions

    private var historyRoot: URL { root.appendingPathComponent(".history", isDirectory: true) }

    private func historyFolder(_ id: UUID) -> URL { historyRoot.appendingPathComponent(id.uuidString, isDirectory: true) }

    /// Keeps a copy every ten minutes of editing, pruned to a day in full and a month of dailies.
    func snapshotIfDue(_ workbook: Workbook, data: Data) {
        let folder = historyFolder(workbook.id)
        let existing = versions(of: workbook.id)
        guard WorkbookVersions.due(last: existing.first?.date, now: Date()) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: folder.appendingPathComponent(WorkbookVersions.fileName(for: Date())), options: .atomic)
        for old in WorkbookVersions.prune(existing, now: Date(), calendar: .current) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(old.file))
        }
    }

    /// Newest first.
    func versions(of id: UUID? = nil) -> [WorkbookVersion] {
        guard let id = id ?? book?.id else { return [] }
        let folder = historyFolder(id)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return files.compactMap { file -> WorkbookVersion? in
            guard let date = WorkbookVersions.date(fromFileName: file) else { return nil }
            let size = (try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(file).path)[.size] as? Int) ?? 0
            return WorkbookVersion(file: file, date: date, cells: size)
        }
        .sorted { $0.date > $1.date }
    }

    /// Puts an earlier version back (as one change, so Undo returns to now).
    func restore(_ version: WorkbookVersion) {
        guard let current = book,
              let data = try? Data(contentsOf: historyFolder(current.id).appendingPathComponent(version.file)),
              var earlier = try? Self.decoder.decode(Workbook.self, from: data) else {
            notice = "That version couldn't be read."
            return
        }
        earlier.id = current.id
        earlier.name = current.name
        change { $0 = earlier }
        showsVersions = false
        notice = "Back to how it was \(version.date.formatted(.relative(presentation: .named))). Undo returns to now."
    }
}
