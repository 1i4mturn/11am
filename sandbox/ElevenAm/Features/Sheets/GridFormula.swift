import Foundation

/// A cell reference inside a formula, remembering which parts are fixed with $.
struct FormulaRef: Equatable, Hashable, Sendable {
    var row: Int
    var column: Int
    var absoluteRow = false
    var absoluteColumn = false

    var address: CellAddress { CellAddress(row: row, column: column) }

    var text: String {
        (absoluteColumn ? "$" : "") + CellAddress.columnName(column) + (absoluteRow ? "$" : "") + "\(row + 1)"
    }

    init(row: Int, column: Int, absoluteRow: Bool = false, absoluteColumn: Bool = false) {
        self.row = row
        self.column = column
        self.absoluteRow = absoluteRow
        self.absoluteColumn = absoluteColumn
    }

    /// "B3", "$B$3", "B$3".
    init?(_ text: String) {
        var characters = Array(text)
        var absoluteColumn = false
        if characters.first == "$" {
            absoluteColumn = true
            characters.removeFirst()
        }
        let letters = characters.prefix { $0.isLetter && $0.isASCII }
        var rest = Array(characters.dropFirst(letters.count))
        var absoluteRow = false
        if rest.first == "$" {
            absoluteRow = true
            rest.removeFirst()
        }
        guard !letters.isEmpty, letters.count <= 3, !rest.isEmpty, rest.allSatisfy({ $0.isASCII && $0.isNumber }),
              let column = CellAddress.columnIndex(String(letters)), let row = Int(String(rest)), row >= 1, row <= 1_048_576 else { return nil }
        self.init(row: row - 1, column: column, absoluteRow: absoluteRow, absoluteColumn: absoluteColumn)
    }
}

indirect enum FormulaExpr: Equatable, Sendable {
    case number(Double)
    case text(String)
    case bool(Bool)
    case error(CellError)
    case reference(sheet: String?, FormulaRef)
    case range(sheet: String?, FormulaRef, FormulaRef)
    /// Whole columns: A:C.
    case columns(sheet: String?, Int, Int)
    case name(String)
    case unary(String, FormulaExpr)
    case percent(FormulaExpr)
    case binary(String, FormulaExpr, FormulaExpr)
    case call(String, [FormulaExpr])
}

struct FormulaToken: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case number, string, bool, error, reference, columns, name, function, op, comma, open, close, colon, sheet, unknown
    }

    var kind: Kind
    var text: String
    /// Character offsets in the formula (after the "="), for rewriting references in place.
    var range: Range<Int>
}

