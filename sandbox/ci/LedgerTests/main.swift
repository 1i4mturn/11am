import Foundation

// Checks George's books: money and GST arithmetic, posting, reconciliation, reports, the BAS,
// statement files and the accountant's pack. Run in Sydney time.

var failures = 0
func check(_ condition: Bool, _ name: String) {
    print(condition ? "PASS" : "FAIL", name)
    if !condition { failures += 1 }
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = .current
func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
}

// MARK: Money and GST

check(LedgerMoney.parse("$1,234.50") == 123_450 && LedgerMoney.parse("(45.00)") == -4_500 && LedgerMoney.parse("45.00 DR") == -4_500
      && LedgerMoney.parse("-12") == -1_200 && LedgerMoney.parse("1 234,50") == 123_450 && LedgerMoney.parse("abc") == nil, "Amounts parse")
check(LedgerMoney.text(-8_000) == "−$80.00" && LedgerMoney.text(123_456_789) == "$1,234,567.89" && LedgerMoney.text(5) == "$0.05", "Amounts print")
check(GST.included(in: 110_000, .gst) == 10_000 && GST.included(in: 100_000, .free) == 0 && GST.added(to: 100_000, .gst) == 10_000
      && GST.included(in: 6, .gst) == 1 && GST.included(in: -11_000, .gst) == -1_000, "GST is one eleventh of the price, to the cent")

// MARK: Posting an invoice

var book = LedgerBook()
let client = Contact(name: "Acme Pty Ltd", email: "a@acme.example")
let supplier = Contact(name: "Kim Design Studio")
book.contacts = [client, supplier]
let invoice = Invoice(kind: .sale, number: book.takeInvoiceNumber(), contact: client.id, issued: date(2026, 9, 1), due: date(2026, 9, 15),
                      lines: [InvoiceLine(description: "Workshop", unitPrice: 100_000, account: "200", gst: .gst)])
book.invoices.append(invoice)
check(invoice.number == "INV-0001" && invoice.total == 110_000 && invoice.tax == 10_000, "An invoice adds 10% GST (\(invoice.number))")
try? book.approve(invoice.id)
let approved = book.invoice(invoice.id)
let posted = book.entries.first { $0.id == approved?.entry }
check(approved?.status == .approved && posted?.isBalanced == true, "Approving posts a balanced entry")
let afterInvoice = book.balances(to: date(2026, 9, 30))
check(afterInvoice["610"] == 110_000 && afterInvoice["200"] == -100_000 && afterInvoice["820"] == -10_000,
      "…receivable up, sales and GST credited")

// MARK: Bank lines

book.importStatement([
    BankLine(account: "090", date: date(2026, 9, 10), description: "ACME PTY LTD INV-0001", amount: 50_000, bankID: "A1"),
    BankLine(account: "090", date: date(2026, 9, 12), description: "AWS EMEA 1234 aws.amazon.com", amount: -11_000, bankID: "A2"),
    BankLine(account: "090", date: date(2026, 9, 20), description: "OFFICEWORKS 4411", amount: -132_000, bankID: "A3"),
    BankLine(account: "090", date: date(2026, 9, 25), description: "ACME PTY LTD INV-0001", amount: 60_000, bankID: "A4"),
    BankLine(account: "090", date: date(2026, 10, 12), description: "AWS EMEA 9876 aws.amazon.com", amount: -12_100, bankID: "A5"),
    BankLine(account: "090", date: date(2026, 10, 14), description: "TRANSFER TO SAVINGS", amount: -200_000, bankID: "A6"),
    BankLine(account: "091", date: date(2026, 10, 14), description: "TRANSFER FROM BUSINESS", amount: 200_000, bankID: "B1"),
    BankLine(account: "090", date: date(2026, 10, 16), description: "STRIPE PAYOUT", amount: 55_000, bankID: "A7"),
])
check(book.bank.count == 8, "Statement lines are added")
let again = book.importStatement([BankLine(account: "090", date: date(2026, 9, 10), description: "ACME PTY LTD INV-0001", amount: 50_000, bankID: "A1")])
check(again.added == 0 && again.duplicates == 1, "…and the same line twice is skipped")

let partLine = book.bank.first { $0.bankID == "A1" }!
check(book.suggestion(for: partLine) == nil || book.suggestion(for: partLine) != nil, "Suggestions don't crash")
try? book.recordPayment(invoice.id, amount: 50_000, date: partLine.date, bankAccount: "090", bankLine: partLine.id)
if let index = book.bank.firstIndex(where: { $0.id == partLine.id }) { book.bank[index].entry = book.entries.last?.id }
check(book.invoice(invoice.id)?.owing == 60_000 && book.invoice(invoice.id)?.status == .approved, "A part payment leaves the rest owing")
let restLine = book.bank.first { $0.bankID == "A4" }!
check(book.suggestion(for: restLine) == .invoice(invoice.id), "The rest is matched to the invoice by its number and amount")
try? book.match(restLine.id, invoice: invoice.id)
check(book.invoice(invoice.id)?.status == .paid && book.invoice(invoice.id)?.owing == 0 && book.balances(to: date(2026, 12, 31))["610"] == 0,
      "Matching the payment marks it paid and clears the receivable")

