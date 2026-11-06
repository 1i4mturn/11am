import Foundation

// George's sheet extras: conditional formatting, data validation (lists, checkboxes, numbers, dates), comments on cells,
// a column doctor that finds and fixes messy data, and version history. Foundation only, tested with the grid.

// MARK: Conditional formatting

/// How a rule paints a cell.
struct RuleStyle: Codable, Equatable, Hashable, Sendable {
    var fill: String?
    var color: String?
    var bold = false
    var italic = false

    static let presets: [(name: String, style: RuleStyle)] = [
        ("Green", RuleStyle(fill: "#DCEFD9", color: "#1F5F2A")),
        ("Red", RuleStyle(fill: "#F7DAD6", color: "#8E2A1E")),
        ("Amber", RuleStyle(fill: "#FBEBC6", color: "#7A5200")),
        ("Grey", RuleStyle(fill: "#E6E6E6", color: "#4A4A4A")),
        ("Ink", RuleStyle(fill: "#1A1A1A", color: "#FFFFFF")),
        ("Bold", RuleStyle(bold: true)),
    ]
}

struct ConditionalRule: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case greaterThan, lessThan, between, equalTo, notEqualTo, containsText, blank, notBlank
        case duplicate, unique, top, bottom, aboveAverage, belowAverage, formula, colorScale, dataBar

        var id: String { rawValue }

        var title: String {
            switch self {
            case .greaterThan: return "Greater than"
            case .lessThan: return "Less than"
            case .between: return "Between"
            case .equalTo: return "Equal to"
            case .notEqualTo: return "Not equal to"
            case .containsText: return "Text contains"
            case .blank: return "Is empty"
            case .notBlank: return "Isn't empty"
            case .duplicate: return "Duplicates"
            case .unique: return "Only once"
            case .top: return "Top"
            case .bottom: return "Bottom"
            case .aboveAverage: return "Above average"
            case .belowAverage: return "Below average"
            case .formula: return "Formula is true"
            case .colorScale: return "Colour scale"
            case .dataBar: return "Data bar"
            }
        }

        /// How many values the rule asks for.
        var values: Int {
            switch self {
            case .between: return 2
            case .greaterThan, .lessThan, .equalTo, .notEqualTo, .containsText, .top, .bottom, .formula: return 1
            default: return 0
            }
        }

        /// Scales and bars paint by value rather than with a style.
        var isGradient: Bool { self == .colorScale || self == .dataBar }
    }

    var id = UUID()
    var range: CellRange
    var kind: Kind
    /// A number, text, "10%" for top and bottom, or a formula like "=$D$1" or "=B2>C2" (written for the range's first cell).
    var value1 = ""
    var value2 = ""
    var style = RuleStyle(fill: "#DCEFD9", color: "#1F5F2A")
    /// Colour scales go from `low` to `high` (through `middle`, if set); a data bar is drawn in `high`.
    var low = "#FFFFFF"
    var middle: String?
    var high = "#6E9E78"

    /// "B2:B40 · Greater than 1000".
    var summary: String {
        var text = "\(range.a1) · \(kind.title)"
        switch kind.values {
        case 2: text += " \(value1) and \(value2)"
        case 1: text += " \(value1)"
        default: break
        }
        return text
    }
}

/// What the rules do to one cell.
struct RuleEffect: Equatable, Sendable {
    var fill: String?
    var color: String?
    var bold = false
    var italic = false
    /// How full a data bar is, 0 to 1, and its colour.
    var bar: Double?
    var barColor: String?
}

enum GridRules {
    /// Every cell a sheet's rules touch, and how. Earlier rules win where two disagree, as in Excel.
    static func effects(sheet index: Int, engine: GridEngine) -> [CellAddress: RuleEffect] {
        guard engine.workbook.sheets.indices.contains(index) else { return [:] }
        let sheet = engine.workbook.sheets[index]
        guard !sheet.rules.isEmpty, let used = sheet.usedRange else { return [:] }
        var effects: [CellAddress: RuleEffect] = [:]
        for rule in sheet.rules {
            guard let range = clip(rule.range, to: used) else { continue }
            let addresses = range.cells
            let values = addresses.map { engine.value(sheet: index, $0) }
            let numbers = values.compactMap(\.number)
            switch rule.kind {
            case .colorScale, .dataBar:
                guard let low = numbers.min(), let high = numbers.max() else { continue }
                for (address, value) in zip(addresses, values) {
                    guard let number = value.number else { continue }
                    var effect = effects[address] ?? RuleEffect()
                    if rule.kind == .colorScale {
                        let t = high == low ? 0.5 : (number - low) / (high - low)
                        if effect.fill == nil { effect.fill = scale(t, low: rule.low, middle: rule.middle, high: rule.high) }
                    } else if effect.bar == nil {
                        let floor = min(0, low)
                        effect.bar = high == floor ? 1 : max(0, min(1, (number - floor) / (high - floor)))
                        effect.barColor = rule.high
                    }
                    effects[address] = effect
                }
            default:
                let context = Context(rule: rule, values: values, numbers: numbers, engine: engine, sheet: index)
                for (offset, address) in addresses.enumerated() where context.matches(values[offset], at: address, origin: rule.range.start) {
                    var effect = effects[address] ?? RuleEffect()
                    if effect.fill == nil { effect.fill = rule.style.fill }
                    if effect.color == nil { effect.color = rule.style.color }
                    effect.bold = effect.bold || rule.style.bold
                    effect.italic = effect.italic || rule.style.italic
                    effects[address] = effect
                }
            }
        }
        return effects
    }

