import Foundation

/// George's grid engine: workbooks of sheets of cells, formulas, number formats and dates the way spreadsheets count them.
/// Foundation only, so the tests run it as it is.

// MARK: Addresses

struct CellAddress: Hashable, Codable, Comparable, Sendable {
    var row: Int
    var column: Int

    init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    /// "B12" or "$B$12".
    init?(_ text: String) {
        let cleaned = text.replacingOccurrences(of: "$", with: "").uppercased()
        let letters = cleaned.prefix { $0.isLetter }
        let digits = cleaned.dropFirst(letters.count)
        guard !letters.isEmpty, letters.count <= 3, !digits.isEmpty, digits.allSatisfy(\.isNumber),
              let column = CellAddress.columnIndex(String(letters)), let row = Int(digits), row >= 1 else { return nil }
        self.row = row - 1
        self.column = column
    }

    var a1: String { CellAddress.columnName(column) + "\(row + 1)" }

    static func columnName(_ index: Int) -> String {
        var index = index
        var name = ""
        repeat {
            name = String(UnicodeScalar(UInt8(65 + index % 26))) + name
            index = index / 26 - 1
        } while index >= 0
        return name
    }

    static func columnIndex(_ name: String) -> Int? {
        var value = 0
        for scalar in name.uppercased().unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90 else { return nil }
            value = value * 26 + Int(scalar.value - 64)
        }
        return value > 0 ? value - 1 : nil
    }

    static func < (a: CellAddress, b: CellAddress) -> Bool {
        (a.row, a.column) < (b.row, b.column)
    }

    func offset(rows: Int, columns: Int) -> CellAddress {
        CellAddress(row: max(0, row + rows), column: max(0, column + columns))
    }
}

struct CellRange: Hashable, Codable, Sendable {
    var start: CellAddress
    var end: CellAddress

    init(_ a: CellAddress, _ b: CellAddress) {
        start = CellAddress(row: min(a.row, b.row), column: min(a.column, b.column))
        end = CellAddress(row: max(a.row, b.row), column: max(a.column, b.column))
    }

    init(_ cell: CellAddress) {
        self.init(cell, cell)
    }

    /// "A1:B3" or "A1".
    init?(_ text: String) {
        let parts = text.split(separator: ":").map(String.init)
        guard let first = parts.first, let a = CellAddress(first) else { return nil }
        if parts.count == 2, let b = CellAddress(parts[1]) { self.init(a, b) } else if parts.count == 1 { self.init(a) } else { return nil }
    }

    var rows: ClosedRange<Int> { start.row...end.row }
    var columns: ClosedRange<Int> { start.column...end.column }
    var rowCount: Int { end.row - start.row + 1 }
    var columnCount: Int { end.column - start.column + 1 }
    var isSingleCell: Bool { start == end }

    func contains(_ cell: CellAddress) -> Bool {
        rows.contains(cell.row) && columns.contains(cell.column)
    }

    /// Row by row.
    var cells: [CellAddress] {
        rows.flatMap { row in columns.map { CellAddress(row: row, column: $0) } }
    }

    var a1: String { isSingleCell ? start.a1 : "\(start.a1):\(end.a1)" }
}

// MARK: Values

enum CellError: String, Codable, Sendable, CaseIterable, Error {
    case div0 = "#DIV/0!"
    case ref = "#REF!"
    case name = "#NAME?"
    case value = "#VALUE!"
    case na = "#N/A"
    case num = "#NUM!"
    case cycle = "#CYCLE!"
}

enum CellValue: Equatable, Hashable, Codable, Sendable {
    case empty
    case number(Double)
    case text(String)
    case bool(Bool)
    case error(CellError)

    var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var isEmpty: Bool { self == .empty }
}

// MARK: Formats

enum NumberFormat: Codable, Equatable, Hashable, Sendable {
    case general
    case number(Int)
    case currency(Int)
    case percent(Int)
    case date
    case shortDate
    case time
    case dateTime
    case text
    /// An Excel format code, from imported files or typed in.
    case custom(String)

    var title: String {
        switch self {
        case .general: return "Automatic"
        case .number(let places): return places == 0 ? "Number" : "Number (\(places) decimals)"
        case .currency(let places): return places == 0 ? "Currency, whole dollars" : "Currency"
        case .percent(let places): return places == 0 ? "Percent" : "Percent (\(places) decimals)"
        case .date: return "Date (1 Nov 2026)"
        case .shortDate: return "Date (01/11/2026)"
        case .time: return "Time"
        case .dateTime: return "Date and time"
        case .text: return "Plain text"
        case .custom(let code): return "Custom (\(code))"
        }
    }

