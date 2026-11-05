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
try? book.unreconcile(stripe.id)
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
try? aging.void(late.id)
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

// MARK: Quotes

var quoting = LedgerBook()
quoting.settings.businessName = "Northside Studio"
let tom = Contact(name: "Northwind Traders", email: "tom@northwind.example")
quoting.contacts = [tom]
let websiteQuote = quoting.saveQuote(Quote(number: "", contact: tom.id, title: "Website", issued: date(2026, 10, 1), expires: date(2026, 10, 31), lines: [
    InvoiceLine(description: "Design", unitPrice: 750_000, account: "200", gst: .gst),
    InvoiceLine(description: "Migration", quantity: 8, unitPrice: 15_001, account: "200", gst: .gst),
]))
check(quoting.quote(websiteQuote)?.number == "QU-0001" && quoting.quote(websiteQuote)?.subtotal == 870_008, "Quotes are numbered and add up")
quoting.setQuote(websiteQuote, status: .sent)
check(quoting.quote(websiteQuote)?.sentAt != nil && quoting.quote(websiteQuote)?.isExpired(on: date(2026, 11, 2), calendar: calendar) == true
      && quoting.quote(websiteQuote)?.statusText(on: date(2026, 11, 2), calendar: calendar) == "Expired"
      && quoting.openQuotes(on: date(2026, 10, 20)).count == 1, "A sent quote lapses after its date")
quoting.setQuote(websiteQuote, status: .accepted)
let deposit = try? quoting.invoice(fromQuote: websiteQuote, part: 0.3, issued: date(2026, 10, 10))
let depositInvoice = deposit.flatMap { quoting.invoice($0) }
check(depositInvoice?.lines.map(\.net) == [225_000, 36_002] && depositInvoice?.number == "INV-0001" && depositInvoice?.status == .draft
      && depositInvoice?.reference == "QU-0001 · Website" && depositInvoice?.lines.first?.description == "Design (30% of QU-0001)",
      "A 30% deposit invoice from the quote (\(depositInvoice?.lines.map(\.net) ?? []))")
check(quoting.quote(websiteQuote)?.status == .accepted && quoting.quote(websiteQuote)?.statusText(on: date(2026, 10, 10), calendar: calendar) == "30% invoiced",
      "…and the quote shows how much is invoiced")
let balance = try? quoting.invoice(fromQuote: websiteQuote, issued: date(2026, 10, 30), approve: true)
let balanceInvoice = balance.flatMap { quoting.invoice($0) }
check(balanceInvoice?.lines.map(\.net) == [525_000, 84_006] && balanceInvoice?.status == .approved
      && (depositInvoice?.subtotal ?? 0) + (balanceInvoice?.subtotal ?? 0) == 870_008, "The balance makes it up to the cent, approved")
check(quoting.quote(websiteQuote)?.status == .invoiced && quoting.quote(websiteQuote)?.invoices.count == 2, "The quote is invoiced in full")
var tooMuch: LedgerError?
do { _ = try quoting.invoice(fromQuote: websiteQuote, issued: date(2026, 11, 1)) } catch { tooMuch = error as? LedgerError }
check(tooMuch == .alreadyInvoiced, "Not invoiced twice")
let wholeQuote = quoting.saveQuote(Quote(number: "", contact: tom.id, issued: date(2026, 10, 2), expires: date(2026, 11, 1), lines: [
    InvoiceLine(description: "Shoot", quantity: 2, unitPrice: 240_000, account: "200", gst: .gst),
]))
let whole = (try? quoting.invoice(fromQuote: wholeQuote, issued: date(2026, 10, 3))).flatMap { quoting.invoice($0) }
check(whole?.lines.first?.quantity == 2 && whole?.lines.first?.description == "Shoot" && whole?.total == 528_000, "A whole quote keeps its lines as they are")
let declinedQuote = quoting.saveQuote(Quote(number: "", contact: tom.id, issued: date(2026, 10, 2), expires: date(2026, 11, 1), lines: [
    InvoiceLine(description: "Extra", unitPrice: 10_000, account: "200", gst: .gst),
]))
quoting.setQuote(declinedQuote, status: .declined)
check((try? quoting.invoice(fromQuote: declinedQuote, issued: date(2026, 10, 3))) == nil && quoting.quote(declinedQuote)?.number == "QU-0003",
      "A declined quote can't be invoiced")
