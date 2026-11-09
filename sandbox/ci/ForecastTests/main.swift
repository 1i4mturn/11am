import Foundation

// Checks George's forecast (cash now, usual money in and out, what's known, runway), "what if" changes from a
// sentence, explaining a report line, the move from Xero's exports, and the pay-online link. Run in Sydney time.

var failures = 0
func check(_ condition: Bool, _ name: String) {
    print(condition ? "PASS" : "FAIL", name)
    if !condition { failures += 1 }
}
func same<T: Equatable>(_ actual: T, _ expected: T, _ name: String) {
    if actual == expected {
        print("PASS", name)
    } else {
        print("FAIL", name, "· expected", expected, "· got", actual)
        failures += 1
    }
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = .current
func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
}
func monthOf(_ value: Date?) -> String {
    guard let value else { return "none" }
    let parts = calendar.dateComponents([.year, .month], from: value)
    return "\(parts.year ?? 0)-\(parts.month ?? 0)"
}
let today = date(2026, 11, 9)

// MARK: Six months of books

var book = LedgerBook()
let acme = Contact(name: "Acme Pty Ltd", email: "accounts@acme.example")
let landlord = Contact(name: "Harbour Property")
book.contacts = [acme, landlord]
_ = try? book.post(JournalEntry(date: date(2026, 5, 1), memo: "Opening balance", source: .opening, lines: [
    JournalLine(account: "090", amount: 2_000_000), JournalLine(account: "880", amount: -2_000_000),
]))
var acmeLines: [(line: UUID, invoice: UUID)] = []
var statement: [BankLine] = []
for month in 5...10 {
    let invoice = Invoice(kind: .sale, number: book.takeInvoiceNumber(), contact: acme.id, issued: date(2026, month, 1), due: date(2026, month, 15),
                          lines: [InvoiceLine(description: "Retainer", unitPrice: 500_000, account: "200", gst: .gst)])
    book.invoices.append(invoice)
    try? book.approve(invoice.id)
    let payment = BankLine(account: "090", date: date(2026, month, 10), description: "ACME PTY LTD \(invoice.number)", amount: 550_000, bankID: "P\(month)")
    acmeLines.append((payment.id, invoice.id))
    statement.append(payment)
    statement.append(BankLine(account: "090", date: date(2026, month, 12), description: "AWS EMEA \(month)00 aws.amazon.com",
                              amount: month <= 7 ? -110_000 : -165_000, bankID: "W\(month)"))
    statement.append(BankLine(account: "090", date: date(2026, month, 1), description: "HARBOUR PROPERTY RENT", amount: -220_000, bankID: "R\(month)"))
}
book.importStatement(statement)
for pair in acmeLines { _ = try? book.match(pair.line, invoice: pair.invoice) }
for line in book.bank where !line.isReconciled {
    _ = try? book.code(line.id, account: line.description.hasPrefix("AWS") ? "485" : "469", gst: .gst)
}
check(book.bank.allSatisfy(\.isReconciled), "books: every statement line reconciled")

// Known for the months ahead: November's invoice and the December rent bill.
let november = Invoice(kind: .sale, number: book.takeInvoiceNumber(), contact: acme.id, issued: date(2026, 11, 1), due: date(2026, 11, 20),
                       lines: [InvoiceLine(description: "Retainer", unitPrice: 500_000, account: "200", gst: .gst)])
book.invoices.append(november)
try? book.approve(november.id)
let rent = Invoice(kind: .bill, number: "RENT-12", contact: landlord.id, issued: date(2026, 11, 5), due: date(2026, 12, 1),
                   lines: [InvoiceLine(description: "December rent", unitPrice: 200_000, account: "469", gst: .gst)])
book.invoices.append(rent)
try? book.approve(rent.id)

// MARK: The forecast

