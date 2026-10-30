import AppKit

/// How a document looks on paper (and when copied as rich text).
struct DocTypography {
    var body: NSFont
    var heading: (Int) -> NSFont
    var mono: NSFont
    var text: NSColor
    var secondary: NSColor
    var rule: NSColor
    var shade: NSColor
    var link: NSColor

    static func serif(_ size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        guard let descriptor = base.fontDescriptor.withDesign(.serif), let font = NSFont(descriptor: descriptor, size: size) else { return base }
        return font
    }

    /// New York for reading, SF for headings, Menlo for code: the same as the Write page.
    static let print = DocTypography(
        body: serif(11),
        heading: { level in
            let sizes: [CGFloat] = [22, 22, 16.5, 13.5, 12, 11, 11]
            return NSFont.systemFont(ofSize: sizes[min(max(level, 0), 6)], weight: level <= 2 ? .bold : .semibold)
        },
        mono: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular),
        text: NSColor(calibratedWhite: 0.08, alpha: 1),
        secondary: NSColor(calibratedWhite: 0.38, alpha: 1),
        rule: NSColor(calibratedWhite: 0.78, alpha: 1),
        shade: NSColor(calibratedRed: 0.957, green: 0.953, blue: 0.941, alpha: 1),
        link: NSColor(calibratedRed: 0.12, green: 0.37, blue: 0.75, alpha: 1)
    )
}

/// Markdown into typeset text, for PDF, printing and rich-text copy.
enum DocRenderer {
    static func attributed(_ markdown: String, baseURL: URL?, width: CGFloat, maxImageHeight: CGFloat = 600,
                           type: DocTypography = .print) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let blocks = MarkdownBlocks.blocks(markdown)
        var counters: [Int: Int] = [:]
        var previousOrdered: [Int: Bool] = [:]

