// Checks George's grid engine on a real Mac: addresses, typed input, formulas and functions, formats, reference
// rewriting, fill, rows and columns, sorting, summaries, CSV and Excel files. Run from an empty folder.
import Foundation

var failures = 0

func check(_ condition: Bool, _ label: String) {
    print(condition ? "PASS" : "FAIL", label)
    if !condition { failures += 1 }
}

let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

// MARK: Addresses and input

check(CellAddress("A1") == CellAddress(row: 0, column: 0) && CellAddress("$AA$10") == CellAddress(row: 9, column: 26), "Addresses parse")
check(CellAddress.columnName(25) == "Z" && CellAddress.columnName(701) == "ZZ" && CellAddress.columnName(702) == "AAA" && CellAddress(row: 4, column: 27).a1 == "AB5", "Column names")
check(CellRange("B3:A1")?.a1 == "A1:B3" && CellRange("B3:A1")?.cells.count == 6, "Ranges normalise")

func interpret(_ text: String) -> (CellValue, NumberFormat?) { GridInput.interpret(text) }
check(interpret("12%").0 == .number(0.12) && interpret("12%").1 == .percent(0), "Typed: 12% is 0.12, shown as a percent")
check(interpret("$1,200.50").0 == .number(1200.5) && interpret("$1,200.50").1 == .currency(2), "Typed: $1,200.50 is dollars")
check(interpret("-$40").0 == .number(-40) && interpret("(1,000)").0 == .number(-1000), "Typed: negative money")
check(interpret("1,234").0 == .number(1234) && interpret("1,2").0 == .text("1,2"), "Typed: thousands, and not-quite-numbers stay text")
check(interpret("1/11/2026").0 == .number(46327) && interpret("1/11/2026").1 == .shortDate, "Typed: 1/11/2026 is 1 November (day first)")
let isoTyped = interpret("2026-11-01"), wordTyped = interpret("1 Nov 2026")
check(isoTyped.0 == .number(46327) && wordTyped.0 == .number(46327) && wordTyped.1 == .date,
      "Typed: other date styles (\(isoTyped.0), \(String(describing: isoTyped.1)); \(wordTyped.0), \(String(describing: wordTyped.1)))")
check(interpret("9:30 am").0.number.map { abs($0 - 9.5 / 24) < 1e-9 } == true, "Typed: a time")
check(interpret("'0123").0 == .text("0123") && interpret("TRUE").0 == .bool(true) && interpret("0412 345 678").0 == .text("0412 345 678"), "Typed: forced text, true, phone numbers")

// MARK: Formulas

var book = Workbook(name: "Test", sheets: [GridSheet(name: "Data"), GridSheet(name: "Sheet 2")])
func set(_ sheet: Int, _ address: String, _ input: String, format: NumberFormat? = nil) {
    guard let cell = CellAddress(address) else { return }
    book.sheets[sheet][cell] = GridCell(input: input, format: format.map { CellFormat(number: $0) })
}
// A1:A5 = 1…5; B = names; C = money; D = dates.
for row in 1...5 { set(0, "A\(row)", "\(row)") }
for (row, name) in ["Acme", "Northwind", "Acme Labs", "Bravo", "Acme"].enumerated() { set(0, "B\(row + 1)", name) }
for (row, money) in ["$100", "$250", "$75.50", "$40", "$1,000"].enumerated() { set(0, "C\(row + 1)", money) }
set(1, "A1", "21")

var engine = GridEngine(book)
func run(_ formula: String) -> CellValue { engine.evaluate(formula: formula, sheet: 0) }
func number(_ formula: String) -> Double { run(formula).number ?? .nan }
func near(_ formula: String, _ expected: Double, _ tolerance: Double = 1e-6) -> Bool { abs(number(formula) - expected) < tolerance }

