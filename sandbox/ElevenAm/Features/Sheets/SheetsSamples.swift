import Foundation

/// The workbooks Sheets starts with, so there's something real to poke at.
enum SheetsSamples {
    static var all: [Workbook] { [budget, trip, clientImport] }

    private static func put(_ sheet: inout GridSheet, _ a1: String, _ input: String, _ format: CellFormat? = nil) {
        guard let address = CellAddress(a1) else { return }
        sheet[address] = GridCell(input: input, format: format)
    }

    private static let bold = CellFormat(bold: true)
    private static let header = CellFormat(bold: true, fill: "#ECEAE6")

    static var budget: Workbook {
        var budget = GridSheet(name: "Budget")
        let months = ["Jul", "Aug", "Sep", "Oct"]
        let columns = ["B", "C", "D", "E"]
        put(&budget, "A1", "Category", header)
        for (index, month) in months.enumerated() { put(&budget, columns[index] + "1", month, CellFormat(bold: true, alignment: .right, fill: "#ECEAE6")) }
        put(&budget, "F1", "Total", CellFormat(bold: true, alignment: .right, fill: "#ECEAE6"))
        put(&budget, "G1", "Share", CellFormat(bold: true, alignment: .right, fill: "#ECEAE6"))
        let lines: [(String, [String])] = [
            ("Rent", ["$2,400", "$2,400", "$2,400", "$2,400"]),
            ("Software", ["$640", "$655", "$655", "$710"]),
            ("Contractors", ["$3,200", "$4,100", "$2,850", "$3,600"]),
            ("Travel", ["$420", "$1,180", "$260", "$890"]),
            ("Marketing", ["$900", "$750", "$1,200", "$980"]),
            ("Insurance", ["$310", "$310", "$310", "$310"]),
        ]
        for (offset, line) in lines.enumerated() {
            let row = offset + 2
            put(&budget, "A\(row)", line.0)
            for (index, value) in line.1.enumerated() { put(&budget, columns[index] + "\(row)", value) }
            put(&budget, "F\(row)", "=SUM(B\(row):E\(row))")
            put(&budget, "G\(row)", "=F\(row)/$F$8", CellFormat(number: .percent(0)))
        }
        put(&budget, "A8", "Total spend", bold)
        for column in columns + ["F"] { put(&budget, "\(column)8", "=SUM(\(column)2:\(column)7)", bold) }
        put(&budget, "A10", "Income")
        for (index, value) in ["$11,500", "$12,200", "$10,900", "$13,400"].enumerated() { put(&budget, columns[index] + "10", value) }
        put(&budget, "F10", "=SUM(B10:E10)")
        put(&budget, "A11", "Left over", bold)
        for column in columns + ["F"] { put(&budget, "\(column)11", "=\(column)10-\(column)8", bold) }
        put(&budget, "A12", "Saved", CellFormat(italic: true))
        for column in columns + ["F"] {
            put(&budget, "\(column)12", "=IF(\(column)10=0,0,\(column)11/\(column)10)", CellFormat(number: .percent(0), italic: true))
        }
        put(&budget, "A14", "Biggest cost")
        put(&budget, "B14", "=INDEX(A2:A7,MATCH(MAX(F2:F7),F2:F7,0))")
        put(&budget, "A15", "Months over $8k")
        put(&budget, "B15", "=COUNTIF(B8:E8,\">8000\")")
        budget.columnWidths = [0: 150, 1: 92, 2: 92, 3: 92, 4: 92, 5: 104, 6: 76]
        budget.frozenRows = 1
        budget.charts = [GridChart(kind: .column, range: CellRange(CellAddress("A1")!, CellAddress("E7")!), title: "Spend by month")]

        var sales = GridSheet(name: "Sales")
        for (index, title) in ["Date", "Client", "Region", "Product", "Amount", "Status", "Checked"].enumerated() {
            sales[CellAddress(row: 0, column: index)] = GridCell(input: title, format: index == 4 ? CellFormat(bold: true, alignment: .right, fill: "#ECEAE6") : header)
        }
        let rows: [(String, String, String, String, String)] = [
            ("1/7/2026", "Acme", "North", "Retainer", "$4,500"),
            ("8/7/2026", "Northwind", "South", "Workshop", "$2,200"),
            ("15/7/2026", "Bluegum", "East", "Audit", "$3,750"),
            ("29/7/2026", "Harbour & Co", "West", "Retainer", "$3,000"),
            ("1/8/2026", "Acme", "North", "Retainer", "$4,500"),
            ("12/8/2026", "Kestrel", "South", "Audit", "$5,100"),
            ("19/8/2026", "Northwind", "South", "Retainer", "$2,800"),
            ("26/8/2026", "Bluegum", "East", "Workshop", "$1,900"),
            ("1/9/2026", "Acme", "North", "Retainer", "$4,500"),
            ("9/9/2026", "Harbour & Co", "West", "Workshop", "$2,400"),
            ("17/9/2026", "Kestrel", "South", "Retainer", "$3,300"),
            ("30/9/2026", "Bluegum", "East", "Audit", "$4,200"),
            ("1/10/2026", "Acme", "North", "Retainer", "$4,500"),
            ("7/10/2026", "Northwind", "South", "Audit", "$3,900"),
            ("14/10/2026", "Harbour & Co", "West", "Retainer", "$3,000"),
            ("21/10/2026", "Kestrel", "South", "Workshop", "$2,600"),
            ("28/10/2026", "Bluegum", "East", "Retainer", "$2,750"),
        ]
        // Who's paid: a list to pick from, and a tick once it's checked against the bank.
        let statuses = ["Paid", "Paid", "Paid", "Paid", "Paid", "Paid", "Paid", "Paid", "Paid", "Paid", "Invoiced", "Overdue",
                        "Invoiced", "Overdue", "Invoiced", "Sent", "Invoiced"]
        for (offset, row) in rows.enumerated() {
            let values = [row.0, row.1, row.2, row.3, row.4, statuses[offset], offset < 10 ? "TRUE" : ""]
            for (column, value) in values.enumerated() where !value.isEmpty {
                sales[CellAddress(row: offset + 1, column: column)] = GridCell(input: value)
            }
        }
        let last = rows.count + 1
        let amounts = CellRange(CellAddress(row: 1, column: 4), CellAddress(row: last - 1, column: 4))
        let status = CellRange(CellAddress(row: 1, column: 5), CellAddress(row: last - 1, column: 5))
        sales.rules = [
            ConditionalRule(range: status, kind: .equalTo, value1: "Overdue", style: RuleStyle(fill: "#F7DAD6", color: "#8E2A1E", bold: true)),
            ConditionalRule(range: status, kind: .equalTo, value1: "Paid", style: RuleStyle(fill: "#DCEFD9", color: "#1F5F2A")),
            ConditionalRule(range: amounts, kind: .top, value1: "3", style: RuleStyle(bold: true)),
            ConditionalRule(range: amounts, kind: .dataBar, high: "#8FB59A"),
        ]
        sales.validations = [
            DataValidation(range: status, kind: .list, choices: ["Invoiced", "Paid", "Overdue"], help: "Invoiced, paid or overdue"),
            DataValidation(range: CellRange(CellAddress(row: 1, column: 6), CellAddress(row: last - 1, column: 6)), kind: .checkbox),
        ]
        let asked = Date().addingTimeInterval(-3_600 * 26)
        sales.comments = [
            GridComment(address: CellAddress(row: 6, column: 4), author: "You", text: "Is this one job or two? @George", date: asked),
            GridComment(address: CellAddress(row: 6, column: 4), author: "George",
                        text: "One job: Kestrel's audit on 12 August, $5,100. It's the biggest sale on the sheet.", date: asked.addingTimeInterval(40)),
        ]
        put(&sales, "D\(last + 2)", "Total", bold)
        put(&sales, "E\(last + 2)", "=SUM(E2:E\(last))", bold)
        put(&sales, "D\(last + 3)", "North only")
        put(&sales, "E\(last + 3)", "=SUMIF(C2:C\(last),\"North\",E2:E\(last))")
        put(&sales, "D\(last + 4)", "Retainers")
        put(&sales, "E\(last + 4)", "=COUNTIF(D2:D\(last),\"Retainer\")")
        put(&sales, "D\(last + 5)", "To collect")
        put(&sales, "E\(last + 5)", "=SUMIF(F2:F\(last),\"<>Paid\",E2:E\(last))")
        put(&sales, "D\(last + 6)", "Checked")
        put(&sales, "E\(last + 6)", "=COUNTIF(G2:G\(last),TRUE)")
        sales.columnWidths = [0: 96, 1: 130, 2: 80, 3: 100, 4: 96, 5: 92, 6: 72]
        sales.frozenRows = 1

        var loan = GridSheet(name: "Loan")
        put(&loan, "A1", "Car loan", CellFormat(bold: true))
        put(&loan, "A3", "Amount")
        put(&loan, "B3", "$45,000")
        put(&loan, "A4", "Interest rate")
        put(&loan, "B4", "6.5%")
        put(&loan, "A5", "Years")
        put(&loan, "B5", "5")
        put(&loan, "A7", "Monthly payment", bold)
        put(&loan, "B7", "=PMT(B4/12,B5*12,-B3)", bold)
        put(&loan, "A8", "Total repaid")
        put(&loan, "B8", "=B7*B5*12")
        put(&loan, "A9", "Interest paid")
        put(&loan, "B9", "=B8-B3")
        put(&loan, "A10", "Paid off")
        put(&loan, "B10", "=EDATE(DATE(2026,11,1),B5*12)")
        loan.columnWidths = [0: 150, 1: 120]

        var book = Workbook(name: "Budget 2026–27", sheets: [budget, sales, loan])
        book.modified = Date()
        return book
    }