quoting.deleteQuote(websiteQuote)
quoting.deleteQuote(declinedQuote)
check(quoting.quote(websiteQuote) != nil && quoting.quote(declinedQuote) == nil, "Only quotes never invoiced can be deleted")
let quoteText = QuoteDocument.markdown(quoting.quote(wholeQuote)!, contact: tom, settings: quoting.settings)
check(quoteText.hasPrefix("# Quote QU-0002") && quoteText.contains("**Valid until:** 1 November 2026") && quoteText.contains("**Total:** $5,280.00"),
      "The quote as a document")

// MARK: Repeating invoices

var repeats = LedgerBook()
repeats.contacts = [tom]
let endOfMonth = RepeatingInvoice(contact: tom.id, lines: [InvoiceLine(description: "Retainer, [Month] [year]", unitPrice: 300_000, account: "200", gst: .gst)],
                                  start: date(2026, 1, 31))
check(calendar.component(.day, from: endOfMonth.occurrence(1, calendar: calendar)) == 28
      && calendar.component(.day, from: endOfMonth.occurrence(2, calendar: calendar)) == 31, "Monthly from the 31st: 28 February, then 31 March")
repeats.saveSchedule(endOfMonth)
let made = repeats.makeRepeatingInvoices(upTo: date(2026, 4, 15))
let madeInvoices = made.compactMap { repeats.invoice($0) }
check(madeInvoices.map(\.number) == ["INV-0001", "INV-0002", "INV-0003"] && madeInvoices.allSatisfy { $0.status == .approved }
      && madeInvoices.last?.lines.first?.description == "Retainer, March 2026", "Catches up on three months, approved (\(madeInvoices.map { $0.lines.first?.description ?? "" }))")
check(repeats.makeRepeatingInvoices(upTo: date(2026, 4, 15)).isEmpty && repeats.schedule(endOfMonth.id)?.made == 3, "Not made twice")
check(madeInvoices.first.map { calendar.dateComponents([.day], from: $0.issued, to: $0.due).day } == 14, "Due 14 days after")
check(repeats.audit.contains { $0.by == "George" && $0.action == "Made repeating invoice INV-0001" } && repeats.actor == "You", "George makes them, in the trail")
var ending = endOfMonth
ending.end = date(2026, 3, 1)
ending.made = 2
check(ending.next(calendar: calendar) == nil, "A schedule ends")
var paused = endOfMonth
paused.id = UUID()
paused.made = 3
paused.paused = true
repeats.saveSchedule(paused)
check(repeats.makeRepeatingInvoices(upTo: date(2026, 5, 15)).count == 1, "A paused one waits (only the first schedule's April invoice)")
check(RepeatingInvoice(contact: tom.id, lines: [], every: 3, start: date(2026, 1, 1)).summary == "Every 3 months"
      && RepeatingInvoice(contact: tom.id, lines: [], unit: .week, start: date(2026, 1, 1)).summary == "Every week", "Schedules in words")
var lockedRepeats = LedgerBook()
lockedRepeats.contacts = [tom]
lockedRepeats.saveSchedule(RepeatingInvoice(contact: tom.id, lines: [InvoiceLine(description: "Care plan", unitPrice: 45_000, account: "200", gst: .gst)],
                                            start: date(2026, 3, 15)))
lockedRepeats.setLockDate(date(2026, 3, 31))
let lockedMade = lockedRepeats.makeRepeatingInvoices(upTo: date(2026, 4, 20)).compactMap { lockedRepeats.invoice($0) }
check(lockedMade.map(\.status) == [.draft, .approved], "One dated in a locked period is left as a draft")
let repeated = repeats.repeatInvoice(madeInvoices[0].id, every: 1, unit: .month).flatMap { repeats.schedule($0) }
check(repeated?.made == 1 && repeated.flatMap { $0.next(calendar: calendar) }.map { calendar.component(.month, from: $0) } == 2,
      "Repeat an invoice: the next is a month on")
