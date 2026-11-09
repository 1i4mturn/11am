import Foundation

/// Charts on slides that read from George's sheets: the numbers worked out from the workbook as it is now, and a
/// guess at which columns to use.
enum DeckCharts {
    /// The labels and numbers for a linked chart, or nil when the sheet or ranges aren't there any more.
    static func points(_ link: ChartLink, in workbook: Workbook) -> [ChartPoint]? {
        guard let sheet = workbook.sheetIndex(named: link.sheet), let labels = CellRange(link.labels.uppercased()),
              let values = CellRange(link.values.uppercased()) else { return nil }
        let engine = GridEngine(workbook)
        let labelCells = cells(labels)
        let valueCells = cells(values)
        guard !labelCells.isEmpty, labelCells.count == valueCells.count else { return nil }
        var points: [ChartPoint] = []
        for (labelCell, valueCell) in zip(labelCells, valueCells) {
            let label = engine.display(sheet: sheet, labelCell).trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty, let number = engine.value(sheet: sheet, valueCell).number else { continue }
            points.append(ChartPoint(label: label, value: number))
        }
        return points
    }

    /// The cells of a single row or column, in order.
    static func cells(_ range: CellRange) -> [CellAddress] {
        if range.start.column == range.end.column {
            return range.rows.map { CellAddress(row: $0, column: range.start.column) }
        }
        if range.start.row == range.end.row {
            return (range.start.column...range.end.column).map { CellAddress(row: range.start.row, column: $0) }
        }
        return []
    }

    /// The first column of words and the first column of numbers beside it, below a header row: what most tables look like.
    static func suggest(_ workbook: Workbook, sheet name: String) -> (labels: String, values: String)? {
        guard let index = workbook.sheetIndex(named: name), let used = workbook.sheets[index].usedRange else { return nil }
        let engine = GridEngine(workbook)
        let firstRow = used.start.row
        // A header row if the first row is all words.
        let header = (used.start.column...used.end.column).allSatisfy { column in
            engine.value(sheet: index, CellAddress(row: firstRow, column: column)).number == nil
        }
        let top = header ? firstRow + 1 : firstRow
        guard top <= used.end.row else { return nil }
        var bottom = used.end.row
        func isNumber(_ row: Int, _ column: Int) -> Bool { engine.value(sheet: index, CellAddress(row: row, column: column)).number != nil }
        func isWords(_ row: Int, _ column: Int) -> Bool {
            let value = engine.value(sheet: index, CellAddress(row: row, column: column))
            return value.number == nil && !value.isEmpty
        }
        guard let labelColumn = (used.start.column...used.end.column).first(where: { column in
            (top...bottom).filter { isWords($0, column) }.count * 2 >= (bottom - top + 1)
        }) else { return nil }
        guard labelColumn < used.end.column, let valueColumn = ((labelColumn + 1)...used.end.column).first(where: { column in
            (top...bottom).filter { isNumber($0, column) }.count * 2 >= (bottom - top + 1)
        }) else { return nil }
        // Stop before a total row ("Total", "Sum") so it doesn't dwarf the rest.
        while bottom > top {
            let label = engine.display(sheet: index, CellAddress(row: bottom, column: labelColumn)).lowercased()
            if label.hasPrefix("total") || label == "sum" || label.isEmpty { bottom -= 1 } else { break }
        }
        let labels = CellRange(CellAddress(row: top, column: labelColumn), CellAddress(row: bottom, column: labelColumn))
        let values = CellRange(CellAddress(row: top, column: valueColumn), CellAddress(row: bottom, column: valueColumn))
        return (labels.start.a1 + ":" + labels.end.a1, values.start.a1 + ":" + values.end.a1)
    }

    /// The header above the numbers, for the chart's title.
    static func heading(_ workbook: Workbook, sheet name: String, values: String) -> String? {
        guard let index = workbook.sheetIndex(named: name), let range = CellRange(values.uppercased()), range.start.row > 0 else { return nil }
        let text = GridEngine(workbook).display(sheet: index, CellAddress(row: range.start.row - 1, column: range.start.column))
        return text.isEmpty ? nil : text
    }
}

extension SlideDeck {
    /// Every linked chart brought up to date from the workbooks it can find. Returns how many changed.
    @discardableResult
    mutating func refreshCharts(from workbook: (String) -> Workbook?, now: Date = Date()) -> Int {
        var changed = 0
        for index in slides.indices {
            guard let link = slides[index].content.link, let book = workbook(link.workbook),
                  let points = DeckCharts.points(link, in: book) else { continue }
            if points != slides[index].content.chart {
                slides[index].content.chart = points
                // Laid out again with the new bars, unless it was arranged by hand.
                if !slides[index].customised {
                    slides[index].canvas = DeckLayoutEngine.canvas(slides[index].layout, slides[index].content, theme)
                }
                changed += 1
            }
            slides[index].content.link?.updated = now
        }
        return changed
    }
}

extension CanvasDocument {
    /// Every linked chart on the design drawn again from Sheets. Returns how many changed.
    @discardableResult
    mutating func refreshCharts(from workbook: (String) -> Workbook?, now: Date = Date()) -> Int {
        var changed = 0
        for frame in chartFrames {
            guard var chart = frame.chart, let link = chart.link, let book = workbook(link.workbook),
                  let points = DeckCharts.points(link, in: book) else { continue }
            chart.link?.updated = now
            if points != chart.points {
                chart.points = points
                redrawChart(frame.id, chart: chart)
                changed += 1
            } else if let index = index(of: frame.id) {
                layers[index].chart = chart
            }
        }
        return changed
    }
}
