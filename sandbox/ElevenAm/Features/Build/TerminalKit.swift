import Foundation

// Johnny's terminal engine: an xterm-compatible screen fed with the bytes a program writes,
// plus the keys, mouse and paste encodings that go back. No UI here, so it is tested on its own.

enum TermColor: Hashable, Sendable {
    case normal
    /// The 256-colour palette: 0–15 are the theme's colours, then a 6×6×6 cube and a grey ramp.
    case indexed(UInt8)
    case rgb(UInt8, UInt8, UInt8)
}

struct TermStyle: Hashable, Sendable {
    struct Flags: OptionSet, Hashable, Sendable {
        let rawValue: UInt16
        static let bold = Flags(rawValue: 1 << 0)
        static let dim = Flags(rawValue: 1 << 1)
        static let italic = Flags(rawValue: 1 << 2)
        static let underline = Flags(rawValue: 1 << 3)
        static let blink = Flags(rawValue: 1 << 4)
        static let inverse = Flags(rawValue: 1 << 5)
        static let hidden = Flags(rawValue: 1 << 6)
        static let strike = Flags(rawValue: 1 << 7)
    }

    var foreground: TermColor = .normal
    var background: TermColor = .normal
    var flags: Flags = []
    /// A hyperlink (OSC 8), or 0.
    var link: UInt32 = 0

    /// What erased cells get: only the background carries over, as in xterm.
    var erased: TermStyle { TermStyle(background: background) }
}

struct TermCell: Hashable, Sendable {
    /// One grapheme, or empty for a cell nothing was written to.
    var text: String = ""
    var style = TermStyle()
    /// 1 for most characters, 2 for wide ones (CJK, emoji), 0 for the right half of a wide one.
    var width: UInt8 = 1

    var isBlank: Bool { (text.isEmpty || text == " ") && style == TermStyle() }
}

/// Shell-integration marks (OSC 133), kept on the line they were written on.
struct TermMark: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case promptStart, commandStart, outputStart
        case commandEnd(Int32?)
    }

    var kind: Kind
    var column: Int
}

struct TermLine: Sendable {
    var cells: [TermCell]
    /// The text carries on into the next line: it was wrapped, not ended.
    var wrapped = false
    var marks: [TermMark] = []

    init(columns: Int, style: TermStyle = TermStyle()) {
        cells = Array(repeating: TermCell(style: style), count: columns)
    }

    init(cells: [TermCell], wrapped: Bool = false, marks: [TermMark] = []) {
        self.cells = cells
        self.wrapped = wrapped
        self.marks = marks
    }

    var isBlank: Bool { marks.isEmpty && cells.allSatisfy(\.isBlank) }

    /// The line as text, trailing spaces removed.
    var text: String { text(from: 0, to: cells.count) }

    /// Text between two columns. Trailing spaces are dropped unless the text carries on into the next line.
    func text(from start: Int, to end: Int, trimming: Bool = true) -> String {
        guard start < min(end, cells.count) else { return "" }
        var output = ""
        for cell in cells[max(0, start)..<min(end, cells.count)] where cell.width != 0 {
            output += cell.text.isEmpty ? " " : cell.text
        }
        if trimming { while output.hasSuffix(" ") { output.removeLast() } }
        return output
    }
}

/// A command the shell ran, found from its marks.
struct TermCommand: Hashable, Sendable {
    /// Line numbers count from the first line ever written, so they stay put as the scrollback trims.
    var promptLine: Int
    var commandLine: Int
    var outputLine: Int?
    var endLine: Int?
    var command: String
    var exitStatus: Int32?

    var isFinished: Bool { endLine != nil }
}

enum TermMouseMode: Sendable {
    case off, clicks, drags, motion
}

final class TerminalEmulator {
    private(set) var columns: Int
    private(set) var rows: Int
    private(set) var screen: [TermLine]
    /// Oldest first.
    private(set) var scrollback: [TermLine] = []
    var scrollbackLimit = 10_000
    /// Lines that fell off the top of the scrollback.
    private(set) var droppedLines = 0

    private(set) var cursorX = 0
    private(set) var cursorY = 0
    private(set) var isAlternateScreen = false
    var style = TermStyle()

    // Modes programs can set.
    private(set) var cursorVisible = true
    private(set) var cursorShape = 0
    private(set) var applicationCursor = false
    private(set) var applicationKeypad = false
    private(set) var bracketedPaste = false
    private(set) var mouseMode: TermMouseMode = .off
    private(set) var mouseSGR = false
    private(set) var focusEvents = false
    private(set) var reverseVideo = false

    private(set) var title = ""
    /// From OSC 7: where the shell is.
    private(set) var directory: String?
    private(set) var links: [UInt32: String] = [:]
    private(set) var bellCount = 0

    /// Answers to status queries, to write back to the program.
    var onResponse: (([UInt8]) -> Void)?
    var onBell: (() -> Void)?
    var onTitle: ((String) -> Void)?
    /// A command finished (OSC 133;D), with its exit status.
    var onCommandFinished: ((Int32?) -> Void)?
    var onCommandStarted: (() -> Void)?

    private var pendingWrap = false
    private var autowrap = true
    private var originMode = false
    private var insertMode = false
    private var newlineMode = false
    private var scrollTop = 0
    private var scrollBottom: Int
    private var tabStops: [Bool]
    private var savedMain: [TermLine]?
    private var charsets: [Bool] = [false, false]
    private var shiftOut = false
    private var lastPrinted: String?
    private var joinNext = false
    private var linkIDs: [String: UInt32] = [:]

    private struct SavedCursor {
        var x: Int, y: Int, style: TermStyle, originMode: Bool, pendingWrap: Bool, charsets: [Bool], shiftOut: Bool
    }

    private var savedCursor: SavedCursor?
    private var savedCursorMain: SavedCursor?

    // Parser
    private enum State { case ground, escape, escapeIntermediate, csi, osc, oscEscape, string, stringEscape }
    private var state = State.ground
    private var params: [[Int]] = []
    private var currentParam: [Int] = []
    private var currentNumber: Int?
    private var sawParam = false
    private var privateMarker: UInt8?
    private var intermediates: [UInt8] = []
    private var oscBytes: [UInt8] = []
    private var utf8Bytes: [UInt8] = []
    private var utf8Needed = 0

    init(columns: Int = 80, rows: Int = 24) {
        self.columns = max(columns, 2)
        self.rows = max(rows, 1)
        screen = Array(repeating: TermLine(columns: max(columns, 2)), count: max(rows, 1))
        scrollBottom = max(rows, 1) - 1
        tabStops = Self.defaultTabs(max(columns, 2))
    }

    private static func defaultTabs(_ columns: Int) -> [Bool] {
        (0..<columns).map { $0 > 0 && $0 % 8 == 0 }
    }

    // MARK: Reading the screen

    /// Scrollback and screen together.
    var lineCount: Int { scrollback.count + rows }

    /// The line number (counting every line ever written) of the first line still kept.
    var firstLine: Int { droppedLines }

    /// Line number of the top of the screen.
    var screenTop: Int { droppedLines + scrollback.count }

    /// A line by its line number, or nil if it has been trimmed away.
    func line(_ number: Int) -> TermLine? {
        let index = number - droppedLines
        if index < 0 { return nil }
        if index < scrollback.count { return scrollback[index] }
        let row = index - scrollback.count
        return row < screen.count ? screen[row] : nil
    }

