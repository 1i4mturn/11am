// Checks William's document engine and Bolton's PDF engine on a real Mac: Markdown parsing, HTML, Word and PDF export,
// importing from Word and rich text, and every PDF operation (pages, passwords, flattening, metadata, redaction, compression).
// Run from an empty folder; it writes its files there.
import AppKit
import CoreText
import PDFKit

var failures = 0

func check(_ condition: Bool, _ label: String) {
    print(condition ? "PASS" : "FAIL", label)
    if !condition { failures += 1 }
}

let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

// MARK: Markdown

let sample = """
# Quarterly plan

Intro with **bold**, *italic*, `code`, ==marked==, ~~gone~~ and a [link](https://example.com/a_b).
Second line of the same paragraph. #planning

## Goals

1. Ship single sign-on
2. Hire a designer
   which carries on here
   - nested point
- [ ] Book the offsite
- [x] Send the update

> [!WARNING] Check the dates
> Board meets on the 12th.

> A plain quote.

```swift
let total = 1 + 2
```

| Item | Owner | Cost |
| :--- | :---: | ---: |
| Laptops | Sam | $4,800 |
| Travel \\| hotels | Mia | `TBC` |

---

![The team](team.png)

See [[Acme pilot]] and [[Board deck|the deck]].
"""

let lines = MarkdownLines.lines(sample)
let kinds = lines.filter { $0.kind != .blank }.map { "\($0.kind)" }
check(kinds.prefix(4) == ["heading", "paragraph", "paragraph", "heading"], "Lines: heading and paragraphs (\(kinds.prefix(4)))")
check(lines.contains { $0.kind == .listItem && $0.task == false } && lines.contains { $0.kind == .listItem && $0.task == true }, "Lines: task items, ticked and not")
check(lines.contains { $0.kind == .quote && $0.callout == .warning }, "Lines: a callout")
check(lines.filter { $0.kind == .fence }.count == 2 && lines.contains { $0.kind == .code } && lines.first { $0.kind == .fence }?.language == "swift", "Lines: a fenced code block with its language")
check(lines.filter { $0.kind == .tableRow }.count == 3 && lines.contains { $0.kind == .tableDelimiter }, "Lines: a table")
check(lines.contains { $0.kind == .divider } && lines.contains { $0.kind == .image }, "Lines: a divider and an image")
let nested = lines.first { $0.kind == .listItem && ($0.level == 1) }
check(nested.map { (sample as NSString).substring(with: $0.contentRange) } == "nested point", "Lines: a nested item's level and text")
if let heading = lines.first(where: { $0.kind == .heading }) {
    check(heading.level == 1 && (sample as NSString).substring(with: heading.markerRange) == "# "
          && (sample as NSString).substring(with: heading.contentRange) == "Quarterly plan", "Lines: marker and content ranges")
}

let blocks = MarkdownBlocks.blocks(sample)
let listItems = blocks.compactMap { block -> (Int, Bool, Int, Bool?, String)? in
    if case .listItem(let level, let ordered, let number, let task) = block.kind { return (level, ordered, number, task, block.text) }
    return nil
}
check(listItems.count == 5 && listItems[1].4 == "Hire a designer\nwhich carries on here" && listItems[1].2 == 2, "Blocks: a list item keeps its continuation line")
check(listItems[2].0 == 1 && listItems[3].3 == false && listItems[4].3 == true, "Blocks: nesting and tasks")
if let table = blocks.compactMap({ block -> DocTable? in if case .table(let table) = block.kind { return table }; return nil }).first {
    check(table.header == ["Item", "Owner", "Cost"] && table.alignments == [.left, .center, .right], "Blocks: table header and alignment")
    check(table.rows.count == 2 && table.rows[1][0] == "Travel \\| hotels" || table.rows[1][0] == "Travel | hotels", "Blocks: an escaped pipe stays in its cell (\(table.rows[1][0]))")
} else {
    check(false, "Blocks: the table")
}
check(blocks.contains { $0.kind == .code(language: "swift") && $0.text == "let total = 1 + 2" }, "Blocks: code")
check(blocks.contains { $0.kind == .quote(.warning) && $0.text.hasPrefix("Check the dates") }, "Blocks: callout text")
check(blocks.contains { $0.kind == .image(alt: "The team", source: "team.png") }, "Blocks: an image on its own line")

