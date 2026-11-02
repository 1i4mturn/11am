import AppKit
import SwiftUI

/// The grid's colours, from the theme.
struct GridStyle: Equatable {
    var paper: NSColor
    var ink: NSColor
    var secondary: NSColor
    var line: NSColor
    var header: NSColor
    var selection: NSColor

    @MainActor
    static func from(_ theme: Theme, _ scheme: ColorScheme) -> GridStyle {
        let paper = NSColor(theme.paper(scheme))
        let ink = NSColor(theme.ink(scheme))
        let dark = scheme == .dark
        return GridStyle(
            paper: paper,
            ink: ink,
            secondary: ink.withAlphaComponent(0.55),
            line: ink.withAlphaComponent(dark ? 0.12 : 0.085),
            header: paper.blended(withFraction: dark ? 0.06 : 0.035, of: dark ? .white : .black) ?? paper,
            selection: ink.withAlphaComponent(dark ? 0.12 : 0.07)
        )
    }
}

enum GridColor {
    /// "#RRGGBB" to a colour.
    static func ns(_ hex: String?) -> NSColor? {
        guard var text = hex?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 8 { text = String(text.suffix(6)) }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    static func swiftUI(_ hex: String?) -> Color? { ns(hex).map(Color.init(nsColor:)) }
}

/// The spreadsheet itself: an AppKit view in a scroll view, drawing only what's on screen.
struct GridCanvas: NSViewRepresentable {
    @ObservedObject var model: SheetsModel
    var style: GridStyle

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let grid = GridView()
        grid.model = model
        grid.style = style
        scroll.documentView = grid
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(grid, selector: #selector(GridView.clipChanged), name: NSView.boundsDidChangeNotification,
                                               object: scroll.contentView)
        NotificationCenter.default.addObserver(grid, selector: #selector(GridView.clipChanged), name: NSView.frameDidChangeNotification,
                                               object: scroll.contentView)
        grid.sync(force: true)
        DispatchQueue.main.async { grid.window?.makeFirstResponder(grid) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let grid = scroll.documentView as? GridView else { return }
        grid.model = model
        if grid.style != style { grid.style = style }
        grid.sync(force: false)
    }
}

/// A text field laid over a cell while you type in it.
final class GridEditorField: NSTextField {
    override var acceptsFirstResponder: Bool { true }
}

final class GridView: NSView, NSTextFieldDelegate {
    weak var model: SheetsModel?
    var style = GridStyle(paper: .white, ink: .black, secondary: .gray, line: .lightGray, header: .white, selection: .lightGray) {
        didSet {
            needsDisplay = true
            styleEditor()
        }
    }

    private let rowHeight: CGFloat = 24
    private let headerHeight: CGFloat = 24
    private let headerWidth: CGFloat = 46
    private var columnX: [CGFloat] = [46]
    private var rowCount = 200
    private var columnCount = 26

    private var seenRevision = -1
    private var seenSheet = -1
    private var seenActive = CellAddress(row: -1, column: -1)
    private var seenExtent = CellAddress(row: -1, column: -1)
    private var seenEditRequest = 0
    private var seenFocusRequest = 0

    private var editor: GridEditorField?
    private var editing: CellAddress?
    private var enterMode = false
    /// The reference George-style point mode last put in the formula being typed, so a new click replaces it.
    private var referenceRange: NSRange?
    private var referenceStart: CellAddress?

    private enum Drag { case none, cells, columns, rows, fill, resize, reference }
    private var drag: Drag = .none
    private var resizing: (column: Int, origin: CGFloat, start: CGFloat, width: CGFloat)?
    private var fillTarget: CellRange?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { editing == nil || !wantsReference }
    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }
    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    private var sheet: GridSheet? { model?.sheet }
    private var frozen: Int { min(sheet?.frozenRows ?? 0, 50) }

    // MARK: Keeping up with the model