check(number("=SUM(A1:A5)") == 15 && number("=AVERAGE(A1:A5)") == 3 && number("=MAX(A1:A5)") == 5 && number("=MIN(A1:A5,0.5)") == 0.5, "SUM, AVERAGE, MAX, MIN")
check(number("=-2^2") == 4 && number("=2+3*4") == 14 && number("=(2+3)*4") == 20 && near("=10%", 0.1) && number("=2^3^2") == 64, "Operator order, as Excel does it")
check(run("=\"Acme\"&\" \"&A2") == .text("Acme 2") && run("=1<2") == .bool(true) && run("=\"abc\"=\"ABC\"") == .bool(true), "Text joining and comparisons")
check(run("=1/0") == .error(.div0) && run("=FOO(1)") == .error(.name) && run("=SUM(1,\"x\")") == .error(.value) && run("=A1+") == .error(.name), "Errors")
check(run("='Sheet 2'!A1*2") == .number(42) && run("=Data!A3") == .number(3), "References to other sheets")
check(number("=COUNT(A1:C5)") == 10 && number("=COUNTA(A1:C5)") == 15 && number("=COUNTBLANK(A1:A9)") == 4, "COUNT, COUNTA, COUNTBLANK")
check(number("=SUMIF(B1:B5,\"Acme\",C1:C5)") == 1100 && number("=SUMIF(A1:A5,\">2\")") == 12 && number("=COUNTIF(B1:B5,\"Acme*\")") == 3, "SUMIF and COUNTIF with criteria and wildcards")
check(number("=SUMIFS(C1:C5,B1:B5,\"Acme*\",A1:A5,\">=3\")") == 1075.5 && number("=COUNTIFS(B1:B5,\"<>Acme\")") == 3, "SUMIFS and COUNTIFS")
check(near("=AVERAGEIFS(C1:C5,B1:B5,\"Acme\")", 550) && number("=MAXIFS(C1:C5,B1:B5,\"Acme*\")") == 1000 && number("=MINIFS(C1:C5,B1:B5,\"Acme*\")") == 75.5, "AVERAGEIFS, MAXIFS, MINIFS")
check(number("=SUMPRODUCT((A1:A5>2)*A1:A5)") == 12 && number("=SUMPRODUCT(A1:A5,A1:A5)") == 55, "SUMPRODUCT, with array conditions")
check(run("=IF(A1>0,\"yes\",\"no\")") == .text("yes") && run("=IFS(A1>5,\"big\",A1>0,\"small\")") == .text("small") && run("=IFERROR(1/0,\"none\")") == .text("none"), "IF, IFS, IFERROR")
check(run("=AND(A1>0,A2>1)") == .bool(true) && run("=OR(A1>9,A2>9)") == .bool(false) && run("=NOT(TRUE)") == .bool(false) && run("=SWITCH(2,1,\"one\",2,\"two\")") == .text("two"), "AND, OR, NOT, SWITCH")
check(run("=VLOOKUP(\"Bravo\",B1:C5,2,FALSE)") == .number(40) && run("=VLOOKUP(\"Zed\",B1:C5,2,FALSE)") == .error(.na) && number("=VLOOKUP(3.7,A1:C5,3)") == 75.5, "VLOOKUP, exact and approximate")
check(run("=XLOOKUP(\"Northwind\",B1:B5,C1:C5)") == .number(250) && run("=XLOOKUP(\"Zed\",B1:B5,C1:C5,\"not found\")") == .text("not found") && number("=XLOOKUP(\"Acme\",B1:B5,A1:A5,,0,-1)") == 5, "XLOOKUP: found, not found, last match")
check(number("=INDEX(C1:C5,MATCH(\"Bravo\",B1:B5,0))") == 40 && number("=MATCH(3.5,A1:A5)") == 3 && number("=INDEX(A1:C5,2,3)") == 250, "INDEX and MATCH")
check(run("=LEFT(\"Northwind\",5)") == .text("North") && run("=MID(\"Northwind\",6,4)") == .text("wind") && number("=LEN(B2)") == 9 && run("=UPPER(\"acme\")") == .text("ACME"), "LEFT, MID, LEN, UPPER")
check(run("=SUBSTITUTE(\"a-b-c\",\"-\",\"+\")") == .text("a+b+c") && run("=SUBSTITUTE(\"a-b-c\",\"-\",\"+\",2)") == .text("a-b+c") && run("=TEXTJOIN(\", \",TRUE,B1:B3)") == .text("Acme, Northwind, Acme Labs"), "SUBSTITUTE and TEXTJOIN")
check(number("=FIND(\"w\",\"Northwind\")") == 6 && number("=SEARCH(\"W\",\"Northwind\")") == 6 && run("=FIND(\"W\",\"Northwind\")") == .error(.value) && run("=TRIM(\"  a   b \")") == .text("a b"), "FIND, SEARCH, TRIM")
check(run("=TEXT(0.256,\"0.0%\")") == .text("25.6%") && run("=TEXT(46327,\"d mmm yyyy\")") == .text("1 Nov 2026") && run("=TEXT(1234.5,\"$#,##0.00\")") == .text("$1,234.50"), "TEXT with number, date and money codes")
check(run("=TEXT(46327.75,\"dd/mm/yyyy h:mm AM/PM\")") == .text("01/11/2026 6:00 pm"), "TEXT with a date and time (\(run("=TEXT(46327.75,\"dd/mm/yyyy h:mm AM/PM\")")))")
check(number("=DATE(2026,11,1)") == 46327 && number("=DATE(2026,13,1)") == 46388 && number("=EOMONTH(DATE(2026,2,10),0)") == 46081 && number("=EDATE(DATE(2026,1,31),1)") == 46081, "DATE, EOMONTH, EDATE")
check(number("=YEAR(46327)") == 2026 && number("=MONTH(46327)") == 11 && number("=DAY(46356)") == 30 && number("=WEEKDAY(46327)") == 1 && number("=WEEKDAY(46327,2)") == 7, "YEAR, MONTH, DAY, WEEKDAY")
check(number("=NETWORKDAYS(DATE(2026,11,2),DATE(2026,11,8))") == 5 && number("=WORKDAY(DATE(2026,11,6),1)") == 46335 && number("=DAYS(46356,46327)") == 29 && number("=DATEDIF(DATE(2020,5,1),DATE(2026,11,1),\"Y\")") == 6, "Working days, DAYS, DATEDIF")
check(number("=ROUND(2.345,2)") == 2.35 && number("=ROUND(-2.5,0)") == -3 && number("=ROUNDDOWN(2.99,0)") == 2 && number("=ROUNDUP(2.01,0)") == 3 && number("=MOD(-7,3)") == 2, "Rounding and MOD the spreadsheet way")
check(near("=PMT(5%/12,60,30000)", -566.137009, 1e-5) && near("=NPV(10%,100,200,300)", 481.592787, 1e-5), "PMT and NPV")
set(0, "E1", "-1000"); set(0, "E2", "300"); set(0, "E3", "400"); set(0, "E4", "500")
engine = GridEngine(book)
check(near("=IRR(E1:E4)", 0.0889634, 1e-6) && near("=FV(5%,10,-100)", 1257.789254, 1e-5), "IRR and FV")
check(number("=MEDIAN(A1:A5,10)") == 3.5 && near("=STDEV(A1:A5)", 1.5811388) && number("=LARGE(C1:C5,2)") == 250 && number("=RANK(250,C1:C5)") == 2, "MEDIAN, STDEV, LARGE, RANK")