check(repeats.upcomingRepeats(from: date(2026, 4, 20), days: 20).count == 1, "What's coming up")

// MARK: Overdue reminders

var chasing = LedgerBook()
chasing.settings.businessName = "Northside Studio"
chasing.settings.bsb = "063-000"
chasing.settings.accountNumber = "1234 5678"
chasing.settings.accountName = "Northside Studio Pty Ltd"
chasing.contacts = [tom]
let owed = Invoice(kind: .sale, number: chasing.takeInvoiceNumber(), contact: tom.id, issued: date(2026, 9, 17), due: date(2026, 10, 1),
                   lines: [InvoiceLine(description: "Campaign", unitPrice: 180_000, account: "200", gst: .gst)])
chasing.invoices.append(owed)
try? chasing.approve(owed.id)
check(chasing.remindersDue(on: date(2026, 10, 2)).isEmpty, "Not the day after")
let friendly = chasing.remindersDue(on: date(2026, 10, 4))
check(friendly.count == 1 && friendly.first?.tone == .friendly && friendly.first?.daysLate == 3, "Three days late: a friendly reminder")
let friendlyMail = friendly.first.map { chasing.reminderDraft($0) }
check(friendlyMail?.to == "tom@northwind.example" && friendlyMail?.subject == "Reminder: invoice INV-0001 from Northside Studio"
      && friendlyMail?.body.hasPrefix("Hi Tom,\n\nA friendly reminder that invoice INV-0001 for $1,980.00 was due on 1 October.") == true
      && friendlyMail?.body.contains("BSB 063-000, account 1234 5678, with INV-0001 as the reference") == true
      && friendlyMail?.body.hasSuffix("Thanks,\nNorthside Studio") == true, "Marc's draft: \(friendlyMail?.body ?? "")")
chasing.clock = date(2026, 10, 4)
chasing.noteReminder(owed.id, stage: 0)
check(chasing.remindersDue(on: date(2026, 10, 9)).isEmpty, "Not twice at the same stage")
let firm = chasing.remindersDue(on: date(2026, 10, 15))
check(firm.first?.tone == .firm && firm.first.map { chasing.reminderDraft($0).subject } == "Invoice INV-0001 is 14 days overdue"
      && firm.first?.lastSent == date(2026, 10, 4), "Two weeks late: firmer")
chasing.clock = date(2026, 10, 28)
chasing.noteReminder(owed.id, stage: 1)
check(chasing.remindersDue(on: date(2026, 10, 31)).isEmpty, "At least five days between reminders")
let last = chasing.remindersDue(on: date(2026, 11, 2))
check(last.first?.tone == .final && last.first.map { chasing.reminderDraft($0).subject } == "Final reminder: invoice INV-0001, 32 days overdue"
      && last.first.map { chasing.reminderDraft($0).body.contains("Kind regards,") } == true, "A month late: the final reminder")
try? chasing.recordPayment(owed.id, amount: 98_000, date: date(2026, 11, 1), bankAccount: "090")
check(last.first.map { chasing.reminderDraft($0).body.contains("Final reminder") == false && chasing.reminderDraft($0).body.contains("The remaining $1,000.00 on invoice INV-0001 is now 32 days overdue") } == true,
      "Part paid: it asks for the rest")
chasing.clock = date(2026, 11, 2)
chasing.noteReminder(owed.id, stage: 2, skipped: true)
check(chasing.remindersDue(on: date(2026, 11, 20)).isEmpty && chasing.remindersSent(for: owed.id).count == 2
      && chasing.audit.last?.action == "Skipped a reminder for INV-0001" && chasing.audit.last?.by == "You", "Skipping one counts as dealt with")
let veryLate = Invoice(kind: .sale, number: chasing.takeInvoiceNumber(), contact: tom.id, issued: date(2026, 8, 1), due: date(2026, 8, 15),
                       lines: [InvoiceLine(description: "Old", unitPrice: 50_000, account: "200", gst: .gst)])
