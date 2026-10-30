import AppKit
import SwiftUI

extension NSAttributedString.Key {
    /// Marks lines that get a drawn background: "code", "quote", "callout" or "rule".
    static let docBlock = NSAttributedString.Key("au.elevenam.docBlock")
    /// A picture's source, on the line that shows it underneath.
    static let docImage = NSAttributedString.Key("au.elevenam.docImage")
}

/// The look of the editor, from the theme.
struct DocEditorStyle: Equatable {
    var body: NSFont
    var ink: NSColor
    var secondary: NSColor
    var tertiary: NSColor
    var accent: NSColor
    var shade: NSColor
    var highlight: NSColor
}

enum DocCommand: Equatable {
    case bold, italic, underline, strike, highlight, code, link
    case heading(Int)
    case bullets, numbers, checklist, quote, codeBlock, table, divider
    case indent, outdent
}

/// The SwiftUI side asks the editor to do things (format, jump to a heading) through this.
@MainActor
final class DocEditorController: ObservableObject {
    weak var textView: MarkdownTextView?

    func perform(_ command: DocCommand) {
        textView?.apply(command)
    }

    func scroll(to location: Int) {
        guard let textView else { return }
        let length = (textView.string as NSString).length
        let range = NSRange(location: min(location, length), length: 0)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.window?.makeFirstResponder(textView)
    }

    func insert(_ text: String) {
        guard let textView else { return }
        textView.replace(textView.selectedRange(), with: text, select: nil)
    }

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    func showFind() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        textView.performTextFinderAction(item)
    }
}

/// A Markdown editor that stays plain text underneath (so files stay Markdown and William's suggestions still work)
/// but reads like a formatted page as you type.
struct DocEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var style: DocEditorStyle
    var controller: DocEditorController
    var placeholder = "Start writing…"
    var focusMode = false
    var typewriter = false
    var insets = NSSize(width: 0, height: 14)
    /// Where relative picture paths start.
    var baseURL: URL?
    /// Pasted or dropped files: store them and return the Markdown source to link to (nil to refuse).
    var onAttach: ((Data, String) -> String?)?
    var onWikiLink: ((String) -> Void)?
    var onTag: ((String) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)

        let textView = MarkdownTextView(frame: .zero, textContainer: container)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        // "---" is a divider and "--" is common in Markdown, so dashes stay as typed.
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = true
        textView.textContainerInset = insets
        textView.linkTextAttributes = [.cursor: NSCursor.pointingHand]
        textView.registerForDraggedTypes([.fileURL, .png, .tiff])
        textView.string = text
        textView.emptyHint = placeholder
        textView.onAttach = onAttach
        textView.baseURL = baseURL
        textView.editorStyle = style
        textView.restyle()

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        controller.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        controller.textView = textView
        textView.onAttach = onAttach
        textView.emptyHint = placeholder
        var needsStyle = false
        if textView.baseURL != baseURL {
            textView.baseURL = baseURL
            needsStyle = true
        }
        if textView.string != text {
            context.coordinator.isUpdating = true
            let keep = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            let location = min(keep.location, length)
            textView.setSelectedRange(NSRange(location: location, length: min(keep.length, length - location)))
            context.coordinator.isUpdating = false
            needsStyle = true
        }
        if textView.editorStyle != style || textView.focusMode != focusMode {
            textView.editorStyle = style
            textView.focusMode = focusMode
            needsStyle = true
        }
        if textView.typewriter != typewriter {
            textView.typewriter = typewriter
            textView.updateTypewriterInset()
        }
        if textView.textContainerInset != insets && !typewriter {
            textView.textContainerInset = insets
        }
        if needsStyle { textView.restyle() }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DocEditor
        var isUpdating = false

        init(_ parent: DocEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? MarkdownTextView else { return }
            if !textView.hasMarkedText() { textView.restyle() }
            parent.text = textView.string
            textView.keepCaretCentred()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? MarkdownTextView else { return }
            let range = textView.selectedRange()
            if textView.focusMode && !textView.hasMarkedText() { textView.restyle() }
            textView.keepCaretCentred()
            // Selection changes arrive mid-update; hand them to SwiftUI on the next turn.
            DispatchQueue.main.async { [weak self] in
                self?.parent.selection = range
            }
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
            guard let url else { return false }
            // "elevenam-note:Acme%20pilot": everything after the scheme, as it was typed.
            let value = url.absoluteString.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init)?.removingPercentEncoding ?? ""
            switch url.scheme {
            case "elevenam-note":
                parent.onWikiLink?(value)
                return true
            case "elevenam-tag":
                parent.onTag?(value)
                return true
            default:
                NSWorkspace.shared.open(url)
                return true
            }
        }
    }
}