enum FormulaLexer {
    static func tokens(_ formula: String) -> [FormulaToken] {
        let characters = Array(formula)
        var tokens: [FormulaToken] = []
        var index = 0

        func isIdentifier(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_" || character == "." || character == "$" || character == "\\"
        }
        func peek(_ offset: Int = 0) -> Character? {
            index + offset < characters.count ? characters[index + offset] : nil
        }

        while index < characters.count {
            let start = index
            let character = characters[index]
            if character.isWhitespace {
                index += 1
                continue
            }
            if character.isNumber || (character == "." && peek(1)?.isNumber == true) {
                while index < characters.count, characters[index].isNumber || characters[index] == "." { index += 1 }
                if index < characters.count, characters[index] == "e" || characters[index] == "E",
                   let next = peek(1), next.isNumber || ((next == "+" || next == "-") && peek(2)?.isNumber == true) {
                    index += 2
                    while index < characters.count, characters[index].isNumber { index += 1 }
                }
                // "1:3" is a range of whole rows; not supported, so it reads as a number and fails cleanly.
                tokens.append(FormulaToken(kind: .number, text: String(characters[start..<index]), range: start..<index))
                continue
            }
            if character == "\"" {
                index += 1
                var text = ""
                while index < characters.count {
                    if characters[index] == "\"" {
                        if peek(1) == "\"" {
                            text.append("\"")
                            index += 2
                            continue
                        }
                        index += 1
                        break
                    }
                    text.append(characters[index])
                    index += 1
                }
                tokens.append(FormulaToken(kind: .string, text: text, range: start..<index))
                continue
            }
            if character == "'" {
                // 'Sheet name'!
                index += 1
                var name = ""
                while index < characters.count {
                    if characters[index] == "'" {
                        if peek(1) == "'" {
                            name.append("'")
                            index += 2
                            continue
                        }
                        index += 1
                        break
                    }
                    name.append(characters[index])
                    index += 1
                }
                if peek() == "!" {
                    index += 1
                    tokens.append(FormulaToken(kind: .sheet, text: name, range: start..<index))
                } else {
                    tokens.append(FormulaToken(kind: .unknown, text: name, range: start..<index))
                }
                continue
            }
            if character == "#" {
                let rest = String(characters[index...]).uppercased()
                if let error = CellError.allCases.first(where: { rest.hasPrefix($0.rawValue) }) {
                    index += error.rawValue.count
                    tokens.append(FormulaToken(kind: .error, text: error.rawValue, range: start..<index))
                } else {
                    index += 1
                    tokens.append(FormulaToken(kind: .unknown, text: "#", range: start..<index))
                }
                continue
            }
            if character.isLetter || character == "$" || character == "_" {
                while index < characters.count, isIdentifier(characters[index]) { index += 1 }
                let word = String(characters[start..<index])
                if peek() == "!" {
                    index += 1
                    tokens.append(FormulaToken(kind: .sheet, text: word, range: start..<index))
                    continue
                }
                if FormulaRef(word) != nil {
                    tokens.append(FormulaToken(kind: .reference, text: word, range: start..<index))
                    continue
                }
                // A:C, whole columns.
                let bare = word.replacingOccurrences(of: "$", with: "")
                if !bare.isEmpty, bare.count <= 3, bare.allSatisfy({ $0.isLetter && $0.isASCII }), peek() == ":" {
                    var end = index + 1
                    while end < characters.count, characters[end] == "$" || (characters[end].isLetter && characters[end].isASCII) { end += 1 }
                    let other = String(characters[(index + 1)..<end]).replacingOccurrences(of: "$", with: "")
                    if !other.isEmpty, other.count <= 3, end == characters.count || !characters[end].isNumber {
                        tokens.append(FormulaToken(kind: .columns, text: String(characters[start..<end]), range: start..<end))
                        index = end
                        continue
                    }
                }
                var look = index
                while look < characters.count, characters[look].isWhitespace { look += 1 }
                if look < characters.count, characters[look] == "(" {
                    tokens.append(FormulaToken(kind: .function, text: word.uppercased(), range: start..<index))
                } else if word.uppercased() == "TRUE" || word.uppercased() == "FALSE" {
                    tokens.append(FormulaToken(kind: .bool, text: word.uppercased(), range: start..<index))
                } else {
                    tokens.append(FormulaToken(kind: .name, text: word, range: start..<index))
                }
                continue
            }
            switch character {
            case "(":
                tokens.append(FormulaToken(kind: .open, text: "(", range: start..<start + 1))
            case ")":
                tokens.append(FormulaToken(kind: .close, text: ")", range: start..<start + 1))
            case ",", ";":
                tokens.append(FormulaToken(kind: .comma, text: ",", range: start..<start + 1))
            case ":":
                tokens.append(FormulaToken(kind: .colon, text: ":", range: start..<start + 1))
            case "<", ">":
                if let next = peek(1), next == "=" || (character == "<" && next == ">") {
                    tokens.append(FormulaToken(kind: .op, text: String([character, next]), range: start..<start + 2))
                    index += 2
                    continue
                }
                tokens.append(FormulaToken(kind: .op, text: String(character), range: start..<start + 1))
            case "+", "-", "*", "/", "^", "&", "=", "%":
                tokens.append(FormulaToken(kind: .op, text: String(character), range: start..<start + 1))
            default:
                tokens.append(FormulaToken(kind: .unknown, text: String(character), range: start..<start + 1))
            }
            index += 1
        }
        return tokens
    }
}

struct FormulaParseError: Error {}

/// Excel's grammar: comparison < & < + - < * / < ^ < unary minus < %, with ranges and calls at the bottom.
struct FormulaParser {
    private let tokens: [FormulaToken]
    private var position = 0

    static func parse(_ formula: String) -> FormulaExpr {
        var text = formula.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("=") { text.removeFirst() }
        var parser = FormulaParser(tokens: FormulaLexer.tokens(text))
        guard !parser.tokens.isEmpty, let expression = try? parser.comparison(), parser.position == parser.tokens.count else {
            return .error(.name)
        }
        return expression
    }

    private init(tokens: [FormulaToken]) {
        self.tokens = tokens
    }

    private var current: FormulaToken? { position < tokens.count ? tokens[position] : nil }

    private mutating func take(_ kind: FormulaToken.Kind, _ text: String? = nil) -> FormulaToken? {
        guard let token = current, token.kind == kind, text == nil || token.text == text else { return nil }
        position += 1
        return token
    }

    private mutating func comparison() throws -> FormulaExpr {
        var left = try concatenation()
        while let token = current, token.kind == .op, ["=", "<>", "<", ">", "<=", ">="].contains(token.text) {
            position += 1
            left = .binary(token.text, left, try concatenation())
        }
        return left
    }

    private mutating func concatenation() throws -> FormulaExpr {
        var left = try additive()
        while take(.op, "&") != nil {
            left = .binary("&", left, try additive())
        }
        return left
    }