// Cells, cycles, names, display
set(0, "F1", "=F2+1"); set(0, "F2", "=F1+1"); set(0, "F3", "=SUM(C1:C5)"); set(0, "F4", "=A5/A2"); set(0, "F5", "=DATE(2026,11,1)")
set(0, "F6", "=C1*10%", format: nil)
book.names["Amounts"] = "Data!C1:C5"
engine = GridEngine(book)
check(engine.value(sheet: 0, CellAddress("F1")!) == .error(.cycle), "A circular reference is caught")
check(engine.display(sheet: 0, CellAddress("F3")!) == "$1,465.50" && engine.display(sheet: 0, CellAddress("C3")!) == "$75.50", "A total shows in the dollars it adds up (\(engine.display(sheet: 0, CellAddress("F3")!)))")
check(engine.display(sheet: 0, CellAddress("F4")!) == "2.5" && engine.display(sheet: 0, CellAddress("F5")!) == "01/11/2026", "Plain results and dates show sensibly")
check(engine.evaluate(formula: "=SUM(Amounts)", sheet: 0) == .number(1465.5), "Named ranges")

// MARK: Rewriting references

check(FormulaRewrite.shift("=SUM(A1:B2)+$C$1+C$1+$C1", rows: 1, columns: 1) == "=SUM(B2:C3)+$C$1+D$1+$C2", "Copying moves relative references only")
check(FormulaRewrite.shift("=A1", rows: -1, columns: 0) == "=#REF!" && FormulaRewrite.shift("='Sheet 2'!A1&\"A1\"", rows: 2, columns: 0) == "='Sheet 2'!A3&\"A1\"", "Off the sheet is #REF!; text that looks like a reference is left alone")
check(FormulaRewrite.insert("=SUM(A1:A5)+B9", rows: true, at: 2, count: 2, sameSheet: true, target: "Data") == "=SUM(A1:A7)+B11", "Inserting rows stretches ranges")
check(FormulaRewrite.insert("=A2+A5+SUM(A1:A3)", rows: true, at: 1, count: -2, sameSheet: true, target: "Data") == "=#REF!+A3+SUM(A1:A1)", "Deleting rows: gone is #REF!, ranges close in")
check(FormulaRewrite.insert("=Data!A5+A5", rows: true, at: 0, count: 1, sameSheet: false, target: "Data") == "=Data!A6+A5", "Inserting on another sheet moves only references to it")
check(FormulaRewrite.insert("=SUM(C:D)", rows: false, at: 1, count: 1, sameSheet: true, target: "Data") == "=SUM(D:E)", "Whole columns move with inserted columns")