    var isDate: Bool {
        switch self {
        case .date, .shortDate, .time, .dateTime: return true
        case .custom(let code): return ExcelFormat.isDateCode(code)
        default: return false
        }
    }

    /// The Excel code for export.
    var excelCode: String {
        switch self {
        case .general: return "General"
        case .number(let places): return places == 0 ? "#,##0" : "#,##0." + String(repeating: "0", count: places)
        case .currency(let places): return places == 0 ? "\"$\"#,##0" : "\"$\"#,##0." + String(repeating: "0", count: places)
        case .percent(let places): return places == 0 ? "0%" : "0." + String(repeating: "0", count: places) + "%"
        case .date: return "d mmm yyyy"
        case .shortDate: return "dd/mm/yyyy"
        case .time: return "h:mm AM/PM"
        case .dateTime: return "dd/mm/yyyy h:mm"
        case .text: return "@"
        case .custom(let code): return code
        }
    }
}

struct CellFormat: Codable, Equatable, Hashable, Sendable {
    enum Alignment: String, Codable, Sendable, CaseIterable { case left, center, right }

    var number: NumberFormat = .general
    var bold = false
    var italic = false
    var alignment: Alignment?
    /// "#RRGGBB"
    var fill: String?
    var color: String?
    var wrap = false

    var isPlain: Bool { self == CellFormat() }
}

struct GridCell: Codable, Equatable, Sendable {
    /// Exactly what was typed: "12", "12%", "=SUM(A1:A3)", "hello".
    var input: String = ""
    var format: CellFormat?
    var note: String?

    var isEmpty: Bool { input.isEmpty && (format?.isPlain ?? true) && note == nil }
}

struct GridChart: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case column, bar, line, area, pie, scatter

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var id = UUID()
    var kind: Kind
    var range: CellRange
    var title: String
}

struct GridSheet: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var cells: [CellAddress: GridCell] = [:]
    var columnWidths: [Int: Double] = [:]
    var frozenRows = 0
    var color: String?
    var charts: [GridChart] = []
    /// Rows a filter is hiding.
    var hiddenRows: Set<Int> = []

    init(name: String) {
        self.name = name
    }

    subscript(_ address: CellAddress) -> GridCell {
        get { cells[address] ?? GridCell() }
        set { cells[address] = newValue.isEmpty ? nil : newValue }
    }

    func input(_ address: CellAddress) -> String { cells[address]?.input ?? "" }

    /// The smallest range holding every cell with something in it.
    var usedRange: CellRange? {
        let filled = cells.filter { !$0.value.input.isEmpty }.keys
        guard let first = filled.first else { return nil }
        var low = first, high = first
        for address in filled {
            low = CellAddress(row: min(low.row, address.row), column: min(low.column, address.column))
            high = CellAddress(row: max(high.row, address.row), column: max(high.column, address.column))
        }
        return CellRange(CellAddress(row: 0, column: 0), high)
    }

    func width(of column: Int) -> Double { columnWidths[column] ?? 100 }
}