        func paragraph(_ configure: (NSMutableParagraphStyle) -> Void) -> NSMutableParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = 1.18
            style.paragraphSpacing = 7
            configure(style)
            return style
        }
        func append(_ text: NSAttributedString, style: NSParagraphStyle) {
            let line = NSMutableAttributedString(attributedString: text)
            line.append(NSAttributedString(string: "\n", attributes: [.font: type.body]))
            line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
            result.append(line)
        }
        let base: [NSAttributedString.Key: Any] = [.font: type.body, .foregroundColor: type.text]

        for (index, block) in blocks.enumerated() {
            let nextIsList: Bool = {
                guard index + 1 < blocks.count, case .listItem = blocks[index + 1].kind else { return false }
                return true
            }()
            if case .listItem = block.kind {} else {
                counters = [:]
                previousOrdered = [:]
            }
            switch block.kind {
            case .heading(let level):
                let font = type.heading(level)
                let style = paragraph {
                    $0.paragraphSpacingBefore = level == 1 ? 14 : 10
                    $0.paragraphSpacing = level == 1 ? 8 : 5
                    $0.lineHeightMultiple = 1.05
                }
                append(inline(block.text, attributes: [.font: font, .foregroundColor: type.text], type: type), style: style)
            case .paragraph:
                append(inline(block.text, attributes: base, type: type), style: paragraph { _ in })
            case .listItem(let level, let ordered, let number, let task):
                for deeper in counters.keys where deeper > level {
                    counters[deeper] = nil
                    previousOrdered[deeper] = nil
                }
                let marker: String
                if let task {
                    marker = task ? "☑" : "☐"
                } else if ordered {
                    let next = previousOrdered[level] == true ? (counters[level] ?? number - 1) + 1 : number
                    counters[level] = next
                    marker = "\(next)."
                } else {
                    marker = ["•", "◦", "▪"][level % 3]
                }
                previousOrdered[level] = ordered && task == nil
                let indent = CGFloat(20 + level * 18)
                let style = paragraph {
                    $0.headIndent = indent
                    $0.firstLineHeadIndent = indent - 14
                    $0.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
                    $0.paragraphSpacing = nextIsList ? 2.5 : 8
                }
                let line = NSMutableAttributedString(string: marker + "\t", attributes: base)
                var body = base
                if task == true { body[.foregroundColor] = type.secondary }
                line.append(inline(block.text, attributes: body, type: type))
                append(line, style: style)
            case .quote(let callout):
                let frame = NSTextBlock()
                frame.setWidth(callout == nil ? 2.5 : 3, type: .absoluteValueType, for: .border, edge: .minX)
                frame.setBorderColor(callout == nil ? type.rule : type.secondary, for: .minX)
                frame.setWidth(12, type: .absoluteValueType, for: .padding, edge: .minX)
                frame.setWidth(callout == nil ? 2 : 8, type: .absoluteValueType, for: .padding, edge: .minY)
                frame.setWidth(callout == nil ? 2 : 8, type: .absoluteValueType, for: .padding, edge: .maxY)
                if callout != nil { frame.backgroundColor = type.shade }
                let style = paragraph {
                    $0.textBlocks = [frame]
                    $0.paragraphSpacing = 9
                }
                let content = NSMutableAttributedString()
                if let callout {
                    let label = NSFont.systemFont(ofSize: 8.5, weight: .bold)
                    content.append(NSAttributedString(string: callout.title.uppercased() + "\u{2028}",
                                                      attributes: [.font: label, .foregroundColor: type.secondary, .kern: 0.8]))
                }
                var attributes = base
                if callout == nil { attributes[.foregroundColor] = type.secondary }
                content.append(inline(block.text, attributes: attributes, type: type))
                append(content, style: style)
            case .code:
                let frame = NSTextBlock()
                frame.backgroundColor = type.shade
                frame.setWidth(9, type: .absoluteValueType, for: .padding)
                let style = paragraph {
                    $0.textBlocks = [frame]
                    $0.lineHeightMultiple = 1.1
                    $0.paragraphSpacing = 9
                }
                // Code keeps its lines inside one shaded block.
                let code = block.text.replacingOccurrences(of: "\n", with: "\u{2028}")
                append(NSAttributedString(string: code, attributes: [.font: type.mono, .foregroundColor: type.text]), style: style)
            case .table(let table):
                result.append(self.table(table, type: type, base: base))
            case .divider:
                let frame = NSTextBlock()
                frame.setWidth(0.75, type: .absoluteValueType, for: .border, edge: .maxY)
                frame.setBorderColor(type.rule, for: .maxY)
                frame.setWidth(6, type: .absoluteValueType, for: .padding, edge: .maxY)
                let style = paragraph {
                    $0.textBlocks = [frame]
                    $0.paragraphSpacing = 12
                }
                append(NSAttributedString(string: " ", attributes: [.font: NSFont.systemFont(ofSize: 3)]), style: style)
            case .image(let alt, let source):
                let style = paragraph {
                    $0.alignment = .center
                    $0.paragraphSpacing = alt.isEmpty ? 10 : 3
                }
                if let picture = image(source, baseURL: baseURL, width: width, maxHeight: maxImageHeight) {
                    append(picture, style: style)
                }
                if !alt.isEmpty {
                    let caption = paragraph {
                        $0.alignment = .center
                        $0.paragraphSpacing = 10
                    }
                    let font = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 9), toHaveTrait: .italicFontMask)
                    append(NSAttributedString(string: alt, attributes: [.font: font, .foregroundColor: type.secondary]), style: caption)
                }
            }
        }
        return result
    }

    static func inline(_ markdown: String, attributes: [NSAttributedString.Key: Any], type: DocTypography) -> NSAttributedString {
        render(MarkdownInline.parse(markdown), attributes: attributes, type: type)
    }

    private static func render(_ inlines: [DocInline], attributes: [NSAttributedString.Key: Any], type: DocTypography) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = attributes[.font] as? NSFont ?? type.body
        for item in inlines {
            var inner = attributes
            switch item.kind {
            case .text:
                result.append(NSAttributedString(string: item.text, attributes: attributes))
            case .lineBreak:
                result.append(NSAttributedString(string: "\u{2028}", attributes: attributes))
            case .strong:
                inner[.font] = trait(font, .bold)
                result.append(render(item.children, attributes: inner, type: type))
            case .emphasis:
                inner[.font] = trait(font, .italic)
                result.append(render(item.children, attributes: inner, type: type))
            case .strike:
                inner[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                result.append(render(item.children, attributes: inner, type: type))
            case .highlight:
                inner[.backgroundColor] = NSColor(calibratedRed: 1, green: 0.94, blue: 0.55, alpha: 1)
                result.append(render(item.children, attributes: inner, type: type))
            case .underline:
                inner[.underlineStyle] = NSUnderlineStyle.single.rawValue
                result.append(render(item.children, attributes: inner, type: type))
            case .code:
                inner[.font] = NSFont.monospacedSystemFont(ofSize: font.pointSize * 0.88, weight: .regular)
                inner[.backgroundColor] = type.shade
                result.append(NSAttributedString(string: item.text, attributes: inner))
            case .link:
                if let url = URL(string: item.url) { inner[.link] = url }
                inner[.foregroundColor] = type.link
                inner[.underlineStyle] = NSUnderlineStyle.single.rawValue
                result.append(render(item.children, attributes: inner, type: type))
            case .wikiLink:
                inner[.underlineStyle] = NSUnderlineStyle.single.union(.patternDot).rawValue
                result.append(render(item.children, attributes: inner, type: type))
            case .tag:
                inner[.foregroundColor] = type.secondary
                result.append(NSAttributedString(string: "#" + item.text, attributes: inner))
            case .image:
                if !item.text.isEmpty {
                    inner[.foregroundColor] = type.secondary
                    result.append(NSAttributedString(string: "[\(item.text)]", attributes: inner))
                }
            }
        }
        return result
    }

    static func trait(_ font: NSFont, _ trait: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait))
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    private static func table(_ table: DocTable, type: DocTypography, base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let columns = max(table.columns, 1)
        let textTable = NSTextTable()
        textTable.numberOfColumns = columns
        textTable.collapsesBorders = true
        textTable.layoutAlgorithm = .automaticLayoutAlgorithm
        for (rowIndex, row) in ([table.header] + table.rows).enumerated() {
            for column in 0..<columns {
                let cell = NSTextTableBlock(table: textTable, startingRow: rowIndex, rowSpan: 1, startingColumn: column, columnSpan: 1)
                cell.setWidth(0.5, type: .absoluteValueType, for: .border)
                cell.setBorderColor(type.rule)
                cell.setWidth(5, type: .absoluteValueType, for: .padding)
                if rowIndex == 0 { cell.backgroundColor = type.shade }
                let style = NSMutableParagraphStyle()
                style.textBlocks = [cell]
                style.lineHeightMultiple = 1.1
                if column < table.alignments.count {
                    switch table.alignments[column] {
                    case .center: style.alignment = .center
                    case .right: style.alignment = .right
                    case .left: style.alignment = .left
                    }
                }
                var attributes = base
                attributes[.font] = (base[.font] as? NSFont).map { NSFont(descriptor: $0.fontDescriptor, size: $0.pointSize * 0.92) ?? $0 } ?? type.body
                if rowIndex == 0, let font = attributes[.font] as? NSFont { attributes[.font] = trait(font, .bold) }
                let text = NSMutableAttributedString(attributedString: inline(column < row.count ? row[column] : "", attributes: attributes, type: type))
                text.append(NSAttributedString(string: "\n", attributes: attributes))
                text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
                result.append(text)
            }
        }
        // A little air after the table.
        let after = NSMutableParagraphStyle()
        after.paragraphSpacing = 6
        result.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 4), .paragraphStyle: after]))
        return result
    }

    private static func image(_ source: String, baseURL: URL?, width: CGFloat, maxHeight: CGFloat) -> NSAttributedString? {
        let url: URL?
        if source.hasPrefix("/") {
            url = URL(fileURLWithPath: source)
        } else if let parsed = URL(string: source), parsed.scheme == "file" {
            url = parsed
        } else if let baseURL, URL(string: source)?.scheme == nil {
            url = baseURL.appendingPathComponent(source.removingPercentEncoding ?? source)
        } else {
            url = nil
        }
        guard let url, let picture = NSImage(contentsOf: url), picture.size.width > 0, picture.size.height > 0 else { return nil }
        let scale = min(1, width / picture.size.width, maxHeight / picture.size.height)
        let attachment = NSTextAttachment()
        attachment.image = picture
        attachment.bounds = CGRect(x: 0, y: 0, width: picture.size.width * scale, height: picture.size.height * scale)
        return NSAttributedString(attachment: attachment)
    }
}

