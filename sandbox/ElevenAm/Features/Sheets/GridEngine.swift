import Foundation

/// A rectangle of values, from a range or array maths.
struct GridArea: Equatable, Sendable {
    var rows: Int
    var columns: Int
    var values: [CellValue]

    subscript(row: Int, column: Int) -> CellValue {
        row < rows && column < columns ? values[row * columns + column] : .empty
    }

    var isVector: Bool { rows == 1 || columns == 1 }

    static func single(_ value: CellValue) -> GridArea { GridArea(rows: 1, columns: 1, values: [value]) }
}

enum GridOperand: Equatable, Sendable {
    case value(CellValue)
    case area(GridArea)

    var scalar: CellValue {
        switch self {
        case .value(let value): return value
        case .area(let area): return area.values.first ?? .error(.value)
        }
    }

    var area: GridArea {
        switch self {
        case .value(let value): return .single(value)
        case .area(let area): return area
        }
    }
}

/// Works out every cell's value, lazily and once per change, catching circular references.
final class GridEngine {
    let workbook: Workbook
    var now = Date()
    private var cache: [Key: CellValue] = [:]
    private var visiting: Set<Key> = []
    private var expressions: [String: FormulaExpr] = [:]
    private var inferred: [Key: NumberFormat] = [:]

    struct Key: Hashable {
        let sheet: Int
        let address: CellAddress
    }

    init(_ workbook: Workbook) {
        self.workbook = workbook
    }

    // MARK: Cells

    func value(sheet: Int, _ address: CellAddress) -> CellValue {
        let key = Key(sheet: sheet, address: address)
        if let cached = cache[key] { return cached }
        guard workbook.sheets.indices.contains(sheet) else { return .error(.ref) }
        let input = workbook.sheets[sheet].input(address)
        let result: CellValue
        if input.hasPrefix("=") && input.count > 1 {
            if visiting.contains(key) { return .error(.cycle) }
            visiting.insert(key)
            result = evaluate(expression(input), sheet: sheet).scalar
            visiting.remove(key)
        } else if workbook.sheets[sheet][address].format?.number == .text {
            result = input.isEmpty ? .empty : .text(input)
        } else {
            result = GridInput.interpret(input).value
        }
        cache[key] = result
        return result
    }

    /// A formula typed somewhere (the formula bar, George), worked out as if it were in `sheet`.
    func evaluate(formula: String, sheet: Int) -> CellValue {
        evaluate(expression(formula.hasPrefix("=") ? formula : "=" + formula), sheet: sheet).scalar
    }

    func expression(_ formula: String) -> FormulaExpr {
        if let parsed = expressions[formula] { return parsed }
        let parsed = FormulaParser.parse(formula)
        expressions[formula] = parsed
        return parsed
    }

    /// The format a cell shows in: its own, or what its input or formula suggests ($ from the cells it adds up, a date from DATE()).
    func format(sheet: Int, _ address: CellAddress) -> NumberFormat {
        guard workbook.sheets.indices.contains(sheet) else { return .general }
        let cell = workbook.sheets[sheet][address]
        if let format = cell.format?.number, format != .general { return format }
        let key = Key(sheet: sheet, address: address)
        if let known = inferred[key] { return known }
        var result = NumberFormat.general
        if cell.input.hasPrefix("=") {
            if !visiting.contains(key) {
                visiting.insert(key)
                result = inferFormat(expression(cell.input), sheet: sheet)
                visiting.remove(key)
            }
        } else {
            result = GridInput.interpret(cell.input).format ?? .general
        }
        inferred[key] = result
        return result
    }

    func display(sheet: Int, _ address: CellAddress) -> String {
        GridDisplay.text(value(sheet: sheet, address), format: format(sheet: sheet, address))
    }

    private func inferFormat(_ expression: FormulaExpr, sheet: Int) -> NumberFormat {
        switch expression {
        case .call(let name, let arguments):
            switch name {
            case "DATE", "TODAY", "EOMONTH", "EDATE", "WORKDAY", "DATEVALUE": return .shortDate
            case "NOW": return .dateTime
            case "TIME": return .time
            case "COUNT", "COUNTA", "COUNTBLANK", "COUNTIF", "COUNTIFS", "ROWS", "COLUMNS", "ROW", "COLUMN", "LEN", "MATCH", "XMATCH",
                 "YEAR", "MONTH", "DAY", "WEEKDAY", "HOUR", "MINUTE", "SECOND", "DAYS", "DATEDIF", "NETWORKDAYS", "FIND", "SEARCH", "CODE":
                return .general
            case "PMT", "PV", "FV", "NPV": return .currency(2)
            case "IRR": return .percent(1)
            case "SUMIF", "AVERAGEIF":
                if arguments.count >= 3 { return inferFormat(arguments[2], sheet: sheet) }
                return arguments.first.map { inferFormat($0, sheet: sheet) } ?? .general
            default:
                for argument in arguments {
                    let format = inferFormat(argument, sheet: sheet)
                    if format != .general { return format }
                }
                return .general
            }
        case .reference(let name, let reference):
            guard let index = sheetIndex(name, current: sheet) else { return .general }
            return format(sheet: index, reference.address)
        case .range(let name, let start, let end):
            guard let index = sheetIndex(name, current: sheet) else { return .general }
            // The most precise format among the cells it covers: $100 and $75.50 add up to dollars and cents.
            var best = NumberFormat.general
            for address in CellRange(start.address, end.address).cells.prefix(200) {
                let candidate = format(sheet: index, address)
                switch (best, candidate) {
                case (.general, _): best = candidate
                case (.currency(let a), .currency(let b)) where b > a: best = candidate
                case (.number(let a), .number(let b)) where b > a: best = candidate
                case (.percent(let a), .percent(let b)) where b > a: best = candidate
                default: break
                }
            }
            return best
        case .binary(let op, let left, let right):
            if ["=", "<>", "<", ">", "<=", ">=", "&"].contains(op) { return .general }
            let leftFormat = inferFormat(left, sheet: sheet)
            if op == "/" && leftFormat.isDate { return .general }
            return leftFormat != .general ? leftFormat : (op == "+" || op == "-" ? inferFormat(right, sheet: sheet) : .general)
        case .unary(_, let inner):
            return inferFormat(inner, sheet: sheet)
        default:
            return .general
        }
    }

    // MARK: Evaluating

    private func sheetIndex(_ name: String?, current: Int) -> Int? {
        guard let name else { return current }
        return workbook.sheetIndex(named: name)
    }

