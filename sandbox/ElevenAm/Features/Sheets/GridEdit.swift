import Foundation

/// Changes to a workbook that keep formulas pointing at the right cells.
enum GridEdit {
    // MARK: Fill

    /// Drags `source` out over `target` (which contains it): numbers and dates continue their step, "Item 1" counts up,
    /// month and day names follow on, formulas move their relative references, anything else repeats.
    static func fill(_ sheet: inout GridSheet, from source: CellRange, to target: CellRange) {
        let down = target.rowCount > source.rowCount
        if down {
            for column in source.columns {
                let cells = source.rows.map { sheet[CellAddress(row: $0, column: column)] }
                let filled = series(cells, count: target.rowCount - source.rowCount, forward: target.end.row > source.end.row)
                for (offset, cell) in filled.enumerated() {
                    let row = target.end.row > source.end.row ? source.end.row + 1 + offset : source.start.row - 1 - offset
                    let origin = source.rows.lowerBound + (offset % source.rowCount)
                    sheet[CellAddress(row: row, column: column)] = shifted(cell, rows: row - origin, columns: 0)
                }
            }
        } else {
            for row in source.rows {
                let cells = source.columns.map { sheet[CellAddress(row: row, column: $0)] }
                let filled = series(cells, count: target.columnCount - source.columnCount, forward: target.end.column > source.end.column)
                for (offset, cell) in filled.enumerated() {
                    let column = target.end.column > source.end.column ? source.end.column + 1 + offset : source.start.column - 1 - offset
                    let origin = source.columns.lowerBound + (offset % source.columnCount)
                    sheet[CellAddress(row: row, column: column)] = shifted(cell, rows: 0, columns: column - origin)
                }
            }
        }
    }

    private static func shifted(_ cell: GridCell, rows: Int, columns: Int) -> GridCell {
        guard cell.input.hasPrefix("=") else { return cell }
        var copy = cell
        copy.input = FormulaRewrite.shift(cell.input, rows: rows, columns: columns)
        return copy
    }

    static let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
    static let days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

    /// The next `count` cells after (or before) a run; formulas are returned unshifted (the caller moves them).
    static func series(_ cells: [GridCell], count: Int, forward: Bool) -> [GridCell] {
        guard !cells.isEmpty, count > 0 else { return [] }
        let values = cells.map { GridInput.interpret($0.input) }
        let numbers = values.compactMap { value -> Double? in if case .number(let number) = value.value, !value.0.isEmpty { return number }; return nil }
        let allNumbers = numbers.count == cells.count && !cells.contains { $0.input.hasPrefix("=") }

        if allNumbers {
            // One number repeats, unless it's a date (dates go up a day); two or more continue the trend.
            let isDate = values.first?.format?.isDate == true
            let step: Double
            if numbers.count >= 2 {
                step = (numbers[numbers.count - 1] - numbers[0]) / Double(numbers.count - 1)
            } else {
                step = isDate ? 1 : 0
            }
            let format = values.first?.format
            return (1...count).map { offset in
                let value = forward ? numbers[numbers.count - 1] + step * Double(offset) : numbers[0] - step * Double(offset)
                var cell = cells[forward ? cells.count - 1 : 0]
                cell.input = render(value, format: format)
                return cell
            }
        }

        // Text with a number at the end: "Week 1", "Q2".
        if cells.count >= 1, cells.allSatisfy({ !$0.input.hasPrefix("=") }), let last = cells.last,
           let match = last.input.range(of: #"\d+$"#, options: .regularExpression) {
            let prefix = String(last.input[..<match.lowerBound])
            if let start = Int(last.input[match]), cells.allSatisfy({ $0.input.hasPrefix(prefix) }) {
                let first = Int(cells[0].input.dropFirst(prefix.count)) ?? start
                let step = cells.count >= 2 ? (start - first) / max(cells.count - 1, 1) : 1
                return (1...count).map { offset in
                    var cell = last
                    cell.input = prefix + String(forward ? start + step * offset : first - step * offset)
                    return cell
                }
            }
        }

        // Month and day names, full or short.
        for names in [months, days] {
            if let last = cells.last?.input.lowercased(), let index = names.firstIndex(where: { $0 == last || $0.prefix(3) == last }) {
                let short = (cells.last?.input.count ?? 0) <= 3
                let capitalised = cells.last?.input.first?.isUppercase ?? true
                return (1...count).map { offset in
                    let position = ((index + (forward ? offset : -offset)) % names.count + names.count) % names.count
                    var name = short ? String(names[position].prefix(3)) : names[position]
                    if capitalised { name = name.capitalized }
                    var cell = cells[cells.count - 1]
                    cell.input = name
                    return cell
                }
            }
        }

        // Anything else repeats the pattern.
        return (0..<count).map { offset in
            forward ? cells[offset % cells.count] : cells[cells.count - 1 - offset % cells.count]
        }
    }