// Inline
let inline = MarkdownInline.parse("Start **bold** and *em* plus `x` [here](https://a.b \"t\") ~~no~~ ==yes== ++u++ #tag/sub [[Note|alias]] www.example.com.")
let inlineKinds = inline.map(\.kind).filter { $0 != .text }
check(inlineKinds == [.strong, .emphasis, .code, .link, .strike, .highlight, .underline, .tag, .wikiLink, .link], "Inline: every kind (\(inlineKinds))")
if let bold = inline.first(where: { $0.kind == .strong }) {
    check(bold.range == NSRange(location: 6, length: 8) && bold.contentRange == NSRange(location: 8, length: 4), "Inline: ranges include and exclude the markers")
}
check(inline.first { $0.kind == .link }?.url == "https://a.b", "Inline: a link's title is dropped")
check(inline.first { $0.kind == .tag }?.text == "tag/sub", "Inline: tag with a slash")
check(inline.first { $0.kind == .wikiLink }.map { $0.text + "|" + MarkdownInline.plain($0.children) } == "Note|alias", "Inline: wiki link with an alias")
check(inline.last { $0.kind == .link }?.url == "https://www.example.com", "Inline: a bare www address, without the full stop")
check(MarkdownInline.parse("snake_case_name and 2 * 3 * 4 and C++ and a == b").allSatisfy { $0.kind == .text }, "Inline: underscores in words, maths and C++ stay text")
check(MarkdownInline.plain("\\*not emphasis\\* and #1 and #42") == "*not emphasis* and #1 and #42", "Inline: escapes, and numbers aren't tags")
let both = MarkdownInline.parse("***both***")
check(both.count == 1 && both[0].kind == .strong && both[0].children.first?.kind == .emphasis, "Inline: ***both*** is strong and emphasis")
check(MarkdownInline.parse("**a***b*").map(\.kind) == [.strong, .emphasis], "Inline: bold then italic, back to back")
check(MarkdownInline.parse("x", offset: 100).first?.range.location == 100, "Inline: offset for the editor")

// Info
let outline = MarkdownInfo.outline(sample)
check(outline.map(\.title) == ["Quarterly plan", "Goals"] && outline[1].level == 2 && outline[1].location > outline[0].location, "Outline")
check(MarkdownInfo.tags(sample) == ["planning"], "Tags")
check(MarkdownInfo.wikiLinks(sample) == ["Acme pilot", "Board deck"], "Wiki links")
check(MarkdownInfo.title(sample) == "Quarterly plan" && MarkdownInfo.title("\n\n- first item **bold**") == "first item bold", "Title from the first line")
let stats = MarkdownInfo.stats("One two three.\n\n**Four** five")
check(stats.words == 5 && stats.readingMinutes == 1, "Word count (\(stats.words))")
check(MarkdownInfo.images(sample) == ["team.png"], "Images")

// Plain text and HTML
let plain = MarkdownPlain.text(sample)
check(plain.contains("Intro with bold, italic, code, marked, gone and a link.") && plain.contains("☐ Book the offsite") && plain.contains("    • nested point"), "Plain text")
let html = MarkdownHTML.body(sample)
check(html.contains("<h1>Quarterly plan</h1>") && html.contains("<strong>bold</strong>") && html.contains("<mark>marked</mark>")
      && html.contains("<a href=\"https://example.com/a_b\">link</a>"), "HTML: headings and inline")
check(html.contains("<ol>\n<li>Ship single sign-on</li>\n<li>Hire a designer<br>\nwhich carries on here\n<ul>\n<li>nested point</li>\n</ul></li>\n</ol>"), "HTML: a nested list inside its item (\(html.prefix(400)))")
check(html.contains("<ul class=\"tasks\">") && html.contains("<input type=\"checkbox\" checked disabled>"), "HTML: task list")
check(html.contains("<th style=\"text-align:center\">Owner</th>") && html.contains("<pre><code class=\"language-swift\">let total = 1 + 2</code></pre>"), "HTML: table and code")
check(MarkdownHTML.inline("<script>") == "&lt;script&gt;", "HTML: escaped")