    /// Text between two points (line number, column), joining wrapped lines without a break.
    func text(from start: (line: Int, column: Int), to end: (line: Int, column: Int)) -> String {
        var (a, b) = (start, end)
        if (b.line, b.column) < (a.line, a.column) { swap(&a, &b) }
        var output = ""
        for number in a.line...b.line {
            guard let line = self.line(number) else { continue }
            let from = number == a.line ? a.column : 0
            let to = number == b.line ? b.column : line.cells.count
            let carriesOn = number != b.line && line.wrapped && to >= line.cells.count
            output += line.text(from: from, to: to, trimming: !carriesOn)
            if number != b.line && !line.wrapped { output += "\n" }
        }
        return output
    }

    /// The whole screen as text, one line per row.
    var screenText: String { screen.map(\.text).joined(separator: "\n") }

    /// Every match of a search, as line numbers and column ranges.
    func find(_ query: String, caseSensitive: Bool = false) -> [(line: Int, columns: Range<Int>)] {
        guard !query.isEmpty else { return [] }
        let needle = caseSensitive ? query : query.lowercased()
        var results: [(line: Int, columns: Range<Int>)] = []
        for index in 0..<lineCount {
            let number = droppedLines + index
            guard let line = self.line(number) else { continue }
            // Each character with the column it starts in.
            var text = ""
            var starts: [Int] = []
            for (column, cell) in line.cells.enumerated() where cell.width != 0 {
                let piece = cell.text.isEmpty ? " " : cell.text
                for _ in piece { starts.append(column) }
                text += piece
            }
            let haystack = Array(caseSensitive ? text : text.lowercased())
            let pattern = Array(needle)
            guard haystack.count == starts.count, haystack.count >= pattern.count else { continue }
            var position = 0
            while position + pattern.count <= haystack.count {
                if Array(haystack[position..<position + pattern.count]) == pattern, position + pattern.count - 1 < starts.count {
                    let first = starts[position]
                    let lastCell = starts[position + pattern.count - 1]
                    let width = Int(max(line.cells[lastCell].width, 1))
                    results.append((number, first..<(lastCell + width)))
                    position += pattern.count
                } else {
                    position += 1
                }
            }
        }
        return results
    }

    /// The commands the shell ran, oldest first, from the shell-integration marks.
    func commands() -> [TermCommand] {
        var found: [TermCommand] = []
        var current: TermCommand?
        var commandStart: (line: Int, column: Int)?
        for index in 0..<lineCount {
            let number = droppedLines + index
            guard let line = self.line(number) else { continue }
            for mark in line.marks {
                switch mark.kind {
                case .promptStart:
                    if let open = current { found.append(open) }
                    current = TermCommand(promptLine: number, commandLine: number, command: "")
                    commandStart = nil
                case .commandStart:
                    if current == nil { current = TermCommand(promptLine: number, commandLine: number, command: "") }
                    current?.commandLine = number
                    commandStart = (number, mark.column)
                case .outputStart:
                    current?.outputLine = number
                    if let start = commandStart {
                        current?.command = text(from: start, to: (number, mark.column)).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                case .commandEnd(let status):
                    current?.endLine = number
                    current?.exitStatus = status
                    if let done = current, done.outputLine != nil { found.append(done) }
                    current = nil
                    commandStart = nil
                }
            }
        }
        if let open = current, open.outputLine != nil { found.append(open) }
        return found
    }

    /// What a command printed.
    func output(of command: TermCommand) -> String {
        guard let start = command.outputLine else { return "" }
        let end = command.endLine ?? (screenTop + cursorY)
        var column = 0
        if let endLine = command.endLine, let row = self.line(endLine),
           let mark = row.marks.first(where: { if case .commandEnd = $0.kind { return true } else { return false } }) {
            column = mark.column
        } else if command.endLine == nil {
            column = cursorX
        }
        return text(from: (start, 0), to: (end, column)).trimmingCharacters(in: .newlines)
    }

    // MARK: Feeding

    func feed(_ text: String) { feed(Array(text.utf8)) }

    func feed(_ bytes: [UInt8]) {
        for byte in bytes { process(byte) }
    }

    private func process(_ byte: UInt8) {
        switch state {
        case .ground:
            if utf8Needed > 0 {
                if byte & 0xC0 == 0x80 {
                    utf8Bytes.append(byte)
                    utf8Needed -= 1
                    if utf8Needed == 0 {
                        if let scalar = String(decoding: utf8Bytes, as: UTF8.self).unicodeScalars.first { printScalar(scalar) }
                        utf8Bytes = []
                    }
                    return
                }
                utf8Bytes = []
                utf8Needed = 0
                printScalar("\u{FFFD}")
            }
            switch byte {
            case 0x1B:
                state = .escape
                intermediates = []
            case 0x00...0x1F, 0x7F:
                control(byte)
            case 0x20...0x7E:
                printScalar(Unicode.Scalar(byte))
            case 0xC2...0xDF:
                utf8Bytes = [byte]; utf8Needed = 1
            case 0xE0...0xEF:
                utf8Bytes = [byte]; utf8Needed = 2
            case 0xF0...0xF4:
                utf8Bytes = [byte]; utf8Needed = 3
            default:
                printScalar("\u{FFFD}")
            }
        case .escape:
            switch byte {
            case 0x5B:
                state = .csi
                params = []; currentParam = []; currentNumber = nil; sawParam = false; privateMarker = nil; intermediates = []
            case 0x5D:
                state = .osc
                oscBytes = []
            case 0x50, 0x58, 0x5E, 0x5F:
                state = .string
            case 0x20...0x2F:
                intermediates.append(byte)
                state = .escapeIntermediate
            case 0x1B:
                break
            case 0x00...0x1F:
                control(byte)
            default:
                state = .ground
                escape(byte)
            }
        case .escapeIntermediate:
            switch byte {
            case 0x20...0x2F: intermediates.append(byte)
            case 0x30...0x7E:
                state = .ground
                escape(byte)
            case 0x1B: state = .escape; intermediates = []
            default: control(byte)
            }
        case .csi:
            switch byte {
            case 0x30...0x39:
                currentNumber = min((currentNumber ?? 0) * 10 + Int(byte - 0x30), 65_535)
                sawParam = true
            case 0x3B:
                params.append(currentParam + [currentNumber ?? -1])
                currentParam = []
                currentNumber = nil
                sawParam = true
            case 0x3A:
                currentParam.append(currentNumber ?? -1)
                currentNumber = nil
                sawParam = true
            case 0x3C...0x3F:
                if !sawParam && privateMarker == nil { privateMarker = byte }
            case 0x20...0x2F:
                intermediates.append(byte)
            case 0x40...0x7E:
                if sawParam { params.append(currentParam + [currentNumber ?? -1]) }
                state = .ground
                csi(byte)
            case 0x1B:
                state = .escape
                intermediates = []
            default:
                control(byte)
            }
        case .osc:
            switch byte {
            case 0x07:
                state = .ground
                osc()
            case 0x1B:
                state = .oscEscape
            default:
                if oscBytes.count < 65_536 { oscBytes.append(byte) }
            }
        case .oscEscape:
            osc()
            state = .ground
            if byte != 0x5C { process(0x1B); process(byte) }
        case .string:
            if byte == 0x07 { state = .ground } else if byte == 0x1B { state = .stringEscape }
        case .stringEscape:
            state = byte == 0x5C ? .ground : .string
        }
    }

    // MARK: Printing

    private static let decSpecial: [UInt8: Character] = [
        0x60: "◆", 0x61: "▒", 0x66: "°", 0x67: "±", 0x6A: "┘", 0x6B: "┐", 0x6C: "┌", 0x6D: "└", 0x6E: "┼", 0x6F: "⎺",
        0x70: "⎻", 0x71: "─", 0x72: "⎼", 0x73: "⎽", 0x74: "├", 0x75: "┤", 0x76: "┴", 0x77: "┬", 0x78: "│", 0x79: "≤",
        0x7A: "≥", 0x7B: "π", 0x7C: "≠", 0x7D: "£", 0x7E: "·",
    ]

    /// How many cells a character takes.
    static func width(_ scalar: Unicode.Scalar) -> Int {
        let value = scalar.value
        if value < 0x300 { return value < 0x20 || (0x7F...0x9F).contains(value) ? 0 : 1 }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .enclosingMark, .format: return 0
        default: break
        }
        if (0x1160...0x11FF).contains(value) || (0xFE00...0xFE0F).contains(value) { return 0 }
        if scalar.properties.isEmojiPresentation { return 2 }
        switch value {
        case 0x1100...0x115F, 0x231A...0x231B, 0x2329...0x232A, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF,
             0x4E00...0x9FFF, 0xA000...0xA4CF, 0xA960...0xA97F, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE10...0xFE19,
             0xFE30...0xFE6F, 0xFF00...0xFF60, 0xFFE0...0xFFE6, 0x1F300...0x1F64F, 0x1F900...0x1F9FF,
             0x20000...0x2FFFD, 0x30000...0x3FFFD:
            return 2
        default:
            return 1
        }
    }