    /// Writes a number back as something the user could have typed, in its format.
    static func render(_ value: Double, format: NumberFormat?) -> String {
        guard let format else { return GridDisplay.general(value) }
        switch format {
        case .percent(let places): return GridDisplay.fixed(value * 100, places: places) + "%"
        case .currency(let places): return (value < 0 ? "-$" : "$") + GridDisplay.grouped(abs(value), places: places)
        case .number(let places): return GridDisplay.grouped(value, places: places)
        case .date: return GridDisplay.dateText(value, "d MMM yyyy")
        case .shortDate: return GridDisplay.dateText(value, "d/M/yyyy")
        default: return GridDisplay.general(value)
        }
    }

    // MARK: Rows and columns

    /// Inserts (count > 0) or deletes (count < 0) rows or columns at `index` on one sheet, and fixes every formula in
    /// the workbook that points there.
    static func insert(_ workbook: inout Workbook, sheet: Int, rows: Bool, at index: Int, count: Int) {
        guard workbook.sheets.indices.contains(sheet), count != 0 else { return }
        let name = workbook.sheets[sheet].name
        var moved: [CellAddress: GridCell] = [:]
        for (address, cell) in workbook.sheets[sheet].cells {
            let position = rows ? address.row : address.column
            var target = address
            if count > 0 {
                if position >= index { target = rows ? address.offset(rows: count, columns: 0) : address.offset(rows: 0, columns: count) }
            } else {
                if position >= index && position < index - count { continue }
                if position >= index - count { target = rows ? address.offset(rows: count, columns: 0) : address.offset(rows: 0, columns: count) }
            }
            moved[target] = cell
        }
        workbook.sheets[sheet].cells = moved
        if !rows {
            var widths: [Int: Double] = [:]
            for (column, width) in workbook.sheets[sheet].columnWidths {
                if count > 0 { widths[column >= index ? column + count : column] = width }
                else if column < index { widths[column] = width }
                else if column >= index - count { widths[column + count] = width }
            }
            workbook.sheets[sheet].columnWidths = widths
        }
        for sheetIndex in workbook.sheets.indices {
            for (address, cell) in workbook.sheets[sheetIndex].cells where cell.input.hasPrefix("=") {
                let updated = FormulaRewrite.insert(cell.input, rows: rows, at: index, count: count, sameSheet: sheetIndex == sheet, target: name)
                if updated != cell.input { workbook.sheets[sheetIndex].cells[address]?.input = updated }
            }
            for position in workbook.sheets[sheetIndex].charts.indices where sheetIndex == sheet {
                workbook.sheets[sheetIndex].charts[position].range = shift(workbook.sheets[sheetIndex].charts[position].range, rows: rows, at: index, count: count)
            }
        }
        // Conditional formatting, validation and comments move with their cells.
        for position in workbook.sheets[sheet].rules.indices {
            workbook.sheets[sheet].rules[position].range = shift(workbook.sheets[sheet].rules[position].range, rows: rows, at: index, count: count)
        }
        for position in workbook.sheets[sheet].validations.indices {
            workbook.sheets[sheet].validations[position].range = shift(workbook.sheets[sheet].validations[position].range, rows: rows, at: index, count: count)
        }
        workbook.sheets[sheet].comments = workbook.sheets[sheet].comments.compactMap { comment in
            var moved = comment
            let position = rows ? comment.address.row : comment.address.column
            guard position >= index else { return moved }
            if count < 0 && position < index - count { return nil }
            moved.address = rows ? comment.address.offset(rows: count, columns: 0) : comment.address.offset(rows: 0, columns: count)
            return moved
        }
    }

    private static func shift(_ range: CellRange, rows: Bool, at index: Int, count: Int) -> CellRange {
        func move(_ address: CellAddress) -> CellAddress {
            let position = rows ? address.row : address.column
            guard position >= index else { return address }
            let updated = max(index, position + count)
            return rows ? CellAddress(row: updated, column: address.column) : CellAddress(row: address.row, column: updated)
        }
        return CellRange(move(range.start), move(range.end))
    }

    // MARK: Sorting