// MARK: Word

func run(_ tool: String, _ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do { try process.run() } catch { return (-1, error.localizedDescription) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

func png(width: Int, height: Int, noise: Bool = false) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    var generator = SystemRandomNumberGenerator()
    if let pixels = rep.bitmapData {
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * rep.bytesPerRow) + x * 4
                let jitter = noise ? Int.random(in: 0..<60, using: &generator) : 0
                pixels[offset] = UInt8(min(255, x * 255 / max(width, 1) / 2 + jitter))
                pixels[offset + 1] = UInt8(min(255, y * 255 / max(height, 1) / 2 + jitter))
                pixels[offset + 2] = UInt8(min(255, 120 + jitter))
                pixels[offset + 3] = 255
            }
        }
    }
    return rep.representation(using: .png, properties: [:])!
}

let picture = png(width: 120, height: 80)
let docx = DocxWriter.data(markdown: sample, title: "Quarterly plan") { source in source == "team.png" ? picture : nil }
let docxURL = folder.appendingPathComponent("plan.docx")
try? docx.write(to: docxURL)
check(run("/usr/bin/unzip", ["-tq", docxURL.path]).status == 0, "Word: a valid zip")
let listing = run("/usr/bin/unzip", ["-l", docxURL.path]).output
check(["[Content_Types].xml", "word/document.xml", "word/styles.xml", "word/numbering.xml", "word/media/image1.png", "docProps/core.xml"].allSatisfy { listing.contains($0) }, "Word: every part, and the picture")
let documentXML = run("/usr/bin/unzip", ["-p", docxURL.path, "word/document.xml"]).output
check(documentXML.contains("<w:pStyle w:val=\"Heading1\"/>") && documentXML.contains("<w:pStyle w:val=\"Heading2\"/>"), "Word: real heading styles")
check(documentXML.contains("<w:numId w:val=\"3\"/>") && documentXML.contains("<w:ilvl w:val=\"1\"/>"), "Word: numbered list with a nested level")
check(documentXML.contains("<w:hyperlink r:id=\"rIdLink1\"") && documentXML.contains("<w:tbl>") && documentXML.contains("<w:drawing>"), "Word: link, table and picture")
check(documentXML.contains("<w:highlight w:val=\"yellow\"/>") && documentXML.contains("<w:strike/>"), "Word: highlight and strikethrough")
if let xml = documentXML.data(using: .utf8) {
    check((try? XMLDocument(data: xml)) != nil, "Word: document.xml is well-formed XML")
}
for part in ["word/styles.xml", "word/numbering.xml", "word/_rels/document.xml.rels", "[Content_Types].xml"] {
    let text = run("/usr/bin/unzip", ["-p", docxURL.path, part.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")]).output
    check((try? XMLDocument(data: Data(text.utf8))) != nil && !text.isEmpty, "Word: \(part) is well-formed")
}
if let read = try? NSAttributedString(url: docxURL, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil) {
    check(read.string.contains("Quarterly plan") && read.string.contains("Hire a designer") && read.string.contains("Laptops"), "Word: opens in the system's Word reader")
    let fallback = DocImport.markdown(from: read)
    check(fallback.contains("**bold**") && fallback.contains("Hire a designer"), "Import: the system reader's text, as a fallback")
} else {
    check(false, "Word: opens in the system's Word reader")
}
if let back = try? DocImport.markdown(from: docxURL) {
    print("  imported back:\n" + back.split(separator: "\n").prefix(30).map { "    " + $0 }.joined(separator: "\n"))
    check(back.hasPrefix("# Quarterly plan\n") && back.contains("\n## Goals\n"), "Import: Word headings become Markdown headings")
    check(back.contains("**bold**") && back.contains("*italic*") && back.contains("`code`") && back.contains("==marked==") && back.contains("~~gone~~")
          && back.contains("[link](https://example.com/a_b)"), "Import: bold, italic, code, highlight, strikethrough and links")
    check(back.contains("1. Ship single sign-on\n1. Hire a designer") && back.contains("\n  - nested point"), "Import: numbered list with a nested bullet")
    check(back.contains("- [ ] Book the offsite\n- [x] Send the update"), "Import: checklist")
    check(back.contains("| Laptops | Sam | $4,800 |") && back.contains("| Item | Owner | Cost |\n| --- | --- | --- |"), "Import: table")
    check(back.contains("```\nlet total = 1 + 2\n```") && back.contains("> A plain quote."), "Import: code block and quote")
    let reparsed = MarkdownBlocks.blocks(back)
    check(reparsed.filter { if case .listItem = $0.kind { return true }; return false }.count == 5, "Import: the result parses back into the same five list items")
} else {
    check(false, "Import: Word document read")
}

// Rich text in
let rich = NSMutableAttributedString(string: "Big title\n", attributes: [.font: NSFont.systemFont(ofSize: 24, weight: .bold)])
rich.append(NSAttributedString(string: "Plain and ", attributes: [.font: NSFont.systemFont(ofSize: 12)]))
rich.append(NSAttributedString(string: "strong", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)]))
rich.append(NSAttributedString(string: " then ", attributes: [.font: NSFont.systemFont(ofSize: 12)]))
rich.append(NSAttributedString(string: "a link", attributes: [.font: NSFont.systemFont(ofSize: 12), .link: URL(string: "https://11am.app")!]))
rich.append(NSAttributedString(string: " with 2*3 and snake_case.\n", attributes: [.font: NSFont.systemFont(ofSize: 12)]))
let fromRich = DocImport.markdown(from: rich)
check(fromRich.contains("# Big title") && fromRich.contains("Plain and **strong** then [a link](https://11am.app) with 2\\*3 and snake_case."), "Import: rich text to Markdown (\(fromRich.replacingOccurrences(of: "\n", with: "⏎")))")