chasing.invoices.append(veryLate)
try? chasing.approve(veryLate.id)
check(chasing.remindersDue(on: date(2026, 10, 1)).first { $0.invoice == veryLate.id }?.tone == .final, "Never chased and very late: straight to the final one")
chasing.bank.append(BankLine(account: "090", date: date(2026, 9, 30), description: "NORTHWIND TRADERS", amount: 55_000))
check(!chasing.remindersDue(on: date(2026, 10, 1)).contains { $0.invoice == veryLate.id }
      && chasing.latePaymentsWaiting(on: date(2026, 10, 1)).first?.invoice.id == veryLate.id, "Not when the payment looks like it's in the bank")
check(ReminderText.greeting(name: "Acme Pty Ltd", email: "accounts@acme.example") == "Hi there,"
      && ReminderText.greeting(name: "Priya Shah", email: "accounts@northwind.vc") == "Hi Priya,"
      && ReminderText.greeting(name: "Kestrel Studio", email: "hello@kestrel.example") == "Hi there,"
      && ReminderText.greeting(name: "", email: "tom.baker@acme.co") == "Hi Tom,", "Greetings by name, not to the accounts inbox")
check(chasing.invoiceMentioned(inSubject: "Re: Final reminder: invoice INV-0002, 47 days overdue") == veryLate.id
      && chasing.invoiceMentioned(inSubject: "About INV-00021") == nil && chasing.invoiceMentioned(inSubject: "Hello") == nil,
      "Which invoice an email is about")
var oneStage = LedgerBook()
oneStage.contacts = [tom]
oneStage.settings.reminderDays = [7]
oneStage.invoices.append(owed)
oneStage.invoices[0].status = .draft
try? oneStage.approve(owed.id)
check(oneStage.remindersDue(on: date(2026, 11, 1)).first?.tone == .friendly, "One reminder day: one friendly reminder")

// MARK: Lock date and audit trail

var locking = LedgerBook()
locking.contacts = [tom]
let septemberWork = Invoice(kind: .sale, number: "INV-1", contact: tom.id, issued: date(2026, 9, 10), due: date(2026, 9, 24),
                            lines: [InvoiceLine(description: "September", unitPrice: 10_000, account: "200", gst: .gst)])
let lateDraft = Invoice(kind: .sale, number: "INV-2", contact: tom.id, issued: date(2026, 9, 20), due: date(2026, 10, 4),
                        lines: [InvoiceLine(description: "Forgotten", unitPrice: 10_000, account: "200", gst: .gst)])
locking.invoices = [septemberWork, lateDraft]
try? locking.approve(septemberWork.id)
locking.importStatement([BankLine(account: "090", date: date(2026, 9, 12), description: "GOOGLE*WORKSPACE", amount: -3_300)])
let googleLine = locking.bank[0].id
try? locking.code(googleLine, account: "485", gst: .gst)
locking.setLockDate(date(2026, 9, 30))
check(locking.isLocked(date(2026, 9, 30)) && !locking.isLocked(date(2026, 10, 1)), "Locked up to and including the lock date")
var lockError: LedgerError?
do {
    try locking.post(JournalEntry(date: date(2026, 9, 15), memo: "Late", source: .manual, lines: [
        JournalLine(account: "090", amount: 100), JournalLine(account: "880", amount: -100)]))
} catch { lockError = error as? LedgerError }
check(lockError == .locked(locking.settings.lockDate!) && lockError?.errorDescription?.contains("locked up to 30 September 2026") == true,
      "Nothing new before the lock date: \(lockError?.errorDescription ?? "")")
check((try? locking.post(JournalEntry(date: date(2026, 10, 1), memo: "Fine", source: .manual, lines: [
    JournalLine(account: "090", amount: 100), JournalLine(account: "880", amount: -100)]))) != nil, "After it is fine")