    /// The part of a range inside the used area (a rule on all of column B only looks at rows with data).
    static func clip(_ range: CellRange, to used: CellRange) -> CellRange? {
        let top = max(range.start.row, used.start.row), bottom = min(range.end.row, used.end.row)
        let left = max(range.start.column, used.start.column), right = min(range.end.column, used.end.column)
        guard top <= bottom, left <= right else { return nil }
        return CellRange(CellAddress(row: top, column: left), CellAddress(row: bottom, column: right))
    }

    private struct Context {
        let rule: ConditionalRule
        let values: [CellValue]
        let numbers: [Double]
        let engine: GridEngine
        let sheet: Int
        let first: CellValue
        let second: CellValue
        let counts: [String: Int]
        let threshold: Double?
        let mean: Double?

        init(rule: ConditionalRule, values: [CellValue], numbers: [Double], engine: GridEngine, sheet: Int) {
            self.rule = rule
            self.values = values
            self.numbers = numbers
            self.engine = engine
            self.sheet = sheet
            first = GridRules.operand(rule.value1, engine: engine, sheet: sheet)
            second = GridRules.operand(rule.value2, engine: engine, sheet: sheet)
            var counts: [String: Int] = [:]
            if rule.kind == .duplicate || rule.kind == .unique {
                for value in values { if let key = GridRules.key(value) { counts[key, default: 0] += 1 } }
            }
            self.counts = counts
            mean = numbers.isEmpty ? nil : numbers.reduce(0, +) / Double(numbers.count)
            if rule.kind == .top || rule.kind == .bottom, !numbers.isEmpty {
                let text = rule.value1.trimmingCharacters(in: .whitespaces)
                var count = 10
                if text.hasSuffix("%"), let percent = Double(text.dropLast()) {
                    count = max(1, Int((Double(numbers.count) * percent / 100).rounded(.up)))
                } else if let typed = Int(text) {
                    count = max(1, typed)
                }
                let sorted = rule.kind == .top ? numbers.sorted(by: >) : numbers.sorted()
                threshold = sorted[min(count, sorted.count) - 1]
            } else {
                threshold = nil
            }
        }

        func matches(_ value: CellValue, at address: CellAddress, origin: CellAddress) -> Bool {
            switch rule.kind {
            case .greaterThan: return compare(value, first).map { $0 > 0 } ?? false
            case .lessThan: return compare(value, first).map { $0 < 0 } ?? false
            case .between:
                guard let low = compare(value, first), let high = compare(value, second) else { return false }
                // Either way round: "between 10 and 5" means the same as "between 5 and 10".
                let ordered = GridEngine.compare(first, second) <= 0
                return ordered ? (low >= 0 && high <= 0) : (high >= 0 && low <= 0)
            case .equalTo: return equal(value, first)
            case .notEqualTo: return !value.isEmpty && !equal(value, first)
            case .containsText:
                let needle = GridEngine.text(first).lowercased()
                return !needle.isEmpty && GridEngine.text(value).lowercased().contains(needle)
            case .blank: return GridEngine.text(value).trimmingCharacters(in: .whitespaces).isEmpty
            case .notBlank: return !GridEngine.text(value).trimmingCharacters(in: .whitespaces).isEmpty
            case .duplicate: return GridRules.key(value).map { (counts[$0] ?? 0) > 1 } ?? false
            case .unique: return GridRules.key(value).map { counts[$0] == 1 } ?? false
            case .top: return value.number.map { number in threshold.map { number >= $0 } ?? false } ?? false
            case .bottom: return value.number.map { number in threshold.map { number <= $0 } ?? false } ?? false
            case .aboveAverage: return value.number.map { number in mean.map { number > $0 } ?? false } ?? false
            case .belowAverage: return value.number.map { number in mean.map { number < $0 } ?? false } ?? false
            case .formula:
                var formula = rule.value1.trimmingCharacters(in: .whitespaces)
                guard !formula.isEmpty else { return false }
                if !formula.hasPrefix("=") { formula = "=" + formula }
                let shifted = FormulaRewrite.shift(formula, rows: address.row - origin.row, columns: address.column - origin.column)
                switch engine.evaluate(formula: shifted, sheet: sheet) {
                case .bool(let flag): return flag
                case .number(let number): return number != 0
                default: return false
                }
            case .colorScale, .dataBar: return false
            }
        }