    /// A contact list exported from somewhere else, untidy in all the usual ways, for George to clean.
    static var clientImport: Workbook {
        var sheet = GridSheet(name: "Import")
        for (index, title) in ["Name", "Email", "Amount", "Date", "Status"].enumerated() {
            sheet[CellAddress(row: 0, column: index)] = GridCell(input: title, format: header)
        }
        let rows: [[String]] = [
            ["  Tom   Baker ", "tom@acme.example", "AUD 1,200", "3rd Nov 2026", "Done"],
            ["Priya Shah", "priya@northwind.example", "1 200", "Tuesday 3 November 2026", "done"],
            ["Kim Lee", "kim@kimdesign.example", "$300", "1/11/2026", "Done"],
            ["Tom Baker", "tom@acme.example", "1.5k", "03.11.2026", ""],
            ["Ana Ruiz", "ana@bluegum.example", "45-", "Sept 3 2026", "Late"],
            ["sam o'neil", "sam@harbour.example", "2,400", "28 Oct 2026", "DONE"],
            ["Jess Wong", "jess@studiowong.example", "US$980", "2026/10/21", "Late"],
            ["Lee Park", "lee@kestrel.example", "640", "14.10.2026", "Done"],
        ]
        for (offset, values) in rows.enumerated() {
            for (column, value) in values.enumerated() where !value.isEmpty {
                sheet[CellAddress(row: offset + 1, column: column)] = GridCell(input: value)
            }
        }
        sheet.columnWidths = [0: 130, 1: 190, 2: 96, 3: 180, 4: 72]
        sheet.frozenRows = 1
        var book = Workbook(name: "Client import", sheets: [sheet])
        book.modified = Date().addingTimeInterval(-86_400)
        return book
    }