check((try? locking.approve(lateDraft.id)) == nil && locking.invoice(lateDraft.id)?.status == .draft, "A draft dated in a locked period can't be approved")
check((try? locking.void(septemberWork.id)) == nil && locking.invoice(septemberWork.id)?.status == .approved, "Nor voided")
check((try? locking.unreconcile(googleLine)) == nil && locking.bank[0].isReconciled, "Nor unreconciled")
locking.setLockDate(nil)
check((try? locking.void(septemberWork.id)) != nil && locking.invoice(septemberWork.id)?.status == .void, "Unlocked, it can be")
let trail = locking.auditTrail()
check(trail.first?.action == "Voided invoice INV-1" && trail.contains { $0.action == "Locked the books" && $0.detail == "Up to 30 September 2026" }
      && trail.contains { $0.action == "Unlocked the books" } && trail.contains { $0.action == "Coded a bank line to \(locking.account("485")?.name ?? "")" }
      && trail.contains { $0.action == "Imported a bank statement" && $0.detail == "1 new line" },
      "The audit trail, newest first: \(trail.map(\.action))")
check(locking.auditTrail(matching: "invoice inv-1").map(\.action) == ["Voided invoice INV-1", "Approved invoice INV-1"], "Searching the trail")
locking.clock = date(2026, 1, 1)
locking.actor = "Marc"
locking.log("Something")
check(locking.audit.last?.date == date(2026, 1, 1) && locking.audit.last?.by == "Marc", "Stamped with who and when")

// MARK: Saved books

var saved = quoting
saved.actor = "George"
saved.clock = date(2026, 1, 1)
saved.saveSchedule(endOfMonth)
let savedData = try! JSONEncoder().encode(saved)
let reopened = try? JSONDecoder().decode(LedgerBook.self, from: savedData)
check(reopened?.quotes.count == saved.quotes.count && reopened?.repeating.count == 1 && reopened?.audit.count == saved.audit.count
      && reopened?.actor == "You" && reopened?.clock == nil, "Quotes, schedules and the trail are saved; who and when aren't")
var older = try! JSONSerialization.jsonObject(with: savedData) as! [String: Any]
for key in ["quotes", "repeating", "reminders", "audit"] { older.removeValue(forKey: key) }
var oldSettings = older["settings"] as! [String: Any]
for key in ["quotePrefix", "nextQuote", "quoteDays", "lockDate", "reminderDays"] { oldSettings.removeValue(forKey: key) }
older["settings"] = oldSettings
let olderBook = try? JSONDecoder().decode(LedgerBook.self, from: JSONSerialization.data(withJSONObject: older))
check(olderBook?.invoices.count == saved.invoices.count && olderBook?.quotes.isEmpty == true && olderBook?.settings.quotePrefix == "QU-"
      && olderBook?.settings.reminderDays == [3, 14, 30] && olderBook?.settings.businessName == "Northside Studio", "Books saved by an older version still open")

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
check(sample.quotes.count == 4 && sample.quotes.filter { $0.isExpired(on: date(2026, 11, 1), calendar: calendar) }.count == 1
      && sample.quotes.contains { $0.parts == [0.5] } && sample.openQuotes(on: date(2026, 11, 1)).count == 1, "…quotes in every state")
let sampleReminders = sample.remindersDue(on: date(2026, 11, 1))
check(sampleReminders.map(\.number) == ["INV-0004"] && sampleReminders.first?.tone == .final
      && sample.latePaymentsWaiting(on: date(2026, 11, 1)).map(\.invoice.number) == ["INV-0005"],
      "…Marc's final reminder for Acme, and Kestrel's payment waiting in the bank (\(sampleReminders.map(\.number)))")
var sampleRepeats = sample
check(sampleRepeats.makeRepeatingInvoices(upTo: date(2026, 11, 1)).isEmpty, "…no repeating invoice due yet")
let novemberRepeats = sampleRepeats.makeRepeatingInvoices(upTo: date(2026, 11, 30)).compactMap { sampleRepeats.invoice($0) }
check(novemberRepeats.compactMap { $0.lines.first?.description }.sorted() == ["Monthly retainer, November", "Website care plan, quarter from November"],
      "…two repeating invoices in November (\(novemberRepeats.compactMap { $0.lines.first?.description }))")
check(sample.isLocked(date(2026, 9, 30)) && !sample.isLocked(date(2026, 10, 1)) && sample.audit.count > 30
      && sample.audit.allSatisfy { $0.date <= date(2026, 11, 1) } && sample.auditTrail().first.map { $0.date > date(2026, 10, 25) } == true,
      "…locked to last quarter, with a backdated trail (\(sample.audit.count) changes)")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