    private func printScalar(_ scalar: Unicode.Scalar) {
        var scalar = scalar
        if charsets[shiftOut ? 1 : 0], scalar.value < 0x80, let mapped = Self.decSpecial[UInt8(scalar.value)] {
            scalar = mapped.unicodeScalars.first ?? scalar
        }
        let isRegional = (0x1F1E6...0x1F1FF).contains(scalar.value)
        if scalar.value == 0x200D {
            attachToPrevious(scalar)
            joinNext = true
            return
        }
        if joinNext {
            joinNext = false
            if attachToPrevious(scalar) { return }
        }
        if isRegional, let previous = previousCell(), let prior = self.cell(at: previous),
           prior.text.unicodeScalars.count == 1, let first = prior.text.unicodeScalars.first, (0x1F1E6...0x1F1FF).contains(first.value) {
            attachToPrevious(scalar)
            return
        }
        let width = Self.width(scalar)
        if width == 0 {
            attachToPrevious(scalar)
            return
        }
        write(String(scalar), width: width)
    }

    private func previousCell() -> (x: Int, y: Int)? {
        var x = pendingWrap ? cursorX : cursorX - 1
        guard x >= 0 else { return nil }
        if screen[cursorY].cells[x].width == 0 && x > 0 { x -= 1 }
        return (x, cursorY)
    }

    private func cell(at point: (x: Int, y: Int)) -> TermCell? {
        screen.indices.contains(point.y) && screen[point.y].cells.indices.contains(point.x) ? screen[point.y].cells[point.x] : nil
    }

    @discardableResult
    private func attachToPrevious(_ scalar: Unicode.Scalar) -> Bool {
        guard let point = previousCell(), !screen[point.y].cells[point.x].text.isEmpty else { return false }
        screen[point.y].cells[point.x].text.unicodeScalars.append(scalar)
        return true
    }

    private func write(_ text: String, width: Int) {
        if pendingWrap {
            if autowrap {
                screen[cursorY].wrapped = true
                cursorX = 0
                lineFeed()
            }
            pendingWrap = false
        }
        if width == 2 && cursorX == columns - 1 {
            if autowrap {
                clearWide(cursorX, cursorY)
                screen[cursorY].cells[cursorX] = TermCell(style: style.erased)
                screen[cursorY].wrapped = true
                cursorX = 0
                lineFeed()
            } else {
                return
            }
        }
        if insertMode { insertBlanks(width) }
        clearWide(cursorX, cursorY)
        if width == 2 { clearWide(cursorX + 1, cursorY) }
        screen[cursorY].cells[cursorX] = TermCell(text: text, style: style, width: UInt8(width))
        if width == 2 { screen[cursorY].cells[cursorX + 1] = TermCell(text: "", style: style, width: 0) }
        lastPrinted = text
        let next = cursorX + width
        if next >= columns {
            cursorX = columns - 1
            pendingWrap = true
        } else {
            cursorX = next
        }
    }

    /// Writing over half of a wide character blanks the other half.
    private func clearWide(_ x: Int, _ y: Int) {
        guard screen[y].cells.indices.contains(x) else { return }
        let cell = screen[y].cells[x]
        if cell.width == 0, x > 0 {
            screen[y].cells[x - 1] = TermCell(style: screen[y].cells[x - 1].style)
            screen[y].cells[x] = TermCell(style: cell.style)
        } else if cell.width == 2, x + 1 < columns {
            screen[y].cells[x + 1] = TermCell(style: cell.style)
        }
    }

    // MARK: Controls

    private func control(_ byte: UInt8) {
        switch byte {
        case 0x07:
            bellCount += 1
            onBell?()
        case 0x08:
            pendingWrap = false
            cursorX = max(0, cursorX - 1)
        case 0x09:
            pendingWrap = false
            cursorX = nextTab(from: cursorX)
        case 0x0A, 0x0B, 0x0C:
            lineFeed()
            if newlineMode { cursorX = 0 }
        case 0x0D:
            cursorX = 0
            pendingWrap = false
        case 0x0E: shiftOut = true
        case 0x0F: shiftOut = false
        default: break
        }
    }

    private func nextTab(from x: Int) -> Int {
        var position = x + 1
        while position < columns - 1 && !tabStops[position] { position += 1 }
        return min(position, columns - 1)
    }

    private func previousTab(from x: Int) -> Int {
        var position = x - 1
        while position > 0 && !tabStops[position] { position -= 1 }
        return max(position, 0)
    }

    private func lineFeed() {
        pendingWrap = false
        if cursorY == scrollBottom {
            scrollUp(1)
        } else if cursorY < rows - 1 {
            cursorY += 1
        }
    }

    private func blankLine() -> TermLine { TermLine(columns: columns, style: style.erased) }

    private func scrollUp(_ count: Int) {
        let count = min(count, scrollBottom - scrollTop + 1)
        guard count > 0 else { return }
        for _ in 0..<count {
            let line = screen.remove(at: scrollTop)
            if scrollTop == 0 && !isAlternateScreen { keep(line) }
            screen.insert(blankLine(), at: scrollBottom)
        }
    }

    private func scrollDown(_ count: Int) {
        let count = min(count, scrollBottom - scrollTop + 1)
        guard count > 0 else { return }
        for _ in 0..<count {
            screen.remove(at: scrollBottom)
            screen.insert(blankLine(), at: scrollTop)
        }
    }

    private func keep(_ line: TermLine) {
        scrollback.append(line)
        // Trim in batches so heavy output doesn't shuffle the whole history every line.
        if scrollback.count > scrollbackLimit + 256 {
            let extra = scrollback.count - scrollbackLimit
            scrollback.removeFirst(extra)
            droppedLines += extra
        }
    }

    // MARK: Escapes