    private mutating func additive() throws -> FormulaExpr {
        var left = try multiplicative()
        while let token = current, token.kind == .op, token.text == "+" || token.text == "-" {
            position += 1
            left = .binary(token.text, left, try multiplicative())
        }
        return left
    }

    private mutating func multiplicative() throws -> FormulaExpr {
        var left = try power()
        while let token = current, token.kind == .op, token.text == "*" || token.text == "/" {
            position += 1
            left = .binary(token.text, left, try power())
        }
        return left
    }

    private mutating func power() throws -> FormulaExpr {
        var left = try unary()
        while take(.op, "^") != nil {
            left = .binary("^", left, try unary())
        }
        return left
    }

    private mutating func unary() throws -> FormulaExpr {
        if let token = current, token.kind == .op, token.text == "-" || token.text == "+" {
            position += 1
            return .unary(token.text, try unary())
        }
        return try postfix()
    }

    private mutating func postfix() throws -> FormulaExpr {
        var expression = try primary()
        while take(.op, "%") != nil { expression = .percent(expression) }
        return expression
    }

    private mutating func primary() throws -> FormulaExpr {
        guard let token = current else { throw FormulaParseError() }
        position += 1
        switch token.kind {
        case .number:
            guard let value = Double(token.text) else { throw FormulaParseError() }
            return .number(value)
        case .string:
            return .text(token.text)
        case .bool:
            return .bool(token.text == "TRUE")
        case .error:
            return .error(CellError(rawValue: token.text) ?? .value)
        case .sheet:
            if let reference = current, reference.kind == .reference || reference.kind == .columns {
                position += 1
                return try referenceExpression(reference, sheet: token.text)
            }
            throw FormulaParseError()
        case .reference, .columns:
            return try referenceExpression(token, sheet: nil)
        case .name:
            return .name(token.text)
        case .function:
            guard take(.open) != nil else { throw FormulaParseError() }
            var arguments: [FormulaExpr] = []
            if take(.close) != nil { return .call(token.text, arguments) }
            while true {
                // An empty argument, as in IF(A1,,2), counts as empty.
                if let next = current, next.kind == .comma || next.kind == .close {
                    arguments.append(.text(""))
                } else {
                    arguments.append(try comparison())
                }
                if take(.comma) != nil { continue }
                guard take(.close) != nil else { throw FormulaParseError() }
                break
            }
            return .call(token.text, arguments)
        case .open:
            let inner = try comparison()
            guard take(.close) != nil else { throw FormulaParseError() }
            return inner
        default:
            throw FormulaParseError()
        }
    }

    private mutating func referenceExpression(_ token: FormulaToken, sheet: String?) throws -> FormulaExpr {
        if token.kind == .columns {
            let parts = token.text.replacingOccurrences(of: "$", with: "").split(separator: ":")
            guard parts.count == 2, let first = CellAddress.columnIndex(String(parts[0])), let last = CellAddress.columnIndex(String(parts[1])) else {
                throw FormulaParseError()
            }
            return .columns(sheet: sheet, min(first, last), max(first, last))
        }
        guard let start = FormulaRef(token.text) else { throw FormulaParseError() }
        if take(.colon) != nil {
            if take(.sheet) != nil {} // Sheet1!A1:Sheet1!B2
            guard let endToken = take(.reference), let end = FormulaRef(endToken.text) else { throw FormulaParseError() }
            return .range(sheet: sheet, start, end)
        }
        return .reference(sheet: sheet, start)
    }
}

/// Rewrites the references in a formula's text, leaving everything else exactly as typed.
enum FormulaRewrite {
    /// Copying or filling: relative parts move by the offset; anything pushed off the sheet becomes #REF!.
    static func shift(_ formula: String, rows: Int, columns: Int) -> String {
        rewrite(formula) { reference, _, _ in
            var moved = reference
            if !reference.absoluteRow { moved.row += rows }
            if !reference.absoluteColumn { moved.column += columns }
            return moved.row < 0 || moved.column < 0 ? nil : moved
        }
    }

    /// Rows (or columns) inserted or deleted on a sheet. `sameSheet` says whether an unqualified reference is on that sheet;
    /// `target` is that sheet's name, for qualified ones. References inside deleted rows become #REF!, or close in
    /// when they're one end of a range.
    static func insert(_ formula: String, rows: Bool, at index: Int, count: Int, sameSheet: Bool, target: String) -> String {
        rewrite(formula) { reference, sheet, role in
            let applies = sheet.map { $0.caseInsensitiveCompare(target) == .orderedSame } ?? sameSheet
            guard applies else { return reference }
            var moved = reference
            let value = rows ? reference.row : reference.column
            var updated = value
            if count > 0 {
                if value >= index { updated = value + count }
            } else {
                let removed = index..<(index - count)
                if removed.contains(value) {
                    switch role {
                    case .rangeStart: updated = index
                    case .rangeEnd: updated = index - 1
                    case .single: return nil
                    }
                    if updated < 0 { return nil }
                } else if value >= removed.upperBound {
                    updated = value + count
                }
            }
            if rows { moved.row = updated } else { moved.column = updated }
            return moved
        }
    }