// MARK: Editing

var sheet = GridSheet(name: "Fill")
sheet[CellAddress("A1")!] = GridCell(input: "1"); sheet[CellAddress("A2")!] = GridCell(input: "2")
GridEdit.fill(&sheet, from: CellRange("A1:A2")!, to: CellRange("A1:A5")!)
check((3...5).allSatisfy { sheet.input(CellAddress(row: $0 - 1, column: 0)) == "\($0)" }, "Fill continues a number series")
sheet[CellAddress("B1")!] = GridCell(input: "Week 1")
GridEdit.fill(&sheet, from: CellRange("B1")!, to: CellRange("B1:B3")!)
sheet[CellAddress("C1")!] = GridCell(input: "Jan")
GridEdit.fill(&sheet, from: CellRange("C1")!, to: CellRange("C1:E1")!)
check(sheet.input(CellAddress("B3")!) == "Week 3" && sheet.input(CellAddress("D1")!) == "Feb" && sheet.input(CellAddress("E1")!) == "Mar", "Fill counts Week 1, 2, 3 and Jan, Feb, Mar")
sheet[CellAddress("F1")!] = GridCell(input: "=A1*2")
GridEdit.fill(&sheet, from: CellRange("F1")!, to: CellRange("F1:F3")!)
check(sheet.input(CellAddress("F3")!) == "=A3*2", "Fill moves formulas")
sheet[CellAddress("G1")!] = GridCell(input: "1/11/2026")
GridEdit.fill(&sheet, from: CellRange("G1")!, to: CellRange("G1:G2")!)
check(GridInput.interpret(sheet.input(CellAddress("G2")!)).value == .number(46328), "Fill moves a date on a day (\(sheet.input(CellAddress("G2")!)))")