    private func escape(_ final: UInt8) {
        if let first = intermediates.first {
            switch (first, final) {
            case (0x28, _): charsets[0] = final == 0x30
            case (0x29, _): charsets[1] = final == 0x30
            case (0x23, 0x38):
                for y in 0..<rows { screen[y] = TermLine(cells: Array(repeating: TermCell(text: "E"), count: columns)) }
            default: break
            }
            return
        }
        switch final {
        case 0x37: saveCursor()
        case 0x38: restoreCursor()
        case 0x44: lineFeed()
        case 0x45:
            cursorX = 0
            lineFeed()
        case 0x4D: reverseIndex()
        case 0x63: reset()
        case 0x48: if cursorX < columns { tabStops[cursorX] = true }
        case 0x3D: applicationKeypad = true
        case 0x3E: applicationKeypad = false
        default: break
        }
    }

    private func reverseIndex() {
        pendingWrap = false
        if cursorY == scrollTop {
            scrollDown(1)
        } else if cursorY > 0 {
            cursorY -= 1
        }
    }

    private func saveCursor() {
        savedCursor = SavedCursor(x: cursorX, y: cursorY, style: style, originMode: originMode, pendingWrap: pendingWrap, charsets: charsets, shiftOut: shiftOut)
    }

    private func restoreCursor() {
        guard let saved = savedCursor else {
            cursorX = 0; cursorY = 0; pendingWrap = false
            return
        }
        cursorX = min(saved.x, columns - 1)
        cursorY = min(saved.y, rows - 1)
        style = saved.style
        originMode = saved.originMode
        pendingWrap = saved.pendingWrap
        charsets = saved.charsets
        shiftOut = saved.shiftOut
    }

    /// Everything back to how it started, except the scrollback.
    func reset() {
        if isAlternateScreen { useAlternateScreen(false) }
        style = TermStyle()
        cursorX = 0; cursorY = 0; pendingWrap = false
        autowrap = true; originMode = false; insertMode = false; newlineMode = false
        cursorVisible = true; cursorShape = 0; applicationCursor = false; applicationKeypad = false
        bracketedPaste = false; mouseMode = .off; mouseSGR = false; focusEvents = false; reverseVideo = false
        scrollTop = 0; scrollBottom = rows - 1
        tabStops = Self.defaultTabs(columns)
        charsets = [false, false]; shiftOut = false
        savedCursor = nil
        screen = Array(repeating: TermLine(columns: columns), count: rows)
    }

    // MARK: CSI

    /// A count parameter: missing or 0 means 1.
    private func count(_ index: Int) -> Int {
        guard index < params.count, let value = params[index].first, value > 0 else { return 1 }
        return value
    }

    /// A plain parameter, with a default when it's missing.
    private func value(_ index: Int, _ fallback: Int) -> Int {
        guard index < params.count, let value = params[index].first, value >= 0 else { return fallback }
        return value
    }

    private var regionTop: Int { originMode ? scrollTop : 0 }
    private var regionBottom: Int { originMode ? scrollBottom : rows - 1 }

    private func csi(_ final: UInt8) {
        let intermediate = intermediates.first
        if let marker = privateMarker {
            switch (marker, final) {
            case (0x3F, 0x68): params.forEach { mode(Int($0.first ?? -1), on: true) }
            case (0x3F, 0x6C): params.forEach { mode(Int($0.first ?? -1), on: false) }
            case (0x3E, 0x63): respond("\u{1B}[>1;10;0c")
            case (0x3F, 0x6E) where value(0, 0) == 6:
                respond("\u{1B}[?\(cursorY - regionTop + 1);\(cursorX + 1)R")
            default: break
            }
            return
        }
        if intermediate == 0x20 && final == 0x71 {
            cursorShape = value(0, 0)
            return
        }
        if intermediate == 0x21 && final == 0x70 {
            softReset()
            return
        }
        guard intermediate == nil else { return }
        switch final {
        case 0x40: insertBlanks(count(0))
        case 0x41: moveCursor(y: max(cursorY >= scrollTop ? scrollTop : 0, cursorY - count(0)))
        case 0x42, 0x65: moveCursor(y: min(cursorY <= scrollBottom ? scrollBottom : rows - 1, cursorY + count(0)))
        case 0x43, 0x61: moveCursor(x: min(columns - 1, cursorX + count(0)))
        case 0x44: moveCursor(x: max(0, cursorX - count(0)))
        case 0x45:
            moveCursor(y: min(cursorY <= scrollBottom ? scrollBottom : rows - 1, cursorY + count(0)))
            cursorX = 0
        case 0x46:
            moveCursor(y: max(cursorY >= scrollTop ? scrollTop : 0, cursorY - count(0)))
            cursorX = 0
        case 0x47, 0x60: moveCursor(x: min(columns - 1, count(0) - 1))
        case 0x48, 0x66:
            moveCursor(x: min(columns - 1, count(1) - 1), y: min(regionBottom, regionTop + count(0) - 1))
        case 0x49:
            for _ in 0..<count(0) { cursorX = nextTab(from: cursorX) }
            pendingWrap = false
        case 0x5A:
            for _ in 0..<count(0) { cursorX = previousTab(from: cursorX) }
            pendingWrap = false
        case 0x4A: eraseDisplay(value(0, 0))
        case 0x4B: eraseLine(value(0, 0))
        case 0x4C: insertLines(count(0))
        case 0x4D: deleteLines(count(0))
        case 0x50: deleteChars(count(0))
        case 0x53: scrollUp(count(0))
        case 0x54: if params.count <= 1 { scrollDown(count(0)) }
        case 0x58: eraseChars(count(0))
        case 0x62:
            if let text = lastPrinted {
                let width = text.unicodeScalars.first.map(Self.width) ?? 1
                for _ in 0..<min(count(0), 65_535) { write(text, width: max(width, 1)) }
            }
        case 0x63: if value(0, 0) == 0 { respond("\u{1B}[?62;22c") }
        case 0x64: moveCursor(y: min(regionBottom, regionTop + count(0) - 1))
        case 0x67:
            switch value(0, 0) {
            case 0: if cursorX < columns { tabStops[cursorX] = false }
            case 3: tabStops = Array(repeating: false, count: columns)
            default: break
            }
        case 0x68, 0x6C:
            for param in params {
                switch param.first ?? -1 {
                case 4: insertMode = final == 0x68
                case 20: newlineMode = final == 0x68
                default: break
                }
            }
        case 0x6D: sgr()
        case 0x6E:
            switch value(0, 0) {
            case 5: respond("\u{1B}[0n")
            case 6: respond("\u{1B}[\(cursorY - regionTop + 1);\(cursorX + 1)R")
            default: break
            }
        case 0x72:
            let top = count(0) - 1
            let bottom = min(value(1, rows), rows) - 1
            if top < bottom {
                scrollTop = top
                scrollBottom = bottom
                moveCursor(x: 0, y: regionTop)
            }
        case 0x73: if params.isEmpty { saveCursor() }
        case 0x75: restoreCursor()
        case 0x74: if value(0, 0) == 18 { respond("\u{1B}[8;\(rows);\(columns)t") }
        default: break
        }
    }

    private func moveCursor(x: Int? = nil, y: Int? = nil) {
        if let x { cursorX = max(0, min(x, columns - 1)) }
        if let y { cursorY = max(0, min(y, rows - 1)) }
        pendingWrap = false
    }

    private func softReset() {
        style = TermStyle()
        cursorVisible = true; originMode = false; autowrap = true; insertMode = false
        applicationCursor = false; applicationKeypad = false
        scrollTop = 0; scrollBottom = rows - 1
        charsets = [false, false]; shiftOut = false
        savedCursor = nil
    }