struct Workbook: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var sheets: [GridSheet]
    /// Named ranges: "Revenue" → "Budget!B2:M2".
    var names: [String: String] = [:]
    var modified = Date()

    init(name: String, sheets: [GridSheet] = [GridSheet(name: "Sheet 1")]) {
        self.name = name
        self.sheets = sheets
    }

    func sheetIndex(named name: String) -> Int? {
        sheets.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

// MARK: Typed input

enum GridInput {
    /// What a typed entry means, and the format it suggests: "12%" is 0.12 shown as a percent, "$1,200" is 1200 in dollars,
    /// "1/11/2026" is a date (day first, as in Australia).
    static func interpret(_ input: String) -> (value: CellValue, format: NumberFormat?) {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return (.empty, nil) }
        if text.hasPrefix("'") { return (.text(String(text.dropFirst())), nil) }
        switch text.uppercased() {
        case "TRUE": return (.bool(true), nil)
        case "FALSE": return (.bool(false), nil)
        default: break
        }
        if let error = CellError(rawValue: text.uppercased()) { return (.error(error), nil) }

        var body = text
        var negative = false
        if body.hasPrefix("(") && body.hasSuffix(")") {
            negative = true
            body = String(body.dropFirst().dropLast())
        }
        if body.hasPrefix("-") || body.hasPrefix("−") {
            negative.toggle()
            body = String(body.dropFirst())
        }
        var currency = false
        if body.hasPrefix("$") {
            currency = true
            body = String(body.dropFirst())
        }
        if body.hasPrefix("-") {
            negative.toggle()
            body = String(body.dropFirst())
        }
        var percent = false
        if body.hasSuffix("%") {
            percent = true
            body = String(body.dropLast())
        }
        let grouped = body.contains(",")
        let plain = body.replacingOccurrences(of: ",", with: "")
        if !plain.isEmpty, plain.first?.isNumber == true || plain.first == ".", let number = Double(plain),
           !grouped || isGrouped(body) {
            let places = plain.split(separator: ".").dropFirst().first.map { $0.prefix { $0.isNumber }.count } ?? 0
            let value = negative ? -number : number
            if percent { return (.number(value / 100), .percent(places)) }
            if currency { return (.number(value), .currency(places == 0 ? 0 : 2)) }
            return (.number(value), grouped ? .number(places) : nil)
        }
        if let found = dateOrTime(text) { return (.number(found.0), found.1) }
        return (.text(text), nil)
    }

    /// "1,234" or "12,345,678.5", not "1,2".
    private static func isGrouped(_ text: String) -> Bool {
        let integer = text.split(separator: ".").first.map(String.init) ?? text
        let groups = integer.split(separator: ",", omittingEmptySubsequences: false)
        guard let first = groups.first, (1...3).contains(first.count) else { return false }
        return groups.dropFirst().allSatisfy { $0.count == 3 }
    }

    private static let dateFormats: [(String, NumberFormat)] = [
        ("yyyy-MM-dd", .shortDate), ("d/M/yyyy", .shortDate), ("d/M/yy", .shortDate), ("d-M-yyyy", .shortDate),
        ("d MMM yyyy", .date), ("d MMMM yyyy", .date), ("MMM d, yyyy", .date), ("MMMM d, yyyy", .date),
        ("yyyy-MM-dd HH:mm", .dateTime), ("d/M/yyyy H:mm", .dateTime),
    ]

    private static let timeFormats = ["H:mm", "H:mm:ss", "h:mm a", "h:mma", "h a", "ha"]

    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.isLenient = false
        return formatter
    }()

    static func dateOrTime(_ text: String) -> (Double, NumberFormat)? {
        for (pattern, format) in dateFormats {
            parser.dateFormat = pattern
            if let date = parser.date(from: text) { return (ExcelDate.serial(utc: date), format) }
        }
        for pattern in timeFormats {
            parser.dateFormat = pattern
            if let date = parser.date(from: text.lowercased().replacingOccurrences(of: "am", with: "AM").replacingOccurrences(of: "pm", with: "PM")) {
                let serial = ExcelDate.serial(utc: date)
                return (serial - serial.rounded(.down), .time)
            }
        }
        return nil
    }
}

// MARK: Dates

/// Dates as spreadsheets count them: days since 30 December 1899, with the time as the fraction.
enum ExcelDate {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    static let epoch: Date = calendar.date(from: DateComponents(year: 1899, month: 12, day: 30)) ?? Date(timeIntervalSince1970: -2_209_161_600)

    /// Out-of-range months and days roll over, as DATE does: (2026, 13, 1) is 1 January 2027, day 0 is the month before's last.
    static func serial(year: Int, month: Int, day: Int) -> Double? {
        let firstOfMonth = calendar.date(from: DateComponents(year: year, month: 1, day: 1))
        guard let base = firstOfMonth,
              let monthStart = calendar.date(byAdding: .month, value: month - 1, to: base),
              let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { return nil }
        return serial(utc: date)
    }

    static func serial(utc date: Date) -> Double {
        date.timeIntervalSince(epoch) / 86_400
    }

    /// A moment in local time, as a serial.
    static func serial(_ date: Date, timeZone: TimeZone = .current) -> Double {
        (date.timeIntervalSince(epoch) + Double(timeZone.secondsFromGMT(for: date))) / 86_400
    }

    static func date(_ serial: Double) -> Date {
        epoch.addingTimeInterval(serial * 86_400)
    }

    static func parts(_ serial: Double) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date((serial * 86_400).rounded() / 86_400))
    }
}

// MARK: Showing values