        /// Numbers against numbers; text against text, ignoring case. Nil when they can't be compared.
        private func compare(_ value: CellValue, _ other: CellValue) -> Int? {
            if let a = value.number, let b = other.number { return a < b ? -1 : a > b ? 1 : 0 }
            if case .text(let a) = value, case .text(let b) = other {
                let order = a.localizedCaseInsensitiveCompare(b)
                return order == .orderedAscending ? -1 : order == .orderedDescending ? 1 : 0
            }
            return nil
        }

        private func equal(_ value: CellValue, _ other: CellValue) -> Bool {
            if let a = value.number, let b = other.number { return abs(a - b) < 1e-9 }
            return GridEngine.text(value).caseInsensitiveCompare(GridEngine.text(other)) == .orderedSame && !value.isEmpty
        }
    }

    /// A rule's value: a formula worked out once, a number, or text.
    static func operand(_ text: String, engine: GridEngine, sheet: Int) -> CellValue {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("=") { return engine.evaluate(formula: trimmed, sheet: sheet) }
        let value = GridInput.interpret(trimmed).value
        if case .bool = value { return .text(trimmed) }
        return value
    }

    /// The same value whatever its case: "Done" and "done" are duplicates.
    static func key(_ value: CellValue) -> String? {
        switch value {
        case .empty: return nil
        case .number(let number): return "n\(number)"
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
            return trimmed.isEmpty ? nil : "t" + trimmed
        case .bool(let flag): return flag ? "TRUE" : "FALSE"
        case .error: return nil
        }
    }

    // MARK: Colour

    static func scale(_ t: Double, low: String, middle: String?, high: String) -> String {
        let clamped = max(0, min(1, t))
        if let middle {
            return clamped < 0.5 ? mix(low, middle, clamped * 2) : mix(middle, high, (clamped - 0.5) * 2)
        }
        return mix(low, high, clamped)
    }

    static func mix(_ a: String, _ b: String, _ t: Double) -> String {
        guard let from = rgb(a), let to = rgb(b) else { return t < 0.5 ? a : b }
        let parts = (0..<3).map { Int((Double(from[$0]) + (Double(to[$0]) - Double(from[$0])) * t).rounded()) }
        return String(format: "#%02X%02X%02X", parts[0], parts[1], parts[2])
    }

    static func rgb(_ hex: String) -> [Int]? {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }
        return [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF]
    }
}

// MARK: Data validation

struct DataValidation: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case list, checkbox, wholeNumber, decimal, date, textLength

        var id: String { rawValue }

        var title: String {
            switch self {
            case .list: return "A list to pick from"
            case .checkbox: return "Tick boxes"
            case .wholeNumber: return "Whole numbers"
            case .decimal: return "Numbers"
            case .date: return "Dates"
            case .textLength: return "Text of a length"
            }
        }
    }

    var id = UUID()
    var range: CellRange
    var kind: Kind
    /// The choices for a list, unless `source` names a range to take them from ("Lists!A2:A9").
    var choices: [String] = []
    var source = ""
    var minimum = ""
    var maximum = ""
    /// Refuse anything else, rather than marking it.
    var reject = false
    /// Shown when the cell is selected.
    var help = ""

    var summary: String {
        switch kind {
        case .list: return "\(range.a1) · \(source.isEmpty ? choices.joined(separator: ", ") : "from \(source)")"
        case .checkbox: return "\(range.a1) · tick boxes"
        default:
            let bounds = [minimum.isEmpty ? nil : "from \(minimum)", maximum.isEmpty ? nil : "to \(maximum)"].compactMap { $0 }.joined(separator: " ")
            return "\(range.a1) · \(kind.title.lowercased())\(bounds.isEmpty ? "" : " " + bounds)"
        }
    }
}