    private func mode(_ number: Int, on: Bool) {
        switch number {
        case 1: applicationCursor = on
        case 5: reverseVideo = on
        case 6:
            originMode = on
            moveCursor(x: 0, y: regionTop)
        case 7: autowrap = on
        case 25: cursorVisible = on
        case 47: useAlternateScreen(on)
        case 1047:
            if on { useAlternateScreen(true) } else {
                if isAlternateScreen { eraseDisplay(2) }
                useAlternateScreen(false)
            }
        case 1048: if on { saveCursor() } else { restoreCursor() }
        case 1049:
            if on {
                saveCursor()
                useAlternateScreen(true)
                eraseDisplay(2)
            } else {
                useAlternateScreen(false)
                restoreCursor()
            }
        case 1000: mouseMode = on ? .clicks : .off
        case 1002: mouseMode = on ? .drags : .off
        case 1003: mouseMode = on ? .motion : .off
        case 1006: mouseSGR = on
        case 1004: focusEvents = on
        case 2004: bracketedPaste = on
        default: break
        }
    }

    private func useAlternateScreen(_ on: Bool) {
        guard on != isAlternateScreen else { return }
        if on {
            savedMain = screen
            savedCursorMain = savedCursor
            screen = Array(repeating: TermLine(columns: columns), count: rows)
        } else {
            screen = savedMain ?? Array(repeating: TermLine(columns: columns), count: rows)
            savedMain = nil
            if let saved = savedCursorMain { savedCursor = saved }
        }
        isAlternateScreen = on
        scrollTop = 0
        scrollBottom = rows - 1
        pendingWrap = false
    }

    private func eraseDisplay(_ mode: Int) {
        switch mode {
        case 0:
            eraseLine(0)
            for y in (cursorY + 1)..<max(rows, cursorY + 1) { screen[y] = blankLine() }
        case 1:
            eraseLine(1)
            for y in 0..<cursorY { screen[y] = blankLine() }
        case 2:
            for y in 0..<rows { screen[y] = blankLine() }
        case 3:
            droppedLines += scrollback.count
            scrollback = []
        default:
            break
        }
    }

    private func eraseLine(_ mode: Int) {
        let blank = TermCell(style: style.erased)
        let range: Range<Int>
        switch mode {
        case 0: range = cursorX..<columns
        case 1: range = 0..<min(cursorX + 1, columns)
        default: range = 0..<columns
        }
        if let first = range.first { clearWide(first, cursorY) }
        if let last = range.last { clearWide(last, cursorY) }
        for x in range { screen[cursorY].cells[x] = blank }
        if mode != 1 { screen[cursorY].wrapped = false }
        pendingWrap = false
    }

    private func eraseChars(_ count: Int) {
        let end = min(columns, cursorX + count)
        clearWide(cursorX, cursorY)
        clearWide(end - 1, cursorY)
        for x in cursorX..<end { screen[cursorY].cells[x] = TermCell(style: style.erased) }
        pendingWrap = false
    }

    private func insertBlanks(_ count: Int) {
        let count = min(count, columns - cursorX)
        guard count > 0 else { return }
        clearWide(cursorX, cursorY)
        var cells = screen[cursorY].cells
        cells.insert(contentsOf: Array(repeating: TermCell(style: style.erased), count: count), at: cursorX)
        cells.removeLast(count)
        if cells[columns - 1].width == 2 { cells[columns - 1] = TermCell(style: cells[columns - 1].style) }
        screen[cursorY].cells = cells
        pendingWrap = false
    }

    private func deleteChars(_ count: Int) {
        let count = min(count, columns - cursorX)
        guard count > 0 else { return }
        clearWide(cursorX, cursorY)
        clearWide(cursorX + count - 1, cursorY)
        var cells = screen[cursorY].cells
        cells.removeSubrange(cursorX..<(cursorX + count))
        cells.append(contentsOf: Array(repeating: TermCell(style: style.erased), count: count))
        screen[cursorY].cells = cells
        pendingWrap = false
    }

    private func insertLines(_ count: Int) {
        guard cursorY >= scrollTop && cursorY <= scrollBottom else { return }
        let count = min(count, scrollBottom - cursorY + 1)
        for _ in 0..<count {
            screen.remove(at: scrollBottom)
            screen.insert(blankLine(), at: cursorY)
        }
        cursorX = 0
        pendingWrap = false
    }

    private func deleteLines(_ count: Int) {
        guard cursorY >= scrollTop && cursorY <= scrollBottom else { return }
        let count = min(count, scrollBottom - cursorY + 1)
        for _ in 0..<count {
            screen.remove(at: cursorY)
            screen.insert(blankLine(), at: scrollBottom)
        }
        cursorX = 0
        pendingWrap = false
    }

    // MARK: Colour and style (SGR)

    private func sgr() {
        if params.isEmpty {
            style = TermStyle(link: style.link)
            return
        }
        var index = 0
        while index < params.count {
            let param = params[index]
            let code = max(param.first ?? 0, 0)
            switch code {
            case 0: style = TermStyle(link: style.link)
            case 1: style.flags.insert(.bold)
            case 2: style.flags.insert(.dim)
            case 3: style.flags.insert(.italic)
            case 4:
                if param.count > 1 && param[1] == 0 { style.flags.remove(.underline) } else { style.flags.insert(.underline) }
            case 5, 6: style.flags.insert(.blink)
            case 7: style.flags.insert(.inverse)
            case 8: style.flags.insert(.hidden)
            case 9: style.flags.insert(.strike)
            case 21: style.flags.insert(.underline)
            case 22: style.flags.remove([.bold, .dim])
            case 23: style.flags.remove(.italic)
            case 24: style.flags.remove(.underline)
            case 25: style.flags.remove(.blink)
            case 27: style.flags.remove(.inverse)
            case 28: style.flags.remove(.hidden)
            case 29: style.flags.remove(.strike)
            case 30...37: style.foreground = .indexed(UInt8(code - 30))
            case 39: style.foreground = .normal
            case 40...47: style.background = .indexed(UInt8(code - 40))
            case 49: style.background = .normal
            case 90...97: style.foreground = .indexed(UInt8(code - 90 + 8))
            case 100...107: style.background = .indexed(UInt8(code - 100 + 8))
            case 38, 48, 58:
                let (color, used) = extendedColor(at: index)
                if code == 38, let color { style.foreground = color }
                if code == 48, let color { style.background = color }
                index += used
            default: break
            }
            index += 1
        }
    }

    /// 38;5;n, 38;2;r;g;b and the colon forms (38:5:n, 38:2::r:g:b). Returns the colour and how many extra parameters it used.
    private func extendedColor(at index: Int) -> (TermColor?, Int) {
        let param = params[index]
        func byte(_ value: Int) -> UInt8 { UInt8(max(0, min(255, value))) }
        if param.count > 1 {
            let sub = Array(param.dropFirst())
            if sub[0] == 5, sub.count >= 2 { return (.indexed(byte(sub[1])), 0) }
            if sub[0] == 2 {
                let values = sub.count >= 5 ? Array(sub.suffix(3)) : Array(sub.dropFirst())
                if values.count >= 3 { return (.rgb(byte(values[0]), byte(values[1]), byte(values[2])), 0) }
            }
            return (nil, 0)
        }
        guard index + 1 < params.count else { return (nil, 0) }
        switch params[index + 1].first ?? -1 {
        case 5:
            guard index + 2 < params.count else { return (nil, 1) }
            return (.indexed(byte(params[index + 2].first ?? 0)), 2)
        case 2:
            guard index + 4 < params.count else { return (nil, params.count - index - 1) }
            return (.rgb(byte(params[index + 2].first ?? 0), byte(params[index + 3].first ?? 0), byte(params[index + 4].first ?? 0)), 4)
        default:
            return (nil, 1)
        }
    }