enum GridDisplay {
    static func text(_ value: CellValue, format: NumberFormat) -> String {
        switch value {
        case .empty: return ""
        case .text(let text): return text
        case .bool(let flag): return flag ? "TRUE" : "FALSE"
        case .error(let error): return error.rawValue
        case .number(let number): return text(number, format: format)
        }
    }

    static func text(_ number: Double, format: NumberFormat) -> String {
        guard number.isFinite else { return CellError.num.rawValue }
        switch format {
        case .general, .text: return general(number)
        case .number(let places): return grouped(number, places: places)
        case .currency(let places): return (number < 0 ? "-$" : "$") + grouped(abs(number), places: places)
        case .percent(let places): return fixed(number * 100, places: places) + "%"
        case .date: return dateText(number, "d MMM yyyy")
        case .shortDate: return dateText(number, "dd/MM/yyyy")
        case .time: return dateText(number, "h:mm a")
        case .dateTime: return dateText(number, "dd/MM/yyyy h:mm a")
        case .custom(let code): return ExcelFormat.format(number, code)
        }
    }

    /// Up to ten significant digits, no trailing zeros.
    static func general(_ number: Double) -> String {
        if number == 0 { return "0" }
        if number == number.rounded() && abs(number) < 1e15 { return String(format: "%.0f", number) }
        if abs(number) >= 1e11 || abs(number) < 1e-9 { return String(format: "%.5E", number) }
        var text = String(format: "%.10g", number)
        if text.contains("e") { return text }
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    private static var formatters: [String: NumberFormatter] = [:]
    private static let lock = NSLock()

    static func grouped(_ number: Double, places: Int) -> String {
        lock.lock()
        defer { lock.unlock() }
        let key = "g\(places)"
        let formatter = formatters[key] ?? {
            let made = NumberFormatter()
            made.locale = Locale(identifier: "en_AU")
            made.numberStyle = .decimal
            made.minimumFractionDigits = places
            made.maximumFractionDigits = places
            made.roundingMode = .halfUp
            formatters[key] = made
            return made
        }()
        return formatter.string(from: NSNumber(value: number)) ?? general(number)
    }

    static func fixed(_ number: Double, places: Int) -> String {
        String(format: "%.\(max(0, places))f", number)
    }

    private static var dateFormatters: [String: DateFormatter] = [:]

    static func dateText(_ serial: Double, _ pattern: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        let formatter = dateFormatters[pattern] ?? {
            let made = DateFormatter()
            // Fixed English month names ("Nov", not "Nov."); the patterns themselves put the day first.
            made.locale = Locale(identifier: "en_US_POSIX")
            made.timeZone = TimeZone(identifier: "UTC")
            made.dateFormat = pattern
            made.amSymbol = "am"
            made.pmSymbol = "pm"
            dateFormatters[pattern] = made
            return made
        }()
        return formatter.string(from: ExcelDate.date(serial))
    }
}

/// Enough of Excel's format codes for imported files and TEXT(): numbers, thousands, decimals, percent, currency and
/// literal text, and dates and times.
enum ExcelFormat {
    static func isDateCode(_ code: String) -> Bool {
        let stripped = removeLiterals(code).lowercased()
        guard !stripped.contains("0"), !stripped.contains("#") else { return false }
        return stripped.contains("y") || stripped.contains("d") || stripped.contains("h") || stripped.contains("mmm")
            || (stripped.contains("m") && stripped.contains("s"))
    }

    /// Takes out "quoted text", \x escapes and [colour] or [$-locale] parts.
    private static func removeLiterals(_ code: String) -> String {
        var result = ""
        var quoted = false
        var bracket = false
        var escape = false
        for character in code {
            if escape { escape = false; continue }
            if character == "\\" { escape = true; continue }
            if character == "\"" { quoted.toggle(); continue }
            if quoted { continue }
            if character == "[" { bracket = true; continue }
            if character == "]" { bracket = false; continue }
            if bracket { continue }
            result.append(character)
        }
        return result
    }

    static func format(_ number: Double, _ code: String) -> String {
        let sections = splitSections(code)
        var section = sections.first ?? "General"
        var value = number
        if number < 0, sections.count > 1 {
            section = sections[1]
            value = abs(number)
        } else if number == 0, sections.count > 2 {
            section = sections[2]
        }
        if section.lowercased() == "general" || section.isEmpty { return GridDisplay.general(value) }
        if isDateCode(section) { return dateFormat(value, section) }
        return numberFormat(value, section)
    }