// MARK: Text view

final class MarkdownTextView: NSTextView {
    var editorStyle = DocEditorStyle(body: .systemFont(ofSize: 14), ink: .textColor, secondary: .secondaryLabelColor,
                                     tertiary: .tertiaryLabelColor, accent: .linkColor, shade: .quaternaryLabelColor, highlight: .yellow)
    var focusMode = false
    var typewriter = false
    var emptyHint = ""
    var onAttach: ((Data, String) -> String?)?
    var baseURL: URL?
    private var pictures: [String: NSImage] = [:]
    private var missing: Set<String> = []

    /// A picture for a Markdown source, loaded once.
    func picture(_ source: String) -> NSImage? {
        if let cached = pictures[source] { return cached }
        if missing.contains(source) { return nil }
        let path = source.removingPercentEncoding ?? source
        var url: URL?
        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else if let parsed = URL(string: source), parsed.isFileURL {
            url = parsed
        } else if let baseURL, URL(string: source)?.scheme == nil {
            url = baseURL.appendingPathComponent(path)
        }
        guard let url, let image = NSImage(contentsOf: url), image.size.width > 0 else {
            missing.insert(source)
            return nil
        }
        pictures[source] = image
        return image
    }

    /// How big a picture shows: the page's width at most, and never taller than 360 points.
    func previewSize(_ source: String) -> CGSize? {
        guard let image = picture(source) else { return nil }
        let width = max((textContainer?.size.width ?? 500) - 4, 80)
        let scale = min(1, width / image.size.width, 360 / image.size.height)
        return CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
    }

    // MARK: Styling