    func sync(force: Bool) {
        guard let model else { return }
        let changed = force || model.revision != seenRevision || model.sheetIndex != seenSheet
        let moved = model.active != seenActive || model.extent != seenExtent
        if model.sheetIndex != seenSheet, editing != nil { cancelEdit() }
        if changed {
            seenRevision = model.revision
            seenSheet = model.sheetIndex
            updateSize()
            needsDisplay = true
        }
        if moved {
            seenActive = model.active
            seenExtent = model.extent
            ensureRows(for: model.extent)
            reveal(model.extent)
            needsDisplay = true
        }
        if model.editRequest != seenEditRequest {
            seenEditRequest = model.editRequest
            beginEditing(initial: nil, enterMode: false)
        }
        if model.focusRequest != seenFocusRequest {
            seenFocusRequest = model.focusRequest
            if editing == nil { window?.makeFirstResponder(self) }
        }
    }

    @objc func clipChanged() {
        needsDisplay = true
        positionEditor()
        if let superview, frame.width < superview.bounds.width || frame.height < superview.bounds.height { updateSize() }
    }

    private func ensureRows(for address: CellAddress) {
        if address.row + 30 > rowCount || address.column + 4 > columnCount { updateSize(minimum: address) }
    }

    func updateSize(minimum: CellAddress? = nil) {
        let used = sheet?.usedRange?.end ?? CellAddress(row: 0, column: 0)
        rowCount = max(used.row + 60, 200, (minimum?.row ?? 0) + 60)
        columnCount = max(used.column + 8, 26, (minimum?.column ?? 0) + 8)
        var xs: [CGFloat] = [headerWidth]
        xs.reserveCapacity(columnCount + 1)
        for column in 0..<columnCount { xs.append(xs[column] + width(column)) }
        columnX = xs
        let clip = superview?.bounds.size ?? .zero
        let size = NSSize(width: max(xs[xs.count - 1] + 40, clip.width), height: max(headerHeight + CGFloat(rowCount) * rowHeight, clip.height))
        if frame.size != size { setFrameSize(size) }
        needsDisplay = true
    }

    private func width(_ column: Int) -> CGFloat {
        if let resizing, resizing.column == column { return resizing.width }
        return CGFloat(sheet?.width(of: column) ?? 100)
    }

    // MARK: Geometry

    private func x(_ column: Int) -> CGFloat {
        if column < columnX.count { return columnX[max(0, column)] }
        return columnX[columnX.count - 1] + CGFloat(column - (columnX.count - 1)) * 100
    }

    private func column(at position: CGFloat) -> Int {
        guard position > headerWidth else { return 0 }
        let last = columnX.count - 1
        if position >= columnX[last] { return last + Int((position - columnX[last]) / 100) }
        var low = 0, high = last
        while low < high - 1 {
            let middle = (low + high) / 2
            if columnX[middle] <= position { low = middle } else { high = middle }
        }
        return low
    }

    private func rowTop(_ row: Int) -> CGFloat {
        row < frozen ? visibleRect.minY + headerHeight + CGFloat(row) * rowHeight : headerHeight + CGFloat(row) * rowHeight
    }

    private func cellRect(_ address: CellAddress) -> NSRect {
        NSRect(x: x(address.column), y: rowTop(address.row), width: x(address.column + 1) - x(address.column), height: rowHeight)
    }

    private func rangeRect(_ range: CellRange) -> NSRect {
        cellRect(range.start).union(cellRect(range.end))
    }

    private var bandBottom: CGFloat { visibleRect.minY + headerHeight + CGFloat(frozen) * rowHeight }

    private func row(at y: CGFloat) -> Int {
        if frozen > 0 && y < bandBottom { return max(0, min(frozen - 1, Int((y - visibleRect.minY - headerHeight) / rowHeight))) }
        return max(frozen, Int((y - headerHeight) / rowHeight))
    }

    private func address(at point: NSPoint) -> CellAddress {
        CellAddress(row: row(at: max(point.y, visibleRect.minY + headerHeight)), column: column(at: max(point.x, visibleRect.minX + headerWidth + 1)))
    }

    private enum Hit { case corner, column(Int), columnEdge(Int), row(Int), cell(CellAddress), fill }