enum GridValidation {
    enum Outcome: Equatable {
        case ok
        case invalid(String)
    }

    /// The rule covering a cell (the last one added wins).
    static func rule(at address: CellAddress, in sheet: GridSheet) -> DataValidation? {
        sheet.validations.last { $0.range.contains(address) }
    }

    /// A list's choices, from the rule or the range it names.
    static func choices(_ rule: DataValidation, engine: GridEngine, sheet: Int) -> [String] {
        let source = rule.source.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "=", with: "")
        guard !source.isEmpty else { return rule.choices.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        var sheetIndex = sheet
        var reference = source
        if let bang = source.lastIndex(of: "!") {
            let name = source[..<bang].trimmingCharacters(in: CharacterSet(charactersIn: "'"))
            guard let found = engine.workbook.sheetIndex(named: name) else { return [] }
            sheetIndex = found
            reference = String(source[source.index(after: bang)...])
        }
        guard let range = CellRange(reference.replacingOccurrences(of: "$", with: "")) else { return [] }
        var seen = Set<String>()
        return range.cells.prefix(500).compactMap { address in
            let text = engine.display(sheet: sheetIndex, address).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, seen.insert(text.lowercased()).inserted else { return nil }
            return text
        }
    }

    /// Whether what's typed fits the rule. Empty is always fine, and formulas are left alone.
    static func check(_ input: String, against rule: DataValidation, engine: GridEngine, sheet: Int) -> Outcome {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !text.hasPrefix("=") else { return .ok }
        switch rule.kind {
        case .list:
            let options = choices(rule, engine: engine, sheet: sheet)
            if options.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) { return .ok }
            return .invalid("Pick one of: \(options.prefix(8).joined(separator: ", "))\(options.count > 8 ? "…" : "").")
        case .checkbox:
            return ["TRUE", "FALSE"].contains(text.uppercased()) ? .ok : .invalid("It's a tick box: TRUE or FALSE.")
        case .wholeNumber, .decimal:
            guard let number = GridInput.interpret(text).value.number else { return .invalid("Type a number\(bounds(rule)).") }
            if rule.kind == .wholeNumber && number != number.rounded() { return .invalid("Type a whole number\(bounds(rule)).") }
            return inside(number, rule) ? .ok : .invalid("Type a \(rule.kind == .wholeNumber ? "whole " : "")number\(bounds(rule)).")
        case .date:
            let typed = GridInput.interpret(text)
            guard let serial = typed.value.number, typed.format?.isDate == true else { return .invalid("Type a date\(bounds(rule)).") }
            return inside(serial, rule) ? .ok : .invalid("Type a date\(bounds(rule)).")
        case .textLength:
            return inside(Double(text.count), rule) ? .ok : .invalid("Keep it to\(bounds(rule, unit: " characters")).")
        }
    }

    private static func limit(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : GridInput.interpret(trimmed).value.number
    }

    private static func inside(_ number: Double, _ rule: DataValidation) -> Bool {
        if let low = limit(rule.minimum), number < low { return false }
        if let high = limit(rule.maximum), number > high { return false }
        return true
    }

    private static func bounds(_ rule: DataValidation, unit: String = "") -> String {
        let low = rule.minimum.trimmingCharacters(in: .whitespaces), high = rule.maximum.trimmingCharacters(in: .whitespaces)
        switch (low.isEmpty, high.isEmpty) {
        case (false, false): return " from \(low) to \(high)\(unit)"
        case (false, true): return " of at least \(low)\(unit)"
        case (true, false): return unit.isEmpty ? " up to \(high)" : " \(high)\(unit) or fewer"
        case (true, true): return unit.isEmpty ? "" : " a sensible length"
        }
    }

    /// Cells already holding something that breaks their rule, to mark.
    static func invalidCells(sheet index: Int, engine: GridEngine) -> Set<CellAddress> {
        guard engine.workbook.sheets.indices.contains(index) else { return [] }
        let sheet = engine.workbook.sheets[index]
        guard !sheet.validations.isEmpty, let used = sheet.usedRange else { return [] }
        var invalid = Set<CellAddress>()
        for rule in sheet.validations {
            guard let range = GridRules.clip(rule.range, to: used) else { continue }
            for address in range.cells where GridValidation.rule(at: address, in: sheet)?.id == rule.id {
                if case .invalid = check(sheet.input(address), against: rule, engine: engine, sheet: index) { invalid.insert(address) }
            }
        }
        return invalid
    }

    /// Whether a cell shows a tick box, and whether it's ticked.
    static func checkbox(at address: CellAddress, in sheet: GridSheet, engine: GridEngine, index: Int) -> Bool? {
        guard rule(at: address, in: sheet)?.kind == .checkbox else { return nil }
        if case .bool(true) = engine.value(sheet: index, address) { return true }
        return false
    }
}

