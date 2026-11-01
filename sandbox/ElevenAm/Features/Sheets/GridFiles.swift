import Foundation

/// Excel files in and out, so Google Sheets, Numbers and Excel all trade with Sheets. Formulas travel as formulas,
/// with their last values, formats and widths.
enum GridXLSX {
    static let main = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"

    /// Functions newer than Excel 2010 carry a prefix in the file, or Excel shows #NAME?.
    static let modern = ["XLOOKUP", "IFS", "SWITCH", "TEXTJOIN", "CONCAT", "MAXIFS", "MINIFS", "XOR", "DAYS", "IFNA", "XMATCH"]

    // MARK: Export

    static func data(_ workbook: Workbook) -> Data {
        let engine = GridEngine(workbook)
        var styles = StyleTable()
        var sheetFiles: [String] = []
        for (index, sheet) in workbook.sheets.enumerated() {
            sheetFiles.append(sheetXML(sheet, index: index, engine: engine, styles: &styles))
        }
        var zip = ZipWriter()
        var overrides = """
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        """
        for index in workbook.sheets.indices {
            overrides += "<Override PartName=\"/xl/worksheets/sheet\(index + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        zip.add("[Content_Types].xml", Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>\(overrides)</Types>
        """.utf8))
        zip.add("_rels/.rels", Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
        </Relationships>
        """.utf8))
        let sheetsList = workbook.sheets.enumerated().map { index, sheet in
            "<sheet name=\"\(escape(String(sheet.name.prefix(31))))\" sheetId=\"\(index + 1)\" r:id=\"rId\(index + 1)\"/>"
        }.joined()
        var defined = ""
        if !workbook.names.isEmpty {
            defined = "<definedNames>" + workbook.names.sorted { $0.key < $1.key }.map { "<definedName name=\"\(escape($0.key))\">\(escape($0.value))</definedName>" }.joined() + "</definedNames>"
        }
        zip.add("xl/workbook.xml", Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="\(main)" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
        <bookViews><workbookView/></bookViews><sheets>\(sheetsList)</sheets>\(defined)<calcPr fullCalcOnLoad="1"/></workbook>
        """.utf8))
        var relationships = workbook.sheets.indices.map {
            "<Relationship Id=\"rId\($0 + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0 + 1).xml\"/>"
        }.joined()
        relationships += "<Relationship Id=\"rIdStyles\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        zip.add("xl/_rels/workbook.xml.rels", Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(relationships)</Relationships>
        """.utf8))
        zip.add("xl/styles.xml", Data(styles.xml.utf8))
        for (index, xml) in sheetFiles.enumerated() {
            zip.add("xl/worksheets/sheet\(index + 1).xml", Data(xml.utf8))
        }
        return zip.finish()
    }

    private static func sheetXML(_ sheet: GridSheet, index: Int, engine: GridEngine, styles: inout StyleTable) -> String {
        var rows: [Int: [CellAddress]] = [:]
        for (address, cell) in sheet.cells where !cell.input.isEmpty || cell.format != nil {
            rows[address.row, default: []].append(address)
        }
        var data = ""
        for row in rows.keys.sorted() {
            data += "<row r=\"\(row + 1)\">"
            for address in (rows[row] ?? []).sorted(by: { $0.column < $1.column }) {
                let cell = sheet[address]
                let format = cell.format ?? CellFormat()
                var effective = format
                if effective.number == .general { effective.number = engine.format(sheet: index, address) }
                let style = styles.index(for: effective)
                let styleAttribute = style == 0 ? "" : " s=\"\(style)\""
                let reference = address.a1
                let value = engine.value(sheet: index, address)
                if cell.input.hasPrefix("=") {
                    var formula = String(cell.input.dropFirst())
                    for name in modern {
                        formula = formula.replacingOccurrences(of: #"(?<![A-Za-z_.])\#(name)\("#, with: "_xlfn.\(name)(", options: [.regularExpression, .caseInsensitive])
                    }
                    let (type, cached) = typed(value)
                    data += "<c r=\"\(reference)\"\(styleAttribute)\(type == "n" ? "" : " t=\"\(type == "inlineStr" ? "str" : type)\"")><f>\(escape(formula))</f>"
                    data += cached.map { "<v>\(escape($0))</v>" } ?? ""
                    data += "</c>"
                } else if cell.input.isEmpty {
                    data += "<c r=\"\(reference)\"\(styleAttribute)/>"
                } else {
                    let (type, cached) = typed(value)
                    if type == "inlineStr" {
                        data += "<c r=\"\(reference)\"\(styleAttribute) t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escape(cached ?? ""))</t></is></c>"
                    } else {
                        data += "<c r=\"\(reference)\"\(styleAttribute)\(type == "n" ? "" : " t=\"\(type)\"")><v>\(escape(cached ?? ""))</v></c>"
                    }
                }
            }
            data += "</row>"
        }
        var columns = ""
        if !sheet.columnWidths.isEmpty {
            columns = "<cols>" + sheet.columnWidths.keys.sorted().map { column in
                let width = (sheet.width(of: column) - 5) / 7
                return "<col min=\"\(column + 1)\" max=\"\(column + 1)\" width=\"\(String(format: "%.2f", max(width, 1)))\" customWidth=\"1\"/>"
            }.joined() + "</cols>"
        }
        let pane = sheet.frozenRows > 0
            ? "<pane ySplit=\"\(sheet.frozenRows)\" topLeftCell=\"A\(sheet.frozenRows + 1)\" activePane=\"bottomLeft\" state=\"frozen\"/>"
            : ""
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="\(main)" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
        <sheetViews><sheetView workbookViewId="0"\(index == 0 ? " tabSelected=\"1\"" : "")>\(pane)</sheetView></sheetViews>\
        <sheetFormatPr defaultRowHeight="15"/>\(columns)<sheetData>\(data)</sheetData></worksheet>
        """
    }

    /// The cell type and the value as it's written.
    private static func typed(_ value: CellValue) -> (String, String?) {
        switch value {
        case .empty: return ("n", nil)
        case .number(let number): return ("n", number.isFinite ? String(number) : "0")
        case .text(let text): return ("inlineStr", text)
        case .bool(let flag): return ("b", flag ? "1" : "0")
        case .error(let error): return ("e", error == .cycle ? CellError.ref.rawValue : error.rawValue)
        }
    }

    static func escape(_ text: String) -> String {
        DocxWriter.escape(text)
    }

    /// Fonts, fills and number formats, shared by every cell that looks the same.
    private struct StyleTable {
        var formats: [CellFormat] = [CellFormat()]
        var codes: [String] = []

        mutating func index(for format: CellFormat) -> Int {
            var key = format
            if key.number == .general && key.isPlain { return 0 }
            if case .custom(let code) = key.number, code == "General" { key.number = .general }
            if let found = formats.firstIndex(of: key) { return found }
            formats.append(key)
            let code = key.number.excelCode
            if key.number != .general && !codes.contains(code) { codes.append(code) }
            return formats.count - 1
        }

        var xml: String {
            let numFmts = codes.enumerated().map { "<numFmt numFmtId=\"\(164 + $0.offset)\" formatCode=\"\(GridXLSX.escape($0.element))\"/>" }.joined()
            var fonts: [String] = ["<font><sz val=\"11\"/><name val=\"Calibri\"/></font>"]
            var fills: [String] = ["<fill><patternFill patternType=\"none\"/></fill>", "<fill><patternFill patternType=\"gray125\"/></fill>"]
            var xfs: [String] = ["<xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>"]
            for format in formats.dropFirst() {
                var fontID = 0
                if format.bold || format.italic || format.color != nil {
                    let color = format.color.map { "<color rgb=\"FF\($0.replacingOccurrences(of: "#", with: "").uppercased())\"/>" } ?? ""
                    fonts.append("<font>\(format.bold ? "<b/>" : "")\(format.italic ? "<i/>" : "")<sz val=\"11\"/>\(color)<name val=\"Calibri\"/></font>")
                    fontID = fonts.count - 1
                }
                var fillID = 0
                if let fill = format.fill {
                    let rgb = fill.replacingOccurrences(of: "#", with: "").uppercased()
                    fills.append("<fill><patternFill patternType=\"solid\"><fgColor rgb=\"FF\(rgb)\"/><bgColor indexed=\"64\"/></patternFill></fill>")
                    fillID = fills.count - 1
                }
                let numberID = format.number == .general ? 0 : 164 + (codes.firstIndex(of: format.number.excelCode) ?? 0)
                var attributes = "numFmtId=\"\(numberID)\" fontId=\"\(fontID)\" fillId=\"\(fillID)\" borderId=\"0\" xfId=\"0\""
                if numberID != 0 { attributes += " applyNumberFormat=\"1\"" }
                if fontID != 0 { attributes += " applyFont=\"1\"" }
                if fillID != 0 { attributes += " applyFill=\"1\"" }
                if format.alignment != nil || format.wrap {
                    let horizontal = format.alignment.map { " horizontal=\"\($0.rawValue)\"" } ?? ""
                    xfs.append("<xf \(attributes) applyAlignment=\"1\"><alignment\(horizontal)\(format.wrap ? " wrapText=\"1\"" : "")/></xf>")
                } else {
                    xfs.append("<xf \(attributes)/>")
                }
            }
            return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <styleSheet xmlns="\(GridXLSX.main)">\
            \(codes.isEmpty ? "" : "<numFmts count=\"\(codes.count)\">\(numFmts)</numFmts>")\
            <fonts count="\(fonts.count)">\(fonts.joined())</fonts>\
            <fills count="\(fills.count)">\(fills.joined())</fills>\
            <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>\
            <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
            <cellXfs count="\(xfs.count)">\(xfs.joined())</cellXfs>\
            <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>\
            </styleSheet>
            """
        }
    }

    // MARK: Import

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func workbook(from url: URL) throws -> Workbook {
        guard let workbookData = part(url, "xl/workbook.xml"), let workbookXML = try? XMLDocument(data: workbookData), let root = workbookXML.rootElement() else {
            throw Failure(message: "\(url.lastPathComponent) isn't an Excel workbook 11am can read.")
        }
        var targets: [String: String] = [:]
        if let data = part(url, "xl/_rels/workbook.xml.rels"), let xml = try? XMLDocument(data: data) {
            for case let item as XMLElement in xml.rootElement()?.children ?? [] {
                if let id = item.attribute(forName: "Id")?.stringValue, var target = item.attribute(forName: "Target")?.stringValue {
                    if target.hasPrefix("/xl/") { target.removeFirst(4) } else if target.hasPrefix("/") { target.removeFirst() }
                    targets[id] = target
                }
            }
        }
        let strings = sharedStrings(part(url, "xl/sharedStrings.xml"))
        let styles = readStyles(part(url, "xl/styles.xml"))

        var book = Workbook(name: url.deletingPathExtension().lastPathComponent, sheets: [])
        let sheetElements = root.elements(forLocalName: "sheets", uri: main).first?.elements(forLocalName: "sheet", uri: main) ?? []
        for element in sheetElements {
            guard let name = element.attribute(forName: "name")?.stringValue,
                  let id = element.attribute(forName: "r:id")?.stringValue, let target = targets[id],
                  let data = part(url, "xl/" + target), let xml = try? XMLDocument(data: data), let sheetRoot = xml.rootElement() else { continue }
            book.sheets.append(readSheet(sheetRoot, name: name, strings: strings, styles: styles))
        }
        if let defined = root.elements(forLocalName: "definedNames", uri: main).first {
            for item in defined.elements(forLocalName: "definedName", uri: main) {
                guard let name = item.attribute(forName: "name")?.stringValue, !name.hasPrefix("_xlnm"), let value = item.stringValue else { continue }
                book.names[name] = value.replacingOccurrences(of: "$", with: "")
            }
        }
        guard !book.sheets.isEmpty else { throw Failure(message: "\(url.lastPathComponent) has no sheets 11am can read.") }
        return book
    }

    /// One file out of the .xlsx (a zip), with the system's unzip.
    static func part(_ url: URL, _ name: String) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 && !data.isEmpty ? data : nil
    }

    private static func sharedStrings(_ data: Data?) -> [String] {
        guard let data, let xml = try? XMLDocument(data: data), let root = xml.rootElement() else { return [] }
        return root.elements(forLocalName: "si", uri: main).map { item in
            let pieces = (try? item.nodes(forXPath: ".//*[local-name()='t' and not(ancestor::*[local-name()='rPh'])]")) ?? []
            return pieces.compactMap(\.stringValue).joined()
        }
    }

    private struct Styles {
        var formats: [CellFormat] = []
    }

    private static func readStyles(_ data: Data?) -> Styles {
        guard let data, let xml = try? XMLDocument(data: data), let root = xml.rootElement() else { return Styles() }
        var codes: [Int: String] = [:]
        for item in root.elements(forLocalName: "numFmts", uri: main).first?.elements(forLocalName: "numFmt", uri: main) ?? [] {
            if let id = item.attribute(forName: "numFmtId")?.stringValue.flatMap(Int.init), let code = item.attribute(forName: "formatCode")?.stringValue {
                codes[id] = code
            }
        }
        let fonts = (root.elements(forLocalName: "fonts", uri: main).first?.elements(forLocalName: "font", uri: main) ?? []).map { font -> (Bool, Bool, String?) in
            let bold = !font.elements(forLocalName: "b", uri: main).isEmpty
            let italic = !font.elements(forLocalName: "i", uri: main).isEmpty
            let color = font.elements(forLocalName: "color", uri: main).first?.attribute(forName: "rgb")?.stringValue
            return (bold, italic, color.map { "#" + String($0.suffix(6)) })
        }
        let fills = (root.elements(forLocalName: "fills", uri: main).first?.elements(forLocalName: "fill", uri: main) ?? []).map { fill -> String? in
            guard let pattern = fill.elements(forLocalName: "patternFill", uri: main).first, pattern.attribute(forName: "patternType")?.stringValue == "solid",
                  let rgb = pattern.elements(forLocalName: "fgColor", uri: main).first?.attribute(forName: "rgb")?.stringValue else { return nil }
            return "#" + String(rgb.suffix(6))
        }
        var styles = Styles()
        for xf in root.elements(forLocalName: "cellXfs", uri: main).first?.elements(forLocalName: "xf", uri: main) ?? [] {
            var format = CellFormat()
            let numberID = Int(xf.attribute(forName: "numFmtId")?.stringValue ?? "0") ?? 0
            format.number = numberFormat(id: numberID, code: codes[numberID])
            if let fontID = Int(xf.attribute(forName: "fontId")?.stringValue ?? ""), fonts.indices.contains(fontID), fontID != 0 {
                format.bold = fonts[fontID].0
                format.italic = fonts[fontID].1
                if let color = fonts[fontID].2, color != "#000000" { format.color = color }
            }
            if let fillID = Int(xf.attribute(forName: "fillId")?.stringValue ?? ""), fills.indices.contains(fillID) {
                format.fill = fills[fillID]
            }
            if let alignment = xf.elements(forLocalName: "alignment", uri: main).first {
                format.alignment = alignment.attribute(forName: "horizontal")?.stringValue.flatMap(CellFormat.Alignment.init(rawValue:))
                format.wrap = alignment.attribute(forName: "wrapText")?.stringValue == "1"
            }
            styles.formats.append(format)
        }
        return styles
    }

    /// Built-in Excel format numbers, and custom codes mapped to Sheets' own formats where they match.
    static func numberFormat(id: Int, code: String?) -> NumberFormat {
        switch id {
        case 0: return .general
        case 1, 3: return .number(0)
        case 2, 4: return .number(2)
        case 5, 6, 7, 8, 44: return .currency(2)
        case 9: return .percent(0)
        case 10: return .percent(2)
        case 14: return .shortDate
        case 15, 16, 17: return .date
        case 18, 19, 20, 21, 45, 46, 47: return .time
        case 22: return .dateTime
        case 49: return .text
        default:
            guard let code else { return .general }
            let lower = code.lowercased()
            if lower == "general" { return .general }
            if lower == "@" { return .text }
            if ExcelFormat.isDateCode(code) { return .custom(code) }
            let places = code.split(separator: ".").dropFirst().first.map { $0.prefix { $0 == "0" }.count } ?? 0
            if code.contains("%") { return .percent(places) }
            if code.contains("$") { return .currency(places) }
            if code == "#,##0" || code == "#,##0.00" || code == "0" || code == "0.00" { return .number(places) }
            return .custom(code)
        }
    }

    private static func readSheet(_ root: XMLElement, name: String, strings: [String], styles: Styles) -> GridSheet {
        var sheet = GridSheet(name: name)
        if let pane = (try? root.nodes(forXPath: ".//*[local-name()='pane']"))?.first as? XMLElement,
           pane.attribute(forName: "state")?.stringValue?.hasPrefix("frozen") == true,
           let split = pane.attribute(forName: "ySplit")?.stringValue.flatMap(Double.init) {
            sheet.frozenRows = Int(split)
        }
        for column in root.elements(forLocalName: "cols", uri: main).first?.elements(forLocalName: "col", uri: main) ?? [] {
            guard let min = Int(column.attribute(forName: "min")?.stringValue ?? ""), let max = Int(column.attribute(forName: "max")?.stringValue ?? ""),
                  let width = Double(column.attribute(forName: "width")?.stringValue ?? ""), max - min < 64 else { continue }
            for index in (min - 1)...(max - 1) { sheet.columnWidths[index] = (width * 7 + 5).rounded() }
        }
        var shared: [String: (formula: String, origin: CellAddress)] = [:]
        let rows = root.elements(forLocalName: "sheetData", uri: main).first?.elements(forLocalName: "row", uri: main) ?? []
        for row in rows {
            for cell in row.elements(forLocalName: "c", uri: main) {
                guard let reference = cell.attribute(forName: "r")?.stringValue, let address = CellAddress(reference) else { continue }
                let type = cell.attribute(forName: "t")?.stringValue ?? "n"
                let styleIndex = Int(cell.attribute(forName: "s")?.stringValue ?? "0") ?? 0
                var format = styles.formats.indices.contains(styleIndex) ? styles.formats[styleIndex] : CellFormat()
                let value = cell.elements(forLocalName: "v", uri: main).first?.stringValue
                var input = ""
                if let formulaElement = cell.elements(forLocalName: "f", uri: main).first {
                    var formula = formulaElement.stringValue ?? ""
                    if formulaElement.attribute(forName: "t")?.stringValue == "shared", let id = formulaElement.attribute(forName: "si")?.stringValue {
                        if !formula.isEmpty {
                            shared[id] = (formula, address)
                        } else if let master = shared[id] {
                            formula = String(FormulaRewrite.shift("=" + master.formula, rows: address.row - master.origin.row,
                                                                  columns: address.column - master.origin.column).dropFirst())
                        }
                    }
                    if !formula.isEmpty {
                        input = "=" + formula.replacingOccurrences(of: "_xlfn.", with: "", options: .caseInsensitive)
                    }
                }
                if input.isEmpty {
                    switch type {
                    case "s":
                        let text = Int(value ?? "").flatMap { strings.indices.contains($0) ? strings[$0] : nil } ?? ""
                        input = protect(text)
                    case "inlineStr":
                        let pieces = (try? cell.nodes(forXPath: ".//*[local-name()='t']")) ?? []
                        input = protect(pieces.compactMap(\.stringValue).joined())
                    case "str":
                        input = protect(value ?? "")
                    case "b":
                        input = value == "1" ? "TRUE" : "FALSE"
                    case "e":
                        input = value ?? "#N/A"
                    default:
                        input = value ?? ""
                        if let number = Double(input) {
                            input = GridDisplay.general(number)
                        }
                    }
                }
                if format.isPlain { format = CellFormat() }
                var gridCell = GridCell(input: input)
                if !format.isPlain { gridCell.format = format }
                sheet[address] = gridCell
            }
        }
        return sheet
    }

    /// Text that would read as a number or a date keeps a leading ' so it stays text.
    private static func protect(_ text: String) -> String {
        guard !text.isEmpty, !text.hasPrefix("=") else { return text.hasPrefix("=") ? "'" + text : text }
        if case .text = GridInput.interpret(text).value { return text }
        return "'" + text
    }
}