same(book.cashNow(today), 3_155_000, "cash now: opening $20,000, six months of $5,500 in and rent and AWS out")
let plain = book.forecast(from: today, months: 12)
same(plain.history, 6, "usual: six full months of history")
same(plain.usualIn, 550_000, "usual: $5,500 a month in")
same(plain.usualOut, 357_500, "usual: $3,575 a month out")
same(plain.months.count, 12, "twelve months ahead")
same(monthOf(plain.months.first?.start), "2026-11", "starting this month")
let nov = plain.months[0]
check(nov.items.contains { $0.kind == .invoice && $0.amount == 550_000 && $0.description.hasPrefix("INV-0007") }, "November: the invoice due on the 20th")
check(!nov.items.contains { $0.kind == .usualIn }, "November: the invoice covers the usual money in")
same(nov.items.first { $0.kind == .usualOut }?.amount, -262_167, "November: usual spending for the 22 days left")
same(nov.closing, 3_442_833, "November closes")
let dec = plain.months[1]
same(dec.items.first { $0.kind == .bill }?.amount, -220_000, "December: the rent bill")
same(dec.items.first { $0.kind == .usualOut }?.amount, -137_500, "December: usual spending less the bill already counted")
same(dec.items.first { $0.kind == .usualIn }?.amount, 550_000, "December: usual money in")
same(dec.closing, 3_635_333, "December closes")
same(plain.months[2].closing, 3_827_833, "January closes")
check(plain.runsOut == nil, "as things are, the cash lasts")

let hire = WhatIf(kind: .cost, name: "Hire", amount: 1_120_000, from: date(2026, 12, 1))
let hiring = book.forecast(from: today, months: 12, whatIfs: [hire])
same(hiring.months[1].closing, 2_515_333, "hiring from December: $11,200 a month out")
same(monthOf(hiring.runsOut), "2027-3", "hiring: the cash runs out in March")
same(monthOf(hiring.lowest?.start), "2027-10", "hiring: the lowest month is the last")
var paused = hire
paused.on = false
same(book.forecast(from: today, months: 12, whatIfs: [paused]).closing, plain.closing, "a change switched off changes nothing")

let loseAcme = WhatIf(kind: .loseClient, name: "Lose Acme", from: date(2026, 12, 1), contact: acme.id)
let losing = book.forecast(from: today, months: 3, whatIfs: [loseAcme])
same(losing.months[0].closing, nov.closing, "losing Acme from December: November unchanged")
same(losing.months[1].items.first { $0.kind == .whatIf }?.amount, -550_000, "losing Acme: their usual $5,500 a month stops from December")
same(losing.months[1].closing, 3_085_333, "losing Acme: December closes $5,500 lower")
let dearerPrices = WhatIf(kind: .prices, name: "Prices up", percent: 10, from: date(2027, 1, 1))
let dearer = book.forecast(from: today, months: 3, whatIfs: [dearerPrices])
same(dearer.months[2].items.first { $0.kind == .whatIf }?.amount, 55_000, "prices up 10% from January: $550 more that month")
same(dearer.months[1].items.contains { $0.kind == .whatIf }, false, "…and nothing before")
let laptop = WhatIf(kind: .oneOff, name: "Laptop", amount: -300_000, from: date(2027, 2, 15))
same(book.forecast(from: today, months: 6, whatIfs: [laptop]).months[3].items.first { $0.kind == .whatIf }?.amount, -300_000, "a one-off in its month")

// A repeating invoice adds what it will make.
var schedule = RepeatingInvoice(contact: acme.id, lines: [InvoiceLine(description: "Support", unitPrice: 100_000, account: "200", gst: .gst)], start: date(2026, 12, 5))
schedule.dueDays = 7
book.repeating.append(schedule)
let withRepeats = book.forecast(from: today, months: 3)
same(withRepeats.months[1].items.filter { $0.kind == .repeating }.count, 1, "repeating: December's support invoice, paid on the 12th")
same(withRepeats.months[1].items.first { $0.kind == .usualIn }?.amount, 440_000, "repeating: counts towards the usual money in")
book.repeating = []

// MARK: What if, from a sentence