let aws = book.bank.first { $0.bankID == "A2" }!
try? book.code(aws.id, account: "485", gst: .gst)
let awsEntry = book.entries.last!
check(awsEntry.isBalanced && awsEntry.lines.contains { $0.account == "485" && $0.amount == 10_000 && $0.taxAmount == 1_000 }
      && awsEntry.lines.contains { $0.account == "820" && $0.amount == 1_000 }, "Coding money out splits the GST out")
let awsAgain = book.bank.first { $0.bankID == "A5" }!
check(book.suggestion(for: awsAgain) == .rule(account: "485", gst: .gst, times: 1), "The next AWS line is suggested the same way")
try? book.code(awsAgain.id, account: "485", gst: .gst)
check(book.rules[LedgerBook.payeeKey("AWS EMEA")]?.count == 2, "…and the rule counts how often (\(LedgerBook.payeeKey("AWS EMEA 9876 aws.amazon.com")))")

let desk = book.bank.first { $0.bankID == "A3" }!
try? book.code(desk.id, account: "710", gst: .capital)
let transferLine = book.bank.first { $0.bankID == "A6" }!
check(book.suggestion(for: transferLine) == .transfer(account: "091"), "A transfer is spotted from the other account")
try? book.transfer(transferLine.id, to: "091")
check(book.bank.first { $0.bankID == "B1" }?.isReconciled == true, "…and both sides reconcile against one entry")

let stripe = book.bank.first { $0.bankID == "A7" }!
try? book.code(stripe.id, account: "200", gst: .free)
check(book.unreconciled.isEmpty, "Everything reconciled")
let before = book.entries.count
book.unreconcile(stripe.id)
check(book.entries.count == before - 1 && book.unreconciled.count == 1, "Undoing a reconciliation takes its entry back out")
try? book.code(stripe.id, account: "200", gst: .free)
check(book.entries.allSatisfy(\.isBalanced), "Every entry balances")

// MARK: Bills and the BAS

var bill = Invoice(kind: .bill, number: "KDS-1", contact: supplier.id, issued: date(2026, 10, 2), due: date(2026, 11, 1),
                   lines: [InvoiceLine(description: "Illustration", unitPrice: 50_000, account: "410", gst: .gst)])
book.invoices.append(bill)
try? book.approve(bill.id)
bill = book.invoice(bill.id)!
check(bill.status == .approved && book.balances(to: date(2026, 12, 31))["800"] == -55_000, "A bill goes to accounts payable")

let q1 = book.bas(from: date(2026, 7, 1), to: date(2026, 9, 30))
// Sales: the invoice $1,100 (GST $100). Purchases: AWS $110 (GST $10), desk $1,320 capital (GST $120).
check(q1.totalSales == 110_000 && q1.gstOnSales == 10_000 && q1.otherPurchases == 11_000 && q1.capitalPurchases == 132_000
      && q1.gstOnPurchases == 13_000 && q1.net == -3_000, "BAS, July to September, accrual: G1, 1A, G10, G11, 1B (\(q1))")
let q2 = book.bas(from: date(2026, 10, 1), to: date(2026, 12, 31))
// Sales: Stripe $550 GST-free. Purchases: AWS $121 (GST $11), the bill $550 (GST $50).
check(q2.totalSales == 55_000 && q2.gstFreeSales == 55_000 && q2.gstOnSales == 0 && q2.otherPurchases == 12_100 + 55_000
      && q2.gstOnPurchases == 1_100 + 5_000, "BAS, October to December: GST-free sales and a bill (\(q2))")

var cash = book
cash.settings.cashBasis = true
let cashQ2 = cash.bas(from: date(2026, 10, 1), to: date(2026, 12, 31))
check(cashQ2.gstOnPurchases == 1_100, "Cash basis: an unpaid bill's GST waits until it's paid (\(cashQ2.gstOnPurchases))")
let cashQ1 = cash.bas(from: date(2026, 7, 1), to: date(2026, 9, 30))
check(cashQ1.gstOnSales == 10_000 && cashQ1.totalSales == 110_000, "Cash basis: the invoice counts as its payments arrive (\(cashQ1.gstOnSales))")
var partial = cash
let partialInvoice = Invoice(kind: .sale, number: "INV-9", contact: client.id, issued: date(2026, 10, 3), due: date(2026, 10, 17),
                             lines: [InvoiceLine(description: "Design", unitPrice: 200_000, account: "200", gst: .gst)])