    func area(sheet: Int, _ range: CellRange) -> GridArea {
        var values: [CellValue] = []
        values.reserveCapacity(range.rowCount * range.columnCount)
        for row in range.rows {
            for column in range.columns { values.append(value(sheet: sheet, CellAddress(row: row, column: column))) }
        }
        return GridArea(rows: range.rowCount, columns: range.columnCount, values: values)
    }

    func evaluate(_ expression: FormulaExpr, sheet: Int) -> GridOperand {
        switch expression {
        case .number(let value): return .value(.number(value))
        case .text(let value): return .value(.text(value))
        case .bool(let value): return .value(.bool(value))
        case .error(let error): return .value(.error(error))
        case .reference(let name, let reference):
            guard let index = sheetIndex(name, current: sheet) else { return .value(.error(.ref)) }
            return .value(value(sheet: index, reference.address))
        case .range(let name, let start, let end):
            guard let index = sheetIndex(name, current: sheet) else { return .value(.error(.ref)) }
            let range = CellRange(start.address, end.address)
            guard range.rowCount * range.columnCount <= 2_000_000 else { return .value(.error(.num)) }
            return .area(area(sheet: index, range))
        case .columns(let name, let first, let last):
            guard let index = sheetIndex(name, current: sheet) else { return .value(.error(.ref)) }
            let lastRow = workbook.sheets[index].usedRange?.end.row ?? 0
            return .area(area(sheet: index, CellRange(CellAddress(row: 0, column: first), CellAddress(row: lastRow, column: last))))
        case .name(let name):
            guard let target = workbook.names.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame })?.value else {
                return .value(.error(.name))
            }
            return evaluate(self.expression("=" + target), sheet: sheet)
        case .unary(let op, let inner):
            return map(evaluate(inner, sheet: sheet)) { value in
                guard case .number(let number) = Self.number(value) else { return Self.number(value) }
                return .number(op == "-" ? -number : number)
            }
        case .percent(let inner):
            return map(evaluate(inner, sheet: sheet)) { value in
                guard case .number(let number) = Self.number(value) else { return Self.number(value) }
                return .number(number / 100)
            }
        case .binary(let op, let left, let right):
            return combine(evaluate(left, sheet: sheet), evaluate(right, sheet: sheet)) { Self.binary(op, $0, $1) }
        case .call(let name, let arguments):
            return GridFunctions.call(name, arguments, engine: self, sheet: sheet)
        }
    }

    func map(_ operand: GridOperand, _ transform: (CellValue) -> CellValue) -> GridOperand {
        switch operand {
        case .value(let value): return .value(transform(value))
        case .area(let area): return .area(GridArea(rows: area.rows, columns: area.columns, values: area.values.map(transform)))
        }
    }

    /// Element by element when either side is a range (so SUMPRODUCT((A1:A9>5)*B1:B9) works); single values stretch.
    func combine(_ left: GridOperand, _ right: GridOperand, _ operation: (CellValue, CellValue) -> CellValue) -> GridOperand {
        switch (left, right) {
        case (.value(let a), .value(let b)):
            return .value(operation(a, b))
        default:
            let a = left.area, b = right.area
            let rows = max(a.rows, b.rows), columns = max(a.columns, b.columns)
            var values: [CellValue] = []
            values.reserveCapacity(rows * columns)
            for row in 0..<rows {
                for column in 0..<columns {
                    let x = a.rows == 1 && a.columns == 1 ? a[0, 0] : (row < a.rows && column < a.columns ? a[row, column] : .error(.na))
                    let y = b.rows == 1 && b.columns == 1 ? b[0, 0] : (row < b.rows && column < b.columns ? b[row, column] : .error(.na))
                    values.append(operation(x, y))
                }
            }
            return .area(GridArea(rows: rows, columns: columns, values: values))
        }
    }

    // MARK: Coercion

    /// As a number: empty is 0, TRUE is 1, numeric text counts, other text is #VALUE!.
    static func number(_ value: CellValue) -> CellValue {
        switch value {
        case .number: return value
        case .empty: return .number(0)
        case .bool(let flag): return .number(flag ? 1 : 0)
        case .text(let text):
            if text.isEmpty { return .number(0) }
            if case .number(let parsed) = GridInput.interpret(text).value { return .number(parsed) }
            return .error(.value)
        case .error: return value
        }
    }

    static func double(_ value: CellValue) -> Double? {
        if case .number(let number) = number(value) { return number }
        return nil
    }

    static func text(_ value: CellValue) -> String {
        switch value {
        case .empty: return ""
        case .number(let number): return GridDisplay.general(number)
        case .text(let text): return text
        case .bool(let flag): return flag ? "TRUE" : "FALSE"
        case .error(let error): return error.rawValue
        }
    }

    static func bool(_ value: CellValue) -> CellValue {
        switch value {
        case .bool: return value
        case .number(let number): return .bool(number != 0)
        case .empty: return .bool(false)
        case .text(let text):
            if text.uppercased() == "TRUE" { return .bool(true) }
            if text.uppercased() == "FALSE" { return .bool(false) }
            return .error(.value)
        case .error: return value
        }
    }

    static func binary(_ op: String, _ a: CellValue, _ b: CellValue) -> CellValue {
        if case .error = a { return a }
        if case .error = b { return b }
        switch op {
        case "&":
            return .text(text(a) + text(b))
        case "=", "<>", "<", ">", "<=", ">=":
            let order = compare(a, b)
            switch op {
            case "=": return .bool(order == 0)
            case "<>": return .bool(order != 0)
            case "<": return .bool(order < 0)
            case ">": return .bool(order > 0)
            case "<=": return .bool(order <= 0)
            default: return .bool(order >= 0)
            }
        default:
            guard case .number(let x) = number(a) else { return number(a) }
            guard case .number(let y) = number(b) else { return number(b) }
            switch op {
            case "+": return .number(x + y)
            case "-": return .number(x - y)
            case "*": return .number(x * y)
            case "/": return y == 0 ? .error(.div0) : .number(x / y)
            case "^":
                let result = pow(x, y)
                return result.isFinite ? .number(result) : .error(.num)
            default: return .error(.value)
            }
        }
    }

    /// Spreadsheet ordering: numbers < text < TRUE/FALSE; text ignores case; empty matches 0 and "".
    static func compare(_ a: CellValue, _ b: CellValue) -> Int {
        func rank(_ value: CellValue) -> Int {
            switch value {
            case .number, .empty: return 0
            case .text: return 1
            case .bool: return 2
            case .error: return 3
            }
        }
        switch (a, b) {
        case (.empty, .text(let text)): return text.isEmpty ? 0 : -1
        case (.text(let text), .empty): return text.isEmpty ? 0 : 1
        case (.empty, .empty): return 0
        default: break
        }
        if rank(a) != rank(b) { return rank(a) < rank(b) ? -1 : 1 }
        switch (a, b) {
        case (.text(let x), .text(let y)):
            let result = x.caseInsensitiveCompare(y)
            return result == .orderedSame ? 0 : (result == .orderedAscending ? -1 : 1)
        case (.bool(let x), .bool(let y)):
            return x == y ? 0 : (!x ? -1 : 1)
        default:
            let x = double(a) ?? 0, y = double(b) ?? 0
            return x == y ? 0 : (x < y ? -1 : 1)
        }
    }
}