    private func hit(_ point: NSPoint) -> Hit {
        let visible = visibleRect
        let inColumnHeader = point.y < visible.minY + headerHeight
        let inRowHeader = point.x < visible.minX + headerWidth
        if inColumnHeader && inRowHeader { return .corner }
        if inColumnHeader {
            let found = column(at: point.x)
            if abs(point.x - x(found + 1)) <= 4 { return .columnEdge(found) }
            if found > 0 && abs(point.x - x(found)) <= 4 { return .columnEdge(found - 1) }
            return .column(found)
        }
        if inRowHeader { return .row(row(at: point.y)) }
        if let model, editing == nil {
            let selection = rangeRect(model.selection)
            let handle = NSRect(x: selection.maxX - 5, y: selection.maxY - 5, width: 9, height: 9)
            if handle.contains(point) { return .fill }
        }
        return .cell(address(at: point))
    }

    private func reveal(_ address: CellAddress) {
        // Before the first layout the view has no size, and scrolling then would jump to the cell.
        guard visibleRect.width > 80, visibleRect.height > 80 else { return }
        var rect = NSRect(x: x(address.column) - headerWidth, y: headerHeight + CGFloat(address.row) * rowHeight,
                          width: x(address.column + 1) - x(address.column) + headerWidth, height: rowHeight)
        if address.row >= frozen {
            let top = headerHeight + CGFloat(frozen) * rowHeight
            rect.origin.y -= top
            rect.size.height += top
        } else {
            rect.origin.y = visibleRect.minY
            rect.size.height = 1
        }
        scrollToVisible(rect)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        style.paper.setFill()
        dirtyRect.fill()
        guard let model, let sheet = model.sheet else { return }
        let visible = visibleRect
        let firstColumn = column(at: visible.minX + headerWidth + 1)
        let lastColumn = max(firstColumn, column(at: visible.maxX))
        let columns = firstColumn...lastColumn
        let firstRow = max(frozen, Int((bandBottom - headerHeight) / rowHeight))
        let lastRow = max(firstRow, Int((visible.maxY - headerHeight) / rowHeight))
        let body = NSRect(x: visible.minX + headerWidth, y: bandBottom, width: visible.width - headerWidth, height: max(0, visible.maxY - bandBottom))
        drawCells(rows: firstRow...lastRow, columns: columns, sheet: sheet, model: model, clip: body)
        drawMarks(model: model, clip: body)
        if frozen > 0 {
            let band = NSRect(x: visible.minX + headerWidth, y: visible.minY + headerHeight, width: visible.width - headerWidth, height: CGFloat(frozen) * rowHeight)
            style.paper.setFill()
            band.fill()
            drawCells(rows: 0...(frozen - 1), columns: columns, sheet: sheet, model: model, clip: band)
            drawMarks(model: model, clip: band)
            style.secondary.withAlphaComponent(0.35).setFill()
            NSRect(x: band.minX, y: band.maxY - 1, width: band.width, height: 1).fill()
        }
        drawHeaders(columns: columns, rows: firstRow...lastRow, model: model)
    }

    private func drawCells(rows: ClosedRange<Int>, columns: ClosedRange<Int>, sheet: GridSheet, model: SheetsModel, clip: NSRect) {
        guard clip.height > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: clip).addClip()

