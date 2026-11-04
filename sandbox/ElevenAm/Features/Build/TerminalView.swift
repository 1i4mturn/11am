import AppKit
import SwiftUI
import UserNotifications

/// Colours for the terminal: the 16 theme colours plus text, background, cursor and selection.
struct TerminalPalette: Equatable {
    var name: String
    var background: NSColor
    var foreground: NSColor
    var cursor: NSColor
    var selection: NSColor
    var ansi: [NSColor]

    private static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    /// Near-black with paper-coloured ink, like the rest of 11am at night.
    static let ink = TerminalPalette(
        name: "11am Ink", background: hex(0x131315), foreground: hex(0xECE8E1), cursor: hex(0xF4F0E8),
        selection: hex(0xECE8E1).withAlphaComponent(0.22),
        ansi: [0x1D1D20, 0xE5675B, 0x8BC37A, 0xE3B65F, 0x6E9FE0, 0xC68BD9, 0x63BFC2, 0xCFCAC2,
               0x5C5B5F, 0xF2867B, 0xA8D896, 0xF0CB7E, 0x8FB6F0, 0xD8A6E8, 0x85D3D6, 0xFFFFFF].map(hex)
    )

    /// Warm paper with dark ink.
    static let paper = TerminalPalette(
        name: "11am Paper", background: hex(0xF8F6F1), foreground: hex(0x1B1B1D), cursor: hex(0x1B1B1D),
        selection: hex(0x1B1B1D).withAlphaComponent(0.16),
        ansi: [0x1B1B1D, 0xC2412F, 0x3F8A35, 0x9A6B00, 0x2D62B8, 0x8E4BA8, 0x1F8487, 0x6F6D6A,
               0x8A8884, 0xD85A47, 0x52A247, 0xB68412, 0x4479D0, 0xA563C0, 0x2E9EA1, 0xA9A6A0].map(hex)
    )

    static let all = [ink, paper]

    func color(_ color: TermColor, foreground isForeground: Bool, bold: Bool) -> NSColor {
        switch color {
        case .normal:
            return isForeground ? foreground : background
        case .indexed(let index):
            var number = Int(index)
            if bold && isForeground && number < 8 { number += 8 }
            if number < 16 { return ansi[number] }
            if number < 232 {
                let levels: [CGFloat] = [0, 95, 135, 175, 215, 255]
                let value = number - 16
                return NSColor(srgbRed: levels[value / 36] / 255, green: levels[(value / 6) % 6] / 255, blue: levels[value % 6] / 255, alpha: 1)
            }
            let grey = CGFloat(8 + (number - 232) * 10) / 255
            return NSColor(srgbRed: grey, green: grey, blue: grey, alpha: 1)
        case .rgb(let r, let g, let b):
            return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        }
    }
}

/// One shell: the screen, the program, and what Johnny knows about it.
@MainActor
final class TerminalSession: ObservableObject, Identifiable {
    let id = UUID()
    let emulator: TerminalEmulator
    @Published private(set) var title = "zsh"
    @Published private(set) var directory: String
    @Published private(set) var isRunning = false
    @Published private(set) var exitStatus: Int32?
    @Published private(set) var lastCommand: TermCommand?
    /// A command Johnny thinks could change or delete things, waiting for a second Return.
    @Published var pendingRisk: String?
    /// Something new to draw.
    var onChange: (() -> Void)?
    private var process: TerminalProcess?
    private var commandStarted: Date?
    private var restoredText: String?

    init(directory: String? = nil, restoredText: String? = nil) {
        emulator = TerminalEmulator(columns: 80, rows: 24)
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser.path
        self.restoredText = restoredText
    }