    /// Sorts the rows of `range` by one column (numbers before text, blanks last). Formulas move with their rows.
    static func sort(_ workbook: inout Workbook, sheet: Int, range: CellRange, by column: Int, ascending: Bool, header: Bool) {
        let engine = GridEngine(workbook)
        let bodyRows = Array(range.rows.dropFirst(header ? 1 : 0))
        guard bodyRows.count > 1 else { return }
        let keyed = bodyRows.map { row in (row, engine.value(sheet: sheet, CellAddress(row: row, column: column))) }
        let sorted = keyed.sorted { a, b in
            if a.1 == .empty { return false }
            if b.1 == .empty { return true }
            let order = GridEngine.compare(a.1, b.1)
            return order == 0 ? a.0 < b.0 : (ascending ? order < 0 : order > 0)
        }
        let original = workbook.sheets[sheet]
        for (offset, entry) in sorted.enumerated() {
            let destination = bodyRows[offset]
            for column in range.columns {
                let from = CellAddress(row: entry.0, column: column)
                var cell = original[from]
                if cell.input.hasPrefix("=") { cell.input = FormulaRewrite.shift(cell.input, rows: destination - entry.0, columns: 0) }
                workbook.sheets[sheet][CellAddress(row: destination, column: column)] = cell
            }
        }
    }

    // MARK: Copy and paste

    /// Cells as tab-separated text, the way other apps paste them.
    static func tsv(_ engine: GridEngine, sheet: Int, range: CellRange) -> String {
        range.rows.map { row in
            range.columns.map { engine.display(sheet: sheet, CellAddress(row: row, column: $0)) }.joined(separator: "\t")
        }.joined(separator: "\n")
    }

    /// Pastes cells copied inside 11am (formulas move with them) at `destination`.
    static func paste(_ cells: [[GridCell]], from origin: CellAddress, into sheet: inout GridSheet, at destination: CellAddress) {
        for (rowOffset, row) in cells.enumerated() {
            for (columnOffset, cell) in row.enumerated() {
                let target = CellAddress(row: destination.row + rowOffset, column: destination.column + columnOffset)
                var copy = cell
                if copy.input.hasPrefix("=") {
                    copy.input = FormulaRewrite.shift(cell.input, rows: destination.row - origin.row, columns: destination.column - origin.column)
                }
                sheet[target] = copy
            }
        }
    }

    /// Pastes text from another app: tabs or commas between cells, one row per line.
    static func paste(text: String, into sheet: inout GridSheet, at destination: CellAddress) -> CellRange {
        let rows = GridCSV.parse(text, delimiter: text.contains("\t") ? "\t" : (text.contains("\n") || text.contains(",") ? "," : "\t"))
        for (rowOffset, row) in rows.enumerated() {
            for (columnOffset, value) in row.enumerated() {
                sheet[CellAddress(row: destination.row + rowOffset, column: destination.column + columnOffset)].input = value
            }
        }
        let height = max(rows.count, 1), width = max(rows.map(\.count).max() ?? 1, 1)
        return CellRange(destination, CellAddress(row: destination.row + height - 1, column: destination.column + width - 1))
    }

    // MARK: Summaries

