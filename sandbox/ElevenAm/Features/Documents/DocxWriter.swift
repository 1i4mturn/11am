import Foundation
import ImageIO

/// Writes a Markdown document as a Word file: real Heading styles (so Word's navigation and Google Docs' outline work),
/// real numbered and bulleted lists, tables, links, images, code, quotes, and page numbers in the footer.
enum DocxWriter {
    struct Image {
        var data: Data
        /// "png" or "jpeg"
        var format: String
        var width: Int
        var height: Int
    }

    /// `image` turns a Markdown image source into its bytes; return nil to leave the image out.
    static func data(markdown: String, title: String, setup: PageSetup = PageSetup(), image: (String) -> Data? = { _ in nil }) -> Data {
        var builder = Builder(image: image)
        let body = builder.body(MarkdownBlocks.blocks(markdown), setup: setup)

        var zip = ZipWriter()
        zip.add("[Content_Types].xml", contentTypes(images: builder.images))
        zip.add("_rels/.rels", rootRelationships)
        zip.add("docProps/core.xml", core(title: title))
        zip.add("word/document.xml", Data(body.utf8))
        zip.add("word/styles.xml", Data(styles.utf8))
        zip.add("word/numbering.xml", Data(builder.numbering().utf8))
        zip.add("word/footer1.xml", Data(footer.utf8))
        zip.add("word/_rels/document.xml.rels", Data(builder.relationships().utf8))
        for (index, item) in builder.images.enumerated() {
            zip.add("word/media/image\(index + 1).\(item.format == "jpeg" ? "jpeg" : "png")", item.data)
        }
        return zip.finish()
    }