    func restyle() {
        guard let storage = textStorage else { return }
        let focus: NSRange? = focusMode ? (string as NSString).paragraphRange(for: selectedRange()) : nil
        missing.removeAll()
        MarkdownStyler.style(storage, style: editorStyle, focus: focus) { [weak self] source in self?.previewSize(source) }
        typingAttributes = [.font: editorStyle.body, .foregroundColor: editorStyle.ink, .paragraphStyle: MarkdownStyler.bodyParagraph]
        insertionPointColor = editorStyle.ink
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !emptyHint.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: editorStyle.body, .foregroundColor: editorStyle.tertiary]
        (emptyHint as NSString).draw(at: NSPoint(x: textContainerOrigin.x, y: textContainerOrigin.y), withAttributes: attributes)
    }

    /// Code blocks, quote bars, callouts and dividers are drawn behind the text, the full width of their lines.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage, storage.length > 0 else { return }
        let glyphs = layout.glyphRange(forBoundingRect: rect, in: container)
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let origin = textContainerOrigin
        storage.enumerateAttribute(.docBlock, in: characters) { value, range, _ in
            guard let kind = value as? String else { return }
            var area = NSRect.null
            let lines = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layout.enumerateLineFragments(forGlyphRange: lines) { fragment, _, _, _, _ in
                area = area.union(fragment)
            }
            guard !area.isNull else { return }
            area = area.offsetBy(dx: origin.x, dy: origin.y)
            switch kind {
            case "code":
                self.editorStyle.shade.setFill()
                NSBezierPath(roundedRect: area.insetBy(dx: -8, dy: 0), xRadius: 6, yRadius: 6).fill()
            case "callout":
                self.editorStyle.shade.setFill()
                NSBezierPath(roundedRect: area.insetBy(dx: -8, dy: 0), xRadius: 6, yRadius: 6).fill()
                self.editorStyle.secondary.setFill()
                NSBezierPath(roundedRect: NSRect(x: area.minX - 8, y: area.minY, width: 3, height: area.height), xRadius: 1.5, yRadius: 1.5).fill()
            case "quote":
                self.editorStyle.tertiary.setFill()
                NSBezierPath(roundedRect: NSRect(x: area.minX, y: area.minY + 2, width: 2.5, height: area.height - 4), xRadius: 1.25, yRadius: 1.25).fill()
            case "rule":
                self.editorStyle.tertiary.setFill()
                NSRect(x: area.minX, y: area.midY.rounded(), width: area.width, height: 1).fill()
            default:
                break
            }
        }
        storage.enumerateAttribute(.docImage, in: characters) { value, range, _ in
            guard let source = value as? String, let image = self.picture(source), let size = self.previewSize(source) else { return }
            let glyph = layout.glyphIndexForCharacter(at: range.location)
            let used = layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            let frame = NSRect(x: origin.x, y: used.maxY + origin.y + 6, width: size.width, height: size.height)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6).addClip()
            image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    // MARK: Clicking checkboxes

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        let ns = string as NSString
        if ns.length > 0 {
            let line = ns.lineRange(for: NSRange(location: min(index, ns.length - 1), length: 0))
            let local = MarkdownLines.lines(ns.substring(with: line))
            if let first = local.first, let box = first.checkboxRange {
                let absolute = NSRange(location: line.location + box.location, length: 3)
                if index >= absolute.location && index <= NSMaxRange(absolute) {
                    let tick = NSRange(location: absolute.location + 1, length: 1)
                    replace(tick, with: first.task == true ? " " : "x", select: selectedRange())
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: Editing helpers

    /// One undoable change.
    func replace(_ range: NSRange, with text: String, select: NSRange?) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
        if let select {
            let length = (string as NSString).length
            let location = min(select.location, length)
            setSelectedRange(NSRange(location: location, length: min(select.length, length - location)))
        }
    }

    private static let listMarker = MarkdownLines.regex(#"^([ \t]*)([-*+]|(\d{1,9})([.)]))([ \t]+)(\[[ xX]\][ \t]+)?"#)
    private static let quoteMarker = MarkdownLines.regex(#"^([ \t]*)>[ \t]?"#)
    private static let anyMarker = MarkdownLines.regex(#"^([ \t]*)([-*+][ \t]+\[[ xX]\][ \t]+|[-*+][ \t]+|\d{1,9}[.)][ \t]+|>[ \t]?|#{1,6}[ \t]+)"#)

    override func insertNewline(_ sender: Any?) {
        let ns = string as NSString
        let caret = selectedRange()
        guard caret.length == 0, ns.length > 0 else { return super.insertNewline(sender) }
        let lineRange = ns.lineRange(for: NSRange(location: caret.location, length: 0))
        var line = ns.substring(with: lineRange)
        if line.hasSuffix("\n") { line.removeLast() }
        let local = NSRange(location: 0, length: (line as NSString).length)

        if let match = Self.listMarker.firstMatch(in: line, range: local) {
            let rest = (line as NSString).substring(from: match.range.length)
            if rest.trimmingCharacters(in: .whitespaces).isEmpty {
                // Return on an empty item ends the list.
                replace(NSRange(location: lineRange.location, length: (line as NSString).length), with: "", select: NSRange(location: lineRange.location, length: 0))
                return
            }
            let indent = (line as NSString).substring(with: match.range(at: 1))
            var next: String
            if match.range(at: 3).location != NSNotFound, let number = Int((line as NSString).substring(with: match.range(at: 3))) {
                next = indent + "\(number + 1)" + (line as NSString).substring(with: match.range(at: 4)) + " "
            } else {
                next = indent + (line as NSString).substring(with: match.range(at: 2)) + " "
            }
            if match.range(at: 6).location != NSNotFound { next += "[ ] " }
            replace(caret, with: "\n" + next, select: NSRange(location: caret.location + 1 + (next as NSString).length, length: 0))
            return
        }
        if let match = Self.quoteMarker.firstMatch(in: line, range: local) {
            let rest = (line as NSString).substring(from: match.range.length)
            if rest.trimmingCharacters(in: .whitespaces).isEmpty {
                replace(NSRange(location: lineRange.location, length: (line as NSString).length), with: "", select: NSRange(location: lineRange.location, length: 0))
                return
            }
            replace(caret, with: "\n> ", select: NSRange(location: caret.location + 3, length: 0))
            return
        }
        super.insertNewline(sender)
    }

    override func insertTab(_ sender: Any?) {
        if currentLineIsListItem { apply(.indent) } else { super.insertTab(sender) }
    }

    override func insertBacktab(_ sender: Any?) {
        if currentLineIsListItem { apply(.outdent) } else { super.insertBacktab(sender) }
    }

    private var currentLineIsListItem: Bool {
        let ns = string as NSString
        guard ns.length > 0 else { return false }
        let line = ns.substring(with: ns.lineRange(for: NSRange(location: min(selectedRange().location, ns.length), length: 0)))
        return Self.listMarker.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    // MARK: Commands

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        var command: DocCommand?
        if flags == [.command] {
            switch key {
            case "b": command = .bold
            case "i": command = .italic
            case "u": command = .underline
            case "k": command = .link
            case "e": command = .code
            default: break
            }
        } else if flags == [.command, .shift] {
            switch key {
            case "x": command = .strike
            case "h": command = .highlight
            case "7", "&": command = .numbers
            case "8", "*": command = .bullets
            case "9", "(", "l": command = .checklist
            case ".", ">": command = .quote
            default: break
            }
        } else if flags == [.command, .option] {
            switch key {
            case "0", "º": command = .heading(0)
            case "1", "¡": command = .heading(1)
            case "2", "™": command = .heading(2)
            case "3", "£": command = .heading(3)
            default: break
            }
        }
        if let command {
            apply(command)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func apply(_ command: DocCommand) {
        switch command {
        case .bold: wrap("**")
        case .italic: wrap("*")
        case .underline: wrap("++")
        case .strike: wrap("~~")
        case .highlight: wrap("==")
        case .code:
            if (string as NSString).substring(with: selectedRange()).contains("\n") { apply(.codeBlock) } else { wrap("`") }
        case .link: link()
        case .heading(let level):
            transformLines { line, _ in
                let stripped = Self.strip(line, heading: true)
                return level == 0 ? stripped : String(repeating: "#", count: level) + " " + stripped
            }
        case .bullets:
            toggleLines(prefix: "- ", matches: { $0.hasPrefix("- ") && !$0.hasPrefix("- [") })
        case .numbers:
            let all = selectedLines().allSatisfy { $0.range(of: #"^\d+[.)] "#, options: .regularExpression) != nil || $0.isEmpty }
            transformLines { line, index in all ? Self.strip(line) : "\(index + 1). " + Self.strip(line) }
        case .checklist:
            toggleLines(prefix: "- [ ] ", matches: { $0.range(of: #"^[-*+] \[[ xX]\] "#, options: .regularExpression) != nil })
        case .quote:
            toggleLines(prefix: "> ", matches: { $0.hasPrefix(">") })
        case .codeBlock:
            let range = selectedRange()
            let selected = (string as NSString).substring(with: range)
            let block = "```\n" + selected + (selected.hasSuffix("\n") || selected.isEmpty ? "" : "\n") + "```\n"
            let lead = needsLeadingNewline(at: range.location) ? "\n" : ""
            replace(range, with: lead + block, select: NSRange(location: range.location + (lead as NSString).length + 4, length: (selected as NSString).length))
        case .table:
            let table = "| Column | Column |\n| --- | --- |\n|  |  |\n"
            let at = selectedRange()
            let lead = needsLeadingNewline(at: at.location) ? "\n\n" : ""
            replace(at, with: lead + table, select: NSRange(location: at.location + (lead as NSString).length + 2, length: 6))
        case .divider:
            let at = selectedRange()
            let lead = needsLeadingNewline(at: at.location) ? "\n\n" : ""
            replace(at, with: lead + "---\n", select: NSRange(location: at.location + (lead as NSString).length + 4, length: 0))
        case .indent:
            transformLines { line, _ in line.isEmpty ? line : "  " + line }
        case .outdent:
            transformLines { line, _ in
                if line.hasPrefix("\t") { return String(line.dropFirst()) }
                if line.hasPrefix("  ") { return String(line.dropFirst(2)) }
                return line.hasPrefix(" ") ? String(line.dropFirst()) : line
            }
        }
    }

    private func needsLeadingNewline(at location: Int) -> Bool {
        let ns = string as NSString
        guard location > 0, location <= ns.length else { return false }
        return ns.character(at: location - 1) != 10
    }

    /// Wraps the selection in markers, or takes them off if they're already there.
    private func wrap(_ marker: String) {
        let ns = string as NSString
        var range = selectedRange()
        let length = (marker as NSString).length
        if range.location >= length, NSMaxRange(range) + length <= ns.length,
           ns.substring(with: NSRange(location: range.location - length, length: length)) == marker,
           ns.substring(with: NSRange(location: NSMaxRange(range), length: length)) == marker {
            let outer = NSRange(location: range.location - length, length: range.length + length * 2)
            replace(outer, with: ns.substring(with: range), select: NSRange(location: outer.location, length: range.length))
            return
        }
        let selected = ns.substring(with: range)
        if selected.count > length * 2, selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let inner = String(selected.dropFirst(marker.count).dropLast(marker.count))
            replace(range, with: inner, select: NSRange(location: range.location, length: (inner as NSString).length))
            return
        }
        // Keep spaces outside the markers: "**word** " not "**word **".
        while range.length > 0, let scalar = UnicodeScalar(ns.character(at: NSMaxRange(range) - 1)), CharacterSet.whitespacesAndNewlines.contains(scalar) {
            range.length -= 1
        }
        while range.length > 0, let scalar = UnicodeScalar(ns.character(at: range.location)), CharacterSet.whitespacesAndNewlines.contains(scalar) {
            range.location += 1
            range.length -= 1
        }
        let text = ns.substring(with: range)
        replace(range, with: marker + text + marker, select: NSRange(location: range.location + length, length: range.length))
    }

    private func link() {
        let range = selectedRange()
        let selected = (string as NSString).substring(with: range)
        if let url = URL(string: selected.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true {
            replace(range, with: "[](\(selected))", select: NSRange(location: range.location + 1, length: 0))
            return
        }
        let placeholder = "https://"
        let text = "[\(selected)](\(placeholder))"
        let urlStart = range.location + (selected as NSString).length + 3
        replace(range, with: text, select: selected.isEmpty ? NSRange(location: range.location + 1, length: 0)
                                                           : NSRange(location: urlStart, length: (placeholder as NSString).length))
    }

    private func selectedLineRange() -> NSRange {
        let ns = string as NSString
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        var range = ns.lineRange(for: selectedRange())
        // Leave the final line break out, so the selection after the change doesn't run onto the next line.
        if range.length > 0, ns.character(at: NSMaxRange(range) - 1) == 10 { range.length -= 1 }
        return range
    }

    private func selectedLines() -> [String] {
        (string as NSString).substring(with: selectedLineRange()).components(separatedBy: "\n")
    }

    private func transformLines(_ transform: (String, Int) -> String) {
        let range = selectedLineRange()
        let lines = selectedLines()
        var counter = 0
        let changed = lines.map { line -> String in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            defer { counter += 1 }
            return transform(line, counter)
        }.joined(separator: "\n")
        let caretAtEnd = selectedRange().length == 0
        replace(range, with: changed, select: caretAtEnd ? NSRange(location: range.location + (changed as NSString).length, length: 0)
                                                        : NSRange(location: range.location, length: (changed as NSString).length))
    }

    private func toggleLines(prefix: String, matches: @escaping (String) -> Bool) {
        let lines = selectedLines().filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let indent = { (line: String) in String(line.prefix { $0 == " " || $0 == "\t" }) }
        let all = !lines.isEmpty && lines.allSatisfy { matches(String($0.drop { $0 == " " || $0 == "\t" })) }
        transformLines { line, _ in
            let lead = indent(line)
            let stripped = Self.strip(line)
            return all ? lead + stripped : lead + prefix + stripped
        }
    }

    /// The line without its list, quote (or heading) marker or indentation.
    static func strip(_ line: String, heading: Bool = true) -> String {
        let local = NSRange(location: 0, length: (line as NSString).length)
        guard let match = anyMarker.firstMatch(in: line, range: local) else { return line.trimmingCharacters(in: .whitespaces) }
        let marker = (line as NSString).substring(with: match.range(at: 2))
        if !heading && marker.hasPrefix("#") { return line }
        return (line as NSString).substring(from: match.range.length)
    }

    // MARK: Typewriter scrolling

    func updateTypewriterInset() {
        guard let scrollView = enclosingScrollView else { return }
        let half = typewriter ? max(scrollView.contentSize.height / 2 - 40, 14) : 14
        textContainerInset = NSSize(width: textContainerInset.width, height: half)
        keepCaretCentred()
    }

    /// Keeps the line you're typing on in the middle of the page.
    func keepCaretCentred() {
        guard typewriter, let layout = layoutManager, let clip = enclosingScrollView?.contentView, layout.numberOfGlyphs > 0 else { return }
        let length = (string as NSString).length
        let caret = min(selectedRange().location, length)
        let glyph = layout.glyphIndexForCharacter(at: min(caret, max(length - 1, 0)))
        let line = layout.lineFragmentRect(forGlyphAt: min(glyph, layout.numberOfGlyphs - 1), effectiveRange: nil)
        let target = line.midY + textContainerOrigin.y - clip.bounds.height / 2
        let maxY = max(0, frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: min(max(0, target), maxY)))
        enclosingScrollView?.reflectScrolledClipView(clip)
    }

    // MARK: Pictures and files

    override func paste(_ sender: Any?) {
        if attach(from: NSPasteboard.general, at: selectedRange()) { return }
        let pasteboard = NSPasteboard.general
        // Rich text from a web page or another app arrives as Markdown.
        if pasteboard.string(forType: .string) == nil || pasteboard.availableType(from: [.rtf, .html]) != nil,
           let markdown = Self.markdown(from: pasteboard), !markdown.isEmpty {
            replace(selectedRange(), with: markdown, select: nil)
            return
        }
        super.paste(sender)
    }

    private static func markdown(from pasteboard: NSPasteboard) -> String? {
        if let data = pasteboard.data(forType: .rtf), let text = NSAttributedString(rtf: data, documentAttributes: nil) {
            return DocImport.markdown(from: text).trimmingCharacters(in: .newlines)
        }
        if let html = pasteboard.string(forType: .html), let data = html.data(using: .utf8),
           let text = NSAttributedString(html: data, options: [.characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) {
            return DocImport.markdown(from: text).trimmingCharacters(in: .newlines)
        }
        return nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let point = convert(sender.draggingLocation, from: nil)
        let index = characterIndexForInsertion(at: point)
        if attach(from: sender.draggingPasteboard, at: NSRange(location: index, length: 0)) { return true }
        return super.performDragOperation(sender)
    }

    /// Files and pictures become attachments: `![](…)` for pictures, a link for anything else.
    private func attach(from pasteboard: NSPasteboard, at range: NSRange) -> Bool {
        guard let onAttach else { return false }
        var pieces: [String] = []
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        for url in urls {
            guard let data = try? Data(contentsOf: url), let source = onAttach(data, url.lastPathComponent) else { continue }
            let isImage = ["png", "jpg", "jpeg", "gif", "heic", "tiff", "webp"].contains(url.pathExtension.lowercased())
            pieces.append(isImage ? "![](\(source))" : "[\(url.lastPathComponent)](\(source))")
        }
        if urls.isEmpty, pasteboard.availableType(from: [.png, .tiff]) != nil, pasteboard.string(forType: .string) == nil,
           let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]), let source = onAttach(png, "Pasted image.png") {
            pieces.append("![](\(source))")
        }
        guard !pieces.isEmpty else { return false }
        let ns = string as NSString
        let lead = range.location > 0 && range.location <= ns.length && ns.character(at: range.location - 1) != 10 ? "\n" : ""
        let text = lead + pieces.joined(separator: "\n") + "\n"
        replace(range, with: text, select: NSRange(location: range.location + (text as NSString).length, length: 0))
        return true
    }
}

// MARK: Styling

enum MarkdownStyler {
    /// Only plain ASCII letters and digits stay unescaped in a link, so any title survives the round trip.
    static let asciiWord = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    static let bodyParagraph: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 3
        return style
    }()

    static func headingFont(_ level: Int, body: NSFont) -> NSFont {
        let sizes: [CGFloat] = [0, 1.75, 1.42, 1.2, 1.08, 1, 1]
        let size = (body.pointSize * sizes[min(max(level, 1), 6)]).rounded()
        return NSFont.systemFont(ofSize: size, weight: level <= 2 ? .bold : .semibold)
    }

    static func style(_ storage: NSTextStorage, style: DocEditorStyle, focus: NSRange?, pictureSize: (String) -> CGSize? = { _ in nil }) {
        let text = storage.string
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        storage.beginEditing()
        storage.setAttributes([.font: style.body, .foregroundColor: style.ink, .paragraphStyle: bodyParagraph], range: full)
        let mono = NSFont.monospacedSystemFont(ofSize: max(style.body.pointSize - 2.5, 10), weight: .regular)

        for line in MarkdownLines.lines(text) where line.range.length > 0 {
            switch line.kind {
            case .blank:
                continue
            case .heading:
                let font = headingFont(line.level, body: style.body)
                let paragraph = NSMutableParagraphStyle()
                paragraph.paragraphSpacingBefore = line.level <= 2 ? 10 : 6
                paragraph.paragraphSpacing = 4
                storage.addAttributes([.font: font, .paragraphStyle: paragraph], range: line.range)
                storage.addAttribute(.foregroundColor, value: style.tertiary, range: line.markerRange)
                inline(line.contentRange, ns: ns, storage: storage, font: font, style: style)
            case .paragraph:
                inline(line.contentRange, ns: ns, storage: storage, font: style.body, style: style)
            case .listItem:
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = 4
                paragraph.paragraphSpacing = 2
                let lead = ns.substring(with: NSRange(location: line.range.location, length: line.contentRange.location - line.range.location))
                paragraph.headIndent = (lead as NSString).size(withAttributes: [.font: style.body]).width
                storage.addAttribute(.paragraphStyle, value: paragraph, range: line.range)
                storage.addAttribute(.foregroundColor, value: style.secondary, range: line.markerRange)
                if let box = line.checkboxRange {
                    storage.addAttributes([.foregroundColor: style.ink, .font: mono], range: box)
                    storage.addAttribute(.cursor, value: NSCursor.pointingHand, range: box)
                }
                inline(line.contentRange, ns: ns, storage: storage, font: style.body, style: style)
                if line.task == true {
                    storage.addAttributes([.foregroundColor: style.tertiary, .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: line.contentRange)
                }
            case .quote:
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineSpacing = 4
                paragraph.firstLineHeadIndent = 10
                paragraph.headIndent = 10
                storage.addAttribute(.paragraphStyle, value: paragraph, range: line.range)
                storage.addAttribute(.docBlock, value: line.callout == nil ? "quote" : "callout", range: line.range)
                storage.addAttribute(.foregroundColor, value: style.tertiary, range: line.markerRange)
                if line.callout != nil {
                    storage.addAttribute(.font, value: DocRenderer.trait(style.body, .bold), range: line.contentRange)
                }
                let font = line.callout == nil ? DocRenderer.trait(style.body, .italic) : style.body
                inline(line.contentRange, ns: ns, storage: storage, font: font, style: style, color: line.callout == nil ? style.secondary : nil)
            case .fence:
                storage.addAttributes([.font: mono, .foregroundColor: style.tertiary, .docBlock: "code"], range: line.range)
            case .code:
                storage.addAttributes([.font: mono, .docBlock: "code"], range: line.range)
            case .divider:
                storage.addAttributes([.foregroundColor: style.tertiary.withAlphaComponent(0.25), .docBlock: "rule"], range: line.range)
            case .tableRow:
                storage.addAttribute(.font, value: mono, range: line.range)
                inline(line.contentRange, ns: ns, storage: storage, font: mono, style: style)
                dimPipes(line.range, ns: ns, storage: storage, style: style)
            case .tableDelimiter:
                storage.addAttributes([.font: mono, .foregroundColor: style.tertiary], range: line.range)
            case .image:
                inline(line.contentRange, ns: ns, storage: storage, font: style.body, style: style)
                // The picture itself is drawn in the space under its line.
                if let source = MarkdownInline.parse(ns.substring(with: line.contentRange)).first(where: { $0.kind == .image })?.url,
                   let size = pictureSize(source) {
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.lineSpacing = 4
                    paragraph.paragraphSpacing = size.height + 14
                    storage.addAttributes([.paragraphStyle: paragraph, .docImage: source], range: line.range)
                    storage.addAttribute(.font, value: NSFont.systemFont(ofSize: max(style.body.pointSize - 4, 10)), range: line.range)
                }
            }
        }

        if let focus {
            if focus.location > 0 {
                storage.addAttribute(.foregroundColor, value: style.tertiary.withAlphaComponent(0.35), range: NSRange(location: 0, length: focus.location))
            }
            let end = NSMaxRange(focus)
            if end < ns.length {
                storage.addAttribute(.foregroundColor, value: style.tertiary.withAlphaComponent(0.35), range: NSRange(location: end, length: ns.length - end))
            }
        }
        storage.endEditing()
    }

    private static func dimPipes(_ range: NSRange, ns: NSString, storage: NSTextStorage, style: DocEditorStyle) {
        for index in range.location..<NSMaxRange(range) where ns.character(at: index) == 124 {
            storage.addAttribute(.foregroundColor, value: style.tertiary, range: NSRange(location: index, length: 1))
        }
    }

    private static func inline(_ range: NSRange, ns: NSString, storage: NSTextStorage, font: NSFont, style: DocEditorStyle, color: NSColor? = nil) {
        guard range.length > 0 else { return }
        if let color { storage.addAttribute(.foregroundColor, value: color, range: range) }
        let nodes = MarkdownInline.parse(ns.substring(with: range), offset: range.location)
        apply(nodes, storage: storage, font: font, style: style)
    }

    private static func dimMarkers(_ node: DocInline, storage: NSTextStorage, style: DocEditorStyle, smaller: NSFont? = nil) {
        let before = NSRange(location: node.range.location, length: node.contentRange.location - node.range.location)
        let after = NSRange(location: NSMaxRange(node.contentRange), length: NSMaxRange(node.range) - NSMaxRange(node.contentRange))
        for part in [before, after] where part.length > 0 {
            storage.addAttribute(.foregroundColor, value: style.tertiary, range: part)
            if let smaller { storage.addAttribute(.font, value: smaller, range: part) }
        }
    }

    private static func apply(_ nodes: [DocInline], storage: NSTextStorage, font: NSFont, style: DocEditorStyle) {
        for node in nodes {
            switch node.kind {
            case .text, .lineBreak:
                if node.range.length > node.contentRange.length { dimMarkers(node, storage: storage, style: style) }
            case .strong:
                let bold = DocRenderer.trait(font, .bold)
                storage.addAttribute(.font, value: bold, range: node.contentRange)
                dimMarkers(node, storage: storage, style: style)
                apply(node.children, storage: storage, font: bold, style: style)
            case .emphasis:
                let italic = DocRenderer.trait(font, .italic)
                storage.addAttribute(.font, value: italic, range: node.contentRange)
                dimMarkers(node, storage: storage, style: style)
                apply(node.children, storage: storage, font: italic, style: style)
            case .strike:
                storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: style.secondary], range: node.contentRange)
                dimMarkers(node, storage: storage, style: style)
                apply(node.children, storage: storage, font: font, style: style)
            case .highlight:
                storage.addAttribute(.backgroundColor, value: style.highlight, range: node.contentRange)
                dimMarkers(node, storage: storage, style: style)
                apply(node.children, storage: storage, font: font, style: style)
            case .underline:
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: node.contentRange)
                dimMarkers(node, storage: storage, style: style)
                apply(node.children, storage: storage, font: font, style: style)
            case .code:
                let mono = NSFont.monospacedSystemFont(ofSize: font.pointSize * 0.88, weight: .regular)
                storage.addAttributes([.font: mono, .backgroundColor: style.shade], range: node.range)
                dimMarkers(node, storage: storage, style: style)
            case .link:
                var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: style.accent]
                if let url = URL(string: node.url) { attributes[.link] = url }
                storage.addAttributes(attributes, range: node.contentRange)
                dimMarkers(node, storage: storage, style: style, smaller: NSFont.systemFont(ofSize: font.pointSize * 0.8))
                apply(node.children, storage: storage, font: font, style: style)
                storage.addAttribute(.foregroundColor, value: style.accent, range: node.contentRange)
            case .wikiLink:
                var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: style.accent]
                if let target = node.text.addingPercentEncoding(withAllowedCharacters: asciiWord), let url = URL(string: "elevenam-note:\(target)") {
                    attributes[.link] = url
                }
                storage.addAttributes(attributes, range: node.contentRange)
                dimMarkers(node, storage: storage, style: style)
            case .image:
                storage.addAttribute(.foregroundColor, value: style.tertiary, range: node.range)
                storage.addAttribute(.foregroundColor, value: style.secondary, range: node.contentRange)
            case .tag:
                var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: style.secondary]
                if let tag = node.text.addingPercentEncoding(withAllowedCharacters: asciiWord), let url = URL(string: "elevenam-tag:\(tag)") {
                    attributes[.link] = url
                }
                storage.addAttributes(attributes, range: node.range)
            }
        }
    }
}