    static var shellPath: String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? ""
        return FileManager.default.isExecutableFile(atPath: shell) ? shell : "/bin/zsh"
    }

    /// Starts the shell at the size the view has worked out.
    func start(columns: Int, rows: Int) {
        guard process == nil else { return }
        emulator.resize(columns: columns, rows: rows)
        if let restoredText, !restoredText.isEmpty {
            emulator.feed("\u{1B}[2m" + restoredText.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n— restored from last time —\u{1B}[0m\r\n")
            self.restoredText = nil
        }
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "11am"
        environment["BASH_SILENCE_DEPRECATION_WARNING"] = "1"
        if environment["LANG"] == nil { environment["LANG"] = "en_AU.UTF-8" }
        let shell = Self.shellPath
        let prepared = ShellIntegration.prepare(shell: shell, in: JSONStore.folder.appendingPathComponent("Shell", isDirectory: true), environment: environment)
        do {
            let process = try TerminalProcess.start(executable: shell, arguments: prepared.arguments, environment: prepared.environment,
                                                    directory: directory, columns: columns, rows: rows, loginName: shell.hasSuffix("zsh"))
            emulator.onResponse = { [weak process] bytes in process?.write(bytes) }
            emulator.onTitle = { [weak self] title in self?.title = title.isEmpty ? URL(fileURLWithPath: shell).lastPathComponent : title }
            emulator.onCommandStarted = { [weak self] in self?.commandStarted = Date() }
            emulator.onCommandFinished = { [weak self] status in self?.finished(status) }
            emulator.onBell = { NSSound.beep() }
            process.onData = { [weak self] bytes in
                guard let self else { return }
                self.emulator.feed(bytes)
                if let folder = self.emulator.directory, folder != self.directory { self.directory = folder }
                self.onChange?()
            }
            process.onExit = { [weak self] status in
                guard let self else { return }
                self.isRunning = false
                self.exitStatus = status
                self.emulator.feed("\r\n\u{1B}[2m[Process finished with exit code \(status). Press Return for a new shell.]\u{1B}[0m\r\n")
                self.onChange?()
            }
            self.process = process
            isRunning = true
            title = URL(fileURLWithPath: shell).lastPathComponent
        } catch {
            emulator.feed("\(error.localizedDescription)\r\n")
        }
        onChange?()
    }

    func restart() {
        process?.terminate()
        process = nil
        exitStatus = nil
        start(columns: emulator.columns, rows: emulator.rows)
    }

    func write(_ bytes: [UInt8]) {
        process?.write(bytes)
    }

    func resize(columns: Int, rows: Int) {
        guard columns != emulator.columns || rows != emulator.rows else { return }
        emulator.resize(columns: columns, rows: rows)
        process?.resize(columns: columns, rows: rows)
        onChange?()
    }

    func terminate() {
        process?.terminate()
    }

    /// Something other than the shell is in front (vim, a build, ssh).
    var isBusy: Bool { process?.isRunningSomething ?? false }

    /// What's been typed at the prompt so far, from the shell's marks.
    var typedCommand: String? {
        let top = emulator.screenTop
        for row in stride(from: emulator.cursorY, through: 0, by: -1) {
            guard let line = emulator.line(top + row) else { continue }
            if let mark = line.marks.last(where: { $0.kind == .commandStart }) {
                return emulator.text(from: (top + row, mark.column), to: (top + emulator.cursorY, emulator.cursorX + 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if line.marks.contains(where: { $0.kind == .outputStart }) { return nil }
        }
        return nil
    }

    private func finished(_ status: Int32?) {
        lastCommand = emulator.commands().last
        let took = commandStarted.map { Date().timeIntervalSince($0) } ?? 0
        commandStarted = nil
        guard took > 10, !NSApp.isActive, let command = lastCommand else { return }
        let content = UNMutableNotificationContent()
        content.title = status == 0 ? "Finished: \(command.command)" : "Failed (\(status ?? -1)): \(command.command)"
        content.body = "Took \(Int(took)) seconds in \(URL(fileURLWithPath: directory).lastPathComponent)."
        let center = UNUserNotificationCenter.current()
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    /// The last few thousand lines as text, for restoring next time.
    func transcript(lines limit: Int = 2_000) -> String {
        if let restoredText { return restoredText }
        let last = emulator.screenTop + emulator.cursorY
        let first = max(emulator.firstLine, last - limit)
        guard first <= last else { return "" }
        return emulator.text(from: (first, 0), to: (last, emulator.columns))
    }
}

/// Draws a terminal session and sends it the keyboard and mouse.
final class TerminalNSView: NSView, NSTextInputClient {
    var session: TerminalSession? {
        didSet {
            guard session !== oldValue else { return }
            oldValue?.onChange = nil
            session?.onChange = { [weak self] in self?.scheduleRedraw() }
            viewTop = nil
            selection = nil
            fitToSize()
            needsDisplay = true
        }
    }
    var palette = TerminalPalette.ink { didSet { if palette != oldValue { needsDisplay = true } } }
    var fontSize: CGFloat = 12.5 { didSet { if fontSize != oldValue { updateFonts(); fitToSize(); needsDisplay = true } } }
    var optionIsMeta = false
    /// Search matches to highlight, with the current one.
    var highlights: [(line: Int, columns: Range<Int>)] = [] { didSet { needsDisplay = true } }
    var currentHighlight: Int? { didSet { revealCurrentHighlight(); needsDisplay = true } }
    var onFocus: (() -> Void)?
    /// Return was pressed on a command that looks risky; the session holds it until Return comes again.
    var riskCheck: ((String) -> Bool)?

    private var regular = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    private var bold = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .bold)
    private var italic = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    private var boldItalic = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .bold)
    private var cellWidth: CGFloat = 7.5
    private var cellHeight: CGFloat = 16
    private var ascent: CGFloat = 12
    private let inset = NSSize(width: 10, height: 6)
    /// The line number at the top of the view, or nil to follow the newest output.
    private var viewTop: Int?
    private var scrollRemainder: CGFloat = 0
    private var redrawPending = false
    private var selection: (anchor: (line: Int, column: Int), head: (line: Int, column: Int))?
    private var markedText = ""
    private var focused = false
    private var scrollbarShownUntil = Date.distantPast

    override init(frame: NSRect) {
        super.init(frame: frame)
        updateFonts()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    private func updateFonts() {
        regular = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        bold = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        italic = NSFontManager.shared.convert(regular, toHaveTrait: .italicFontMask)
        boldItalic = NSFontManager.shared.convert(bold, toHaveTrait: .italicFontMask)
        cellWidth = ceil(("M" as NSString).size(withAttributes: [.font: regular]).width * 100) / 100
        ascent = ceil(regular.ascender)
        cellHeight = ceil((regular.ascender - regular.descender + regular.leading) * 1.12)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fitToSize()
    }

    /// How many columns and rows fit.
    var gridSize: (columns: Int, rows: Int) {
        let columns = Int((bounds.width - inset.width * 2) / cellWidth)
        let rows = Int((bounds.height - inset.height * 2) / cellHeight)
        return (max(columns, 10), max(rows, 3))
    }

    private func fitToSize() {
        guard let session, bounds.width > 40, bounds.height > 30 else { return }
        let size = gridSize
        if session.isRunning || session.exitStatus != nil {
            session.resize(columns: size.columns, rows: size.rows)
        } else {
            // Started just after layout, so nothing changes while SwiftUI is drawing.
            DispatchQueue.main.async { [weak self, weak session] in
                guard let self, let session, self.session === session else { return }
                let size = self.gridSize
                session.start(columns: size.columns, rows: size.rows)
            }
        }
    }

    private func scheduleRedraw() {
        guard !redrawPending else { return }
        redrawPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.redrawPending = false
            self.needsDisplay = true
        }
    }

    // MARK: Drawing

    private var emulator: TerminalEmulator? { session?.emulator }

    /// The line number shown at the top row.
    private var topLine: Int {
        guard let emulator else { return 0 }
        let live = emulator.screenTop
        guard let viewTop else { return live }
        return min(max(viewTop, emulator.firstLine), live)
    }

    override func draw(_ dirtyRect: NSRect) {
        palette.background.setFill()
        dirtyRect.fill()
        guard let emulator else { return }
        let top = topLine
        let rows = emulator.rows
        let selectionRange = normalisedSelection
        for row in 0..<rows {
            let y = inset.height + CGFloat(row) * cellHeight
            guard y < dirtyRect.maxY, y + cellHeight > dirtyRect.minY else { continue }
            let number = top + row
            guard let line = emulator.line(number) else { continue }
            drawLine(line, number: number, y: y, selection: selectionRange)
        }
        drawCursor(emulator, top: top)
        drawScrollbar(emulator, top: top)
    }

    private func drawLine(_ line: TermLine, number: Int, y: CGFloat, selection: ((line: Int, column: Int), (line: Int, column: Int))?) {
        let count = min(line.cells.count, emulator?.columns ?? line.cells.count)
        // Backgrounds and highlights first.
        var column = 0
        while column < count {
            let cell = line.cells[column]
            let paint = colours(for: cell.style)
            if paint.background != palette.background {
                var end = column + 1
                while end < count && colours(for: line.cells[end].style).background == paint.background { end += 1 }
                paint.background.setFill()
                NSRect(x: inset.width + CGFloat(column) * cellWidth, y: y, width: CGFloat(end - column) * cellWidth, height: cellHeight).fill()
                column = end
            } else {
                column += 1
            }
        }
        for (index, match) in highlights.enumerated() where match.line == number {
            let colour = index == currentHighlight ? NSColor.systemYellow.withAlphaComponent(0.75) : NSColor.systemYellow.withAlphaComponent(0.3)
            colour.setFill()
            NSRect(x: inset.width + CGFloat(match.columns.lowerBound) * cellWidth, y: y,
                   width: CGFloat(match.columns.count) * cellWidth, height: cellHeight).fill()
        }
        if let selection, number >= selection.0.line, number <= selection.1.line {
            let from = number == selection.0.line ? selection.0.column : 0
            let to = number == selection.1.line ? selection.1.column : count
            if to > from {
                palette.selection.setFill()
                NSRect(x: inset.width + CGFloat(from) * cellWidth, y: y, width: CGFloat(to - from) * cellWidth, height: cellHeight).fill()
            }
        }
        // Shell marks: a small bar beside each prompt, green when the command before it worked, red when it didn't.
        for mark in line.marks {
            if case .commandEnd(let status) = mark.kind, let status {
                (status == 0 ? NSColor.systemGreen : NSColor.systemRed).withAlphaComponent(0.8).setFill()
                NSRect(x: 2, y: y + 2, width: 3, height: cellHeight - 4).fill()
            }
        }
        // Then the text: plain ASCII runs in one go, anything else cell by cell so it stays on the grid.
        column = 0
        while column < count {
            let cell = line.cells[column]
            if cell.width == 0 || cell.text.isEmpty || cell.text == " " {
                if cell.style.flags.contains(.underline) || cell.style.flags.contains(.strike) { decorate(cell.style, from: column, to: column + 1, y: y) }
                column += 1
                continue
            }
            if cell.text.utf8.count == 1 && cell.width == 1 {
                var end = column + 1
                var text = cell.text
                while end < count, line.cells[end].style == cell.style, line.cells[end].width == 1,
                      line.cells[end].text.utf8.count == 1 {
                    text += line.cells[end].text
                    end += 1
                }
                drawText(text, style: cell.style, column: column, y: y)
                decorate(cell.style, from: column, to: end, y: y)
                column = end
            } else {
                drawText(cell.text, style: cell.style, column: column, y: y, width: Int(cell.width))
                decorate(cell.style, from: column, to: column + Int(max(cell.width, 1)), y: y)
                column += Int(max(cell.width, 1))
            }
        }
    }

    private func colours(for style: TermStyle) -> (foreground: NSColor, background: NSColor) {
        let isBold = style.flags.contains(.bold)
        var foreground = palette.color(style.foreground, foreground: true, bold: isBold)
        var background = palette.color(style.background, foreground: false, bold: false)
        if style.flags.contains(.inverse) != (emulator?.reverseVideo ?? false) {
            swap(&foreground, &background)
            if style.foreground == .normal && style.flags.contains(.inverse) { background = palette.foreground }
        }
        if style.flags.contains(.dim) { foreground = foreground.withAlphaComponent(0.6) }
        if style.flags.contains(.hidden) { foreground = background }
        return (foreground, background)
    }

    private func font(for style: TermStyle) -> NSFont {
        switch (style.flags.contains(.bold), style.flags.contains(.italic)) {
        case (true, true): return boldItalic
        case (true, false): return bold
        case (false, true): return italic
        default: return regular
        }
    }

    private func drawText(_ text: String, style: TermStyle, column: Int, y: CGFloat, width: Int = 1) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font(for: style), .foregroundColor: colours(for: style).foreground]
        let x = inset.width + CGFloat(column) * cellWidth
        if width == 2 || text.unicodeScalars.contains(where: { $0.value > 0x7F }) {
            // Fallback fonts (emoji, CJK) are drawn centred in their cells.
            let size = (text as NSString).size(withAttributes: attributes)
            let room = CGFloat(width) * cellWidth
            let offset = size.width < room ? (room - size.width) / 2 : 0
            (text as NSString).draw(at: NSPoint(x: x + offset, y: y + (cellHeight - size.height) / 2), withAttributes: attributes)
        } else {
            (text as NSString).draw(at: NSPoint(x: x, y: y + (cellHeight - regular.ascender + regular.descender) / 2 - 1), withAttributes: attributes)
        }
    }

    private func decorate(_ style: TermStyle, from: Int, to: Int, y: CGFloat) {
        guard style.flags.contains(.underline) || style.flags.contains(.strike) || style.link != 0 else { return }
        colours(for: style).foreground.setFill()
        let x = inset.width + CGFloat(from) * cellWidth, width = CGFloat(to - from) * cellWidth
        if style.flags.contains(.underline) || style.link != 0 {
            NSRect(x: x, y: y + cellHeight - 2, width: width, height: 1).fill()
        }
        if style.flags.contains(.strike) {
            NSRect(x: x, y: y + cellHeight / 2, width: width, height: 1).fill()
        }
    }

    private func drawCursor(_ emulator: TerminalEmulator, top: Int) {
        guard emulator.cursorVisible || !markedText.isEmpty else { return }
        let row = emulator.screenTop + emulator.cursorY - top
        guard row >= 0, row < emulator.rows else { return }
        let rect = NSRect(x: inset.width + CGFloat(emulator.cursorX) * cellWidth, y: inset.height + CGFloat(row) * cellHeight,
                          width: cellWidth, height: cellHeight)
        if !markedText.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [.font: regular, .foregroundColor: palette.foreground,
                                                             .underlineStyle: NSUnderlineStyle.single.rawValue, .backgroundColor: palette.background]
            (markedText as NSString).draw(at: NSPoint(x: rect.minX, y: rect.minY), withAttributes: attributes)
            return
        }
        palette.cursor.set()
        switch emulator.cursorShape {
        case 3, 4:
            NSRect(x: rect.minX, y: rect.maxY - 2, width: rect.width, height: 2).fill()
        case 5, 6:
            NSRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height).fill()
        default:
            if focused {
                rect.fill()
                // The character under a block cursor, in the background colour.
                if let line = emulator.line(emulator.screenTop + emulator.cursorY), emulator.cursorX < line.cells.count {
                    let cell = line.cells[emulator.cursorX]
                    if !cell.text.isEmpty && cell.width != 0 {
                        let attributes: [NSAttributedString.Key: Any] = [.font: font(for: cell.style), .foregroundColor: palette.background]
                        (cell.text as NSString).draw(at: NSPoint(x: rect.minX, y: rect.minY + (cellHeight - regular.ascender + regular.descender) / 2 - 1),
                                                     withAttributes: attributes)
                    }
                }
            } else {
                let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
                path.lineWidth = 1
                path.stroke()
            }
        }
    }

    private func drawScrollbar(_ emulator: TerminalEmulator, top: Int) {
        let total = emulator.lineCount
        guard total > emulator.rows, Date() < scrollbarShownUntil || viewTop != nil else { return }
        let height = bounds.height - 8
        let thumb = max(24, height * CGFloat(emulator.rows) / CGFloat(total))
        let progress = CGFloat(top - emulator.firstLine) / CGFloat(max(total - emulator.rows, 1))
        let rect = NSRect(x: bounds.width - 7, y: 4 + (height - thumb) * progress, width: 4, height: thumb)
        palette.foreground.withAlphaComponent(0.28).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
    }

    // MARK: Scrolling

    override func scrollWheel(with event: NSEvent) {
        guard let emulator else { return }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / cellHeight : event.scrollingDeltaY * 3
        scrollRemainder += delta
        let lines = Int(scrollRemainder)
        guard lines != 0 else { return }
        scrollRemainder -= CGFloat(lines)
        if emulator.mouseMode != .off && !event.modifierFlags.contains(.shift) {
            let point = cell(at: convert(event.locationInWindow, from: nil))
            for _ in 0..<abs(lines) {
                session?.write(TerminalKeys.mouse(lines > 0 ? .wheelUp : .wheelDown, column: point.column, row: point.row, pressed: true, sgr: emulator.mouseSGR))
            }
            return
        }
        if emulator.isAlternateScreen {
            // Full-screen programs without the mouse get arrow keys, like most terminals.
            for _ in 0..<abs(lines) {
                session?.write(TerminalKeys.encode(lines > 0 ? .up : .down, applicationCursor: emulator.applicationCursor))
            }
            return
        }
        scroll(by: -lines)
    }

    /// Scrolls by lines; positive goes towards newer output.
    func scroll(by lines: Int) {
        guard let emulator else { return }
        let target = topLine + lines
        viewTop = target >= emulator.screenTop ? nil : max(target, emulator.firstLine)
        scrollbarShownUntil = Date().addingTimeInterval(1.2)
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self] in self?.needsDisplay = true }
    }

    func scrollToBottom() {
        viewTop = nil
        needsDisplay = true
    }

    /// Puts a line near the top of the view.
    func reveal(line: Int) {
        guard let emulator else { return }
        let visible = topLine..<(topLine + emulator.rows)
        guard !visible.contains(line) else { return }
        viewTop = line - emulator.rows / 3
        if let viewTop, viewTop >= emulator.screenTop { self.viewTop = nil }
        scrollbarShownUntil = Date().addingTimeInterval(1.2)
        needsDisplay = true
    }

    private func revealCurrentHighlight() {
        guard let currentHighlight, highlights.indices.contains(currentHighlight) else { return }
        reveal(line: highlights[currentHighlight].line)
    }

    /// Jumps to the previous or next prompt.
    func jumpToPrompt(forward: Bool) {
        guard let emulator else { return }
        let prompts = emulator.commands().map(\.promptLine)
        let top = topLine
        if forward {
            if let next = prompts.first(where: { $0 > top }) { viewTop = next >= emulator.screenTop ? nil : next } else { viewTop = nil }
        } else if let previous = prompts.last(where: { $0 < top }) {
            viewTop = previous
        }
        scrollbarShownUntil = Date().addingTimeInterval(1.2)
        needsDisplay = true
    }

    // MARK: Mouse and selection

    private func cell(at point: NSPoint) -> (column: Int, row: Int) {
        let column = Int((point.x - inset.width) / cellWidth)
        let row = Int((point.y - inset.height) / cellHeight)
        return (max(0, min(column, (emulator?.columns ?? 1) - 1)), max(0, min(row, (emulator?.rows ?? 1) - 1)))
    }

    private func position(at point: NSPoint) -> (line: Int, column: Int) {
        let spot = cell(at: point)
        let column = Int(((point.x - inset.width) / cellWidth).rounded())
        return (topLine + spot.row, max(0, min(column, emulator?.columns ?? 0)))
    }

    private var normalisedSelection: ((line: Int, column: Int), (line: Int, column: Int))? {
        guard let selection else { return nil }
        let a = selection.anchor, b = selection.head
        if (a.line, a.column) == (b.line, b.column) { return nil }
        return (a.line, a.column) < (b.line, b.column) ? (a, b) : (b, a)
    }

    var selectedText: String? {
        guard let range = normalisedSelection, let emulator else { return nil }
        return emulator.text(from: range.0, to: range.1)
    }

    private func modifiers(_ event: NSEvent) -> TerminalKeys.Modifiers {
        var modifiers: TerminalKeys.Modifiers = []
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }

    private func reportsMouse(_ event: NSEvent) -> Bool {
        (emulator?.mouseMode ?? .off) != .off && !event.modifierFlags.contains(.shift)
    }

    private func sendMouse(_ button: TerminalKeys.MouseButton, _ event: NSEvent, pressed: Bool, moving: Bool = false) {
        guard let emulator else { return }
        let spot = cell(at: convert(event.locationInWindow, from: nil))
        session?.write(TerminalKeys.mouse(button, column: spot.column, row: spot.row, pressed: pressed, moving: moving,
                                          modifiers: modifiers(event), sgr: emulator.mouseSGR))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onFocus?()
        if reportsMouse(event) {
            sendMouse(.left, event, pressed: true)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.command), openLink(at: point) { return }
        let spot = position(at: point)
        switch event.clickCount {
        case 2: selectWord(at: spot)
        case 3: selection = ((spot.line, 0), (spot.line, emulator?.columns ?? 0))
        default: selection = (spot, spot)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if reportsMouse(event) {
            if emulator?.mouseMode == .drags || emulator?.mouseMode == .motion { sendMouse(.left, event, pressed: true, moving: true) }
            return
        }
        guard selection != nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection?.head = position(at: point)
        if point.y < 0 { scroll(by: -1) } else if point.y > bounds.height { scroll(by: 1) }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if reportsMouse(event) { sendMouse(.left, event, pressed: false) }
    }

    override func rightMouseDown(with event: NSEvent) {
        if reportsMouse(event) {
            sendMouse(.right, event, pressed: true)
            return
        }
        super.rightMouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        for (title, action) in [("Copy", #selector(copy(_:))), ("Paste", #selector(paste(_:))), ("Select All", #selector(selectEverything(_:))),
                                ("Clear Scrollback", #selector(clearScrollback(_:)))] {
            if title == "Select All" { menu.addItem(.separator()) }
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    private func selectWord(at spot: (line: Int, column: Int)) {
        guard let line = emulator?.line(spot.line) else { return }
        func isWord(_ index: Int) -> Bool {
            guard line.cells.indices.contains(index) else { return false }
            let text = line.cells[index].text
            return !text.isEmpty && text != " " && !"()[]{}<>'\"`|,;".contains(text)
        }
        var start = min(spot.column, line.cells.count - 1), end = start
        guard isWord(start) else { return }
        while start > 0 && isWord(start - 1) { start -= 1 }
        while end < line.cells.count - 1 && isWord(end + 1) { end += 1 }
        selection = ((spot.line, start), (spot.line, end + 1))
    }

    /// ⌘-click: a hyperlink, a web address, or a file path on the line.
    private func openLink(at point: NSPoint) -> Bool {
        guard let emulator else { return false }
        let spot = position(at: point)
        let column = cell(at: point).column
        guard let line = emulator.line(spot.line) else { return false }
        if column < line.cells.count, line.cells[column].style.link != 0, let target = emulator.links[line.cells[column].style.link],
           let url = URL(string: target) {
            NSWorkspace.shared.open(url)
            return true
        }
        let text = line.text
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) where match.range.contains(column) {
                if let url = match.url {
                    NSWorkspace.shared.open(url)
                    return true
                }
            }
        }
        // A path: the run of non-space characters under the pointer.
        let characters = Array(line.cells.map { $0.text.isEmpty ? " " : $0.text })
        guard characters.indices.contains(column), characters[column] != " " else { return false }
        var start = column, end = column
        while start > 0 && characters[start - 1] != " " { start -= 1 }
        while end < characters.count - 1 && characters[end + 1] != " " { end += 1 }
        var path = characters[start...end].joined().trimmingCharacters(in: CharacterSet(charactersIn: "'\":,()"))
        if let colon = path.firstIndex(of: ":"), path[path.index(after: colon)...].allSatisfy({ $0.isNumber || $0 == ":" }) {
            path = String(path[..<colon])
        }
        let expanded = (path as NSString).expandingTildeInPath
        let full = expanded.hasPrefix("/") ? expanded : ((session?.directory ?? NSHomeDirectory()) as NSString).appendingPathComponent(expanded)
        guard FileManager.default.fileExists(atPath: full) else { return false }
        NSWorkspace.shared.open(URL(fileURLWithPath: full))
        return true
    }

    // MARK: Keyboard

    override func becomeFirstResponder() -> Bool {
        focused = true
        if emulator?.focusEvents == true { session?.write(Array("\u{1B}[I".utf8)) }
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        focused = false
        if emulator?.focusEvents == true { session?.write(Array("\u{1B}[O".utf8)) }
        needsDisplay = true
        return true
    }

    private func send(_ bytes: [UInt8]) {
        guard let session else { return }
        selection = nil
        if viewTop != nil { scrollToBottom() }
        session.write(bytes)
    }

    override func keyDown(with event: NSEvent) {
        guard let session, let emulator else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !session.isRunning, event.keyCode == 36 {
            session.restart()
            return
        }
        if flags.contains(.command) {
            // ⌘ arrows and delete edit the line the way Mac text fields do.
            switch event.keyCode {
            case 123: send([0x01]); return
            case 124: send([0x05]); return
            case 51: send([0x15]); return
            case 126: jumpToPrompt(forward: false); return
            case 125: jumpToPrompt(forward: true); return
            default:
                super.keyDown(with: event)
                return
            }
        }
        var modifiers: TerminalKeys.Modifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        let app = emulator.applicationCursor
        let key: TerminalKeys.Key?
        switch event.keyCode {
        case 126: key = .up
        case 125: key = .down
        case 124:
            if flags.contains(.option) && !flags.contains(.control) { send([0x1B, 0x66]); return }
            key = .right
        case 123:
            if flags.contains(.option) && !flags.contains(.control) { send([0x1B, 0x62]); return }
            key = .left
        case 115: key = .home
        case 119: key = .end
        case 116:
            if flags.contains(.shift) { scroll(by: -emulator.rows); return }
            key = .pageUp
        case 121:
            if flags.contains(.shift) { scroll(by: emulator.rows); return }
            key = .pageDown
        case 117: key = .delete
        case 114: key = .insert
        case 122: key = .function(1)
        case 120: key = .function(2)
        case 99: key = .function(3)
        case 118: key = .function(4)
        case 96: key = .function(5)
        case 97: key = .function(6)
        case 98: key = .function(7)
        case 100: key = .function(8)
        case 101: key = .function(9)
        case 109: key = .function(10)
        case 103: key = .function(11)
        case 111: key = .function(12)
        case 48: key = .tab
        case 36, 76:
            if let typed = session.typedCommand, !typed.isEmpty, session.pendingRisk != typed, riskCheck?(typed) == true {
                session.pendingRisk = typed
                return
            }
            session.pendingRisk = nil
            key = .enter
        case 51:
            if flags.contains(.option) { send([0x1B, 0x7F]); return }
            key = .backspace
        case 53: key = .escape
        default: key = nil
        }
        if let key {
            let keyModifiers = (key == .enter || key == .tab || key == .backspace || key == .escape) ? modifiers.subtracting(optionIsMeta ? [] : [.option]) : modifiers
            send(TerminalKeys.encode(key, modifiers: keyModifiers, applicationCursor: app))
            return
        }
        if flags.contains(.control), let characters = event.charactersIgnoringModifiers, !characters.isEmpty {
            send(TerminalKeys.encode(text: characters, modifiers: modifiers.subtracting(optionIsMeta ? [] : [.option]), optionIsMeta: optionIsMeta))
            return
        }
        if flags.contains(.option) && optionIsMeta, let characters = event.charactersIgnoringModifiers, !characters.isEmpty {
            send(TerminalKeys.encode(text: characters, modifiers: [.option], optionIsMeta: true))
            return
        }
        interpretKeyEvents([event])
    }

    override func doCommand(by selector: Selector) {
        // Keys interpretKeyEvents turns into commands are already handled above.
    }

    @objc func copy(_ sender: Any?) {
        guard let text = selectedText, !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func paste(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string), let emulator else { return }
        send(TerminalKeys.paste(text, bracketed: emulator.bracketedPaste))
    }

    @objc func selectEverything(_ sender: Any?) {
        guard let emulator else { return }
        selection = ((emulator.firstLine, 0), (emulator.screenTop + emulator.rows - 1, emulator.columns))
        needsDisplay = true
    }

    @objc func clearScrollback(_ sender: Any?) {
        session?.emulator.feed("\u{1B}[3J")
        viewTop = nil
        needsDisplay = true
    }

    // MARK: Text input (typing, accents, input methods)

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        markedText = ""
        guard !text.isEmpty else { return }
        send(Array(text.utf8))
        needsDisplay = true
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        markedText = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        needsDisplay = true
    }

    func unmarkText() {
        markedText = ""
        needsDisplay = true
    }

    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }

    func markedRange() -> NSRange { markedText.isEmpty ? NSRange(location: NSNotFound, length: 0) : NSRange(location: 0, length: markedText.utf16.count) }

    func hasMarkedText() -> Bool { !markedText.isEmpty }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let emulator, let window else { return .zero }
        let row = emulator.screenTop + emulator.cursorY - topLine
        let rect = NSRect(x: inset.width + CGFloat(emulator.cursorX) * cellWidth, y: inset.height + CGFloat(row + 1) * cellHeight,
                          width: cellWidth, height: cellHeight)
        return window.convertToScreen(convert(rect, to: nil))
    }

    func characterIndex(for point: NSPoint) -> Int { NSNotFound }
}

/// The terminal view in SwiftUI.
struct TerminalSurface: NSViewRepresentable {
    @ObservedObject var session: TerminalSession
    var palette: TerminalPalette
    var fontSize: CGFloat
    var optionIsMeta: Bool
    var highlights: [(line: Int, columns: Range<Int>)]
    var currentHighlight: Int?
    var focusOnAppear: Bool
    var onFocus: () -> Void
    var riskCheck: (String) -> Bool

    func makeNSView(context: Context) -> TerminalNSView {
        let view = TerminalNSView(frame: .zero)
        configure(view)
        if focusOnAppear {
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
        return view
    }

    func updateNSView(_ view: TerminalNSView, context: Context) {
        configure(view)
    }

    private func configure(_ view: TerminalNSView) {
        view.palette = palette
        view.fontSize = fontSize
        view.optionIsMeta = optionIsMeta
        view.onFocus = onFocus
        view.riskCheck = riskCheck
        view.session = session
        if view.highlights.count != highlights.count || zip(view.highlights, highlights).contains(where: { $0.line != $1.line || $0.columns != $1.columns }) {
            view.highlights = highlights
        }
        if view.currentHighlight != currentHighlight { view.currentHighlight = currentHighlight }
    }
}