    /// Reads an image's pixel size and type, for the inline picture.
    static func imageInfo(_ data: Data) -> Image? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        let format: String
        if type == "public.png" {
            format = "png"
        } else if type == "public.jpeg" {
            format = "jpeg"
        } else {
            return nil
        }
        return Image(data: data, format: format, width: width, height: height)
    }

    // MARK: Parts

    private static func contentTypes(images: [Image]) -> Data {
        var defaults = """
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>
        """
        if images.contains(where: { $0.format == "png" }) { defaults += #"<Default Extension="png" ContentType="image/png"/>"# }
        if images.contains(where: { $0.format == "jpeg" }) { defaults += #"<Default Extension="jpeg" ContentType="image/jpeg"/>"# }
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\(defaults)\
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
        <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>\
        <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>\
        <Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>\
        <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>\
        </Types>
        """
        return Data(xml.utf8)
    }

    private static let rootRelationships = Data("""
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>\
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>\
    </Relationships>
    """.utf8)

    private static func core(title: String) -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let now = formatter.string(from: Date())
        return Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" \
        xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" \
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\
        <dc:title>\(escape(title))</dc:title>\
        <dcterms:created xsi:type="dcterms:W3CDTF">\(now)</dcterms:created>\
        <dcterms:modified xsi:type="dcterms:W3CDTF">\(now)</dcterms:modified>\
        </cp:coreProperties>
        """.utf8)
    }

    private static let footer = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
    <w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:fldSimple w:instr=" PAGE "><w:r><w:t>1</w:t></w:r></w:fldSimple></w:p>\
    </w:ftr>
    """

    private static func headingStyle(_ level: Int, size: Int, before: Int) -> String {
        """
        <w:style w:type="paragraph" w:styleId="Heading\(level)"><w:name w:val="heading \(level)"/><w:basedOn w:val="Normal"/>\
        <w:next w:val="Normal"/><w:uiPriority w:val="9"/><w:qFormat/>\
        <w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before="\(before)" w:after="80"/><w:outlineLvl w:val="\(level - 1)"/></w:pPr>\
        <w:rPr><w:b/><w:sz w:val="\(size)"/><w:szCs w:val="\(size)"/></w:rPr></w:style>
        """
    }

    private static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
    <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/>\
    <w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="en-AU"/></w:rPr></w:rPrDefault>\
    <w:pPrDefault><w:pPr><w:spacing w:after="140" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>\
    <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>\
    \(headingStyle(1, size: 36, before: 360))\(headingStyle(2, size: 30, before: 300))\(headingStyle(3, size: 26, before: 240))\
    \(headingStyle(4, size: 24, before: 200))\(headingStyle(5, size: 22, before: 200))\(headingStyle(6, size: 22, before: 200))\
    <w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>\
    <w:pPr><w:pBdr><w:left w:val="single" w:sz="18" w:space="8" w:color="C8C6C0"/></w:pBdr><w:ind w:left="360"/></w:pPr>\
    <w:rPr><w:i/><w:color w:val="555555"/></w:rPr></w:style>\
    <w:style w:type="paragraph" w:styleId="Code"><w:name w:val="Code"/><w:basedOn w:val="Normal"/><w:qFormat/>\
    <w:pPr><w:shd w:val="clear" w:color="auto" w:fill="F4F3F0"/><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>\
    <w:rPr><w:rFonts w:ascii="Menlo" w:hAnsi="Menlo" w:cs="Consolas"/><w:sz w:val="19"/><w:szCs w:val="19"/></w:rPr></w:style>\
    <w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:qFormat/>\
    <w:pPr><w:spacing w:after="60"/><w:ind w:left="720"/><w:contextualSpacing/></w:pPr></w:style>\
    <w:style w:type="paragraph" w:styleId="Caption"><w:name w:val="caption"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>\
    <w:pPr><w:jc w:val="center"/></w:pPr><w:rPr><w:i/><w:color w:val="6B6B6B"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>\
    <w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:uiPriority w:val="99"/><w:unhideWhenUsed/>\
    <w:rPr><w:color w:val="1F5FBF"/><w:u w:val="single"/></w:rPr></w:style>\
    <w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:uiPriority w:val="39"/>\
    <w:tblPr><w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="BFBDB7"/><w:left w:val="single" w:sz="4" w:space="0" w:color="BFBDB7"/>\
    <w:bottom w:val="single" w:sz="4" w:space="0" w:color="BFBDB7"/><w:right w:val="single" w:sz="4" w:space="0" w:color="BFBDB7"/>\
    <w:insideH w:val="single" w:sz="4" w:space="0" w:color="BFBDB7"/><w:insideV w:val="single" w:sz="4" w:space="0" w:color="BFBDB7"/></w:tblBorders>\
    <w:tblCellMar><w:left w:w="100" w:type="dxa"/><w:right w:w="100" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>\
    </w:styles>
    """

    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            // XML 1.0 can't carry most control characters; Word refuses the file if they're there.
            case "\u{9}", "\u{A}", "\u{D}": result.unicodeScalars.append(scalar)
            default:
                if scalar.value < 0x20 || scalar.value == 0xFFFE || scalar.value == 0xFFFF { continue }
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    // MARK: Body

    private struct RunStyle {
        var bold = false
        var italic = false
        var strike = false
        var underline = false
        var highlight = false
        var code = false
        var link = false

        var properties: String {
            var parts: [String] = []
            if link { parts.append(#"<w:rStyle w:val="Hyperlink"/>"#) }
            if code { parts.append(#"<w:rFonts w:ascii="Menlo" w:hAnsi="Menlo" w:cs="Consolas"/>"#) }
            if bold { parts.append("<w:b/>") }
            if italic { parts.append("<w:i/>") }
            if strike { parts.append("<w:strike/>") }
            if code { parts.append(#"<w:sz w:val="20"/>"#) }
            if highlight { parts.append(#"<w:highlight w:val="yellow"/>"#) }
            if underline && !link { parts.append(#"<w:u w:val="single"/>"#) }
            if code { parts.append(#"<w:shd w:val="clear" w:color="auto" w:fill="F4F3F0"/>"#) }
            return parts.isEmpty ? "" : "<w:rPr>\(parts.joined())</w:rPr>"
        }
    }

    private struct Builder {
        let image: (String) -> Data?
        var images: [Image] = []
        var links: [String] = []
        /// Ordered lists each restart from their own first number.
        var orderedStarts: [Int] = []

        init(image: @escaping (String) -> Data?) {
            self.image = image
        }

        mutating func body(_ blocks: [DocBlock], setup: PageSetup) -> String {
            var xml: [String] = []
            var listNumber: Int?
            var inList = false
            for block in blocks {
                if case .listItem(let level, let ordered, let number, let task) = block.kind {
                    if !inList { listNumber = nil }
                    inList = true
                    if let task {
                        let indent = 360 * (level + 1)
                        let box = task ? "☒" : "☐"
                        xml.append("<w:p><w:pPr><w:pStyle w:val=\"ListParagraph\"/><w:ind w:left=\"\(indent + 360)\" w:hanging=\"360\"/></w:pPr>"
                                   + run(box + " ", RunStyle()) + inline(block.text) + "</w:p>")
                        continue
                    }
                    var numID = 1
                    if ordered {
                        if listNumber == nil {
                            orderedStarts.append(number)
                            listNumber = orderedStarts.count + 2
                        }
                        numID = listNumber ?? 2
                    }
                    xml.append("<w:p><w:pPr><w:pStyle w:val=\"ListParagraph\"/><w:numPr><w:ilvl w:val=\"\(min(level, 8))\"/><w:numId w:val=\"\(numID)\"/></w:numPr></w:pPr>"
                               + inline(block.text) + "</w:p>")
                    continue
                }
                inList = false
                switch block.kind {
                case .heading(let level):
                    xml.append("<w:p><w:pPr><w:pStyle w:val=\"Heading\(level)\"/></w:pPr>\(inline(block.text))</w:p>")
                case .paragraph:
                    xml.append("<w:p>\(inline(block.text))</w:p>")
                case .quote(let callout):
                    var content = ""
                    if let callout {
                        content = run(callout.title.uppercased(), RunStyle(bold: true)) + "<w:r><w:br/></w:r>"
                    }
                    xml.append("<w:p><w:pPr><w:pStyle w:val=\"Quote\"/></w:pPr>\(content)\(inline(block.text))</w:p>")
                case .code:
                    for line in block.text.components(separatedBy: "\n") {
                        xml.append("<w:p><w:pPr><w:pStyle w:val=\"Code\"/></w:pPr>\(run(line, RunStyle()))</w:p>")
                    }
                    xml.append("<w:p/>")
                case .table(let table):
                    xml.append(self.table(table, setup: setup))
                    xml.append("<w:p/>")
                case .divider:
                    xml.append(#"<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="BFBDB7"/></w:pBdr></w:pPr></w:p>"#)
                case .image(let alt, let source):
                    if let drawing = picture(source: source, alt: alt, setup: setup) {
                        xml.append("<w:p><w:pPr><w:jc w:val=\"center\"/></w:pPr>\(drawing)</w:p>")
                        if !alt.isEmpty {
                            xml.append("<w:p><w:pPr><w:pStyle w:val=\"Caption\"/></w:pPr>\(run(alt, RunStyle()))</w:p>")
                        }
                    } else if !alt.isEmpty {
                        xml.append("<w:p>\(run("[\(alt)]", RunStyle(italic: true)))</w:p>")
                    }
                case .listItem:
                    break
                }
            }
            let size = setup.pageSize
            let margin = Int(setup.margin * 20)
            let section = """
            <w:sectPr>\(setup.pageNumbers ? #"<w:footerReference w:type="default" r:id="rIdFooter"/>"# : "")\
            <w:pgSz w:w="\(Int(size.width * 20))" w:h="\(Int(size.height * 20))"\(setup.landscape ? #" w:orient="landscape""# : "")/>\
            <w:pgMar w:top="\(margin)" w:right="\(margin)" w:bottom="\(margin)" w:left="\(margin)" w:header="708" w:footer="708" w:gutter="0"/>\
            </w:sectPr>
            """
            return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
            xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" \
            xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
            xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">\
            <w:body>\(xml.joined())\(section)</w:body></w:document>
            """
        }

        func run(_ text: String, _ style: RunStyle) -> String {
            guard !text.isEmpty else { return "" }
            return "<w:r>\(style.properties)<w:t xml:space=\"preserve\">\(DocxWriter.escape(text))</w:t></w:r>"
        }

        mutating func inline(_ markdown: String) -> String {
            render(MarkdownInline.parse(markdown), RunStyle())
        }

        mutating func render(_ inlines: [DocInline], _ style: RunStyle) -> String {
            var xml = ""
            for item in inlines {
                var inner = style
                switch item.kind {
                case .text:
                    xml += run(item.text, style)
                case .lineBreak:
                    xml += "<w:r><w:br/></w:r>"
                case .strong:
                    inner.bold = true
                    xml += render(item.children, inner)
                case .emphasis:
                    inner.italic = true
                    xml += render(item.children, inner)
                case .strike:
                    inner.strike = true
                    xml += render(item.children, inner)
                case .highlight:
                    inner.highlight = true
                    xml += render(item.children, inner)
                case .underline:
                    inner.underline = true
                    xml += render(item.children, inner)
                case .code:
                    inner.code = true
                    xml += run(item.text, inner)
                case .link:
                    links.append(item.url)
                    inner.link = true
                    xml += "<w:hyperlink r:id=\"rIdLink\(links.count)\" w:history=\"1\">\(render(item.children, inner))</w:hyperlink>"
                case .wikiLink:
                    inner.underline = true
                    xml += render(item.children, inner)
                case .tag:
                    xml += run("#" + item.text, style)
                case .image:
                    xml += run(item.text.isEmpty ? "" : "[\(item.text)]", style)
                }
            }
            return xml
        }

        mutating func table(_ table: DocTable, setup: PageSetup) -> String {
            let columns = max(table.columns, 1)
            let usable = Int((setup.pageSize.width - setup.margin * 2) * 20)
            let width = usable / columns
            var xml = "<w:tbl><w:tblPr><w:tblStyle w:val=\"TableGrid\"/><w:tblW w:w=\"\(width * columns)\" w:type=\"dxa\"/>"
                + "<w:tblLook w:val=\"04A0\" w:firstRow=\"1\" w:lastRow=\"0\" w:firstColumn=\"0\" w:lastColumn=\"0\" w:noHBand=\"0\" w:noVBand=\"1\"/></w:tblPr><w:tblGrid>"
            xml += String(repeating: "<w:gridCol w:w=\"\(width)\"/>", count: columns)
            xml += "</w:tblGrid>"
            for (rowIndex, row) in ([table.header] + table.rows).enumerated() {
                xml += rowIndex == 0 ? "<w:tr><w:trPr><w:tblHeader/></w:trPr>" : "<w:tr>"
                for column in 0..<columns {
                    let cell = column < row.count ? row[column] : ""
                    var paragraph = "<w:pPr><w:spacing w:after=\"0\"/>"
                    if column < table.alignments.count {
                        switch table.alignments[column] {
                        case .center: paragraph += "<w:jc w:val=\"center\"/>"
                        case .right: paragraph += "<w:jc w:val=\"right\"/>"
                        case .left: break
                        }
                    }
                    paragraph += "</w:pPr>"
                    let content = render(MarkdownInline.parse(cell), RunStyle(bold: rowIndex == 0))
                    xml += "<w:tc><w:tcPr><w:tcW w:w=\"\(width)\" w:type=\"dxa\"/>"
                        + (rowIndex == 0 ? "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"F4F3F0\"/>" : "")
                        + "</w:tcPr><w:p>\(paragraph)\(content)</w:p></w:tc>"
                }
                xml += "</w:tr>"
            }
            return xml + "</w:tbl>"
        }

        mutating func picture(source: String, alt: String, setup: PageSetup) -> String? {
            guard let data = image(source), let info = DocxWriter.imageInfo(data) else { return nil }
            images.append(info)
            let number = images.count
            // 96 dpi, scaled down to fit between the margins.
            let emuPerPixel = 9_525.0
            let maxWidth = (setup.pageSize.width - setup.margin * 2) * 12_700
            var cx = Double(info.width) * emuPerPixel
            var cy = Double(info.height) * emuPerPixel
            if cx > maxWidth {
                cy *= maxWidth / cx
                cx = maxWidth
            }
            let name = DocxWriter.escape(alt.isEmpty ? "Picture \(number)" : alt)
            return """
            <w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(Int(cx))" cy="\(Int(cy))"/>\
            <wp:docPr id="\(number)" name="\(name)" descr="\(name)"/><wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>\
            <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic>\
            <pic:nvPicPr><pic:cNvPr id="\(number)" name="\(name)"/><pic:cNvPicPr/></pic:nvPicPr>\
            <pic:blipFill><a:blip r:embed="rIdImage\(number)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>\
            <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(Int(cx))" cy="\(Int(cy))"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>\
            </pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>
            """
        }

        func relationships() -> String {
            var items = [
                #"<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>"#,
                #"<Relationship Id="rIdNumbering" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>"#,
                #"<Relationship Id="rIdFooter" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>"#,
            ]
            for (index, url) in links.enumerated() {
                items.append("<Relationship Id=\"rIdLink\(index + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(DocxWriter.escape(url))\" TargetMode=\"External\"/>")
            }
            for (index, item) in images.enumerated() {
                let file = "media/image\(index + 1).\(item.format == "jpeg" ? "jpeg" : "png")"
                items.append("<Relationship Id=\"rIdImage\(index + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"\(file)\"/>")
            }
            return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(items.joined())</Relationships>
            """
        }

        /// Bullets are list 1, numbers list 2; each numbered list after that restarts at its own first number.
        func numbering() -> String {
            let bullets = ["•", "◦", "▪", "•", "◦", "▪", "•", "◦", "▪"]
            let formats = ["decimal", "lowerLetter", "lowerRoman", "decimal", "lowerLetter", "lowerRoman", "decimal", "lowerLetter", "lowerRoman"]
            func level(_ index: Int, format: String, text: String) -> String {
                """
                <w:lvl w:ilvl="\(index)"><w:start w:val="1"/><w:numFmt w:val="\(format)"/><w:lvlText w:val="\(text)"/><w:lvlJc w:val="left"/>\
                <w:pPr><w:ind w:left="\(720 * (index + 1))" w:hanging="360"/></w:pPr></w:lvl>
                """
            }
            let bulletLevels = (0..<9).map { level($0, format: "bullet", text: bullets[$0]) }.joined()
            let numberLevels = (0..<9).map { level($0, format: formats[$0], text: "%\($0 + 1).") }.joined()
            var nums = #"<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num><w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>"#
            for (index, start) in orderedStarts.enumerated() {
                nums += "<w:num w:numId=\"\(index + 3)\"><w:abstractNumId w:val=\"1\"/><w:lvlOverride w:ilvl=\"0\"><w:startOverride w:val=\"\(start)\"/></w:lvlOverride></w:num>"
            }
            return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
            <w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="hybridMultilevel"/>\(bulletLevels)</w:abstractNum>\
            <w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="hybridMultilevel"/>\(numberLevels)</w:abstractNum>\
            \(nums)</w:numbering>
            """
        }
    }
}

// MARK: Zip

/// A plain (stored, uncompressed) ZIP file, which is all a .docx needs to be.
struct ZipWriter {
    private var data = Data()
    private var directory = Data()
    private var count: UInt16 = 0
    private let time: UInt16
    private let date: UInt16

    init(now: Date = Date()) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: now)
        time = UInt16((parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2)
        date = UInt16(max(0, (parts.year ?? 1980) - 1980) << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1))
    }

    mutating func add(_ name: String, _ content: Data) {
        let nameBytes = Data(name.utf8)
        let crc = CRC32.checksum(content)
        let offset = UInt32(data.count)
        data.appendLittleEndian(UInt32(0x0403_4B50))
        data.appendLittleEndian(UInt16(20))
        data.appendLittleEndian(UInt16(0x0800)) // names are UTF-8
        data.appendLittleEndian(UInt16(0))      // stored
        data.appendLittleEndian(time)
        data.appendLittleEndian(date)
        data.appendLittleEndian(crc)
        data.appendLittleEndian(UInt32(content.count))
        data.appendLittleEndian(UInt32(content.count))
        data.appendLittleEndian(UInt16(nameBytes.count))
        data.appendLittleEndian(UInt16(0))
        data.append(nameBytes)
        data.append(content)

        directory.appendLittleEndian(UInt32(0x0201_4B50))
        directory.appendLittleEndian(UInt16(20))
        directory.appendLittleEndian(UInt16(20))
        directory.appendLittleEndian(UInt16(0x0800))
        directory.appendLittleEndian(UInt16(0))
        directory.appendLittleEndian(time)
        directory.appendLittleEndian(date)
        directory.appendLittleEndian(crc)
        directory.appendLittleEndian(UInt32(content.count))
        directory.appendLittleEndian(UInt32(content.count))
        directory.appendLittleEndian(UInt16(nameBytes.count))
        directory.appendLittleEndian(UInt16(0)) // extra
        directory.appendLittleEndian(UInt16(0)) // comment
        directory.appendLittleEndian(UInt16(0)) // disk
        directory.appendLittleEndian(UInt16(0)) // internal attributes
        directory.appendLittleEndian(UInt32(0)) // external attributes
        directory.appendLittleEndian(offset)
        directory.append(nameBytes)
        count += 1
    }

    func finish() -> Data {
        var result = data
        result.append(directory)
        result.appendLittleEndian(UInt32(0x0605_4B50))
        result.appendLittleEndian(UInt16(0))
        result.appendLittleEndian(UInt16(0))
        result.appendLittleEndian(count)
        result.appendLittleEndian(count)
        result.appendLittleEndian(UInt32(directory.count))
        result.appendLittleEndian(UInt32(data.count))
        result.appendLittleEndian(UInt16(0))
        return result
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