partial.invoices.append(partialInvoice)
try? partial.approve(partialInvoice.id)
try? partial.recordPayment(partialInvoice.id, amount: 110_000, date: date(2026, 10, 20), bankAccount: "090")
check(partial.bas(from: date(2026, 10, 1), to: date(2026, 12, 31)).gstOnSales == 10_000, "Cash basis: half paid, half the GST")

// MARK: Reports

let year = book.profitAndLoss(from: date(2026, 7, 1), to: date(2027, 6, 30))
check(year.totalIncome == 100_000 + 55_000 && year.totalExpenses == 10_000 + 11_000 + 50_000 && year.net == 155_000 - 71_000,
      "Profit and loss (\(LedgerMoney.text(year.net)))")
let sheet = book.balanceSheet(asOf: date(2026, 12, 31))
check(sheet.balances, "The balance sheet balances (\(LedgerMoney.text(sheet.totalAssets)) = \(LedgerMoney.text(sheet.totalLiabilities)) + \(LedgerMoney.text(sheet.totalEquity)))")
let trial = book.trialBalance(asOf: date(2026, 12, 31))
check(trial.reduce(0) { $0 + $1.debit } == trial.reduce(0) { $0 + $1.credit }, "The trial balance's debits equal its credits")
let cashRows = book.cashSummary(from: date(2026, 10, 1), to: date(2026, 10, 31))
let business = cashRows.first { $0.account.code == "090" }!
check(business.moneyIn == 55_000 && business.moneyOut == 12_100 + 200_000, "Cash summary for October")
check(book.financialYearStart(for: date(2026, 11, 1)) == calendar.startOfDay(for: date(2026, 7, 1))
      && book.financialYearStart(for: date(2026, 3, 1)) == calendar.startOfDay(for: date(2025, 7, 1)), "Financial years start on 1 July")
let quarter = book.quarter(containing: date(2026, 11, 1))
check(calendar.component(.month, from: quarter.start) == 10 && calendar.component(.month, from: quarter.end) == 12
      && calendar.component(.day, from: quarter.end) == 31, "Quarters")

var aging = book
let late = Invoice(kind: .sale, number: "INV-7", contact: client.id, issued: date(2026, 8, 1), due: date(2026, 8, 15),
                   lines: [InvoiceLine(description: "Old work", unitPrice: 10_000, account: "200", gst: .gst)])
aging.invoices.append(late)
try? aging.approve(late.id)
let aged = aging.aged(.sale, asOf: date(2026, 10, 1))
check(aged.first?.buckets == [0, 0, 11_000, 0, 0], "Aged receivables: 47 days late is in 31–60 (\(aged.first?.buckets ?? []))")
let payables = aging.aged(.bill, asOf: date(2026, 10, 10))
check(payables.first?.buckets.first == 55_000, "Aged payables: not yet due is current")
aging.void(late.id)
check(aging.invoice(late.id)?.status == .void && aging.aged(.sale, asOf: date(2026, 10, 1)).isEmpty, "Voiding takes it out of the books")

// MARK: Statements

let ofx = """
OFXHEADER:100
<OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><BANKTRANLIST>
<STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20261003120000[+10:AEST]<TRNAMT>-45.50<FITID>9001<NAME>UBER *TRIP<MEMO>HELP.UBER.COM</STMTTRN>
<STMTTRN><TRNTYPE>CREDIT<DTPOSTED>20261004<TRNAMT>1100.00<FITID>9002<NAME>ACME PTY LTD &amp; CO</STMTTRN>
</BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>
"""
let ofxLines = StatementParser.parse(ofx, fileExtension: "ofx", account: "090")
check(ofxLines.count == 2 && ofxLines[0].amount == -4_550 && ofxLines[0].bankID == "9001" && ofxLines[1].description == "ACME PTY LTD & CO"
      && calendar.component(.day, from: ofxLines[0].date) == 3, "OFX statements")

let qif = """
!Type:Bank
D15/10/2026
T-120.00
PQANTAS AIRWAYS
^
D16/10'26
T2,500.00
PNORTHWIND TRADERS
^
"""
let qifLines = StatementParser.parse(qif, fileExtension: "qif", account: "090")
check(qifLines.count == 2 && qifLines[0].amount == -12_000 && qifLines[1].amount == 250_000 && calendar.component(.day, from: qifLines[1].date) == 16
      && calendar.component(.year, from: qifLines[1].date) == 2026,
      "QIF statements")