var edits = book
set(1, "B1", "=SUM(Data!A1:A5)")
edits = book
GridEdit.insert(&edits, sheet: 0, rows: true, at: 0, count: 2)
check(edits.sheets[0].input(CellAddress("A3")!) == "1" && edits.sheets[1].input(CellAddress("B1")!) == "=SUM(Data!A3:A7)", "Inserting rows moves cells and fixes formulas on other sheets")
check(edits.sheets[0].input(CellAddress("H3")!) == "=SUM(C3:C7)" || edits.sheets[0].input(CellAddress("F5")!) == "=SUM(C3:C7)", "…and on the same sheet")
GridEdit.insert(&edits, sheet: 0, rows: false, at: 0, count: -1)
check(edits.sheets[0].input(CellAddress("A3")!) == "Acme" && edits.sheets[1].input(CellAddress("B1")!) == "=SUM(Data!#REF!)", "Deleting a column")

var sorting = Workbook(name: "Sort", sheets: [GridSheet(name: "S")])
for (row, pair) in [("Name", "Score"), ("Mia", "7"), ("Sam", "9"), ("Ana", "3")].enumerated() {
    sorting.sheets[0][CellAddress(row: row, column: 0)] = GridCell(input: pair.0)
    sorting.sheets[0][CellAddress(row: row, column: 1)] = GridCell(input: pair.1)
    if row > 0 { sorting.sheets[0][CellAddress(row: row, column: 2)] = GridCell(input: "=B\(row + 1)*10") }
}
GridEdit.sort(&sorting, sheet: 0, range: CellRange("A1:C4")!, by: 1, ascending: false, header: true)
let sorted = GridEngine(sorting)
check(sorting.sheets[0].input(CellAddress("A2")!) == "Sam" && sorting.sheets[0].input(CellAddress("A4")!) == "Ana" && sorted.value(sheet: 0, CellAddress("C2")!) == .number(90), "Sorting moves rows, formulas and all")

let summary = GridEdit.summarise(book, sheet: 0, range: CellRange("B1:C5")!, group: 1, value: 2, summary: .sum)
var withSummary = book
withSummary.sheets.append(summary)
let summaryEngine = GridEngine(withSummary)
let summaryIndex = withSummary.sheets.count - 1
let firstKey = summaryEngine.display(sheet: summaryIndex, CellAddress("A2")!)
check(firstKey == "Acme", "Summary groups the values, biggest first (\(firstKey))")
check(summaryEngine.value(sheet: summaryIndex, CellAddress(row: 1, column: 1)).number.map { $0 > 0 } == true && summary.input(CellAddress("B2")!).hasPrefix("=SUMIFS("), "Summary uses live SUMIFS formulas")

// MARK: CSV

let csv = "Date,Description,Amount\n2026-10-01,\"Stripe, payout\",\"1,200.50\"\n2026-10-02,\"Quote \"\"x\"\"\",-40\n"
let rows = GridCSV.parse(csv)
check(rows.count == 3 && rows[1] == ["2026-10-01", "Stripe, payout", "1,200.50"] && rows[2][1] == "Quote \"x\"", "CSV: quotes, commas and escaped quotes")
let fromCSV = GridCSV.sheet(from: csv, name: "Bank")
check(fromCSV.frozenRows == 1 && fromCSV[CellAddress("A1")!].format?.bold == true && GridEngine(Workbook(name: "x", sheets: [fromCSV])).value(sheet: 0, CellAddress("C2")!) == .number(1200.5), "CSV: header row, numbers read")
check(GridCSV.parse("a;b;c\n1;2;3").first == ["a", "b", "c"] && GridCSV.parse("a\tb\n1\t2").first == ["a", "b"], "CSV: semicolons and tabs")

// MARK: Excel