// MARK: Comments

struct GridComment: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var address: CellAddress
    /// "You" or "George".
    var author: String
    var text: String
    var date: Date
    var resolved = false
}

enum GridComments {
    /// Open threads by cell, oldest comment first.
    static func threads(_ sheet: GridSheet) -> [(address: CellAddress, comments: [GridComment])] {
        let open = sheet.comments.filter { !$0.resolved }
        let grouped = Dictionary(grouping: open, by: \.address)
        return grouped.map { (address: $0.key, comments: $0.value.sorted { $0.date < $1.date }) }
            .sorted { $0.address < $1.address }
    }

    /// Asks George when a comment says @George.
    static func mentionsGeorge(_ text: String) -> Bool {
        text.range(of: "@george", options: .caseInsensitive) != nil
    }
}

// MARK: Cleaning a column

struct ColumnIssue: Equatable, Identifiable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case extraSpaces, numbersAsText, datesAsText, mixedCase, duplicates, blanks

        var fix: String {
            switch self {
            case .extraSpaces: return "Trim the spaces"
            case .numbersAsText: return "Make them numbers"
            case .datesAsText: return "Make them dates"
            case .mixedCase: return "Use one spelling"
            case .duplicates: return "Remove the repeats"
            case .blanks: return "Fill from above"
            }
        }
    }

    var kind: Kind
    /// The rows affected (0-based).
    var rows: [Int]
    var title: String
    var example: String
    var id: String { kind.rawValue }
}

enum ColumnDoctor {
    enum CaseStyle: String, CaseIterable, Identifiable, Sendable {
        case title, upper, lower, sentence
        var id: String { rawValue }
        var title: String {
            switch self {
            case .title: return "Title Case"
            case .upper: return "UPPER CASE"
            case .lower: return "lower case"
            case .sentence: return "Sentence case"
            }
        }
    }

    /// The data rows of a column: from below the header to the last row with anything in it.
    static func dataRows(_ sheet: GridSheet, column: Int, header: Bool) -> ClosedRange<Int>? {
        let filled = sheet.cells.filter { $0.key.column == column && !$0.value.input.isEmpty }.map(\.key.row)
        guard let last = filled.max() else { return nil }
        let first = header ? 1 : 0
        return first <= last ? first...last : nil
    }

    /// What's wrong with a column, most useful first.
    static func diagnose(_ sheet: GridSheet, column: Int, header: Bool) -> [ColumnIssue] {
        guard let rows = dataRows(sheet, column: column, header: header) else { return [] }
        var spaces: [Int] = [], numbers: [Int] = [], dates: [Int] = [], blanks: [Int] = []
        var spellings: [String: [String: [Int]]] = [:]
        var seen: [String: Int] = [:]
        var repeats: [Int] = []
        var examples: [ColumnIssue.Kind: String] = [:]
        for row in rows {
            let input = sheet.input(CellAddress(row: row, column: column))
            if input.isEmpty { blanks.append(row); continue }
            if input.hasPrefix("=") { continue }
            if tidy(input) != input {
                spaces.append(row)
                examples[.extraSpaces] = examples[.extraSpaces] ?? "\u{201C}\(input)\u{201D}"
            }
            let clean = tidy(input)
            if case .text = GridInput.interpret(clean).value {
                if number(in: clean) != nil {
                    numbers.append(row)
                    examples[.numbersAsText] = examples[.numbersAsText] ?? clean
                } else if date(in: clean) != nil {
                    dates.append(row)
                    examples[.datesAsText] = examples[.datesAsText] ?? clean
                } else {
                    spellings[clean.lowercased(), default: [:]][clean, default: []].append(row)
                }
            }
            let key = clean.lowercased()
            if seen[key] != nil {
                repeats.append(row)
                examples[.duplicates] = examples[.duplicates] ?? clean
            } else {
                seen[key] = row
            }
        }
        var mixed: [Int] = []
        for (_, variants) in spellings where variants.count > 1 {
            let common = variants.max { $0.value.count != $1.value.count ? $0.value.count < $1.value.count : $0.key > $1.key }?.key
            for (spelling, rows) in variants where spelling != common { mixed += rows }
            if examples[.mixedCase] == nil { examples[.mixedCase] = variants.keys.sorted().joined(separator: " / ") }
        }
        // Blanks only count between filled rows, and only when most of the column is filled.
        let filledCount = rows.count - blanks.count
        if filledCount < rows.count / 2 { blanks = [] }
        var issues: [ColumnIssue] = []
        func add(_ kind: ColumnIssue.Kind, _ rows: [Int], _ title: String) {
            guard !rows.isEmpty else { return }
            issues.append(ColumnIssue(kind: kind, rows: rows.sorted(), title: title, example: examples[kind] ?? ""))
        }
        add(.numbersAsText, numbers, "\(numbers.count) \(numbers.count == 1 ? "number is" : "numbers are") stored as text")
        add(.datesAsText, dates, "\(dates.count) \(dates.count == 1 ? "date is" : "dates are") text, not dates")
        add(.extraSpaces, spaces, "\(spaces.count) \(spaces.count == 1 ? "cell has" : "cells have") extra spaces")
        add(.mixedCase, mixed, "\(mixed.count) \(mixed.count == 1 ? "value is" : "values are") spelt differently from the rest")
        add(.duplicates, repeats, "\(repeats.count) \(repeats.count == 1 ? "row repeats" : "rows repeat") a value above")
        add(.blanks, blanks, "\(blanks.count) empty \(blanks.count == 1 ? "cell" : "cells")")
        return issues
    }