    // MARK: OSC

    private func osc() {
        let text = String(decoding: oscBytes, as: UTF8.self)
        oscBytes = []
        let parts = text.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, let code = Int(first) else { return }
        let body = parts.count > 1 ? String(parts[1]) : ""
        switch code {
        case 0, 2:
            title = body
            onTitle?(body)
        case 7:
            if let url = URL(string: body), url.isFileURL {
                directory = url.path
            } else if body.hasPrefix("/") {
                directory = body
            }
        case 8:
            let pieces = body.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            let uri = pieces.count > 1 ? String(pieces[1]) : ""
            if uri.isEmpty {
                style.link = 0
            } else if let id = linkIDs[uri] {
                style.link = id
            } else {
                let id = UInt32(linkIDs.count + 1)
                linkIDs[uri] = id
                links[id] = uri
                style.link = id
            }
        case 133:
            let fields = body.split(separator: ";", omittingEmptySubsequences: false)
            guard let kind = fields.first else { return }
            switch kind {
            case "A": mark(.promptStart)
            case "B": mark(.commandStart)
            case "C":
                mark(.outputStart)
                onCommandStarted?()
            case "D":
                let status = fields.count > 1 ? Int32(fields[1]) : nil
                mark(.commandEnd(status))
                onCommandFinished?(status)
            default: break
            }
        default:
            break
        }
    }

    private func mark(_ kind: TermMark.Kind) {
        let column = pendingWrap ? columns : cursorX
        screen[cursorY].marks.append(TermMark(kind: kind, column: column))
    }

    private func respond(_ text: String) {
        onResponse?(Array(text.utf8))
    }

    // MARK: Resizing

    /// Changes the size. On the main screen wrapped lines are re-wrapped to the new width, scrollback too.
    func resize(columns newColumns: Int, rows newRows: Int) {
        let newColumns = max(newColumns, 2), newRows = max(newRows, 1)
        guard newColumns != columns || newRows != rows else { return }
        if isAlternateScreen {
            screen = Self.fit(screen, columns: newColumns, rows: newRows)
            if let main = savedMain { savedMain = Self.fit(main, columns: newColumns, rows: newRows) }
            columns = newColumns
            rows = newRows
            cursorX = min(cursorX, columns - 1)
            cursorY = min(cursorY, rows - 1)
        } else {
            reflow(columns: newColumns, rows: newRows)
        }
        tabStops = Self.defaultTabs(columns)
        scrollTop = 0
        scrollBottom = rows - 1
        pendingWrap = false
        if let saved = savedCursor {
            savedCursor?.x = min(saved.x, columns - 1)
            savedCursor?.y = min(saved.y, rows - 1)
        }
    }

    /// Pads or cuts lines to a size, keeping the top.
    private static func fit(_ lines: [TermLine], columns: Int, rows: Int) -> [TermLine] {
        var result = Array(lines.prefix(rows)).map { line -> TermLine in
            var copy = line
            if copy.cells.count > columns {
                copy.cells = Array(copy.cells.prefix(columns))
                if copy.cells[columns - 1].width == 2 { copy.cells[columns - 1] = TermCell(style: copy.cells[columns - 1].style) }
            } else if copy.cells.count < columns {
                copy.cells += Array(repeating: TermCell(), count: columns - copy.cells.count)
            }
            return copy
        }
        while result.count < rows { result.append(TermLine(columns: columns)) }
        return result
    }

    private func reflow(columns newColumns: Int, rows newRows: Int) {
        var all = scrollback + screen
        let cursorIndex = scrollback.count + cursorY
        var last = all.count - 1
        while last > cursorIndex && all[last].isBlank && !all[last - 1].wrapped { last -= 1 }
        all = Array(all[0...last])

        // Join wrapped rows into logical lines, remembering where the cursor and the marks are.
        struct Logical { var cells: [TermCell] = []; var marks: [TermMark] = [] }
        var logical: [Logical] = []
        var current = Logical()
        var cursorLogical = (line: 0, offset: 0)
        for (index, row) in all.enumerated() {
            let base = current.cells.count
            var cells = row.cells
            if index == cursorIndex {
                cursorLogical = (logical.count, base + cursorX + (pendingWrap ? 1 : 0))
            }
            for mark in row.marks { current.marks.append(TermMark(kind: mark.kind, column: base + min(mark.column, cells.count))) }
            if !row.wrapped {
                var keep = cells.count
                while keep > 0 && cells[keep - 1].isBlank { keep -= 1 }
                if index == cursorIndex { keep = max(keep, min(cursorX + (pendingWrap ? 1 : 0), cells.count)) }
                let markEnd = row.marks.map(\.column).max() ?? 0
                keep = max(keep, min(markEnd, cells.count))
                cells = Array(cells.prefix(keep))
            }
            current.cells += cells
            if !row.wrapped {
                logical.append(current)
                current = Logical()
            }
        }
        if !current.cells.isEmpty || !current.marks.isEmpty { logical.append(current) }

        // Wrap each logical line at the new width.
        var lines: [TermLine] = []
        var cursorRow = 0, cursorColumn = 0
        for (index, item) in logical.enumerated() {
            let firstRow = lines.count
            var starts: [Int] = []
            var position = 0
            repeat {
                var take = min(newColumns, item.cells.count - position)
                if take == newColumns, take > 1, item.cells[position + take - 1].width == 2 { take -= 1 }
                var cells = Array(item.cells[position..<(position + take)])
                if cells.count < newColumns { cells += Array(repeating: TermCell(), count: newColumns - cells.count) }
                starts.append(position)
                position += take
                lines.append(TermLine(cells: cells, wrapped: position < item.cells.count))
            } while position < item.cells.count
            func place(_ offset: Int) -> (row: Int, column: Int) {
                var row = starts.count - 1
                while row > 0 && starts[row] > offset { row -= 1 }
                return (firstRow + row, offset - starts[row])
            }
            for mark in item.marks {
                let spot = place(mark.column)
                lines[spot.row].marks.append(TermMark(kind: mark.kind, column: min(spot.column, newColumns)))
            }
            if index == cursorLogical.line {
                var spot = place(cursorLogical.offset)
                if spot.column >= newColumns {
                    lines[spot.row].wrapped = true
                    lines.insert(TermLine(columns: newColumns), at: spot.row + 1)
                    spot = (spot.row + 1, spot.column - newColumns)
                }
                cursorRow = spot.row
                cursorColumn = min(spot.column, newColumns - 1)
            }
        }
        if lines.isEmpty { lines = [TermLine(columns: newColumns)] }

        let top = min(max(0, lines.count - newRows), cursorRow)
        scrollback = Array(lines[0..<top])
        var visible = Array(lines[top...].prefix(newRows))
        while visible.count < newRows { visible.append(TermLine(columns: newColumns)) }
        screen = visible
        if scrollback.count > scrollbackLimit {
            let extra = scrollback.count - scrollbackLimit
            scrollback.removeFirst(extra)
            droppedLines += extra
        }
        columns = newColumns
        rows = newRows
        cursorX = cursorColumn
        cursorY = cursorRow - top
    }
}