func runTool(_ tool: String, _ arguments: [String]) -> (Int32, String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try? process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

var excel = book
excel.sheets[0].frozenRows = 1
excel.sheets[0].columnWidths[1] = 160
excel.sheets[0][CellAddress("G1")!] = GridCell(input: "=XLOOKUP(\"Bravo\",B1:B5,C1:C5)")
excel.sheets[0][CellAddress("G2")!] = GridCell(input: "Bold note", format: CellFormat(bold: true, fill: "#FFF3A3"))
excel.sheets[0][CellAddress("G3")!] = GridCell(input: "0.256", format: CellFormat(number: .percent(1)))
let xlsxURL = folder.appendingPathComponent("test.xlsx")
try? GridXLSX.data(excel).write(to: xlsxURL)
check(runTool("/usr/bin/unzip", ["-tq", xlsxURL.path]).0 == 0, "Excel: a valid zip")
for part in ["xl/workbook.xml", "xl/styles.xml", "xl/worksheets/sheet1.xml", "xl/worksheets/sheet2.xml", "xl/_rels/workbook.xml.rels"] {
    let text = runTool("/usr/bin/unzip", ["-p", xlsxURL.path, part]).1
    check(!text.isEmpty && (try? XMLDocument(data: Data(text.utf8))) != nil, "Excel: \(part) is well-formed")
}
let sheetXML = runTool("/usr/bin/unzip", ["-p", xlsxURL.path, "xl/worksheets/sheet1.xml"]).1
check(sheetXML.contains("<f>_xlfn.XLOOKUP(") && sheetXML.contains("<f>SUM(C1:C5)</f><v>1465.5</v>") && sheetXML.contains("state=\"frozen\""), "Excel: formulas with their values, the newer-function prefix, a frozen header")
if let back = try? GridXLSX.workbook(from: xlsxURL) {
    check(back.sheets.map(\.name) == ["Data", "Sheet 2"], "Excel in: sheet names")
    check(back.sheets[0].input(CellAddress("F3")!) == "=SUM(C1:C5)" && back.sheets[0].input(CellAddress("G1")!) == "=XLOOKUP(\"Bravo\",B1:B5,C1:C5)", "Excel in: formulas, without the prefix")
    check(back.sheets[1].input(CellAddress("A1")!) == "21" && back.sheets[0].input(CellAddress("B2")!) == "Northwind", "Excel in: numbers and text")
    check(back.sheets[0][CellAddress("C3")!].format?.number == .currency(2) && back.sheets[0][CellAddress("G3")!].format?.number == .percent(1), "Excel in: number formats (\(String(describing: back.sheets[0][CellAddress("C3")!].format?.number)))")
    check(back.sheets[0][CellAddress("G2")!].format?.bold == true && back.sheets[0][CellAddress("G2")!].format?.fill == "#FFF3A3", "Excel in: bold and fill")
    check(back.sheets[0].frozenRows == 1 && abs(back.sheets[0].width(of: 1) - 160) < 8 && back.names["Amounts"] == "Data!C1:C5", "Excel in: frozen rows, widths, named ranges")
    let backEngine = GridEngine(back)
    check(backEngine.value(sheet: 0, CellAddress("F3")!) == .number(1465.5) && backEngine.value(sheet: 0, CellAddress("G1")!) == .number(40), "Excel in: formulas calculate the same")
} else {
    check(false, "Excel in: read back")
}

// MARK: Size

var big = Workbook(name: "Big", sheets: [GridSheet(name: "Rows")])
for row in 0..<20_000 {
    big.sheets[0][CellAddress(row: row, column: 0)] = GridCell(input: "\(row % 97)")
}
big.sheets[0][CellAddress(row: 0, column: 2)] = GridCell(input: "=SUMIF(A:A,\">50\")")
let started = Date()
let bigValue = GridEngine(big).value(sheet: 0, CellAddress(row: 0, column: 2))
let seconds = Date().timeIntervalSince(started)
check(bigValue.number.map { $0 > 0 } == true && seconds < 3, "20,000 rows: SUMIF over a whole column in \(String(format: "%.2f", seconds)) s")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