    private static func splitSections(_ code: String) -> [String] {
        var sections: [String] = []
        var current = ""
        var quoted = false
        for character in code {
            if character == "\"" { quoted.toggle() }
            if character == ";" && !quoted {
                sections.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        sections.append(current)
        return sections
    }

    private static func numberFormat(_ number: Double, _ section: String) -> String {
        // Literal text before and after the digits.
        var prefix = ""
        var suffix = ""
        var pattern = ""
        var seenDigits = false
        var quoted = false
        var escape = false
        var skip = false
        var bracket = ""
        var inBracket = false
        for character in section {
            if skip {
                // "_)" leaves a space the width of ")"; "*-" repeats "-" to fill. Neither shows here.
                skip = false
                continue
            }
            if escape {
                if seenDigits { suffix.append(character) } else { prefix.append(character) }
                escape = false
                continue
            }
            if inBracket {
                if character == "]" {
                    inBracket = false
                    // [$$-409] and [$€-x]: a currency symbol.
                    if bracket.hasPrefix("$") {
                        let symbol = bracket.dropFirst().prefix { $0 != "-" }
                        if seenDigits { suffix += symbol } else { prefix += symbol }
                    }
                    bracket = ""
                } else {
                    bracket.append(character)
                }
                continue
            }
            switch character {
            case "\\": escape = true
            case "\"": quoted.toggle()
            case "[": inBracket = true
            default:
                if quoted {
                    if seenDigits { suffix.append(character) } else { prefix.append(character) }
                } else if "0#?.,".contains(character) {
                    seenDigits = true
                    pattern.append(character)
                } else if character == "%" {
                    suffix.append(character)
                } else if character == "_" || character == "*" {
                    skip = true
                } else {
                    if seenDigits { suffix.append(character) } else { prefix.append(character) }
                }
            }
        }
        var value = number
        if suffix.contains("%") { value *= 100 }
        let parts = pattern.split(separator: ".", omittingEmptySubsequences: false)
        let places = parts.count > 1 ? parts[1].filter { $0 == "0" || $0 == "#" || $0 == "?" }.count : 0
        let grouping = parts.first?.contains(",") ?? false
        let body = grouping ? GridDisplay.grouped(abs(value), places: places) : GridDisplay.fixed(abs(value), places: places)
        let sign = value < 0 ? "-" : ""
        return sign + prefix + body + suffix
    }

    private static func dateFormat(_ serial: Double, _ section: String) -> String {
        let source = Array(removeLiterals(section))
        let hasMeridiem = section.uppercased().contains("AM/PM") || section.uppercased().contains("A/P")
        var output = ""
        var index = 0
        var lastWasHour = false
        func run(_ character: Character) -> Int {
            var count = 0
            while index + count < source.count, source[index + count].lowercased() == String(character) { count += 1 }
            return count
        }
        while index < source.count {
            let character = Character(source[index].lowercased())
            switch character {
            case "y":
                let count = run("y")
                output += count <= 2 ? "yy" : "yyyy"
                index += count
            case "m":
                let count = run("m")
                // "m" straight after an hour, or before seconds, is minutes.
                let rest = String(source[(index + count)...]).lowercased()
                let isMinutes = (lastWasHour || rest.trimmingCharacters(in: CharacterSet(charactersIn: ": ")).hasPrefix("s")) && count <= 2
                output += isMinutes ? (count == 1 ? "m" : "mm") : (count == 1 ? "M" : count == 2 ? "MM" : count == 3 ? "MMM" : "MMMM")
                index += count
                lastWasHour = false
                continue
            case "d":
                let count = run("d")
                output += count == 1 ? "d" : count == 2 ? "dd" : count == 3 ? "EEE" : "EEEE"
                index += count
            case "h":
                let count = run("h")
                output += hasMeridiem ? (count == 1 ? "h" : "hh") : (count == 1 ? "H" : "HH")
                index += count
                lastWasHour = true
                continue
            case "s":
                let count = run("s")
                output += count == 1 ? "s" : "ss"
                index += count
            case "a":
                // AM/PM or A/P
                let upper = String(source[index...]).uppercased()
                if upper.hasPrefix("AM/PM") {
                    output += "a"
                    index += 5
                } else if upper.hasPrefix("A/P") {
                    output += "a"
                    index += 3
                } else {
                    output += "'a'"
                    index += 1
                }
            default:
                output += character.isLetter ? "'\(source[index])'" : String(source[index])
                index += 1
            }
            if character != "h" { lastWasHour = lastWasHour && character == ":" }
        }
        return GridDisplay.dateText(serial, output)
    }
}