    enum Summary: String, CaseIterable, Identifiable {
        case sum, count, average, min, max

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    /// A pivot of one table: one row per value in `group`, the `summary` of `value` for each, sorted biggest first,
    /// as a new sheet with formulas, so it stays live.
    static func summarise(_ workbook: Workbook, sheet: Int, range: CellRange, group: Int, value: Int, summary: Summary) -> GridSheet {
        let engine = GridEngine(workbook)
        let source = workbook.sheets[sheet]
        let headerGroup = engine.display(sheet: sheet, CellAddress(row: range.start.row, column: group))
        let headerValue = engine.display(sheet: sheet, CellAddress(row: range.start.row, column: value))
        var keys: [String] = []
        for row in range.rows.dropFirst() {
            let key = engine.display(sheet: sheet, CellAddress(row: row, column: group))
            if !key.isEmpty && !keys.contains(key) { keys.append(key) }
        }
        var result = GridSheet(name: "\(headerValue.isEmpty ? "Summary" : headerValue) by \(headerGroup.isEmpty ? "group" : headerGroup)")
        result.frozenRows = 1
        result[CellAddress(row: 0, column: 0)] = GridCell(input: headerGroup.isEmpty ? "Group" : headerGroup, format: CellFormat(bold: true))
        result[CellAddress(row: 0, column: 1)] = GridCell(input: "\(summary.title) of \(headerValue.isEmpty ? "value" : headerValue)", format: CellFormat(bold: true))
        let quoted = "'" + source.name.replacingOccurrences(of: "'", with: "''") + "'!"
        // Absolute, so sorting the summary (which moves its formulas) keeps pointing at the whole table.
        func absolute(_ column: Int) -> String {
            let letter = CellAddress.columnName(column)
            return "$\(letter)$\(range.start.row + 2):$\(letter)$\(range.end.row + 1)"
        }
        let groupRange = quoted + absolute(group)
        let valueRange = quoted + absolute(value)
        let format = engine.format(sheet: sheet, CellAddress(row: range.start.row + 1, column: value))
        for (offset, key) in keys.enumerated() {
            let row = offset + 1
            result[CellAddress(row: row, column: 0)] = GridCell(input: key)
            let criterion = "A\(row + 1)"
            let formula: String
            switch summary {
            case .sum: formula = "=SUMIFS(\(valueRange),\(groupRange),\(criterion))"
            case .count: formula = "=COUNTIFS(\(groupRange),\(criterion))"
            case .average: formula = "=AVERAGEIFS(\(valueRange),\(groupRange),\(criterion))"
            case .min: formula = "=MINIFS(\(valueRange),\(groupRange),\(criterion))"
            case .max: formula = "=MAXIFS(\(valueRange),\(groupRange),\(criterion))"
            }
            result[CellAddress(row: row, column: 1)] = GridCell(input: formula, format: summary == .count ? nil : CellFormat(number: format))
        }
        let totalRow = keys.count + 1
        result[CellAddress(row: totalRow, column: 0)] = GridCell(input: "Total", format: CellFormat(bold: true))
        if summary == .sum || summary == .count {
            result[CellAddress(row: totalRow, column: 1)] = GridCell(input: "=SUM(B2:B\(totalRow))", format: CellFormat(number: summary == .count ? .general : format, bold: true))
        }
        result.columnWidths = [0: 180, 1: 150]
        // Biggest first, as a starting point.
        var book = workbook
        book.sheets.append(result)
        if keys.count > 1 {
            sort(&book, sheet: book.sheets.count - 1, range: CellRange(CellAddress(row: 1, column: 0), CellAddress(row: keys.count, column: 1)),
                 by: 1, ascending: false, header: false)
        }
        return book.sheets[book.sheets.count - 1]
    }
}

// MARK: CSV

enum GridCSV {
    static func parse(_ text: String, delimiter: Character? = nil) -> [[String]] {
        let separator = delimiter ?? guessDelimiter(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var characters = Array(text)
        if characters.first == "\u{FEFF}" { characters.removeFirst() }
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if quoted {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" && field.isEmpty {
                quoted = true
            } else if character == separator {
                row.append(field)
                field = ""
            } else if character == "\n" || character == "\r\n" || character == "\r" {
                row.append(field)
                field = ""
                rows.append(row)
                row = []
            } else {
                field.append(character)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private static func guessDelimiter(_ text: String) -> Character {
        let firstLine = text.split(separator: "\n", maxSplits: 1).first ?? ""
        let counts: [(Character, Int)] = [(",", firstLine.filter { $0 == "," }.count), ("\t", firstLine.filter { $0 == "\t" }.count), (";", firstLine.filter { $0 == ";" }.count)]
        return counts.max { $0.1 < $1.1 }.flatMap { $0.1 > 0 ? $0.0 : nil } ?? ","
    }

    static func sheet(from text: String, name: String) -> GridSheet {
        var sheet = GridSheet(name: name)
        for (row, values) in parse(text).enumerated() {
            for (column, value) in values.enumerated() where !value.isEmpty {
                sheet[CellAddress(row: row, column: column)] = GridCell(input: value)
            }
        }
        if let header = parse(text).first, header.allSatisfy({ !$0.isEmpty && Double($0) == nil }) {
            sheet.frozenRows = 1
            for column in header.indices { sheet[CellAddress(row: 0, column: column)].format = CellFormat(bold: true) }
        }
        return sheet
    }

    /// What you see, as CSV.
    static func text(_ engine: GridEngine, sheet: Int) -> String {
        guard let used = engine.workbook.sheets[sheet].usedRange else { return "" }
        return used.rows.map { row in
            used.columns.map { column -> String in
                let value = engine.display(sheet: sheet, CellAddress(row: row, column: column))
                return value.contains(",") || value.contains("\"") || value.contains("\n") ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : value
            }.joined(separator: ",")
        }.joined(separator: "\n") + "\n"
    }
}