func parse(_ text: String) -> WhatIf? { WhatIfParser.parse(text, today: today, contacts: book.contacts, calendar: calendar) }
let developer = parse("hire a developer at $10k a month from March")
check(developer?.kind == .cost && developer?.amount == 1_120_000 && monthOf(developer?.from) == "2027-3", "sentence: hire at $10k a month, plus super, from next March")
same(developer?.name ?? "", "Hire at $10,000 a month from March 2027 (+ $1,200 super)", "sentence: the hire's name")
let weekly = parse("Hire someone at $1,500 a week")
check(weekly?.amount == 728_000 && monthOf(weekly?.from) == "2026-12", "sentence: a weekly wage made monthly, from next month")
let lose = parse("What if we lose Acme in May?")
check(lose?.kind == .loseClient && lose?.contact == acme.id && monthOf(lose?.from) == "2027-5", "sentence: lose a client")
let up = parse("put prices up 10% from July")
check(up?.kind == .prices && up?.percent == 10 && monthOf(up?.from) == "2027-7", "sentence: prices up")
check(parse("cut prices by 5%")?.percent == -5, "sentence: prices down")
let laptopSentence = parse("buy a laptop for $3,000 in February")
let laptopDay: Int? = laptopSentence.map { calendar.component(.day, from: $0.from) }
check(laptopSentence?.kind == .oneOff && laptopSentence?.amount == -300_000, "sentence: a one-off purchase")
check(laptopDay == 15 && monthOf(laptopSentence?.from) == "2027-2", "sentence: mid-February")
let grant = parse("a $20k grant in May")
check(grant?.kind == .oneOff && grant?.amount == 2_000_000, "sentence: a windfall")
let retainer = parse("win a $4,000 a month retainer from January")
check(retainer?.kind == .income && retainer?.amount == 400_000 && monthOf(retainer?.from) == "2027-1", "sentence: new monthly income")
let saving = parse("cut software by $500 a month")
check(saving?.kind == .cost && saving?.amount == -50_000, "sentence: a monthly saving")
let lease = parse("rent goes up $800 a month from July for 12 months")
check(lease?.kind == .cost && lease?.amount == 80_000 && monthOf(lease?.until) == "2028-6", "sentence: for twelve months")
check(parse("what if it rains") == nil, "sentence: nothing to model")
same(WhatIfParser.money(in: "in 2027 spend $50"), 5_000, "money: a year isn't money")
same(WhatIfParser.money(in: "a $1.5m raise"), 150_000_000, "money: millions")
same(WhatIfParser.money(in: "20 thousand"), 2_000_000, "money: words")
check(WhatIfParser.money(in: "up 10%") == nil, "money: a percentage isn't money")

// MARK: Explaining a report line

let software = book.explain(account: "485", from: date(2026, 8, 1), to: date(2026, 10, 31))
same(software?.total, 450_000, "explain: software was $4,500 (net of GST) in the quarter")
same(software?.previous, 300_000, "explain: $3,000 the quarter before")
same(software?.months.map(\.amount), [150_000, 150_000, 150_000], "explain: by month")
same(software?.payees.first?.name, "AWS EMEA", "explain: who it went to, as the bank wrote it")
same(software?.payees.first?.count, 3, "explain: three entries")
let facts = software?.facts(calendar: calendar) ?? ""
check(facts.contains("Software and subscriptions (account 485) was $4,500.00") && facts.contains("up $1,500.00 (50%)"), "explain: the facts George works from")
check(!facts.contains("not tax advice"), "explain: no tax note on an ordinary line")
let salesLine = book.explain(account: "200", from: date(2026, 5, 1), to: date(2026, 10, 31))
same(salesLine?.total, 3_000_000, "explain: income reads as a positive number")
let gstLine = book.explain(account: "820", from: date(2026, 7, 1), to: date(2026, 9, 30))
check(gstLine?.isTax == true && (gstLine?.facts(calendar: calendar) ?? "").contains("not tax advice"), "explain: GST comes with the tax note")

// MARK: The move from Xero

let contactsCSV = "*ContactName,EmailAddress,POAddressLine1,POCity,PORegion,POPostalCode,TaxNumber,PhoneNumber\n"
    + "Kestrel Labs,hello@kestrel.example,\"12 Smith St, Level 2\",Fitzroy,VIC,3065,51 824 753 556,03 9000 0000\n"
    + "\"Brown & Co\",,,,,,,\n"
let xeroContacts = XeroImport.contacts(contactsCSV)
same(xeroContacts.count, 2, "Xero: contacts")
same(xeroContacts.first?.address ?? "", "12 Smith St, Level 2, Fitzroy, VIC, 3065", "Xero: an address with a comma inside quotes")
same(xeroContacts.first?.abn ?? "", "51 824 753 556", "Xero: the ABN")
same(xeroContacts.last?.name ?? "", "Brown & Co", "Xero: quoted names")

let accountsCSV = "*Code,*Name,*Type,*Tax Code,Description\n090,Business Bank Account,Bank,BAS Excluded,\n200,Sales,Revenue,GST on Income,\n"
    + "455,Marketing,Overhead,GST on Expenses,\n460,Bank interest,Other Income,GST Free Income,\n720,Computer Equipment,Fixed Asset,GST on Capital,\n800,Accounts Payable,Current Liability,BAS Excluded,\n"
let xeroAccounts = XeroImport.accounts(accountsCSV)
same(xeroAccounts.count, 6, "Xero: chart of accounts")
check(xeroAccounts[0].isBank && xeroAccounts[0].type == .asset, "Xero: a bank account")
check(xeroAccounts[2].type == .expense && xeroAccounts[2].gst == .gst, "Xero: an overhead with GST")
check(xeroAccounts[3].type == .income && xeroAccounts[3].gst == .free, "Xero: other income, GST free")
check(xeroAccounts[4].gst == .capital && xeroAccounts[5].type == .liability, "Xero: capital GST and a liability")