    /// Fixes one kind of issue in place (all but duplicates, which remove rows; see `removeDuplicateRows`). Returns how many cells changed.
    @discardableResult
    static func fix(_ kind: ColumnIssue.Kind, in sheet: inout GridSheet, column: Int, header: Bool) -> Int {
        guard let rows = dataRows(sheet, column: column, header: header) else { return 0 }
        var changed = 0
        switch kind {
        case .extraSpaces:
            for row in rows {
                let address = CellAddress(row: row, column: column)
                let input = sheet.input(address)
                guard !input.hasPrefix("="), tidy(input) != input else { continue }
                sheet[address].input = tidy(input)
                changed += 1
            }
        case .numbersAsText:
            for row in rows {
                let address = CellAddress(row: row, column: column)
                let input = tidy(sheet.input(address))
                guard !input.hasPrefix("="), case .text = GridInput.interpret(input).value, let found = number(in: input) else { continue }
                var cell = sheet[address]
                cell.input = found.percent ? GridDisplay.general(found.value * 100) + "%" : GridDisplay.general(found.value)
                if found.currency {
                    var format = cell.format ?? CellFormat()
                    format.number = .currency(2)
                    cell.format = format
                }
                sheet[address] = cell
                changed += 1
            }
        case .datesAsText:
            for row in rows {
                let address = CellAddress(row: row, column: column)
                let input = tidy(sheet.input(address))
                guard !input.hasPrefix("="), case .text = GridInput.interpret(input).value, let found = date(in: input) else { continue }
                var cell = sheet[address]
                cell.input = found
                var format = cell.format ?? CellFormat()
                if !format.number.isDate { format.number = .date }
                cell.format = format
                sheet[address] = cell
                changed += 1
            }
        case .mixedCase:
            var variants: [String: [String: Int]] = [:]
            for row in rows {
                let input = tidy(sheet.input(CellAddress(row: row, column: column)))
                guard !input.isEmpty, !input.hasPrefix("="), case .text = GridInput.interpret(input).value else { continue }
                variants[input.lowercased(), default: [:]][input, default: 0] += 1
            }
            for row in rows {
                let address = CellAddress(row: row, column: column)
                let input = tidy(sheet.input(address))
                guard let group = variants[input.lowercased()], group.count > 1,
                      let common = group.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key })?.key, common != input else { continue }
                sheet[address].input = common
                changed += 1
            }
        case .blanks:
            var above = ""
            for row in rows {
                let address = CellAddress(row: row, column: column)
                let input = sheet.input(address)
                if input.isEmpty {
                    guard !above.isEmpty else { continue }
                    var cell = sheet[address]
                    cell.input = above
                    sheet[address] = cell
                    changed += 1
                } else if !input.hasPrefix("=") {
                    above = input
                }
            }
        case .duplicates:
            break
        }
        return changed
    }

    /// Deletes every row whose value in this column appeared in a row above. Returns how many went.
    @discardableResult
    static func removeDuplicateRows(_ workbook: inout Workbook, sheet index: Int, column: Int, header: Bool) -> Int {
        guard workbook.sheets.indices.contains(index) else { return 0 }
        let issues = diagnose(workbook.sheets[index], column: column, header: header)
        guard let repeats = issues.first(where: { $0.kind == .duplicates })?.rows else { return 0 }
        for row in repeats.sorted(by: >) {
            GridEdit.insert(&workbook, sheet: index, rows: true, at: row, count: -1)
        }
        return repeats.count
    }

    /// Changes the capitals of every text value in the column.
    @discardableResult
    static func setCase(_ style: CaseStyle, in sheet: inout GridSheet, column: Int, header: Bool) -> Int {
        guard let rows = dataRows(sheet, column: column, header: header) else { return 0 }
        var changed = 0
        for row in rows {
            let address = CellAddress(row: row, column: column)
            let input = sheet.input(address)
            guard !input.isEmpty, !input.hasPrefix("="), case .text = GridInput.interpret(input).value else { continue }
            let updated = recase(input, style)
            if updated != input {
                sheet[address].input = updated
                changed += 1
            }
        }
        return changed
    }

    static func recase(_ text: String, _ style: CaseStyle) -> String {
        switch style {
        case .upper: return text.uppercased()
        case .lower: return text.lowercased()
        case .title:
            return text.lowercased().split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
                guard let first = word.first else { return String(word) }
                return String(first).uppercased() + word.dropFirst()
            }.joined(separator: " ")
        case .sentence:
            let lower = text.lowercased()
            guard let first = lower.first else { return lower }
            return String(first).uppercased() + lower.dropFirst()
        }
    }

    /// Splits a column into several at a separator ("Tom Baker" → "Tom" | "Baker"), into new columns to its right.
    /// Returns how many columns it made.
    @discardableResult
    static func split(_ workbook: inout Workbook, sheet index: Int, column: Int, header: Bool, separator: String) -> Int {
        guard workbook.sheets.indices.contains(index), !separator.isEmpty,
              let rows = dataRows(workbook.sheets[index], column: column, header: header) else { return 0 }
        let sheet = workbook.sheets[index]
        var parts: [Int: [String]] = [:]
        var widest = 1
        for row in rows {
            let input = sheet.input(CellAddress(row: row, column: column))
            guard !input.hasPrefix("=") else { continue }
            let pieces = separator == " "
                ? input.split(separator: " ").map(String.init)
                : input.components(separatedBy: separator).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pieces.count > 1 else { continue }
            let limited = Array(pieces.prefix(6))
            parts[row] = limited
            widest = max(widest, limited.count)
        }
        guard widest > 1 else { return 0 }
        GridEdit.insert(&workbook, sheet: index, rows: false, at: column + 1, count: widest - 1)
        for (row, pieces) in parts {
            for (offset, piece) in pieces.enumerated() {
                var cell = workbook.sheets[index][CellAddress(row: row, column: column + offset)]
                cell.input = piece
                workbook.sheets[index][CellAddress(row: row, column: column + offset)] = cell
            }
        }
        if header {
            let title = sheet.input(CellAddress(row: 0, column: column))
            for offset in 1..<widest {
                var cell = workbook.sheets[index][CellAddress(row: 0, column: column + offset)]
                cell.input = title.isEmpty ? "Part \(offset + 1)" : "\(title) \(offset + 1)"
                workbook.sheets[index][CellAddress(row: 0, column: column + offset)] = cell
            }
        }
        return widest - 1
    }

    /// Spaces trimmed and runs of spaces (and tabs and non-breaking spaces) made single.
    static func tidy(_ text: String) -> String {
        let unified = text.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\t", with: " ")
        return unified.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    /// A number written in a way the grid reads as text: "AUD 1,200", "1 200", "1.2k", "45-", "US$20", "12 %".
    static func number(in text: String) -> (value: Double, currency: Bool, percent: Bool)? {
        var body = text.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty, body.count < 40 else { return nil }
        if body.hasPrefix("'") { body.removeFirst() }
        var currency = false, percent = false, negative = false
        for code in ["AUD", "USD", "NZD", "EUR", "GBP", "A$", "US$", "NZ$", "AU$", "$", "€", "£"] {
            if body.uppercased().hasPrefix(code) { body = String(body.dropFirst(code.count)); currency = true; break }
            if body.uppercased().hasSuffix(code) { body = String(body.dropLast(code.count)); currency = true; break }
        }
        body = body.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("(") && body.hasSuffix(")") { negative = true; body = String(body.dropFirst().dropLast()) }
        if body.hasSuffix("-") { negative = true; body.removeLast() }
        if body.hasPrefix("-") || body.hasPrefix("−") { negative.toggle(); body.removeFirst() }
        if body.uppercased().hasSuffix(" CR") { body = String(body.dropLast(3)) }
        if body.uppercased().hasSuffix(" DR") { negative.toggle(); body = String(body.dropLast(3)) }
        body = body.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("$") { currency = true; body.removeFirst() }
        if body.hasSuffix("%") { percent = true; body = String(body.dropLast()).trimmingCharacters(in: .whitespaces) }
        var multiplier = 1.0
        if let last = body.last, "kKmM".contains(last), body.count > 1 {
            multiplier = "kK".contains(last) ? 1_000 : 1_000_000
            body.removeLast()
        }
        let digits = body.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")
        guard !digits.isEmpty, digits.allSatisfy({ $0.isNumber || $0 == "." }), digits.filter({ $0 == "." }).count <= 1,
              let value = Double(digits) else { return nil }
        // Spaces only as thousands separators: "1 200", not "12 34".
        if body.contains(" ") {
            let groups = body.split(separator: " ")
            guard groups.dropFirst().allSatisfy({ $0.count == 3 || ($0.contains(".") && $0.split(separator: ".").first?.count == 3) }) else { return nil }
        }
        let result = (negative ? -value : value) * multiplier
        return (percent ? result / 100 : result, currency, percent)
    }

    private static let datePatterns = ["d MMM yyyy", "d MMMM yyyy", "d MMM yy", "d MMMM yy", "MMM d yyyy", "MMMM d yyyy", "EEEE d MMMM yyyy", "EEEE, d MMMM yyyy", "EEE d MMM yyyy",
                                       "d-MMM-yyyy", "d-MMM-yy", "d.M.yyyy", "d.M.yy", "yyyy/M/d", "yyyyMMdd", "MMM yyyy", "MMMM yyyy"]

    private static let dateParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.isLenient = false
        return formatter
    }()

    /// A date written as text, as "yyyy-MM-dd" (which the grid reads as a date): "3rd Nov 2026", "Tuesday 3 November 2026", "03.11.2026".
    static func date(in text: String) -> String? {
        var cleaned = text.trimmingCharacters(in: .whitespaces)
        cleaned = cleaned.replacingOccurrences(of: #"(\d)(st|nd|rd|th)\b"#, with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "Sept ", with: "Sep ")
        guard cleaned.count >= 6, cleaned.count <= 40, cleaned.contains(where: \.isNumber) else { return nil }
        let output = DateFormatter()
        output.locale = Locale(identifier: "en_US_POSIX")
        output.timeZone = TimeZone(identifier: "UTC")
        output.dateFormat = "yyyy-MM-dd"
        for pattern in datePatterns {
            dateParser.dateFormat = pattern
            if let date = dateParser.date(from: cleaned) ?? dateParser.date(from: cleaned.replacingOccurrences(of: ",", with: "")) {
                let year = ExcelDate.calendar.component(.year, from: date)
                guard (1900...2200).contains(year) else { continue }
                return output.string(from: date)
            }
        }
        return nil
    }
}