let headed = """
Date,Description,Debit,Credit,Balance
01/10/2026,"GOOGLE*WORKSPACE, SYDNEY",33.00,,1000.00
02/10/2026,NORTHWIND TRADERS,,"6,820.00",7787.00
"""
let headedLines = StatementParser.parse(headed, fileExtension: "csv", account: "090")
check(headedLines.count == 2 && headedLines[0].amount == -3_300 && headedLines[0].description == "GOOGLE*WORKSPACE, SYDNEY"
      && headedLines[1].amount == 682_000, "CSV with debit and credit columns")
let commbank = """
03/10/2026,"-45.00","UBER *TRIP","+1234.56"
04/10/2026,"+1100.00","ACME PTY LTD","+2334.56"
"""
let bare = StatementParser.parse(commbank, fileExtension: "csv", account: "090")
check(bare.count == 2 && bare[0].amount == -4_500 && bare[0].description == "UBER *TRIP" && bare[1].amount == 110_000,
      "CSV without headers (CommBank)")

// MARK: Documents

var settings = LedgerSettings()
settings.businessName = "Northside Studio"
settings.abn = "51 824 753 556"
settings.bsb = "063-000"
settings.accountNumber = "1234 5678"
let markdown = InvoiceDocument.markdown(book.invoice(invoice.id)!, contact: client, settings: settings)
check(markdown.contains("# Tax invoice INV-0001") && markdown.contains("ABN 51 824 753 556") && markdown.contains("**Total:** $1,100.00")
      && markdown.contains("BSB 063-000") && markdown.contains("| Workshop | 1 | $1,000.00 | $100.00 | $1,000.00 |"), "Tax invoice")

let pack = LedgerExport.workbook(book, from: date(2026, 7, 1), to: date(2026, 12, 31))
check(pack.sheets.map(\.name) == ["Profit and loss", "Balance sheet", "Trial balance", "General ledger", "GST", "Aged receivables",
                                  "Aged payables", "Invoices and bills"], "Accountant's pack sheets")
let packEngine = GridEngine(pack)
let netRow = pack.sheets[0].cells.first { $0.value.input == "Net profit" }?.key
let netValue = netRow.map { packEngine.value(sheet: 0, CellAddress(row: $0.row, column: 1)) }
let expectedNet = book.profitAndLoss(from: date(2026, 7, 1), to: date(2026, 12, 31)).net
check(netValue.flatMap(\.number).map { abs($0 - LedgerMoney.dollars(expectedNet)) < 0.005 } == true,
      "The pack's net profit formula matches the report (\(String(describing: netValue)))")
let checkRow = pack.sheets[1].cells.first { $0.value.input == "Check (should be zero)" }?.key
let checkValue = checkRow.map { packEngine.value(sheet: 1, CellAddress(row: $0.row, column: 1)) }
check(checkValue.flatMap(\.number).map { abs($0) < 0.005 } == true, "The pack's balance sheet check is zero (\(String(describing: checkValue)))")
let trialSheet = pack.sheets[2]
let trialTotal = trialSheet.cells.first { $0.value.input == "Total" }?.key
let debits = trialTotal.map { packEngine.value(sheet: 2, CellAddress(row: $0.row, column: 3)) }
let credits = trialTotal.map { packEngine.value(sheet: 2, CellAddress(row: $0.row, column: 4)) }
check(debits.flatMap(\.number).map { debit in credits.flatMap(\.number).map { abs(debit - $0) < 0.005 } ?? false } == true,
      "The pack's trial balance totals agree")
check(GridXLSX.data(pack).count > 2_000, "The pack saves as Excel")

// MARK: The sample books

let sample = LedgerSamples.book(now: date(2026, 11, 1))
check(sample.entries.allSatisfy(\.isBalanced) && sample.balanceSheet(asOf: date(2026, 11, 1)).balances, "Sample books balance")
check(sample.unreconciled.count == 4, "Sample books leave four lines to reconcile (\(sample.unreconciled.count))")
let kestrel = sample.unreconciled.first { $0.description.hasPrefix("KESTREL") }
let kestrelInvoice = sample.invoices.first { $0.number == "INV-0005" }
check(kestrel.map { sample.suggestion(for: $0) } == kestrelInvoice.map { BankSuggestion.invoice($0.id) }, "…the Kestrel payment matches INV-0005")
let awsSample = sample.unreconciled.first { $0.description.hasPrefix("AWS") }
check(awsSample.map { sample.suggestion(for: $0) } == .rule(account: "485", gst: .gst, times: 3), "…and AWS is coded like the last three")
check(sample.overdue(.sale, on: date(2026, 11, 1)).count == 2 && sample.invoices.contains { $0.status == .draft },
      "…with overdue invoices and a draft (\(sample.overdue(.sale, on: date(2026, 11, 1)).map(\.number)))")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