let invoicesCSV = """
*ContactName,EmailAddress,*InvoiceNumber,Reference,*InvoiceDate,*DueDate,Total,TaxTotal,InvoiceAmountPaid,InvoiceAmountDue,*Description,*Quantity,*UnitAmount,LineAmount,*AccountCode,*TaxType,TaxAmount,Status
Kestrel Labs,hello@kestrel.example,INV-0412,Website,1/10/2026,31/10/2026,3300.00,300.00,0.00,3300.00,Design,10,150.00,1500.00,200,GST on Income,150.00,AUTHORISED
Kestrel Labs,hello@kestrel.example,INV-0412,Website,1/10/2026,31/10/2026,3300.00,300.00,0.00,3300.00,Build,1,1500.00,1500.00,200,GST on Income,150.00,AUTHORISED
Brown & Co,,INV-0413,,5/10/2026,19/10/2026,1100.00,100.00,600.00,500.00,Workshop,1,1100.00,1100.00,200,GST on Income,100.00,AUTHORISED
Acme Pty Ltd,,INV-0399,,1/9/2026,15/9/2026,550.00,50.00,550.00,0.00,Retainer,1,500.00,500.00,200,GST on Income,50.00,PAID
"""
var moving = book
let xeroResult = XeroImport.invoices(invoicesCSV, kind: .sale, book: &moving)
same(xeroResult.imported.count, 2, "Xero: invoices still owing come across")
same(xeroResult.skipped, 1, "Xero: paid ones stay in Xero")
let kestrelInvoice = xeroResult.imported.first { $0.number == "INV-0412" }
same(kestrelInvoice?.lines.count, 2, "Xero: one invoice from two rows")
same(kestrelInvoice?.total, 330_000, "Xero: GST added on top when the lines left it out")
same(kestrelInvoice?.lines.first?.unitPrice, 15_000, "Xero: the unit price")
check(kestrelInvoice?.status == .approved && kestrelInvoice?.owing == 330_000, "Xero: approved and owing")
let brown = xeroResult.imported.first { $0.number == "INV-0413" }
same(brown?.total, 110_000, "Xero: amounts that included GST read without it")
same(brown?.owing, 50_000, "Xero: part-paid in Xero, only the rest is owing")
check(moving.contacts.contains { $0.name == "Kestrel Labs" } && moving.contacts.count == book.contacts.count + 2, "Xero: new contacts added, known ones reused")
same(XeroImport.invoices(invoicesCSV, kind: .sale, book: &moving).imported.count, 0, "Xero: importing twice adds nothing")

// MARK: Paying online

let payURL = InvoiceDocument.payLink("https://buy.stripe.com/test_123?client_reference_id=[invoice]&prefilled_email=[email]&amount=[amount]",
                                   invoice: book.invoice(november.id)!, contact: acme)
same(payURL ?? "", "https://buy.stripe.com/test_123?client_reference_id=INV-0007&prefilled_email=accounts@acme.example&amount=5500.00", "pay online: the link filled in")
check(InvoiceDocument.payLink("", invoice: book.invoice(november.id)!, contact: acme) == nil, "pay online: no link without one set")
check(InvoiceDocument.payLink("https://pay.example/[invoice]", invoice: book.invoice(rent.id)!, contact: landlord) == nil, "pay online: never on a bill")

var linked = book
linked.settings.payLink = "https://buy.stripe.com/test_123?client_reference_id=[invoice]"
let lateReminder = OverdueReminder(invoice: november.id, number: "INV-0007", contact: "Acme Pty Ltd", email: "accounts@acme.example", owing: 550_000,
                           daysLate: 3, stage: 0, tone: .friendly)
check(linked.reminderDraft(lateReminder).body.contains("Or pay online: https://buy.stripe.com/test_123?client_reference_id=INV-0007"), "pay online: in Marc's reminders too")
check(InvoiceDocument.markdown(linked.invoice(november.id)!, contact: acme, settings: linked.settings).contains("**Pay online:** [https://buy.stripe.com/test_123?client_reference_id=INV-0007]"), "pay online: on the invoice")

print(failures == 0 ? "All forecast checks passed." : "\(failures) forecast checks failed.")
exit(failures == 0 ? 0 : 1)