// MARK: Criteria

/// ">5", "<>done", "=Acme", "Ac*", or just a value, as SUMIF and COUNTIFS take them.
struct GridCriterion {
    enum Comparison { case equal, notEqual, less, lessOrEqual, greater, greaterOrEqual }

    let comparison: Comparison
    let value: CellValue
    let pattern: NSRegularExpression?

    init(_ criterion: CellValue) {
        guard case .text(let text) = criterion else {
            comparison = .equal
            value = criterion
            pattern = nil
            return
        }
        var rest = text
        var comparison = Comparison.equal
        for (prefix, kind) in [(">=", Comparison.greaterOrEqual), ("<=", .lessOrEqual), ("<>", .notEqual), (">", .greater), ("<", .less), ("=", .equal)]
        where rest.hasPrefix(prefix) {
            comparison = kind
            rest = String(rest.dropFirst(prefix.count))
            break
        }
        self.comparison = comparison
        let interpreted = GridInput.interpret(rest).value
        if case .number = interpreted {
            value = interpreted
            pattern = nil
        } else {
            value = rest.isEmpty ? .empty : .text(rest)
            if rest.contains("*") || rest.contains("?") {
                var regex = "^"
                for character in rest {
                    switch character {
                    case "*": regex += ".*"
                    case "?": regex += "."
                    default: regex += NSRegularExpression.escapedPattern(for: String(character))
                    }
                }
                pattern = try? NSRegularExpression(pattern: regex + "$", options: [.caseInsensitive, .dotMatchesLineSeparators])
            } else {
                pattern = nil
            }
        }
    }

    func matches(_ candidate: CellValue) -> Bool {
        if let pattern, comparison == .equal || comparison == .notEqual {
            let text = GridEngine.text(candidate)
            let found = pattern.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
            return comparison == .equal ? found : !found
        }
        if value == .empty {
            let blank = candidate == .empty || candidate == .text("")
            return comparison == .notEqual ? !blank : (comparison == .equal ? blank : false)
        }
        // Numbers only compare with numbers, text with text.
        switch (value, candidate) {
        case (.number, .number), (.text, .text), (.bool, .bool):
            break
        case (.number, .text(let text)):
            guard case .number = GridInput.interpret(text).value else { return comparison == .notEqual }
        default:
            return comparison == .notEqual
        }
        let order = GridEngine.compare(candidate, value)
        switch comparison {
        case .equal: return order == 0
        case .notEqual: return order != 0
        case .less: return order < 0
        case .lessOrEqual: return order <= 0
        case .greater: return order > 0
        case .greaterOrEqual: return order >= 0
        }
    }
}

// MARK: Functions

enum GridFunctions {
    static let names: [String] = [
        "ABS", "AND", "AVERAGE", "AVERAGEIF", "AVERAGEIFS", "CEILING", "CHAR", "CHOOSE", "CODE", "COLUMN", "COLUMNS", "CONCAT", "CONCATENATE",
        "COUNT", "COUNTA", "COUNTBLANK", "COUNTIF", "COUNTIFS", "DATE", "DATEDIF", "DATEVALUE", "DAY", "DAYS", "EDATE", "EOMONTH", "EVEN",
        "EXACT", "EXP", "FALSE", "FIND", "FLOOR", "FV", "HLOOKUP", "HOUR", "IF", "IFERROR", "IFNA", "IFS", "INDEX", "INT", "IRR", "ISBLANK",
        "ISERROR", "ISEVEN", "ISLOGICAL", "ISNA", "ISNUMBER", "ISODD", "ISTEXT", "LARGE", "LEFT", "LEN", "LN", "LOG", "LOG10", "LOWER",
        "MATCH", "MAX", "MAXIFS", "MEDIAN", "MID", "MIN", "MINIFS", "MINUTE", "MOD", "MONTH", "MROUND", "NA", "NETWORKDAYS", "NOT", "NOW",
        "NPV", "ODD", "OR", "PI", "PMT", "POWER", "PRODUCT", "PROPER", "PV", "RAND", "RANDBETWEEN", "RANK", "REPLACE", "REPT", "RIGHT",
        "ROUND", "ROUNDDOWN", "ROUNDUP", "ROW", "ROWS", "SEARCH", "SECOND", "SIGN", "SMALL", "SQRT", "STDEV", "STDEVP", "SUBSTITUTE", "SUM",
        "SUMIF", "SUMIFS", "SUMPRODUCT", "SWITCH", "TEXT", "TEXTJOIN", "TIME", "TODAY", "TRIM", "TRUE", "TRUNC", "UPPER", "VALUE", "VAR",
        "VLOOKUP", "WEEKDAY", "WORKDAY", "XLOOKUP", "XOR", "YEAR",
    ]