// MARK: PDF export

let long = "# Report\n\n" + (1...60).map { "Paragraph \($0) with **bold** words and enough text to wrap across the line a couple of times, so pages fill up." }.joined(separator: "\n\n")
let exported = DocPDF.data(long, title: "Report", setup: PageSetup(), baseURL: nil)
if let document = PDFDocument(data: exported) {
    let first = document.page(at: 0)?.string ?? ""
    check(document.pageCount >= 2, "PDF export: paginated (\(document.pageCount) pages)")
    check(first.contains("Report") && first.contains("Paragraph 1 with bold") && !first.contains("**") && !first.contains("# "), "PDF export: real text, no Markdown")
    check(first.contains("1 of \(document.pageCount)") && (document.page(at: 1)?.string ?? "").contains("Report"), "PDF export: page numbers and the title on later pages")
    check((document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String) == "Report", "PDF export: titled")
    let size = document.page(at: 0)?.bounds(for: .mediaBox).size ?? .zero
    check(abs(size.width - PageSetup().pageSize.width) < 1, "PDF export: paper size")
} else {
    check(false, "PDF export: readable")
}
var landscape = PageSetup()
landscape.landscape = true
landscape.paper = .letter
let wide = PDFDocument(data: DocPDF.data(sample, title: "Plan", setup: landscape, baseURL: folder))
check(wide?.page(at: 0)?.bounds(for: .mediaBox).width == 792, "PDF export: landscape Letter")
check((wide?.page(at: 0)?.string ?? "").contains("Laptops"), "PDF export: tables come through")

// MARK: PDF engine

func makePDF(_ pages: [String], _ name: String) -> URL {
    let url = folder.appendingPathComponent(name)
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    guard let context = CGContext(url as CFURL, mediaBox: &box, [kCGPDFContextTitle as String: "Secret title", kCGPDFContextAuthor as String: "Someone"] as CFDictionary) else { return url }
    let font = NSFont(name: "Helvetica", size: 18) ?? .systemFont(ofSize: 18)
    for text in pages {
        context.beginPDFPage(nil)
        for (index, words) in text.components(separatedBy: "\n").enumerated() {
            let typeset = CTLineCreateWithAttributedString(NSAttributedString(string: words, attributes: [.font: font]))
            context.textPosition = CGPoint(x: 72, y: 760 - CGFloat(index) * 40)
            CTLineDraw(typeset, context)
        }
        context.endPDFPage()
    }
    context.closePDF()
    return url
}

