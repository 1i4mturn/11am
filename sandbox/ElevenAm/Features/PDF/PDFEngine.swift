import AppKit
import PDFKit

/// Bolton's PDF engine: everything Acrobat and Preview do to a file, on PDFKit. No UI here, so the tests run it as it is.
enum PDFEngine {
    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }

        init(_ message: String) {
            self.message = message
        }
    }

    // MARK: Making documents

    /// PDFs and images, in order, as one document.
    static func combine(_ urls: [URL]) throws -> PDFDocument {
        let result = PDFDocument()
        for url in urls {
            if let document = PDFDocument(url: url) {
                guard !document.isLocked else { throw Failure("\(url.lastPathComponent) is locked with a password. Open it and unlock it first.") }
                for index in 0..<document.pageCount {
                    if let page = document.page(at: index)?.copy() as? PDFPage { result.insert(page, at: result.pageCount) }
                }
            } else if let image = NSImage(contentsOf: url), let page = imagePage(image) {
                result.insert(page, at: result.pageCount)
            } else {
                throw Failure("\(url.lastPathComponent) isn't a PDF or an image 11am can read.")
            }
        }
        guard result.pageCount > 0 else { throw Failure("There were no pages to combine.") }
        return result
    }

    /// An image as a page, scaled to fit A4 (portrait or landscape to match) but never enlarged.
    static func imagePage(_ image: NSImage) -> PDFPage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let landscape = size.width > size.height
        let limit = landscape ? CGSize(width: 842, height: 595) : CGSize(width: 595, height: 842)
        let scale = min(1, limit.width / size.width, limit.height / size.height)
        guard let copy = image.copy() as? NSImage else { return nil }
        copy.size = NSSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        return PDFPage(image: copy)
    }

    // MARK: Pages

    static func extract(_ document: PDFDocument, pages: IndexSet) -> PDFDocument {
        let result = PDFDocument()
        for index in pages.sorted() {
            if let page = document.page(at: index)?.copy() as? PDFPage { result.insert(page, at: result.pageCount) }
        }
        return result
    }

    /// Every `size` pages becomes its own document.
    static func split(_ document: PDFDocument, every size: Int) -> [PDFDocument] {
        let size = max(1, size)
        return stride(from: 0, to: document.pageCount, by: size).map { start in
            extract(document, pages: IndexSet(start..<min(start + size, document.pageCount)))
        }
    }

    static func rotate(_ document: PDFDocument, pages: IndexSet, by degrees: Int) {
        for index in pages {
            guard let page = document.page(at: index) else { continue }
            page.rotation = ((page.rotation + degrees) % 360 + 360) % 360
        }
    }

    static func delete(_ document: PDFDocument, pages: IndexSet) {
        for index in pages.sorted(by: >) where index < document.pageCount && document.pageCount > 1 {
            document.removePage(at: index)
        }
    }

    static func duplicate(_ document: PDFDocument, page index: Int) {
        guard let copy = document.page(at: index)?.copy() as? PDFPage else { return }
        document.insert(copy, at: index + 1)
    }

    /// Moves pages so they sit before `destination` (an index in the document as it was).
    static func move(_ document: PDFDocument, pages: IndexSet, to destination: Int) {
        let moving = pages.sorted().compactMap { document.page(at: $0) }
        var target = destination
        for index in pages.sorted(by: >) where index < document.pageCount {
            document.removePage(at: index)
            if index < destination { target -= 1 }
        }
        for (offset, page) in moving.enumerated() {
            document.insert(page, at: min(max(0, target) + offset, document.pageCount))
        }
    }

    /// Pages from another file (PDF or images), inserted at `index`.
    static func insert(_ urls: [URL], into document: PDFDocument, at index: Int) throws {
        let incoming = try combine(urls)
        for offset in 0..<incoming.pageCount {
            if let page = incoming.page(at: offset)?.copy() as? PDFPage {
                document.insert(page, at: min(index + offset, document.pageCount))
            }
        }
    }

    // MARK: Writing

    static func write(_ document: PDFDocument, to url: URL, options: [PDFDocumentWriteOption: Any] = [:]) throws {
        guard document.write(to: url, withOptions: options) else { throw Failure("Couldn't save \(url.lastPathComponent).") }
    }

    /// Images re-saved as JPEG at screen resolution. Returns the sizes before and after.
    @discardableResult
    static func compress(_ document: PDFDocument, to url: URL) throws -> (before: Int, after: Int) {
        let before = document.dataRepresentation()?.count ?? 0
        try write(document, to: url, options: [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true])
        let after = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return (before, after)
    }

    /// A password to open it. Printing and copying can be turned off (they're enforced by an owner password only 11am knows,
    /// unless you give one).
    static func protect(_ document: PDFDocument, to url: URL, password: String, ownerPassword: String? = nil,
                        allowPrinting: Bool = true, allowCopying: Bool = true) throws {
        guard !password.isEmpty else { throw Failure("Choose a password.") }
        let owner = ownerPassword.flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
        try write(document, to: url, options: [
            .userPasswordOption: password,
            .ownerPasswordOption: owner,
            PDFDocumentWriteOption(rawValue: kCGPDFContextAllowsPrinting as String): allowPrinting,
            PDFDocumentWriteOption(rawValue: kCGPDFContextAllowsCopying as String): allowCopying,
        ])
    }

    /// Markup and filled-in form fields become part of the page.
    static func flatten(_ document: PDFDocument, to url: URL) throws {
        try write(document, to: url, options: [.burnInAnnotationsOption: true])
    }

    /// Author, title, subject, keywords and the app that made it, removed.
    static func removeMetadata(_ document: PDFDocument, to url: URL) throws {
        guard let data = document.dataRepresentation(), let copy = PDFDocument(data: data) else { throw Failure("Couldn't read the document.") }
        copy.documentAttributes = [:]
        try write(copy, to: url)
    }

    /// Scanned pages get a text layer from on-device text recognition, so they can be searched and copied.
    static func makeSearchable(_ document: PDFDocument, to url: URL) throws {
        try write(document, to: url, options: [.saveTextFromOCROption: true])
    }

    static func pagesWithoutText(_ document: PDFDocument) -> Int {
        (0..<document.pageCount).filter { (document.page(at: $0)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    // MARK: Redaction

    struct RedactionReport: Equatable {
        var pages: Int
        /// Text that was under a mark and can still be found. Should always be empty.
        var leftover: [String]
    }

    /// Real redaction: each marked page is redrawn as an image with the boxes burnt in, so the text and pictures underneath
    /// are gone from the file, then given a fresh text layer by on-device recognition. Afterwards it checks that none of the
    /// text that was under the boxes can be found in the saved file.
    @discardableResult
    static func redact(_ document: PDFDocument, marks: [Int: [CGRect]], to url: URL, scale: CGFloat = 3) throws -> RedactionReport {
        var hidden: [Int: [String]] = [:]
        for (index, rects) in marks {
            guard let page = document.page(at: index) else { continue }
            hidden[index] = rects.compactMap { rect in
                let text = page.selection(for: rect)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return text.count >= 3 ? text : nil
            }
        }
        guard let data = document.dataRepresentation(), let result = PDFDocument(data: data) else { throw Failure("Couldn't read the document.") }
        var changed = 0
        for (index, rects) in marks.sorted(by: { $0.key < $1.key }) where !rects.isEmpty {
            guard let page = result.page(at: index), let redrawn = rasterize(page, covering: rects, scale: scale) else { continue }
            result.removePage(at: index)
            result.insert(redrawn, at: index)
            changed += 1
        }
        try write(result, to: url, options: [.saveTextFromOCROption: true])

        var leftover: [String] = []
        let check = PDFDocument(url: url)
        for (index, phrases) in hidden {
            let text = check?.page(at: index)?.string ?? ""
            for phrase in phrases where text.contains(phrase) && !leftover.contains(phrase) { leftover.append(phrase) }
        }
        return RedactionReport(pages: changed, leftover: leftover)
    }

    /// The page as pixels with black boxes, as a new page the same size and rotation.
    static func rasterize(_ page: PDFPage, covering rects: [CGRect], scale: CGFloat) -> PDFPage? {
        let box = page.bounds(for: .mediaBox)
        let width = Int((box.width * scale).rounded()), height = Int((box.height * scale).rounded())
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        if let reference = page.pageRef { context.drawPDFPage(reference) }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for rect in rects { context.fill(rect.insetBy(dx: -1, dy: -1)) }
        guard let image = context.makeImage() else { return nil }
        let picture = NSImage(cgImage: image, size: NSSize(width: box.width, height: box.height))
        guard let redrawn = PDFPage(image: picture) else { return nil }
        redrawn.rotation = page.rotation
        return redrawn
    }

    // MARK: Reading

    /// The text, marked with page numbers so answers can say where they came from.
    static func text(_ document: PDFDocument, limit: Int = 80_000) -> String {
        var parts: [String] = []
        var total = 0
        for index in 0..<document.pageCount {
            let text = (document.page(at: index)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let part = "[Page \(index + 1)]\n\(text)"
            total += part.count
            parts.append(part)
            if total > limit { break }
        }
        let joined = parts.joined(separator: "\n\n")
        return joined.count > limit ? String(joined.prefix(limit)) : joined
    }

    // MARK: Markup

    /// Highlight, underline or strike through every line of a selection.
    @discardableResult
    static func markup(_ selection: PDFSelection, type: PDFAnnotationSubtype, color: NSColor) -> [PDFAnnotation] {
        var added: [PDFAnnotation] = []
        for line in selection.selectionsByLine() {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                guard bounds.width > 0, bounds.height > 0 else { continue }
                let annotation = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
                annotation.color = color
                annotation.quadrilateralPoints = [
                    NSValue(point: NSPoint(x: 0, y: bounds.height)), NSValue(point: NSPoint(x: bounds.width, y: bounds.height)),
                    NSValue(point: NSPoint(x: 0, y: 0)), NSValue(point: NSPoint(x: bounds.width, y: 0)),
                ]
                page.addAnnotation(annotation)
                added.append(annotation)
            }
        }
        return added
    }

    @discardableResult
    static func note(_ text: String, at point: CGPoint, on page: PDFPage) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20), forType: .text, withProperties: nil)
        annotation.contents = text
        annotation.color = NSColor(calibratedRed: 1, green: 0.85, blue: 0.3, alpha: 1)
        annotation.iconType = .note
        page.addAnnotation(annotation)
        return annotation
    }

    @discardableResult
    static func textBox(_ text: String, at point: CGPoint, on page: PDFPage, size: CGFloat = 12) -> PDFAnnotation {
        let font = NSFont(name: "Helvetica", size: size) ?? .systemFont(ofSize: size)
        let measured = (text as NSString).boundingRect(with: CGSize(width: 320, height: 2_000), options: [.usesLineFragmentOrigin],
                                                       attributes: [.font: font])
        let bounds = CGRect(x: point.x, y: point.y - measured.height - 6, width: ceil(measured.width) + 12, height: ceil(measured.height) + 8)
        let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        annotation.contents = text
        annotation.font = font
        annotation.fontColor = .black
        annotation.color = .clear
        let border = PDFBorder()
        border.lineWidth = 0
        annotation.border = border
        page.addAnnotation(annotation)
        return annotation
    }

    /// Freehand strokes (or a drawn signature) as an ink annotation. Points are in `canvas` space (top-left origin),
    /// fitted into `rect` on the page.
    static func ink(_ strokes: [[CGPoint]], canvas: CGSize, in rect: CGRect, color: NSColor = .black, width: CGFloat = 1.6) -> PDFAnnotation {
        let scale = min(rect.width / max(canvas.width, 1), rect.height / max(canvas.height, 1))
        let drawn = CGSize(width: canvas.width * scale, height: canvas.height * scale)
        let inset = CGPoint(x: (rect.width - drawn.width) / 2, y: (rect.height - drawn.height) / 2)
        let annotation = PDFAnnotation(bounds: rect, forType: .ink, withProperties: nil)
        for stroke in strokes where stroke.count > 1 {
            let path = NSBezierPath()
            for (index, point) in stroke.enumerated() {
                let mapped = NSPoint(x: inset.x + point.x * scale, y: inset.y + (canvas.height - point.y) * scale)
                if index == 0 { path.move(to: mapped) } else { path.line(to: mapped) }
            }
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            annotation.add(path)
        }
        annotation.color = color
        let border = PDFBorder()
        border.lineWidth = width
        annotation.border = border
        return annotation
    }

    /// A typed signature in a handwriting face.
    @discardableResult
    static func typedSignature(_ name: String, at point: CGPoint, on page: PDFPage) -> PDFAnnotation {
        let font = NSFont(name: "SnellRoundhand-Bold", size: 26) ?? NSFont(name: "Zapfino", size: 18) ?? .systemFont(ofSize: 24)
        let size = (name as NSString).size(withAttributes: [.font: font])
        let bounds = CGRect(x: point.x, y: point.y - size.height / 2, width: ceil(size.width) + 16, height: ceil(size.height) + 8)
        let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        annotation.contents = name
        annotation.font = font
        annotation.fontColor = NSColor(calibratedRed: 0.05, green: 0.1, blue: 0.3, alpha: 1)
        annotation.color = .clear
        let border = PDFBorder()
        border.lineWidth = 0
        annotation.border = border
        page.addAnnotation(annotation)
        return annotation
    }

    @discardableResult
    static func box(_ rect: CGRect, on page: PDFPage, color: NSColor) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: rect, forType: .square, withProperties: nil)
        annotation.color = color
        let border = PDFBorder()
        border.lineWidth = 2
        annotation.border = border
        page.addAnnotation(annotation)
        return annotation
    }
}