    enum Role { case single, rangeStart, rangeEnd }

    /// Calls `transform` for each reference (with its sheet, if named); nil turns it into #REF!. A range whose ends cross
    /// (everything it covered was deleted) becomes #REF! as a whole.
    static func rewrite(_ formula: String, _ transform: (FormulaRef, String?, Role) -> FormulaRef?) -> String {
        guard formula.hasPrefix("=") else { return formula }
        let body = String(formula.dropFirst())
        let tokens = FormulaLexer.tokens(body)
        var characters = Array(body)

        struct Unit {
            var span: Range<Int>
            var start: Int
            var end: Int?
            var sheet: String?
        }
        var units: [Unit] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            guard token.kind == .reference || token.kind == .columns else {
                index += 1
                continue
            }
            let sheet = index > 0 && tokens[index - 1].kind == .sheet ? tokens[index - 1].text : nil
            if token.kind == .reference, index + 2 < tokens.count, tokens[index + 1].kind == .colon {
                var endIndex = index + 2
                if tokens[endIndex].kind == .sheet, endIndex + 1 < tokens.count { endIndex += 1 }
                if tokens[endIndex].kind == .reference {
                    units.append(Unit(span: token.range.lowerBound..<tokens[endIndex].range.upperBound, start: index, end: endIndex, sheet: sheet))
                    index = endIndex + 1
                    continue
                }
            }
            units.append(Unit(span: token.range, start: index, end: nil, sheet: sheet))
            index += 1
        }

        // From the end, so earlier offsets stay right.
        for unit in units.reversed() {
            let token = tokens[unit.start]
            let replacement: String
            if token.kind == .columns {
                // Whole columns move with column changes only.
                let parts = token.text.split(separator: ":").map(String.init)
                var mapped: [String] = []
                var columnsSeen: [Int] = []
                for (offset, part) in parts.enumerated() {
                    let absolute = part.hasPrefix("$")
                    guard let column = CellAddress.columnIndex(part.replacingOccurrences(of: "$", with: "")) else {
                        mapped.append(part)
                        continue
                    }
                    let probe = FormulaRef(row: 0, column: column, absoluteRow: true, absoluteColumn: absolute)
                    guard let moved = transform(probe, unit.sheet, offset == 0 ? .rangeStart : .rangeEnd) else {
                        mapped.append("#REF!")
                        continue
                    }
                    columnsSeen.append(moved.column)
                    mapped.append((absolute ? "$" : "") + CellAddress.columnName(moved.column))
                }
                let crossed = columnsSeen.count == 2 && columnsSeen[1] < columnsSeen[0]
                replacement = mapped.contains("#REF!") || crossed ? "#REF!" : mapped.joined(separator: ":")
            } else if let endIndex = unit.end {
                guard let first = FormulaRef(token.text), let last = FormulaRef(tokens[endIndex].text) else { continue }
                if let a = transform(first, unit.sheet, .rangeStart), let b = transform(last, unit.sheet, .rangeEnd), b.row >= a.row, b.column >= a.column {
                    replacement = a.text + ":" + b.text
                } else {
                    replacement = "#REF!"
                }
            } else {
                guard let reference = FormulaRef(token.text) else { continue }
                replacement = transform(reference, unit.sheet, .single)?.text ?? "#REF!"
            }
            characters.replaceSubrange(unit.span, with: Array(replacement))
        }
        return "=" + String(characters)
    }

    /// The references a formula reads, on its own sheet (for highlighting them while you type).
    static func references(_ formula: String) -> [CellRange] {
        guard formula.hasPrefix("=") else { return [] }
        var ranges: [CellRange] = []
        func visit(_ expression: FormulaExpr) {
            switch expression {
            case .reference(let sheet, let reference) where sheet == nil:
                ranges.append(CellRange(reference.address))
            case .range(let sheet, let start, let end) where sheet == nil:
                ranges.append(CellRange(start.address, end.address))
            case .unary(_, let inner), .percent(let inner):
                visit(inner)
            case .binary(_, let left, let right):
                visit(left)
                visit(right)
            case .call(_, let arguments):
                arguments.forEach(visit)
            default:
                break
            }
        }
        visit(FormulaParser.parse(formula))
        return ranges
    }
}