    static func call(_ name: String, _ arguments: [FormulaExpr], engine: GridEngine, sheet: Int) -> GridOperand {
        let name = name.hasPrefix("_XLFN.") ? String(name.dropFirst(6)) : name
        func eval(_ index: Int) -> GridOperand {
            index < arguments.count ? engine.evaluate(arguments[index], sheet: sheet) : .value(.empty)
        }
        func scalar(_ index: Int) -> CellValue { eval(index).scalar }
        func number(_ index: Int, default fallback: Double? = nil) -> Result<Double, CellError> {
            if index >= arguments.count, let fallback { return .success(fallback) }
            switch GridEngine.number(scalar(index)) {
            case .number(let value): return .success(value)
            case .error(let error): return .failure(error)
            default: return .failure(.value)
            }
        }
        func text(_ index: Int) -> CellValue {
            let value = scalar(index)
            if case .error = value { return value }
            return .text(GridEngine.text(value))
        }
        func area(_ index: Int) -> GridArea { eval(index).area }
        func result(_ value: Double) -> GridOperand { .value(value.isFinite ? .number(value) : .error(.num)) }
        func fail(_ error: CellError) -> GridOperand { .value(.error(error)) }
        let count = arguments.count

        /// Numbers for SUM and friends: from ranges and references only numbers count; typed values are converted.
        func numbers(_ indices: Range<Int>) -> Result<[Double], CellError> {
            var values: [Double] = []
            for index in indices {
                let operand = eval(index)
                let fromCells: Bool
                switch arguments[index] {
                case .reference, .range, .columns, .name: fromCells = true
                default: fromCells = false
                }
                if case .area(let found) = operand {
                    for value in found.values {
                        switch value {
                        case .number(let number): values.append(number)
                        case .error(let error): return .failure(error)
                        default: continue
                        }
                    }
                } else {
                    let value = operand.scalar
                    switch value {
                    case .number(let number): values.append(number)
                    case .error(let error): return .failure(error)
                    case .empty: continue
                    case .text, .bool:
                        if fromCells { continue }
                        guard case .number(let number) = GridEngine.number(value) else { return .failure(.value) }
                        values.append(number)
                    }
                }
            }
            return .success(values)
        }
        func aggregate(_ indices: Range<Int>, _ reduce: ([Double]) -> Double?) -> GridOperand {
            switch numbers(indices) {
            case .success(let values):
                guard let value = reduce(values) else { return fail(.div0) }
                return result(value)
            case .failure(let error):
                return fail(error)
            }
        }
        func roundTo(_ value: Double, _ places: Double, _ rule: FloatingPointRoundingRule) -> Double {
            let factor = pow(10, places)
            let scaled = (value * factor * 1e9).rounded() / 1e9
            return (scaled.rounded(rule)) / factor
        }

        /// The cells where every (range, criterion) pair matches.
        func matching(pairs start: Int) -> Result<[Int], CellError> {
            guard (count - start) >= 2, (count - start) % 2 == 0 else { return .failure(.value) }
            var hits: [Int]?
            var size = 0
            for pair in stride(from: start, to: count, by: 2) {
                let range = area(pair)
                let criterion = GridCriterion(scalar(pair + 1))
                if hits == nil { size = range.values.count }
                guard range.values.count == size else { return .failure(.value) }
                let matched = range.values.indices.filter { criterion.matches(range.values[$0]) }
                hits = hits.map { Array(Set($0).intersection(matched)).sorted() } ?? matched
            }
            return .success(hits ?? [])
        }
        func sum(_ values: [CellValue], at indices: [Int]) -> Double {
            indices.reduce(0.0) { total, index in
                guard index < values.count, case .number(let number) = values[index] else { return total }
                return total + number
            }
        }
        func dateParts(_ index: Int) -> Result<DateComponents, CellError> {
            switch number(index) {
            case .success(let serial): return .success(ExcelDate.parts(serial))
            case .failure(let error): return .failure(error)
            }
        }

        switch name {
        // Maths
        case "SUM": return aggregate(0..<count) { $0.reduce(0, +) }
        case "PRODUCT": return aggregate(0..<count) { $0.isEmpty ? 0 : $0.reduce(1, *) }
        case "AVERAGE": return aggregate(0..<count) { $0.isEmpty ? nil : $0.reduce(0, +) / Double($0.count) }
        case "MIN": return aggregate(0..<count) { $0.min() ?? 0 }
        case "MAX": return aggregate(0..<count) { $0.max() ?? 0 }
        case "MEDIAN":
            return aggregate(0..<count) { values in
                guard !values.isEmpty else { return nil }
                let sorted = values.sorted()
                return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
            }
        case "STDEV", "STDEVP", "VAR":
            return aggregate(0..<count) { values in
                let sample = name != "STDEVP"
                guard values.count > (sample ? 1 : 0) else { return nil }
                let mean = values.reduce(0, +) / Double(values.count)
                let variance = values.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - (sample ? 1 : 0))
                return name == "VAR" ? variance : variance.squareRoot()
            }
        case "LARGE", "SMALL":
            guard count == 2 else { return fail(.value) }
            switch (numbers(0..<1), number(1)) {
            case (.success(let values), .success(let k)):
                let sorted = name == "LARGE" ? values.sorted(by: >) : values.sorted()
                let position = Int(k) - 1
                return sorted.indices.contains(position) ? result(sorted[position]) : fail(.num)
            case (.failure(let error), _), (_, .failure(let error)):
                return fail(error)
            }
        case "RANK":
            guard count >= 2 else { return fail(.value) }
            switch (number(0), numbers(1..<2), number(2, default: 0)) {
            case (.success(let value), .success(let values), .success(let order)):
                let sorted = order == 0 ? values.sorted(by: >) : values.sorted()
                guard let position = sorted.firstIndex(of: value) else { return fail(.na) }
                return result(Double(position + 1))
            case (.failure(let error), _, _), (_, .failure(let error), _), (_, _, .failure(let error)):
                return fail(error)
            }
        case "COUNT":
            var total = 0
            for index in 0..<count {
                switch eval(index) {
                case .area(let found): total += found.values.filter { if case .number = $0 { return true }; return false }.count
                case .value(let value):
                    if case .number = GridEngine.number(value), value != .empty { total += 1 }
                }
            }
            return result(Double(total))
        case "COUNTA":
            let total = (0..<count).reduce(0) { sum, index in sum + eval(index).area.values.filter { $0 != .empty }.count }
            return result(Double(total))
        case "COUNTBLANK":
            let found = area(0)
            return result(Double(found.values.filter { $0 == .empty || $0 == .text("") }.count))
        case "ROUND", "ROUNDUP", "ROUNDDOWN":
            switch (number(0), number(1, default: 0)) {
            case (.success(let value), .success(let places)):
                let rule: FloatingPointRoundingRule = name == "ROUND" ? .toNearestOrAwayFromZero : (name == "ROUNDUP" ? .awayFromZero : .towardZero)
                return result(roundTo(value, places.rounded(.towardZero), rule))
            case (.failure(let error), _), (_, .failure(let error)):
                return fail(error)
            }
        case "MROUND":
            switch (number(0), number(1)) {
            case (.success(let value), .success(let multiple)):
                guard multiple != 0 else { return result(0) }
                return result((value / multiple).rounded(.toNearestOrAwayFromZero) * multiple)
            case (.failure(let error), _), (_, .failure(let error)):
                return fail(error)
            }
        case "INT", "TRUNC", "ABS", "SQRT", "EXP", "LN", "LOG10", "SIGN", "EVEN", "ODD":
            switch number(0) {
            case .success(let value):
                switch name {
                case "INT": return result(value.rounded(.down))
                case "TRUNC":
                    if case .success(let places) = number(1, default: 0) { return result(roundTo(value, places, .towardZero)) }
                    return fail(.value)
                case "ABS": return result(abs(value))
                case "SQRT": return value < 0 ? fail(.num) : result(value.squareRoot())
                case "EXP": return result(exp(value))
                case "LN": return value <= 0 ? fail(.num) : result(log(value))
                case "LOG10": return value <= 0 ? fail(.num) : result(log10(value))
                case "SIGN": return result(value > 0 ? 1 : (value < 0 ? -1 : 0))
                case "EVEN":
                    let up = (abs(value) / 2).rounded(.up) * 2
                    return result(value < 0 ? -up : up)
                default:
                    var up = abs(value).rounded(.up)
                    if up.truncatingRemainder(dividingBy: 2) == 0 { up += 1 }
                    return result(value < 0 ? -up : up)
                }
            case .failure(let error):
                return fail(error)
            }
        case "LOG":
            switch (number(0), number(1, default: 10)) {
            case (.success(let value), .success(let base)):
                return value <= 0 || base <= 0 || base == 1 ? fail(.num) : result(log(value) / log(base))
            case (.failure(let error), _), (_, .failure(let error)):
                return fail(error)
            }
        case "MOD", "POWER":
            switch (number(0), number(1)) {
            case (.success(let a), .success(let b)):
                if name == "POWER" { return result(pow(a, b)) }
                guard b != 0 else { return fail(.div0) }
                return result(a - b * (a / b).rounded(.down))
            case (.failure(let error), _), (_, .failure(let error)):
                return fail(error)
            }
        case "CEILING", "FLOOR":
            switch (number(0), number(1, default: 1)) {
            case (.success(let value), .success(let significance)):
                guard significance != 0 else { return result(0) }
                let steps = value / significance
                return result((name == "CEILING" ? steps.rounded(.up) : steps.rounded(.down)) * significance)
            case (.failure(let error), _), (_, .failure(let error)):
                return fail(error)
            }
        case "PI": return result(Double.pi)
        case "RAND": return result(Double.random(in: 0..<1))
        case "RANDBETWEEN":
            switch (number(0), number(1)) {
            case (.success(let low), .success(let high)):
                guard low <= high else { return fail(.num) }
                return result(Double(Int.random(in: Int(low.rounded(.up))...Int(high.rounded(.down)))))
            case (.failure(let error), _), (_, .failure(let error)):
                return fail(error)
            }
        case "SUMPRODUCT":
            let areas = (0..<count).map(area)
            guard let first = areas.first, areas.allSatisfy({ $0.values.count == first.values.count }) else { return fail(.value) }
            var total = 0.0
            for index in first.values.indices {
                var product = 1.0
                for found in areas {
                    switch found.values[index] {
                    case .number(let number): product *= number
                    case .bool(let flag): product *= flag ? 1 : 0
                    case .error(let error): return fail(error)
                    default: product = 0
                    }
                }
                total += product
            }
            return result(total)

        // Conditional sums and counts
        case "SUMIF", "AVERAGEIF":
            guard count >= 2 else { return fail(.value) }
            let range = area(0)
            let target = count >= 3 ? area(2) : range
            let criterion = GridCriterion(scalar(1))
            let hits = range.values.indices.filter { criterion.matches(range.values[$0]) }
            let numbersHit = hits.filter { $0 < target.values.count && target.values[$0].number != nil }
            if name == "SUMIF" { return result(sum(target.values, at: hits)) }
            return numbersHit.isEmpty ? fail(.div0) : result(sum(target.values, at: numbersHit) / Double(numbersHit.count))
        case "COUNTIF":
            guard count == 2 else { return fail(.value) }
            let criterion = GridCriterion(scalar(1))
            return result(Double(area(0).values.filter { criterion.matches($0) }.count))
        case "COUNTIFS":
            switch matching(pairs: 0) {
            case .success(let hits): return result(Double(hits.count))
            case .failure(let error): return fail(error)
            }
        case "SUMIFS", "AVERAGEIFS", "MAXIFS", "MINIFS":
            let target = area(0)
            switch matching(pairs: 1) {
            case .success(let hits):
                guard hits.allSatisfy({ $0 < target.values.count }) else { return fail(.value) }
                let values = hits.compactMap { target.values[$0].number }
                switch name {
                case "SUMIFS": return result(values.reduce(0, +))
                case "AVERAGEIFS": return values.isEmpty ? fail(.div0) : result(values.reduce(0, +) / Double(values.count))
                case "MAXIFS": return result(values.max() ?? 0)
                default: return result(values.min() ?? 0)
                }
            case .failure(let error):
                return fail(error)
            }

        // Logic
        case "IF":
            guard count >= 2 else { return fail(.value) }
            let condition = GridEngine.bool(scalar(0))
            guard case .bool(let flag) = condition else { return .value(condition) }
            if flag { return eval(1) }
            return count >= 3 ? eval(2) : .value(.bool(false))
        case "IFS":
            for pair in stride(from: 0, to: count - 1, by: 2) {
                let condition = GridEngine.bool(scalar(pair))
                if case .error = condition { return .value(condition) }
                if condition == .bool(true) { return eval(pair + 1) }
            }
            return fail(.na)
        case "IFERROR", "IFNA":
            let first = eval(0)
            if case .error(let error) = first.scalar, name == "IFERROR" || error == .na { return eval(1) }
            return first
        case "SWITCH":
            guard count >= 3 else { return fail(.value) }
            let subject = scalar(0)
            var index = 1
            while index + 1 < count {
                if GridEngine.compare(subject, scalar(index)) == 0 { return eval(index + 1) }
                index += 2
            }
            return index < count ? eval(index) : fail(.na)
        case "AND", "OR", "XOR":
            var flags: [Bool] = []
            for index in 0..<count {
                for value in eval(index).area.values {
                    switch GridEngine.bool(value) {
                    case .bool(let flag):
                        if value != .empty { flags.append(flag) }
                    case .error(let error):
                        if case .text = value { continue }
                        return fail(error)
                    default: continue
                    }
                }
            }
            guard !flags.isEmpty else { return fail(.value) }
            switch name {
            case "AND": return .value(.bool(flags.allSatisfy { $0 }))
            case "OR": return .value(.bool(flags.contains(true)))
            default: return .value(.bool(flags.filter { $0 }.count % 2 == 1))
            }
        case "NOT":
            let condition = GridEngine.bool(scalar(0))
            guard case .bool(let flag) = condition else { return .value(condition) }
            return .value(.bool(!flag))
        case "TRUE": return .value(.bool(true))
        case "FALSE": return .value(.bool(false))

        // Looking things up
        case "VLOOKUP", "HLOOKUP":
            guard count >= 3 else { return fail(.value) }
            let wanted = scalar(0)
            let table = area(1)
            guard case .success(let pick) = number(2) else { return fail(.value) }
            let approximate: Bool
            if count >= 4, case .bool(let flag) = GridEngine.bool(scalar(3)) { approximate = flag } else { approximate = true }
            let vertical = name == "VLOOKUP"
            let length = vertical ? table.rows : table.columns
            let column = Int(pick) - 1
            guard column >= 0, column < (vertical ? table.columns : table.rows) else { return fail(.ref) }
            func key(_ index: Int) -> CellValue { vertical ? table[index, 0] : table[0, index] }
            var found: Int?
            if approximate {
                for index in 0..<length {
                    let candidate = key(index)
                    if candidate == .empty { continue }
                    if GridEngine.compare(candidate, wanted) <= 0 { found = index } else { break }
                }
            } else {
                let criterion = GridCriterion(wanted)
                found = (0..<length).first { index in
                    if case .text = wanted { return criterion.matches(key(index)) }
                    return GridEngine.compare(key(index), wanted) == 0 && key(index) != .empty
                }
            }
            guard let row = found else { return fail(.na) }
            return .value(vertical ? table[row, column] : table[column, row])
        case "XLOOKUP":
            guard count >= 3 else { return fail(.value) }
            let wanted = scalar(0)
            let keys = area(1)
            let results = area(2)
            let mode = count >= 5 ? Int((try? number(4).get()) ?? 0) : 0
            let reverse = count >= 6 && ((try? number(5).get()) ?? 1) < 0
            var order = Array(keys.values.indices)
            if reverse { order.reverse() }
            var found: Int?
            switch mode {
            case 2:
                let criterion = GridCriterion(wanted)
                found = order.first { criterion.matches(keys.values[$0]) }
            case -1, 1:
                found = order.first { GridEngine.compare(keys.values[$0], wanted) == 0 }
                if found == nil {
                    let candidates = order.filter { mode == -1 ? GridEngine.compare(keys.values[$0], wanted) < 0 : GridEngine.compare(keys.values[$0], wanted) > 0 }
                    found = mode == -1 ? candidates.max { GridEngine.compare(keys.values[$0], keys.values[$1]) < 0 }
                                       : candidates.min { GridEngine.compare(keys.values[$0], keys.values[$1]) < 0 }
                }
            default:
                found = order.first { keys.values[$0] != .empty && GridEngine.compare(keys.values[$0], wanted) == 0 }
            }
            guard let index = found else { return count >= 4 && arguments[3] != .text("") ? eval(3) : fail(.na) }
            if keys.columns == 1 && results.rows == keys.rows && results.columns > 1 {
                return .area(GridArea(rows: 1, columns: results.columns, values: (0..<results.columns).map { results[index, $0] }))
            }
            if keys.rows == 1 && results.columns == keys.columns && results.rows > 1 {
                return .area(GridArea(rows: results.rows, columns: 1, values: (0..<results.rows).map { results[$0, index] }))
            }
            return index < results.values.count ? .value(results.values[index]) : fail(.value)
        case "MATCH":
            guard count >= 2 else { return fail(.value) }
            let wanted = scalar(0)
            let values = area(1).values
            let type = count >= 3 ? ((try? number(2).get()) ?? 1) : 1
            if type == 0 {
                let criterion = GridCriterion(wanted)
                let index = values.firstIndex { value in
                    if case .text = wanted { return criterion.matches(value) }
                    return GridEngine.compare(value, wanted) == 0 && value != .empty
                }
                return index.map { result(Double($0 + 1)) } ?? fail(.na)
            }
            var found: Int?
            for (index, value) in values.enumerated() where value != .empty {
                let order = GridEngine.compare(value, wanted)
                if type > 0 { if order <= 0 { found = index } else { break } } else { if order >= 0 { found = index } else { break } }
            }
            return found.map { result(Double($0 + 1)) } ?? fail(.na)
        case "INDEX":
            guard count >= 2 else { return fail(.value) }
            let table = area(0)
            guard case .success(let first) = number(1) else { return fail(.value) }
            var row = Int(first), column = 1
            if count >= 3, case .success(let second) = number(2) { column = Int(second) }
            if count == 2 && table.rows == 1 { column = row; row = 1 }
            if row == 0 && table.columns == 1 { row = 1 }
            guard row >= 1, column >= 1, row <= table.rows, column <= table.columns else { return fail(.ref) }
            return .value(table[row - 1, column - 1])
        case "CHOOSE":
            guard count >= 2, case .success(let pick) = number(0) else { return fail(.value) }
            let index = Int(pick)
            guard index >= 1, index < count else { return fail(.value) }
            return eval(index)
        case "ROWS", "COLUMNS":
            let found = area(0)
            return result(Double(name == "ROWS" ? found.rows : found.columns))
        case "ROW", "COLUMN":
            if count == 0 { return fail(.value) }
            switch arguments[0] {
            case .reference(_, let reference): return result(Double((name == "ROW" ? reference.row : reference.column) + 1))
            case .range(_, let start, _): return result(Double((name == "ROW" ? start.row : start.column) + 1))
            default: return fail(.value)
            }

        // Text
        case "LEN":
            let value = text(0)
            guard case .text(let string) = value else { return .value(value) }
            return result(Double(string.count))
        case "LEFT", "RIGHT":
            let value = text(0)
            guard case .text(let string) = value, case .success(let length) = number(1, default: 1), length >= 0 else { return fail(.value) }
            return .value(.text(String(name == "LEFT" ? string.prefix(Int(length)) : string.suffix(Int(length)))))
        case "MID":
            let value = text(0)
            guard case .text(let string) = value, case .success(let start) = number(1), case .success(let length) = number(2), start >= 1, length >= 0 else {
                return fail(.value)
            }
            return .value(.text(String(string.dropFirst(Int(start) - 1).prefix(Int(length)))))
        case "UPPER", "LOWER", "PROPER", "TRIM":
            let value = text(0)
            guard case .text(let string) = value else { return .value(value) }
            switch name {
            case "UPPER": return .value(.text(string.uppercased()))
            case "LOWER": return .value(.text(string.lowercased()))
            case "PROPER": return .value(.text(string.capitalized))
            default: return .value(.text(string.split(separator: " ").joined(separator: " ")))
            }
        case "CONCAT", "CONCATENATE":
            var joined = ""
            for index in 0..<count {
                for value in eval(index).area.values {
                    if case .error = value { return .value(value) }
                    joined += GridEngine.text(value)
                }
            }
            return .value(.text(joined))
        case "TEXTJOIN":
            guard count >= 3 else { return fail(.value) }
            let delimiter = GridEngine.text(scalar(0))
            let skipEmpty = GridEngine.bool(scalar(1)) == .bool(true)
            var parts: [String] = []
            for index in 2..<count {
                for value in eval(index).area.values {
                    if case .error = value { return .value(value) }
                    let piece = GridEngine.text(value)
                    if skipEmpty && piece.isEmpty { continue }
                    parts.append(piece)
                }
            }
            return .value(.text(parts.joined(separator: delimiter)))
        case "SUBSTITUTE":
            guard count >= 3 else { return fail(.value) }
            let source = GridEngine.text(scalar(0)), old = GridEngine.text(scalar(1)), new = GridEngine.text(scalar(2))
            guard !old.isEmpty else { return .value(.text(source)) }
            if count >= 4, case .success(let instance) = number(3) {
                var occurrence = 0
                var output = ""
                var rest = Substring(source)
                while let range = rest.range(of: old) {
                    occurrence += 1
                    output += rest[..<range.lowerBound]
                    output += occurrence == Int(instance) ? new : old
                    rest = rest[range.upperBound...]
                }
                return .value(.text(output + rest))
            }
            return .value(.text(source.replacingOccurrences(of: old, with: new)))
        case "REPLACE":
            guard count == 4, case .success(let start) = number(1), case .success(let length) = number(2), start >= 1 else { return fail(.value) }
            let source = Array(GridEngine.text(scalar(0)))
            let from = min(Int(start) - 1, source.count)
            let to = min(from + Int(length), source.count)
            return .value(.text(String(source[..<from]) + GridEngine.text(scalar(3)) + String(source[to...])))
        case "FIND", "SEARCH":
            guard count >= 2 else { return fail(.value) }
            let needle = GridEngine.text(scalar(0)), haystack = GridEngine.text(scalar(1))
            guard case .success(let start) = number(2, default: 1), start >= 1, Int(start) <= haystack.count + 1 else { return fail(.value) }
            let searchArea = haystack.dropFirst(Int(start) - 1)
            let options: String.CompareOptions = name == "SEARCH" ? [.caseInsensitive] : []
            guard let range = searchArea.range(of: needle, options: options) else { return fail(.value) }
            return result(Double(haystack.distance(from: haystack.startIndex, to: range.lowerBound) + 1))
        case "REPT":
            guard case .success(let times) = number(1), times >= 0 else { return fail(.value) }
            return .value(.text(String(repeating: GridEngine.text(scalar(0)), count: Int(times))))
        case "EXACT":
            return .value(.bool(GridEngine.text(scalar(0)) == GridEngine.text(scalar(1))))
        case "CHAR":
            guard case .success(let code) = number(0), let scalarValue = UnicodeScalar(Int(code)) else { return fail(.value) }
            return .value(.text(String(Character(scalarValue))))
        case "CODE":
            let string = GridEngine.text(scalar(0))
            guard let first = string.unicodeScalars.first else { return fail(.value) }
            return result(Double(first.value))
        case "TEXT":
            guard count == 2 else { return fail(.value) }
            let value = scalar(0)
            let code = GridEngine.text(scalar(1))
            guard case .number(let number) = GridEngine.number(value) else {
                if case .error = value { return .value(value) }
                return .value(.text(GridEngine.text(value)))
            }
            return .value(.text(ExcelFormat.format(number, code)))
        case "VALUE":
            let value = scalar(0)
            return .value(GridEngine.number(value))

        // Dates
        case "DATE":
            switch (number(0), number(1), number(2)) {
            case (.success(let year), .success(let month), .success(let day)):
                var adjustedYear = Int(year)
                if adjustedYear < 1900 { adjustedYear += 1900 }
                guard let serial = ExcelDate.serial(year: adjustedYear, month: Int(month), day: Int(day)) else { return fail(.num) }
                return result(serial)
            case (.failure(let error), _, _), (_, .failure(let error), _), (_, _, .failure(let error)):
                return fail(error)
            }
        case "TIME":
            switch (number(0), number(1), number(2)) {
            case (.success(let hour), .success(let minute), .success(let second)):
                let fraction = (hour * 3_600 + minute * 60 + second) / 86_400
                return result(fraction - fraction.rounded(.down))
            case (.failure(let error), _, _), (_, .failure(let error), _), (_, _, .failure(let error)):
                return fail(error)
            }
        case "TODAY": return result(ExcelDate.serial(engine.now).rounded(.down))
        case "NOW": return result(ExcelDate.serial(engine.now))
        case "YEAR", "MONTH", "DAY", "HOUR", "MINUTE", "SECOND":
            switch dateParts(0) {
            case .success(let parts):
                let pick: Int?
                switch name {
                case "YEAR": pick = parts.year
                case "MONTH": pick = parts.month
                case "DAY": pick = parts.day
                case "HOUR": pick = parts.hour
                case "MINUTE": pick = parts.minute
                default: pick = parts.second
                }
                return result(Double(pick ?? 0))
            case .failure(let error):
                return fail(error)
            }
        case "WEEKDAY":
            switch (dateParts(0), number(1, default: 1)) {
            case (.success(let parts), .success(let type)):
                let sundayFirst = parts.weekday ?? 1
                switch Int(type) {
                case 2: return result(Double((sundayFirst + 5) % 7 + 1))
                case 3: return result(Double((sundayFirst + 5) % 7))
                default: return result(Double(sundayFirst))
                }
            case (.failure(let error), _), (_, .failure(let error)):
                return fail(error)
            }
        case "EOMONTH", "EDATE":
            switch (dateParts(0), number(1)) {
            case (.success(let parts), .success(let months)):
                guard let year = parts.year, let month = parts.month, let day = parts.day else { return fail(.num) }
                if name == "EOMONTH" {
                    return ExcelDate.serial(year: year, month: month + Int(months) + 1, day: 0).map(result) ?? fail(.num)
                }
                // EDATE keeps the day, or the month's last day if it's shorter.
                guard let firstOfTarget = ExcelDate.serial(year: year, month: month + Int(months), day: 1),
                      let lastOfTarget = ExcelDate.serial(year: year, month: month + Int(months) + 1, day: 0) else { return fail(.num) }
                return result(min(firstOfTarget + Double(day - 1), lastOfTarget))
            case (.failure(let error), _), (_, .failure(let error)):
                return fail(error)
            }
        case "DAYS":
            switch (number(0), number(1)) {
            case (.success(let end), .success(let start)): return result((end.rounded(.down) - start.rounded(.down)))
            case (.failure(let error), _), (_, .failure(let error)): return fail(error)
            }
        case "DATEDIF":
            guard count == 3 else { return fail(.value) }
            switch (number(0), number(1)) {
            case (.success(let start), .success(let end)):
                guard end >= start else { return fail(.num) }
                let unit = GridEngine.text(scalar(2)).uppercased()
                let components = ExcelDate.calendar.dateComponents([.year, .month, .day], from: ExcelDate.date(start), to: ExcelDate.date(end))
                switch unit {
                case "Y": return result(Double(components.year ?? 0))
                case "M": return result(Double((components.year ?? 0) * 12 + (components.month ?? 0)))
                case "D": return result((end - start).rounded(.down))
                case "MD": return result(Double(components.day ?? 0))
                case "YM": return result(Double(components.month ?? 0))
                default: return fail(.num)
                }
            case (.failure(let error), _), (_, .failure(let error)):
                return fail(error)
            }
        case "NETWORKDAYS":
            switch (number(0), number(1)) {
            case (.success(let start), .success(let end)):
                let low = Int(min(start, end)), high = Int(max(start, end))
                let days = (low...high).filter { serial in
                    let weekday = ExcelDate.parts(Double(serial)).weekday ?? 1
                    return weekday != 1 && weekday != 7
                }.count
                return result(Double(start <= end ? days : -days))
            case (.failure(let error), _), (_, .failure(let error)):
                return fail(error)
            }
        case "WORKDAY":
            switch (number(0), number(1)) {
            case (.success(let start), .success(let days)):
                var serial = Int(start)
                var remaining = Int(days)
                let step = remaining >= 0 ? 1 : -1
                while remaining != 0 {
                    serial += step
                    let weekday = ExcelDate.parts(Double(serial)).weekday ?? 1
                    if weekday != 1 && weekday != 7 { remaining -= step }
                }
                return result(Double(serial))
            case (.failure(let error), _), (_, .failure(let error)):
                return fail(error)
            }
        case "DATEVALUE":
            let string = GridEngine.text(scalar(0))
            guard let found = GridInput.dateOrTime(string) else { return fail(.value) }
            return result(found.0.rounded(.down))

        // Information
        case "ISBLANK": return .value(.bool(scalar(0) == .empty))
        case "ISNUMBER": return .value(.bool(scalar(0).number != nil))
        case "ISTEXT":
            if case .text = scalar(0) { return .value(.bool(true)) }
            return .value(.bool(false))
        case "ISLOGICAL":
            if case .bool = scalar(0) { return .value(.bool(true)) }
            return .value(.bool(false))
        case "ISERROR":
            if case .error = scalar(0) { return .value(.bool(true)) }
            return .value(.bool(false))
        case "ISNA": return .value(.bool(scalar(0) == .error(.na)))
        case "ISEVEN", "ISODD":
            guard case .success(let value) = number(0) else { return fail(.value) }
            let even = Int(value.rounded(.towardZero)) % 2 == 0
            return .value(.bool(name == "ISEVEN" ? even : !even))
        case "NA": return fail(.na)

        // Money
        case "PMT", "PV", "FV":
            switch (number(0), number(1), number(2), number(3, default: 0), number(4, default: 0)) {
            case (.success(let rate), .success(let periods), .success(let third), .success(let fourth), .success(let type)):
                let due = type != 0 ? 1.0 : 0.0
                switch name {
                case "PMT":
                    let present: Double = third, future: Double = fourth
                    if rate == 0 { return result(-(present + future) / periods) }
                    let growth: Double = pow(1 + rate, periods)
                    let top: Double = rate * (present * growth + future)
                    let bottom: Double = (1 + rate * due) * (growth - 1)
                    return result(-top / bottom)
                case "PV":
                    let payment: Double = third, future: Double = fourth
                    if rate == 0 { return result(-(payment * periods + future)) }
                    let growth: Double = pow(1 + rate, periods)
                    let annuity: Double = payment * (1 + rate * due) * (growth - 1) / rate
                    return result(-(annuity + future) / growth)
                default:
                    let payment: Double = third, present: Double = fourth
                    if rate == 0 { return result(-(present + payment * periods)) }
                    let growth: Double = pow(1 + rate, periods)
                    let annuity: Double = payment * (1 + rate * due) * (growth - 1) / rate
                    return result(-(present * growth + annuity))
                }
            case (.failure(let error), _, _, _, _), (_, .failure(let error), _, _, _), (_, _, .failure(let error), _, _),
                 (_, _, _, .failure(let error), _), (_, _, _, _, .failure(let error)):
                return fail(error)
            }
        case "NPV":
            guard count >= 2, case .success(let rate) = number(0) else { return fail(.value) }
            switch numbers(1..<count) {
            case .success(let flows):
                var total = 0.0
                for (offset, flow) in flows.enumerated() { total += flow / pow(1 + rate, Double(offset + 1)) }
                return result(total)
            case .failure(let error):
                return fail(error)
            }
        case "IRR":
            switch numbers(0..<1) {
            case .success(let flows):
                guard flows.contains(where: { $0 < 0 }), flows.contains(where: { $0 > 0 }) else { return fail(.num) }
                func npv(_ rate: Double) -> Double {
                    var total = 0.0
                    for (offset, flow) in flows.enumerated() { total += flow / pow(1 + rate, Double(offset)) }
                    return total
                }
                var guess = (try? number(1, default: 0.1).get()) ?? 0.1
                for _ in 0..<100 {
                    let value = npv(guess)
                    let slope = (npv(guess + 1e-6) - value) / 1e-6
                    guard slope != 0 else { break }
                    let next = guess - value / slope
                    if abs(next - guess) < 1e-10 { return result(next) }
                    guess = next
                }
                // Fall back to halving between -99% and 1000%.
                var low = -0.99, high = 10.0
                guard npv(low).sign != npv(high).sign else { return fail(.num) }
                for _ in 0..<200 {
                    let middle = (low + high) / 2
                    if npv(middle).sign == npv(low).sign { low = middle } else { high = middle }
                }
                return result((low + high) / 2)
            case .failure(let error):
                return fail(error)
            }

        default:
            return fail(.name)
        }
    }
}