// MARK: Version history

struct WorkbookVersion: Codable, Equatable, Identifiable, Sendable {
    var id: String { file }
    /// The snapshot's file name: "2026-11-05T09-14-03Z.json".
    var file: String
    var date: Date
    var cells: Int
}

enum WorkbookVersions {
    /// Saves a snapshot when the last one is at least this old.
    static let spacing: TimeInterval = 10 * 60

    static func due(last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= spacing
    }

    /// Which snapshots to delete: keep the last 24 hours in full, then one a day for 30 days, then nothing.
    static func prune(_ versions: [WorkbookVersion], now: Date, calendar: Calendar) -> [WorkbookVersion] {
        var keepDays = Set<DateComponents>()
        var remove: [WorkbookVersion] = []
        for version in versions.sorted(by: { $0.date > $1.date }) {
            let age = now.timeIntervalSince(version.date)
            if age <= 86_400 { continue }
            if age > 30 * 86_400 { remove.append(version); continue }
            let day = calendar.dateComponents([.year, .month, .day], from: version.date)
            if keepDays.contains(day) { remove.append(version) } else { keepDays.insert(day) }
        }
        return remove
    }

    static func fileName(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "-") + ".json"
    }

    static func date(fromFileName name: String) -> Date? {
        guard name.hasSuffix(".json") else { return nil }
        var stem = String(name.dropLast(5))
        // Put the time's colons back: 2026-11-05T09-14-03Z → 2026-11-05T09:14:03Z.
        if let t = stem.firstIndex(of: "T") {
            let time = stem[stem.index(after: t)...].replacingOccurrences(of: "-", with: ":")
            stem = String(stem[...t]) + time
        }
        return ISO8601DateFormatter().date(from: stem)
    }
}