let aURL = makePDF(["Alpha page one", "Alpha page two", "Alpha page three"], "a.pdf")
let bURL = makePDF(["Bravo page one\nAccount 4417 1234 5678\nKeep this line", "Bravo page two", "Bravo page three"], "b.pdf")
let pictureURL = folder.appendingPathComponent("photo.png")
try? png(width: 1600, height: 1200).write(to: pictureURL)

func pageText(_ document: PDFDocument, _ index: Int) -> String { document.page(at: index)?.string ?? "" }

do {
    let combined = try PDFEngine.combine([aURL, bURL, pictureURL])
    check(combined.pageCount == 7 && pageText(combined, 3).contains("Bravo page one"), "PDF: combine PDFs and an image")
    let photo = combined.page(at: 6)?.bounds(for: .mediaBox).size ?? .zero
    check(photo.width <= 842 && photo.height <= 595 && photo.width > photo.height, "PDF: an image page fits A4 landscape (\(photo))")
    do {
        _ = try PDFEngine.combine([folder.appendingPathComponent("missing.pdf")])
        check(false, "PDF: an unreadable file is reported")
    } catch {
        check(error.localizedDescription.contains("missing.pdf"), "PDF: an unreadable file is reported")
    }

    let pieces = PDFEngine.split(combined, every: 3)
    check(pieces.map(\.pageCount) == [3, 3, 1], "PDF: split every 3 pages")
    let picked = PDFEngine.extract(combined, pages: IndexSet([0, 4]))
    check(picked.pageCount == 2 && pageText(picked, 1).contains("Bravo page two"), "PDF: extract pages")

    let working = try PDFEngine.combine([aURL])
    PDFEngine.rotate(working, pages: IndexSet([0]), by: 90)
    check(working.page(at: 0)?.rotation == 90, "PDF: rotate right")
    PDFEngine.rotate(working, pages: IndexSet([0]), by: -180)
    check(working.page(at: 0)?.rotation == 270, "PDF: rotate left wraps around")
    PDFEngine.move(working, pages: IndexSet([2]), to: 0)
    check(pageText(working, 0).contains("three") && pageText(working, 1).contains("one"), "PDF: move a page to the front")
    PDFEngine.move(working, pages: IndexSet([0]), to: 3)
    check(pageText(working, 2).contains("three"), "PDF: move a page to the end")
    PDFEngine.duplicate(working, page: 0)
    check(working.pageCount == 4 && pageText(working, 1) == pageText(working, 0), "PDF: duplicate")
    PDFEngine.delete(working, pages: IndexSet([0, 1, 2]))
    check(working.pageCount == 1, "PDF: delete")
    PDFEngine.delete(working, pages: IndexSet([0]))
    check(working.pageCount == 1, "PDF: never deletes the last page")
    try PDFEngine.insert([bURL], into: working, at: 0)
    check(working.pageCount == 4 && pageText(working, 0).contains("Bravo"), "PDF: insert pages from a file")

    // Passwords
    let lockedURL = folder.appendingPathComponent("locked.pdf")
    try PDFEngine.protect(try PDFEngine.combine([aURL]), to: lockedURL, password: "open sesame", allowPrinting: false)
    if let locked = PDFDocument(url: lockedURL) {
        check(locked.isEncrypted && locked.isLocked, "PDF: password needed to open")
        check(!locked.unlock(withPassword: "wrong") && locked.unlock(withPassword: "open sesame"), "PDF: only the right password opens it")
        check(!locked.allowsPrinting && locked.allowsCopying, "PDF: printing turned off, copying left on")
    } else {
        check(false, "PDF: protected file readable")
    }

    // Flatten
    let marked = try PDFEngine.combine([bURL])
    if let page = marked.page(at: 0) {
        PDFEngine.box(CGRect(x: 60, y: 700, width: 200, height: 60), on: page, color: .red)
        PDFEngine.textBox("Approved", at: CGPoint(x: 300, y: 500), on: page)
        if let found = marked.findString("Keep this", withOptions: []).first {
            let added = PDFEngine.markup(found, type: .highlight, color: .yellow)
            check(added.count == 1 && (added[0].type ?? "").lowercased().contains("highlight") && added[0].quadrilateralPoints?.count == 4, "PDF: highlight a selection")
        }
        let strokes = [[CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 20), CGPoint(x: 100, y: 0)], [CGPoint(x: 10, y: 30), CGPoint(x: 90, y: 30)]]
        let ink = PDFEngine.ink(strokes, canvas: CGSize(width: 100, height: 40), in: CGRect(x: 300, y: 100, width: 200, height: 80))
        page.addAnnotation(ink)
        check(ink.paths?.count == 2, "PDF: a drawn signature as ink")
        check(page.annotations.count == 4, "PDF: four marks on the page")
    }
    let flatURL = folder.appendingPathComponent("flat.pdf")
    try PDFEngine.flatten(marked, to: flatURL)
    check(PDFDocument(url: flatURL)?.page(at: 0)?.annotations.isEmpty == true, "PDF: flattened marks are part of the page")

    // Metadata
    let original = try PDFEngine.combine([aURL])
    original.documentAttributes = [PDFDocumentAttribute.titleAttribute: "Secret title", PDFDocumentAttribute.authorAttribute: "Someone"]
    let cleanURL = folder.appendingPathComponent("clean.pdf")
    try PDFEngine.removeMetadata(original, to: cleanURL)
    let cleaned = PDFDocument(url: cleanURL)?.documentAttributes ?? [:]
    check(cleaned[PDFDocumentAttribute.titleAttribute] == nil && cleaned[PDFDocumentAttribute.authorAttribute] == nil, "PDF: title and author removed")

    // Redaction
    let secret = try PDFEngine.combine([bURL])
    if let page = secret.page(at: 0), let account = secret.findString("4417 1234 5678", withOptions: []).first {
        let rect = account.bounds(for: page).insetBy(dx: -4, dy: -4)
        let redactedURL = folder.appendingPathComponent("redacted.pdf")
        let report = try PDFEngine.redact(secret, marks: [0: [rect]], to: redactedURL)
        let result = PDFDocument(url: redactedURL)
        let text = result.map { pageText($0, 0) } ?? ""
        check(report.pages == 1 && report.leftover.isEmpty, "PDF: redaction reports nothing left under the box")
        check(!text.contains("4417") && !text.contains("5678"), "PDF: the redacted number is gone from the file")
        check(result?.pageCount == 3 && pageText(result!, 1).contains("Bravo page two"), "PDF: other pages untouched")
        print("  text recognised on the redacted page: \(text.replacingOccurrences(of: "\n", with: " ⏎ "))")
    } else {
        check(false, "PDF: found the text to redact")
    }

    // Compression
    let heavyImage = NSImage(data: png(width: 2400, height: 2400, noise: true))!
    heavyImage.size = NSSize(width: 500, height: 500)
    let heavy = PDFDocument()
    if let page = PDFEngine.imagePage(heavyImage) { heavy.insert(page, at: 0) }
    let smallURL = folder.appendingPathComponent("small.pdf")
    let sizes = try PDFEngine.compress(heavy, to: smallURL)
    check(sizes.after > 0 && sizes.after < sizes.before, "PDF: compressed \(sizes.before / 1024) KB to \(sizes.after / 1024) KB")

    // Reading
    let text = PDFEngine.text(try PDFEngine.combine([aURL, bURL]))
    check(text.hasPrefix("[Page 1]\nAlpha page one") && text.contains("[Page 4]\nBravo page one"), "PDF: text with page markers")
    check(PDFEngine.pagesWithoutText(heavy) == 1, "PDF: finds pages that need text recognition")
} catch {
    check(false, "PDF run: \(error.localizedDescription)")
}

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