// MARK: Keys, mouse and paste

/// What a key press sends to the program.
enum TerminalKeys {
    enum Key: Hashable {
        case up, down, right, left, home, end, pageUp, pageDown, insert, delete
        case function(Int)
        case tab, backTab, enter, backspace, escape
    }

    struct Modifiers: OptionSet, Hashable {
        let rawValue: Int
        static let shift = Modifiers(rawValue: 1)
        static let option = Modifiers(rawValue: 2)
        static let control = Modifiers(rawValue: 4)

        /// The xterm modifier parameter: 1 plus shift 1, alt 2, control 4.
        var parameter: Int { 1 + rawValue }
    }

    static func encode(_ key: Key, modifiers: Modifiers = [], applicationCursor: Bool = false) -> [UInt8] {
        let esc = "\u{1B}"
        let mods: Int? = modifiers.isEmpty ? nil : modifiers.parameter
        func letter(_ final: String) -> String {
            if let mods { return "\(esc)[1;\(mods)\(final)" }
            return applicationCursor ? "\(esc)O\(final)" : "\(esc)[\(final)"
        }
        func tilde(_ number: Int) -> String {
            if let mods { return "\(esc)[\(number);\(mods)~" }
            return "\(esc)[\(number)~"
        }
        let text: String
        switch key {
        case .up: text = letter("A")
        case .down: text = letter("B")
        case .right: text = letter("C")
        case .left: text = letter("D")
        case .home: text = letter("H")
        case .end: text = letter("F")
        case .insert: text = tilde(2)
        case .delete: text = tilde(3)
        case .pageUp: text = tilde(5)
        case .pageDown: text = tilde(6)
        case .function(let number):
            switch number {
            case 1...4:
                let final = ["P", "Q", "R", "S"][number - 1]
                text = mods.map { "\(esc)[1;\($0)\(final)" } ?? "\(esc)O\(final)"
            case 5...12:
                text = tilde([15, 17, 18, 19, 20, 21, 23, 24][number - 5])
            default:
                text = ""
            }
        case .tab: text = modifiers.contains(.shift) ? "\(esc)[Z" : "\t"
        case .backTab: text = "\(esc)[Z"
        case .enter: text = modifiers.contains(.option) ? "\(esc)\r" : "\r"
        case .backspace:
            if modifiers.contains(.control) { text = "\u{08}" } else { text = modifiers.contains(.option) ? "\(esc)\u{7F}" : "\u{7F}" }
        case .escape: text = esc
        }
        return Array(text.utf8)
    }

    /// Typed text, with control and option (as Meta) applied.
    static func encode(text: String, modifiers: Modifiers = [], optionIsMeta: Bool = true) -> [UInt8] {
        var bytes: [UInt8] = []
        if modifiers.contains(.control), text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first, scalar.isASCII {
            let value = UInt8(scalar.value)
            switch value {
            case 0x61...0x7A: bytes = [value - 0x60]
            case 0x41...0x5A: bytes = [value - 0x40]
            case 0x20, 0x32, 0x40: bytes = [0]
            case 0x5B, 0x33: bytes = [0x1B]
            case 0x5C, 0x34: bytes = [0x1C]
            case 0x5D, 0x35: bytes = [0x1D]
            case 0x5E, 0x36: bytes = [0x1E]
            case 0x5F, 0x2D, 0x37: bytes = [0x1F]
            case 0x3F, 0x38: bytes = [0x7F]
            default: bytes = [value]
            }
        } else {
            bytes = Array(text.utf8)
        }
        if modifiers.contains(.option) && optionIsMeta { bytes.insert(0x1B, at: 0) }
        return bytes
    }

    enum MouseButton: Int {
        case left = 0, middle = 1, right = 2, none = 3, wheelUp = 64, wheelDown = 65
    }

    /// A mouse event for programs that asked for one (vim, htop, tmux). Column and row start at 0.
    static func mouse(_ button: MouseButton, column: Int, row: Int, pressed: Bool, moving: Bool = false,
                      modifiers: Modifiers = [], sgr: Bool) -> [UInt8] {
        var code = button.rawValue
        if moving { code += 32 }
        if modifiers.contains(.shift) { code += 4 }
        if modifiers.contains(.option) { code += 8 }
        if modifiers.contains(.control) { code += 16 }
        if sgr {
            return Array("\u{1B}[<\(code);\(column + 1);\(row + 1)\(pressed ? "M" : "m")".utf8)
        }
        guard column < 223, row < 223 else { return [] }
        let legacy = pressed || button.rawValue >= 64 ? code : 3 + (code & ~3)
        return [0x1B, 0x5B, 0x4D, UInt8(32 + legacy), UInt8(33 + column), UInt8(33 + row)]
    }

    /// Pasted text: line breaks as returns, wrapped in bracketed-paste markers when the program asked for them.
    static func paste(_ text: String, bracketed: Bool) -> [UInt8] {
        var clean = text.replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r")
        if bracketed {
            clean = clean.replacingOccurrences(of: "\u{1B}", with: "")
            return Array("\u{1B}[200~\(clean)\u{1B}[201~".utf8)
        }
        return Array(clean.utf8)
    }
}

// MARK: Shell integration