// MARK: PDF

/// Typesets a document onto pages: paper size, margins, the title at the top of each page after the first, page numbers.
enum DocPDF {
    static func data(_ markdown: String, title: String, setup: PageSetup, baseURL: URL?, type: DocTypography = .print) -> Data {
        let page = CGSize(width: setup.pageSize.width, height: setup.pageSize.height)
        let margin = CGFloat(setup.margin)
        let content = CGSize(width: page.width - margin * 2, height: page.height - margin * 2)
        let text = DocRenderer.attributed(markdown, baseURL: baseURL, width: content.width, maxImageHeight: content.height * 0.85, type: type)

        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        var containers: [NSTextContainer] = []
        repeat {
            let container = NSTextContainer(size: content)
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            containers.append(container)
            layout.ensureLayout(for: container)
        } while NSMaxRange(layout.glyphRange(for: containers[containers.count - 1])) < layout.numberOfGlyphs && containers.count < 2_000

        let output = NSMutableData()
        var box = CGRect(origin: .zero, size: page)
        let info = [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "11am"] as CFDictionary
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, info) else { return Data() }
        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        let small = NSFont.systemFont(ofSize: 8.5)
        let quiet: [NSAttributedString.Key: Any] = [.font: small, .foregroundColor: type.secondary]

        for (index, container) in containers.enumerated() {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            context.saveGState()
            context.translateBy(x: 0, y: page.height)
            context.scaleBy(x: 1, y: -1)
            let glyphs = layout.glyphRange(for: container)
            let origin = CGPoint(x: margin, y: margin)
            layout.drawBackground(forGlyphRange: glyphs, at: origin)
            layout.drawGlyphs(forGlyphRange: glyphs, at: origin)
            if setup.showsTitle && index > 0 && !title.isEmpty {
                let header = NSAttributedString(string: title, attributes: quiet)
                header.draw(at: CGPoint(x: margin, y: margin / 2 - header.size().height / 2))
            }
            if setup.pageNumbers && containers.count > 1 {
                let number = NSAttributedString(string: "\(index + 1) of \(containers.count)", attributes: quiet)
                let size = number.size()
                number.draw(at: CGPoint(x: (page.width - size.width) / 2, y: page.height - margin / 2 - size.height / 2))
            }
            context.restoreGState()
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }
}