        // Fills
        for row in rows {
            for column in columns {
                let address = CellAddress(row: row, column: column)
                if let fill = GridColor.ns(sheet.cells[address]?.format?.fill) {
                    fill.setFill()
                    cellRect(address).fill()
                }
            }
        }
        // Lines
        style.line.setFill()
        let left = x(columns.lowerBound), right = x(columns.upperBound + 1)
        for row in rows {
            NSRect(x: left, y: rowTop(row) + rowHeight - 1, width: right - left, height: 1).fill()
        }
        let top = rowTop(rows.lowerBound), bottom = rowTop(rows.upperBound) + rowHeight
        for column in columns {
            NSRect(x: x(column + 1) - 1, y: top, width: 1, height: bottom - top).fill()
        }
        // Text
        let engine = model.engine
        let sheetIndex = model.sheetIndex
        for row in rows {
            for column in columns {
                let address = CellAddress(row: row, column: column)
                guard let cell = sheet.cells[address], !cell.input.isEmpty else { continue }
                drawText(cell: cell, at: address, engine: engine, sheetIndex: sheetIndex, sheet: sheet, lastVisible: columns.upperBound)
            }
        }
    }

    private static let lineHeight: CGFloat = 15

    private func drawText(cell: GridCell, at address: CellAddress, engine: GridEngine, sheetIndex: Int, sheet: GridSheet, lastVisible: Int) {
        let value = engine.value(sheet: sheetIndex, address)
        var text = engine.display(sheet: sheetIndex, address)
        guard !text.isEmpty else { return }
        let format = cell.format ?? CellFormat()
        let isNumber: Bool
        if case .number = value { isNumber = true } else { isNumber = false }
        var font = isNumber ? NSFont.monospacedDigitSystemFont(ofSize: 12, weight: format.bold ? .semibold : .regular)
                            : NSFont.systemFont(ofSize: 12, weight: format.bold ? .semibold : .regular)
        if format.italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        var color = GridColor.ns(format.color) ?? style.ink
        // On a filled cell, pick ink that reads on the fill (a light fill in dark mode gets dark text).
        if format.color == nil, let fill = GridColor.ns(format.fill), let rgb = fill.usingColorSpace(.sRGB) {
            let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
            color = luminance > 0.55 ? NSColor(white: 0.1, alpha: 1) : NSColor(white: 0.96, alpha: 1)
        }
        if case .error = value { color = style.secondary }
        let alignment: NSTextAlignment
        switch format.alignment {
        case .left: alignment = .left
        case .center: alignment = .center
        case .right: alignment = .right
        case nil:
            switch value {
            case .number: alignment = .right
            case .bool, .error: alignment = .center
            default: alignment = .left
            }
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        var rect = cellRect(address)
        let textWidth = (text as NSString).size(withAttributes: attributes).width
        if isNumber && textWidth > rect.width - 8 {
            let hash = ("#" as NSString).size(withAttributes: attributes).width
            text = String(repeating: "#", count: max(1, Int((rect.width - 8) / max(hash, 1))))
        } else if !isNumber && alignment == .left && textWidth > rect.width - 10 {
            // Long text runs on into empty cells to its right, as in Excel.
            var end = address.column
            while textWidth > x(end + 1) - rect.minX - 10, end < lastVisible + 8,
                  sheet.input(CellAddress(row: address.row, column: end + 1)).isEmpty {
                end += 1
                let neighbour = CellAddress(row: address.row, column: end)
                (GridColor.ns(sheet.cells[neighbour]?.format?.fill) ?? style.paper).setFill()
                NSRect(x: x(end) - 1, y: rect.minY, width: 1, height: rowHeight - 1).fill()
            }
            rect.size.width = x(end + 1) - rect.minX
        }
        let inset = rect.insetBy(dx: 5, dy: 0)
        let drawRect = NSRect(x: inset.minX, y: rect.minY + (rowHeight - Self.lineHeight) / 2 - 0.5, width: inset.width, height: Self.lineHeight + 1)
        (text as NSString).draw(with: drawRect, options: [.usesLineFragmentOrigin], attributes: attributes)
    }

    /// Selection, fill handle, copy marquee.
    private func drawMarks(model: SheetsModel, clip: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: clip).addClip()
        let focused = window?.firstResponder === self || editing != nil
        let accent = focused ? style.ink : style.secondary
        let selection = rangeRect(model.selection)
        if !model.selection.isSingleCell {
            let path = NSBezierPath(rect: selection)
            path.append(NSBezierPath(rect: cellRect(model.active)))
            path.windingRule = .evenOdd
            style.selection.setFill()
            path.fill()
        }
        accent.setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: 0, dy: 0).offsetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 2
        border.stroke()
        if editing == nil {
            let handle = NSRect(x: selection.maxX - 4, y: selection.maxY - 4, width: 7, height: 7)
            style.paper.setFill()
            handle.insetBy(dx: -1, dy: -1).fill()
            accent.setFill()
            handle.fill()
        }
        if let fillTarget, fillTarget != model.selection {
            let dashed = NSBezierPath(rect: rangeRect(fillTarget).insetBy(dx: 0.5, dy: 0.5))
            dashed.lineWidth = 1
            dashed.setLineDash([4, 3], count: 2, phase: 0)
            style.ink.setStroke()
            dashed.stroke()
        }
        if let copied = model.clip, copied.sheetID == sheet?.id {
            let marquee = NSBezierPath(rect: rangeRect(copied.range).insetBy(dx: 1, dy: 1))
            marquee.lineWidth = 1.5
            marquee.setLineDash([5, 3], count: 2, phase: 0)
            style.ink.withAlphaComponent(0.7).setStroke()
            marquee.stroke()
        }
    }

    private func drawHeaders(columns: ClosedRange<Int>, rows: ClosedRange<Int>, model: SheetsModel) {
        let visible = visibleRect
        let selection = model.selection
        let font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        let strong = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center

        // Column letters
        let band = NSRect(x: visible.minX, y: visible.minY, width: visible.width, height: headerHeight)
        style.header.setFill()
        band.fill()
        for column in columns {
            let rect = NSRect(x: x(column), y: visible.minY, width: x(column + 1) - x(column), height: headerHeight)
            let selected = selection.columns.contains(column)
            if selected {
                style.selection.setFill()
                rect.fill()
            }
            style.line.setFill()
            NSRect(x: rect.maxX - 1, y: rect.minY + 5, width: 1, height: rect.height - 10).fill()
            let label = CellAddress.columnName(column) as NSString
            label.draw(with: NSRect(x: rect.minX, y: rect.minY + 5, width: rect.width, height: 14), options: [.usesLineFragmentOrigin],
                       attributes: [.font: selected ? strong : font, .foregroundColor: selected ? style.ink : style.secondary, .paragraphStyle: centred])
        }
        style.line.setFill()
        NSRect(x: band.minX, y: band.maxY - 1, width: band.width, height: 1).fill()

        // Row numbers
        let side = NSRect(x: visible.minX, y: visible.minY + headerHeight, width: headerWidth, height: visible.height - headerHeight)
        style.header.setFill()
        side.fill()
        let shown = Array(0..<frozen) + Array(rows)
        for row in shown {
            let rect = NSRect(x: visible.minX, y: rowTop(row), width: headerWidth, height: rowHeight)
            if row >= frozen && rect.minY < bandBottom - 0.5 { continue }
            let selected = selection.rows.contains(row)
            if selected {
                style.selection.setFill()
                rect.fill()
            }
            style.line.setFill()
            NSRect(x: rect.minX + 6, y: rect.maxY - 1, width: rect.width - 12, height: 1).fill()
            ("\(row + 1)" as NSString).draw(with: NSRect(x: rect.minX, y: rect.minY + 5, width: rect.width, height: 14), options: [.usesLineFragmentOrigin],
                                            attributes: [.font: selected ? strong : font, .foregroundColor: selected ? style.ink : style.secondary, .paragraphStyle: centred])
        }
        style.line.setFill()
        NSRect(x: side.maxX - 1, y: side.minY, width: 1, height: side.height).fill()

        // Corner
        let corner = NSRect(x: visible.minX, y: visible.minY, width: headerWidth, height: headerHeight)
        style.header.setFill()
        corner.fill()
        style.line.setFill()
        NSRect(x: corner.maxX - 1, y: corner.minY, width: 1, height: corner.height).fill()
        NSRect(x: corner.minX, y: corner.maxY - 1, width: corner.width, height: 1).fill()
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        switch hit(convert(event.locationInWindow, from: nil)) {
        case .columnEdge: NSCursor.resizeLeftRight.set()
        case .fill: NSCursor.crosshair.set()
        default: NSCursor.arrow.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let model else { return }
        let point = convert(event.locationInWindow, from: nil)
        let found = hit(point)
        if editing != nil, wantsReference, case .cell(let address) = found {
            insertReference(CellRange(address))
            referenceStart = address
            drag = .reference
            return
        }
        if editing != nil { commitEdit(rows: 0, columns: 0) }
        window?.makeFirstResponder(self)
        let shift = event.modifierFlags.contains(.shift)
        drag = .none
        switch found {
        case .corner:
            model.selectAll()
        case .column(let column):
            model.selectColumn(column, extend: shift)
            drag = .columns
        case .columnEdge(let column):
            if event.clickCount == 2 {
                model.autoFit(column)
            } else {
                let current = width(column)
                resizing = (column, point.x, current, current)
                drag = .resize
            }
        case .row(let row):
            model.selectRow(row, extend: shift)
            drag = .rows
        case .fill:
            fillTarget = model.selection
            drag = .fill
        case .cell(let address):
            if event.clickCount >= 2 {
                model.select(address)
                beginEditing(initial: nil, enterMode: false)
            } else {
                model.select(address, extend: shift)
                drag = .cells
            }
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let model else { return }
        if drag != .resize { autoscroll(with: event) }
        let point = convert(event.locationInWindow, from: nil)
        switch drag {
        case .none:
            break
        case .cells:
            model.select(address(at: point), extend: true)
        case .columns:
            let column = column(at: max(point.x, visibleRect.minX + headerWidth + 1))
            model.extent = CellAddress(row: model.extent.row, column: column)
        case .rows:
            model.extent = CellAddress(row: row(at: max(point.y, visibleRect.minY + headerHeight)), column: model.extent.column)
        case .resize:
            guard var current = resizing else { return }
            current.width = max(28, current.start + point.x - current.origin)
            resizing = current
            updateSize()
        case .fill:
            fillTarget = fillRange(to: address(at: point), from: model.selection)
            needsDisplay = true
        case .reference:
            if let start = referenceStart { insertReference(CellRange(start, address(at: point))) }
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let model else { return }
        switch drag {
        case .resize:
            if let current = resizing {
                resizing = nil
                model.setColumnWidth(current.column, Double(current.width))
            }
        case .fill:
            if let target = fillTarget, target != model.selection { model.fill(to: target) }
            fillTarget = nil
            needsDisplay = true
        default:
            break
        }
        drag = .none
    }

    private func fillRange(to target: CellAddress, from source: CellRange) -> CellRange {
        if source.contains(target) { return source }
        let down = target.row > source.end.row ? target.row - source.end.row : (target.row < source.start.row ? source.start.row - target.row : 0)
        let across = target.column > source.end.column ? target.column - source.end.column : (target.column < source.start.column ? source.start.column - target.column : 0)
        if down >= across {
            return CellRange(CellAddress(row: min(source.start.row, target.row), column: source.start.column),
                             CellAddress(row: max(source.end.row, target.row), column: source.end.column))
        }
        return CellRange(CellAddress(row: source.start.row, column: min(source.start.column, target.column)),
                         CellAddress(row: source.end.row, column: max(source.end.column, target.column)))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        if case .cell(let address) = hit(point), !model.selection.contains(address) { model.select(address) }
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        add("Cut", #selector(cutCells(_:)))
        add("Copy", #selector(copyCells(_:)))
        add("Paste", #selector(pasteCells(_:)))
        menu.addItem(.separator())
        add("Insert Rows Above", #selector(insertRowsAbove))
        add("Insert Rows Below", #selector(insertRowsBelow))
        add("Insert Columns Left", #selector(insertColumnsLeft))
        add("Insert Columns Right", #selector(insertColumnsRight))
        add(model.selection.rowCount > 1 ? "Delete Rows" : "Delete Row", #selector(deleteRows))
        add(model.selection.columnCount > 1 ? "Delete Columns" : "Delete Column", #selector(deleteColumns))
        menu.addItem(.separator())
        add("Sort A to Z", #selector(sortUp))
        add("Sort Z to A", #selector(sortDown))
        add("Fill Down", #selector(fillDown))
        menu.addItem(.separator())
        add("Clear Contents", #selector(clearContents))
        add("Clear Formatting", #selector(clearFormats))
        menu.addItem(.separator())
        if frozen > 0 && model.active.row + 1 == frozen {
            add("Unfreeze Rows", #selector(unfreeze))
        } else {
            add(model.active.row == 0 ? "Freeze Top Row" : "Freeze Rows 1–\(model.active.row + 1)", #selector(freezeHere))
        }
        if frozen > 0 && model.active.row + 1 != frozen { add("Unfreeze Rows", #selector(unfreeze)) }
        add("Fit Column Width", #selector(fitColumn))
        return menu
    }

    @objc private func insertRowsAbove() { model?.insertRows() }
    @objc private func insertRowsBelow() { model?.insertRows(below: true) }
    @objc private func insertColumnsLeft() { model?.insertColumns() }
    @objc private func insertColumnsRight() { model?.insertColumns(right: true) }
    @objc private func deleteRows() { model?.deleteRows() }
    @objc private func deleteColumns() { model?.deleteColumns() }
    @objc private func sortUp() { model?.sort(ascending: true) }
    @objc private func sortDown() { model?.sort(ascending: false) }
    @objc private func fillDown() { model?.fillDown() }
    @objc private func clearContents() { model?.clearContents() }
    @objc private func clearFormats() { model?.clearFormats() }
    @objc private func freezeHere() { if let model { model.freezeRows(model.active.row + 1) } }
    @objc private func unfreeze() { model?.freezeRows(0) }
    @objc private func fitColumn() { if let model { model.autoFit(model.active.column) } }

    // MARK: Edit menu

    @objc(copy:) func copyCells(_ sender: Any?) {
        model?.copy()
        needsDisplay = true
    }

    @objc(cut:) func cutCells(_ sender: Any?) {
        model?.copy(cut: true)
        needsDisplay = true
    }

    @objc(paste:) func pasteCells(_ sender: Any?) { model?.paste() }
    @objc(undo:) func undoChange(_ sender: Any?) { model?.undo() }
    @objc(redo:) func redoChange(_ sender: Any?) { model?.redo() }
    @objc(selectAll:) func selectEverything(_ sender: Any?) { model?.selectAll() }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        guard let model else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shift = flags.contains(.shift)
        let command = flags.contains(.command)
        if let special = event.specialKey {
            switch special {
            case .upArrow: model.move(rows: -1, columns: 0, extend: shift, jump: command)
            case .downArrow: model.move(rows: 1, columns: 0, extend: shift, jump: command)
            case .leftArrow: model.move(rows: 0, columns: -1, extend: shift, jump: command)
            case .rightArrow: model.move(rows: 0, columns: 1, extend: shift, jump: command)
            case .carriageReturn, .enter, .newline:
                if command { beginEditing(initial: nil, enterMode: false) } else { model.move(rows: shift ? -1 : 1, columns: 0, extend: false, jump: false) }
            case .tab: model.move(rows: 0, columns: 1, extend: false, jump: false)
            case .backTab: model.move(rows: 0, columns: -1, extend: false, jump: false)
            case .delete, .deleteForward, .backspace: model.clearContents()
            case .f2: beginEditing(initial: nil, enterMode: false)
            case .home: model.select(CellAddress(row: command ? 0 : model.active.row, column: 0))
            case .end: model.move(rows: 0, columns: 1, extend: shift, jump: true)
            case .pageDown: model.move(rows: visibleRows, columns: 0, extend: shift, jump: false)
            case .pageUp: model.move(rows: -visibleRows, columns: 0, extend: shift, jump: false)
            default: super.keyDown(with: event)
            }
            return
        }
        if command {
            switch event.charactersIgnoringModifiers?.lowercased() ?? "" {
            case "b": model.toggleBold()
            case "i": model.toggleItalic()
            case "d": model.fillDown()
            case "z": if shift { model.redo() } else { model.undo() }
            case "c": model.copy()
            case "x": model.copy(cut: true)
            case "v": model.paste()
            case "a": model.selectAll()
            default: super.keyDown(with: event)
            }
            needsDisplay = true
            return
        }
        if flags.contains(.control) {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 {
            // Escape drops the copy marquee.
            model.clip = nil
            needsDisplay = true
            return
        }
        if let characters = event.characters, let scalar = characters.unicodeScalars.first,
           !CharacterSet.controlCharacters.contains(scalar) {
            beginEditing(initial: characters, enterMode: true)
            return
        }
        super.keyDown(with: event)
    }

    private var visibleRows: Int { max(1, Int((visibleRect.height - headerHeight) / rowHeight) - frozen - 1) }

    // MARK: Typing in a cell

    func beginEditing(initial: String?, enterMode: Bool) {
        guard let model, model.sheet != nil else { return }
        if editing != nil { cancelEdit() }
        let address = model.active
        editing = address
        self.enterMode = enterMode
        referenceRange = nil
        let field = GridEditorField(frame: .zero)
        field.isBordered = false
        field.drawsBackground = true
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 12)
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.stringValue = initial ?? model.input(address)
        editor = field
        styleEditor()
        addSubview(field)
        positionEditor()
        window?.makeFirstResponder(field)
        if let text = field.currentEditor() {
            text.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
        }
        needsDisplay = true
    }

    private func styleEditor() {
        guard let editor else { return }
        editor.backgroundColor = style.paper
        editor.textColor = style.ink
        editor.wantsLayer = true
        editor.layer?.borderWidth = 2
        editor.layer?.borderColor = style.ink.cgColor
    }

    private func positionEditor() {
        guard let editor, let editing else { return }
        let rect = cellRect(editing)
        let text = editor.stringValue as NSString
        let needed = text.size(withAttributes: [.font: editor.font ?? NSFont.systemFont(ofSize: 12)]).width + 18
        let width = min(max(rect.width + 1, needed), max(rect.width + 1, visibleRect.maxX - rect.minX - 4))
        editor.frame = NSRect(x: rect.minX - 1, y: rect.minY - 1, width: width, height: rect.height + 1)
    }

    private var wantsReference: Bool {
        guard let editor, let text = editor.currentEditor() as? NSTextView else { return false }
        let string = text.string as NSString
        guard string.hasPrefix("=") else { return false }
        let caret = text.selectedRange()
        if let referenceRange, caret.location == NSMaxRange(referenceRange) || NSEqualRanges(caret, referenceRange) { return true }
        guard caret.location > 0, caret.location <= string.length else { return false }
        let before = string.substring(with: NSRange(location: caret.location - 1, length: 1))
        return "=(,+-*/^&<>:; ".contains(before)
    }

    private func insertReference(_ range: CellRange) {
        guard let editor, let text = editor.currentEditor() as? NSTextView else { return }
        var target = text.selectedRange()
        if let referenceRange, target.location == NSMaxRange(referenceRange) || NSEqualRanges(target, referenceRange) { target = referenceRange }
        let reference = range.a1
        text.insertText(reference, replacementRange: target)
        referenceRange = NSRange(location: target.location, length: (reference as NSString).length)
        positionEditor()
        needsDisplay = true
    }

    func controlTextDidChange(_ notification: Notification) {
        referenceRange = nil
        positionEditor()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        // Clicking away or into another field keeps what was typed.
        guard editing != nil else { return }
        commitEdit(rows: 0, columns: 0, refocus: false)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            commitEdit(rows: shift ? -1 : 1, columns: 0)
            return true
        case #selector(NSResponder.insertTab(_:)):
            commitEdit(rows: 0, columns: 1)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            commitEdit(rows: 0, columns: -1)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancelEdit()
            return true
        case #selector(NSResponder.moveUp(_:)) where enterMode:
            commitEdit(rows: -1, columns: 0)
            return true
        case #selector(NSResponder.moveDown(_:)) where enterMode:
            commitEdit(rows: 1, columns: 0)
            return true
        case #selector(NSResponder.moveLeft(_:)) where enterMode && !textView.string.hasPrefix("="):
            commitEdit(rows: 0, columns: -1)
            return true
        case #selector(NSResponder.moveRight(_:)) where enterMode && !textView.string.hasPrefix("="):
            commitEdit(rows: 0, columns: 1)
            return true
        default:
            return false
        }
    }

    private func commitEdit(rows: Int, columns: Int, refocus: Bool = true) {
        guard let model, let address = editing, let editor else { return }
        let text = editor.stringValue
        editing = nil
        referenceRange = nil
        editor.delegate = nil
        self.editor = nil
        if refocus {
            editor.removeFromSuperview()
        } else {
            // Ending editing from inside AppKit's own callback: hide now, remove after it returns.
            editor.isHidden = true
            DispatchQueue.main.async { editor.removeFromSuperview() }
        }
        if text != model.input(address) { model.setInput(text, at: address) }
        if rows != 0 || columns != 0 {
            model.select(address)
            model.move(rows: rows, columns: columns, extend: false, jump: false)
        }
        if refocus { window?.makeFirstResponder(self) }
        needsDisplay = true
    }

    func cancelEdit() {
        guard let editor else { return }
        editing = nil
        referenceRange = nil
        editor.delegate = nil
        editor.removeFromSuperview()
        self.editor = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }
}