/// Small startup files that make zsh and bash mark each prompt, command and exit status (OSC 133) and say where they are (OSC 7).
/// They load your own startup files first, so your prompt and settings are unchanged.
enum ShellIntegration {
    static let zshenv = #"""
    # 11am shell integration. Loads your own zsh files, then marks prompts and commands for Johnny.
    if [[ -n "${ELEVENAM_USER_ZDOTDIR-}" ]]; then
      ZDOTDIR="$ELEVENAM_USER_ZDOTDIR"
    else
      unset ZDOTDIR
    fi
    unset ELEVENAM_USER_ZDOTDIR
    [[ -f "${ZDOTDIR:-$HOME}/.zshenv" ]] && builtin source "${ZDOTDIR:-$HOME}/.zshenv"
    if [[ -o interactive ]]; then
      _elevenam_status() { _elevenam_ret=$? }
      _elevenam_prompt() {
        if [[ -n "${_elevenam_ran-}" ]]; then
          builtin print -n "\e]133;D;${_elevenam_ret}\a"
          unset _elevenam_ran
        fi
        builtin print -n "\e]7;file://${HOST}${PWD// /%20}\a"
        if [[ "$PS1" != *$'\e]133;A'* ]]; then
          PS1=$'%{\e]133;A\a%}'"$PS1"$'%{\e]133;B\a%}'
        fi
      }
      _elevenam_order() {
        precmd_functions=(_elevenam_status ${precmd_functions:#(_elevenam_status|_elevenam_prompt|_elevenam_order)} _elevenam_prompt)
        _elevenam_prompt
      }
      _elevenam_preexec() {
        _elevenam_ran=1
        builtin print -n "\e]133;C\a"
      }
      typeset -ga precmd_functions preexec_functions
      precmd_functions+=(_elevenam_order)
      preexec_functions+=(_elevenam_preexec)
    fi
    """#

    static let bashrc = #"""
    # 11am shell integration. Loads your own bash files, then marks prompts and commands for Johnny.
    if [[ -f ~/.bash_profile ]]; then source ~/.bash_profile; elif [[ -f ~/.bashrc ]]; then source ~/.bashrc; fi
    _elevenam_prompt() {
      if [[ -n "${_elevenam_ran-}" ]]; then printf '\e]133;D;%s\a' "${_elevenam_ret-}"; fi
      _elevenam_ran=
      _elevenam_ready=1
      printf '\e]7;file://%s%s\a' "$HOSTNAME" "${PWD// /%20}"
      if [[ "$PS1" != *'133;A'* ]]; then PS1='\[\e]133;A\a\]'"$PS1"'\[\e]133;B\a\]'; fi
    }
    _elevenam_preexec() {
      if [[ -n "${_elevenam_ready-}" && "$BASH_COMMAND" != _elevenam_prompt* ]]; then
        _elevenam_ready=
        _elevenam_ran=1
        printf '\e]133;C\a'
      fi
    }
    _elevenam_status() { _elevenam_ret=$?; }
    PROMPT_COMMAND="_elevenam_status;${PROMPT_COMMAND:+$PROMPT_COMMAND;}_elevenam_prompt"
    trap '_elevenam_preexec' DEBUG
    """#

    /// Writes the files to a folder and returns the arguments and environment to start a shell with them.
    static func prepare(shell: String, in folder: URL, environment: [String: String]) -> (arguments: [String], environment: [String: String]) {
        var environment = environment
        let name = URL(fileURLWithPath: shell).lastPathComponent
        let fileManager = FileManager.default
        switch name {
        case "zsh":
            let directory = folder.appendingPathComponent("zsh", isDirectory: true)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try? zshenv.write(to: directory.appendingPathComponent(".zshenv"), atomically: true, encoding: .utf8)
            if let existing = environment["ZDOTDIR"] { environment["ELEVENAM_USER_ZDOTDIR"] = existing }
            environment["ZDOTDIR"] = directory.path
            return (["-l"], environment)
        case "bash":
            let file = folder.appendingPathComponent("bashrc")
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try? bashrc.write(to: file, atomically: true, encoding: .utf8)
            return (["--rcfile", file.path, "-i"], environment)
        default:
            return (["-l"], environment)
        }
    }
}

// MARK: The program behind it

enum TerminalProcessError: LocalizedError {
    case couldNotStart(Int32)

    var errorDescription: String? {
        switch self {
        case .couldNotStart(let code): return "The shell couldn't start (\(String(cString: strerror(code))))."
        }
    }
}

/// A program running in a pseudo-terminal. Output arrives on the main queue.
final class TerminalProcess: @unchecked Sendable {
    let pid: pid_t
    let master: Int32
    private var reader: DispatchSourceRead?
    private var watcher: DispatchSourceProcess?
    private let writeQueue = DispatchQueue(label: "11am.terminal.write")
    private let readQueue = DispatchQueue(label: "11am.terminal.read")
    private(set) var exitStatus: Int32?
    var onData: (([UInt8]) -> Void)?
    var onExit: ((Int32) -> Void)?

    private init(pid: pid_t, master: Int32) {
        self.pid = pid
        self.master = master
    }

    /// Starts a program in a new pseudo-terminal of the given size.
    static func start(executable: String, arguments: [String], environment: [String: String], directory: String,
                      columns: Int, rows: Int, loginName: Bool = false) throws -> TerminalProcess {
        let name = URL(fileURLWithPath: executable).lastPathComponent
        let argv0 = loginName ? "-" + name : name
        // Everything the child needs is made before forking: after fork it only changes folder and runs the program.
        func cString(_ text: String) -> UnsafeMutablePointer<CChar> { strdup(text)! }
        let argumentList = [argv0] + arguments
        let argv = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: argumentList.count + 1)
        for (index, argument) in argumentList.enumerated() { argv[index] = cString(argument) }
        argv[argumentList.count] = nil
        let pairs = environment.map { "\($0.key)=\($0.value)" }
        let envp = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: pairs.count + 1)
        for (index, pair) in pairs.enumerated() { envp[index] = cString(pair) }
        envp[pairs.count] = nil
        let path = cString(executable)
        let folder = cString(directory)
        defer {
            for index in 0..<argumentList.count { free(argv[index]) }
            argv.deallocate()
            for index in 0..<pairs.count { free(envp[index]) }
            envp.deallocate()
            free(path)
            free(folder)
        }
        var master: Int32 = -1
        var size = winsize(ws_row: UInt16(clamping: rows), ws_col: UInt16(clamping: columns), ws_xpixel: 0, ws_ypixel: 0)
        let pid = forkpty(&master, nil, nil, &size)
        if pid == 0 {
            _ = chdir(folder)
            execve(path, argv, envp)
            _exit(127)
        }
        guard pid > 0 else { throw TerminalProcessError.couldNotStart(errno) }
        let flags = fcntl(master, F_GETFL)
        _ = fcntl(master, F_SETFL, flags | O_NONBLOCK)
        let process = TerminalProcess(pid: pid, master: master)
        process.listen()
        return process
    }

    private func listen() {
        let reader = DispatchSource.makeReadSource(fileDescriptor: master, queue: readQueue)
        reader.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 65_536)
            var chunk: [UInt8] = []
            while true {
                let count = read(self.master, &buffer, buffer.count)
                if count > 0 {
                    chunk.append(contentsOf: buffer[0..<count])
                    if chunk.count > 512 * 1024 { break }
                } else {
                    if count == 0 || (errno != EAGAIN && errno != EINTR) { self.reader?.cancel() }
                    break
                }
            }
            if !chunk.isEmpty {
                DispatchQueue.main.async { self.onData?(chunk) }
            }
        }
        reader.resume()
        self.reader = reader
        let watcher = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: readQueue)
        watcher.setEventHandler { [weak self] in
            guard let self else { return }
            var status: Int32 = 0
            waitpid(self.pid, &status, 0)
            // Whatever the program wrote last is read before saying it ended.
            var buffer = [UInt8](repeating: 0, count: 65_536)
            var chunk: [UInt8] = []
            while true {
                let count = read(self.master, &buffer, buffer.count)
                if count > 0 { chunk.append(contentsOf: buffer[0..<count]) } else { break }
            }
            let code = (status & 0x7F) == 0 ? (status >> 8) & 0xFF : 128 + (status & 0x7F)
            self.watcher?.cancel()
            DispatchQueue.main.async {
                if !chunk.isEmpty { self.onData?(chunk) }
                self.exitStatus = code
                self.onExit?(code)
            }
        }
        watcher.resume()
        self.watcher = watcher
    }

    func write(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        let master = self.master
        writeQueue.async {
            var offset = 0
            var attempts = 0
            while offset < bytes.count && attempts < 2_000 {
                let written = bytes[offset...].withUnsafeBytes { Darwin.write(master, $0.baseAddress, $0.count) }
                if written > 0 {
                    offset += written
                } else if errno == EAGAIN || errno == EINTR {
                    attempts += 1
                    usleep(1_000)
                } else {
                    return
                }
            }
        }
    }

    func resize(columns: Int, rows: Int) {
        var size = winsize(ws_row: UInt16(clamping: rows), ws_col: UInt16(clamping: columns), ws_xpixel: 0, ws_ypixel: 0)
        // TIOCSWINSZ, which Swift can't import from its C macro.
        _ = ioctl(master, UInt(0x8008_7467), &size)
    }

    /// The program in front (the one you're typing to), by its process group.
    var foregroundGroup: pid_t { tcgetpgrp(master) }

    var isRunningSomething: Bool {
        let group = foregroundGroup
        return group > 0 && group != pid
    }

    func terminate() {
        kill(pid, SIGHUP)
    }

    deinit {
        reader?.cancel()
        watcher?.cancel()
        close(master)
    }
}