    static var trip: Workbook {
        var sheet = GridSheet(name: "Costs")
        for (index, title) in ["Item", "Who", "Cost", "Paid"].enumerated() {
            sheet[CellAddress(row: 0, column: index)] = GridCell(input: title, format: header)
        }
        let items: [(String, String, String, String)] = [
            ("Flights", "Sam", "$1,840", "Yes"),
            ("Ryokan, 3 nights", "Alex", "$960", "Yes"),
            ("Rail passes", "Sam", "$620", "No"),
            ("Tokyo apartment", "Alex", "$1,150", "Yes"),
            ("Food and the rest", "Both", "$900", "No"),
        ]
        for (offset, item) in items.enumerated() {
            let values = [item.0, item.1, item.2, item.3]
            for (column, value) in values.enumerated() { sheet[CellAddress(row: offset + 1, column: column)] = GridCell(input: value) }
        }
        put(&sheet, "A8", "Total", bold)
        put(&sheet, "C8", "=SUM(C2:C6)", bold)
        put(&sheet, "A9", "Still to pay")
        put(&sheet, "C9", "=SUMIF(D2:D6,\"No\",C2:C6)")
        put(&sheet, "A10", "Sam's share")
        put(&sheet, "C10", "=SUMIF(B2:B6,\"Sam\",C2:C6)+SUMIF(B2:B6,\"Both\",C2:C6)/2")
        put(&sheet, "A11", "Alex's share")
        put(&sheet, "C11", "=C8-C10")
        sheet.columnWidths = [0: 170, 1: 80, 2: 96, 3: 64]
        sheet.frozenRows = 1
        sheet.charts = [GridChart(kind: .pie, range: CellRange(CellAddress("A1")!, CellAddress("C6")!), title: "Where it goes")]
        var book = Workbook(name: "Japan trip", sheets: [sheet])
        book.modified = Date().addingTimeInterval(-86_400 * 3)
        return book
    }
}