// MARK: Import

/// Word, RTF, HTML, OpenDocument and web archives into Markdown, through the system's own readers.
enum DocImport {
    static let fileExtensions = ["md", "markdown", "txt", "text", "docx", "doc", "rtf", "rtfd", "html", "htm", "odt", "webarchive"]

    /// `saveImage` stores a picture and returns the Markdown source to use for it (nil leaves it out).
    static func markdown(from url: URL, saveImage: @escaping (Data, String) -> String? = { _, _ in nil }) throws -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "md", "markdown", "txt", "text":
            if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
            return try String(contentsOf: url, encoding: .isoLatin1)
        default:
            let type: NSAttributedString.DocumentType
            switch ext {
            case "docx": type = .officeOpenXML
            case "doc": type = .docFormat
            case "rtf": type = .rtf
            case "rtfd": type = .rtfd
            case "html", "htm": type = .html
            case "odt": type = .openDocument
            case "webarchive": type = .webArchive
            default: throw PDFEngine.Failure("11am can't open .\(ext) files as documents yet.")
            }
            var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: type]
            if type == .html { options[.characterEncoding] = String.Encoding.utf8.rawValue }
            let text = try NSAttributedString(url: url, options: options, documentAttributes: nil)
            return markdown(from: text, saveImage: saveImage)
        }
    }

    static func markdown(from text: NSAttributedString, saveImage: @escaping (Data, String) -> String? = { _, _ in nil }) -> String {
        let string = text.string as NSString
        let bodySize = commonFontSize(text)
        var output: [String] = []
        var codeLines: [String] = []
        var table: (id: ObjectIdentifier, rows: [Int: [Int: String]])?
        var previousWasList = false

        func flushCode() {
            guard !codeLines.isEmpty else { return }
            output.append("```\n" + codeLines.joined(separator: "\n") + "\n```")
            codeLines = []
        }
        func flushTable() {
            guard let current = table else { return }
            let rowNumbers = current.rows.keys.sorted()
            let columns = (current.rows.values.flatMap(\.keys).max() ?? 0) + 1
            var lines: [String] = []
            for (position, row) in rowNumbers.enumerated() {
                let cells = (0..<columns).map { current.rows[row]?[$0] ?? "" }
                lines.append("| " + cells.joined(separator: " | ") + " |")
                if position == 0 { lines.append("|" + String(repeating: " --- |", count: columns)) }
            }
            output.append(lines.joined(separator: "\n"))
            table = nil
        }

        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            let style = range.length > 0 ? text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle : nil
            let raw = string.substring(with: range)

            if let cell = style?.textBlocks.compactMap({ $0 as? NSTextTableBlock }).first {
                flushCode()
                let id = ObjectIdentifier(cell.table)
                if let current = table, current.id != id { flushTable() }
                if table == nil { table = (id, [:]) }
                let content = inlineMarkdown(text, range: range, bodySize: bodySize, saveImage: saveImage).replacingOccurrences(of: "|", with: "\\|")
                table?.rows[cell.startingRow, default: [:]][cell.startingColumn] = content.replacingOccurrences(of: "\n", with: " ")
                return
            }
            flushTable()

            if raw.trimmingCharacters(in: .whitespaces).isEmpty {
                flushCode()
                previousWasList = false
                return
            }
            if isMonospaced(text, range: range) {
                codeLines.append(raw)
                return
            }
            flushCode()

            var line = inlineMarkdown(text, range: range, bodySize: bodySize, saveImage: saveImage)
            if let lists = style?.textLists, let list = lists.last {
                // The marker ("\t•\t", "\t3.\t") is part of the imported text.
                line = line.replacingOccurrences(of: #"^\t?[^\t]{0,12}\t"#, with: "", options: .regularExpression)
                let indent = String(repeating: "  ", count: max(0, lists.count - 1))
                let ordered = [NSTextList.MarkerFormat.decimal, .lowercaseAlpha, .uppercaseAlpha, .lowercaseRoman, .uppercaseRoman].contains(list.markerFormat)
                var marker = ordered ? "1." : "-"
                for (box, done) in [("☐", false), ("☑", true), ("☒", true)] where line.hasPrefix(box) {
                    marker = done ? "- [x]" : "- [ ]"
                    line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                if !previousWasList, let last = output.last, !last.isEmpty { output.append("") }
                output.append(indent + marker + " " + line)
                previousWasList = true
                return
            }
            if previousWasList { output.append("") }
            previousWasList = false

            let level = headingLevel(text, range: range, style: style, bodySize: bodySize, line: line)
            if level > 0 {
                line = "\(String(repeating: "#", count: level)) " + stripOuterBold(line)
            }
            output.append(line)
            output.append("")
        }
        flushCode()
        flushTable()

        var markdown = output.joined(separator: "\n")
        while markdown.contains("\n\n\n") { markdown = markdown.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return markdown.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func commonFontSize(_ text: NSAttributedString) -> CGFloat {
        var weights: [CGFloat: Int] = [:]
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let font = value as? NSFont { weights[font.pointSize.rounded(), default: 0] += range.length }
        }
        return weights.max { $0.value < $1.value }?.key ?? 12
    }

    private static func isMonospaced(_ text: NSAttributedString, range: NSRange) -> Bool {
        var all = true
        text.enumerateAttribute(.font, in: range) { value, _, stop in
            guard let font = value as? NSFont, font.isFixedPitch || font.fontDescriptor.symbolicTraits.contains(.monoSpace) else {
                all = false
                stop.pointee = true
                return
            }
        }
        return all && range.length > 0
    }

    private static func headingLevel(_ text: NSAttributedString, range: NSRange, style: NSParagraphStyle?, bodySize: CGFloat, line: String) -> Int {
        if let level = style?.headerLevel, level > 0 { return min(level, 6) }
        guard range.length > 0, line.count < 160, let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont else { return 0 }
        let ratio = font.pointSize / max(bodySize, 1)
        if ratio >= 1.6 { return 1 }
        if ratio >= 1.3 { return 2 }
        if ratio >= 1.1 && font.fontDescriptor.symbolicTraits.contains(.bold) { return 3 }
        return 0
    }

    private static func stripOuterBold(_ line: String) -> String {
        guard line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4 else { return line }
        let inner = String(line.dropFirst(2).dropLast(2))
        return inner.contains("**") ? line : inner
    }

    private struct Style: Equatable {
        var bold = false, italic = false, strike = false, underline = false, highlight = false, code = false
        var link: String?
    }

    /// One paragraph's runs as inline Markdown, with markers kept off the surrounding spaces.
    private static func inlineMarkdown(_ text: NSAttributedString, range: NSRange, bodySize: CGFloat, saveImage: @escaping (Data, String) -> String?) -> String {
        var segments: [(String, Style)] = []
        text.enumerateAttributes(in: range) { attributes, runRange, _ in
            if let attachment = attributes[.attachment] as? NSTextAttachment {
                if let data = attachment.fileWrapper?.regularFileContents, let source = saveImage(data, attachment.fileWrapper?.preferredFilename ?? "image.png") {
                    segments.append(("![](\(source))", Style(code: true)))
                } else if let image = attachment.image, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                          let png = bitmap.representation(using: .png, properties: [:]), let source = saveImage(png, "image.png") {
                    segments.append(("![](\(source))", Style(code: true)))
                }
                return
            }
            var style = Style()
            if let font = attributes[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                style.bold = traits.contains(.bold)
                style.italic = traits.contains(.italic)
                style.code = font.isFixedPitch || traits.contains(.monoSpace)
            }
            style.strike = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
            if let link = attributes[.link] {
                style.link = (link as? URL)?.absoluteString ?? (link as? String)
            }
            style.underline = (attributes[.underlineStyle] as? Int ?? 0) != 0 && style.link == nil
            if let background = (attributes[.backgroundColor] as? NSColor)?.usingColorSpace(.sRGB),
               background.alphaComponent > 0.1, background.brightnessComponent < 0.99 || background.saturationComponent > 0.1 {
                style.highlight = true
            }
            let piece = (text.string as NSString).substring(with: runRange).replacingOccurrences(of: "\u{2028}", with: "\n")
            if let last = segments.last, last.1 == style, !last.0.hasPrefix("![](") {
                segments[segments.count - 1].0 += piece
            } else {
                segments.append((piece, style))
            }
        }

        var markdown = ""
        for (piece, style) in segments {
            if piece.hasPrefix("![](") && style.code {
                markdown += piece
                continue
            }
            let core = piece.trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty else {
                markdown += piece
                continue
            }
            let leading = String(piece.prefix { $0 == " " || $0 == "\t" })
            let trailing = String(piece.reversed().prefix { $0 == " " || $0 == "\t" }.reversed())
            var body: String
            if style.code {
                body = "`\(core.replacingOccurrences(of: "`", with: "'"))`"
            } else {
                body = escape(core)
                if style.underline { body = "++\(body)++" }
                if style.highlight { body = "==\(body)==" }
                if style.strike { body = "~~\(body)~~" }
                if style.italic { body = "*\(body)*" }
                if style.bold { body = "**\(body)**" }
            }
            if let link = style.link { body = "[\(body)](\(link))" }
            markdown += leading + body + trailing
        }
        return markdown.trimmingCharacters(in: .newlines)
    }

    /// Escapes what would otherwise read as Markdown.
    static func escape(_ text: String) -> String {
        var result = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            switch character {
            case "\\", "*", "`", "[", "]":
                result += "\\" + String(character)
            case "_":
                let before = index > 0 ? characters[index - 1] : " "
                let after = index + 1 < characters.count ? characters[index + 1] : " "
                result += (before.isLetter || before.isNumber) && (after.isLetter || after.isNumber) ? "_" : "\\_"
            case "#" where index == 0:
                result += "\\#"
            default:
                result.append(character)
            }
        }
        return result
    }
}

// MARK: Copy and share

enum DocExport {
    /// Rich text, HTML and the plain text on the pasteboard, so it pastes well into Mail, Docs or Word.
    static func copyRichText(_ markdown: String, baseURL: URL?) {
        let attributed = DocRenderer.attributed(markdown, baseURL: baseURL, width: 600)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let rtf = attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            pasteboard.setData(rtf, forType: .rtf)
        }
        pasteboard.setString(MarkdownHTML.body(markdown), forType: .html)
        pasteboard.setString(MarkdownPlain.text(markdown), forType: .string)
    }

    static func rtf(_ markdown: String, baseURL: URL?) -> Data? {
        let attributed = DocRenderer.attributed(markdown, baseURL: baseURL, width: 600)
        return attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }
}
