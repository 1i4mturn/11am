import Foundation

// Checks Marc's toolkit: snippet fields, sending later, and noticing receipts, meeting requests and agreements.

var failures = 0
func check(_ condition: Bool, _ name: String) {
    print(condition ? "PASS" : "FAIL", name)
    if !condition { failures += 1 }
}

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Australia/Sydney")!
func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))! }

// MARK: Snippets

let reminder = "Hi {{first name}},\n\nInvoice {{invoice number}} for {{ Amount }} was due {{due date}}. {{invoice number}} again.\n\n{{my name}}"
check(Snippets.fields(in: reminder) == ["first name", "invoice number", "amount", "due date", "my name"], "Fields in order, once each, any case")
check(Snippets.blanks(in: reminder) == ["invoice number", "amount", "due date"], "The ones you fill in yourself")
let filled = Snippets.fill(reminder, values: ["first name": "Tom", "Invoice Number": "INV-0004", "amount": "$1,200", "my name": "Sam"])
check(filled.hasPrefix("Hi Tom,") && filled.contains("Invoice INV-0004 for $1,200 was due {{due date}}. INV-0004 again.") && filled.hasSuffix("Sam"),
      "Filled, with the blank left showing: \(filled)")
check(Snippets.fill("No fields here", values: ["x": "y"]) == "No fields here" && Snippets.fill("{{unclosed", values: [:]) == "{{unclosed", "Text without fields is left alone")
check(Snippets.firstName(fromRecipients: "Tom Baker <tom@acme.co>, rita@acme.co") == "Tom", "First name from a display name")
check(Snippets.firstName(fromRecipients: "priya.shah@northwind.vc") == "Priya", "First name from an address")
check(Snippets.firstName(fromRecipients: "") == "" && Snippets.firstName(fromRecipients: "x1@y.com") == "", "No name when there isn't one")
check(Snippets.builtIns.allSatisfy { !$0.name.isEmpty && Snippets.fields(in: $0.body).contains("first name") }, "Built-in snippets greet by name")

// MARK: Send later

// Thursday 5 November 2026, 10:20 am.
let thursday = day(2026, 11, 5, 10, 20)
let options = SendLater.options(now: thursday, calendar: cal)
check(options.map { $0.title } == ["In an hour", "This afternoon", "Tomorrow morning", "Monday morning"], "Four choices on a Thursday morning: \(options.map { $0.title })")
check(options[0].date == day(2026, 11, 5, 11) && options[1].date == day(2026, 11, 5, 14), "In an hour is on the hour; this afternoon is 2 pm")
check(options[2].date == day(2026, 11, 6, 8) && options[3].date == day(2026, 11, 9, 8), "Tomorrow and Monday at 8 am")
let friday = SendLater.options(now: day(2026, 11, 6, 15), calendar: cal)
check(friday.map { $0.title } == ["In an hour", "Monday morning"], "Friday afternoon: no weekend morning, no afternoon gone by")
let sunday = SendLater.options(now: day(2026, 11, 8, 9), calendar: cal)
check(sunday.map { $0.title } == ["In an hour", "This afternoon", "Tomorrow morning"] && sunday[2].date == day(2026, 11, 9, 8), "Sunday: tomorrow is Monday, not twice")

// MARK: What an email is

let receipt = MailRouter.route(subject: "Your receipt from Lumen Coffee", body: "Flat white  $5.50\nBanana bread  $6.00\nGST  $1.05\nTotal  $11.50\nThanks!", fromName: "Lumen Coffee", fromAddress: "receipts@lumen.coffee")
check(receipt == .receipt(vendor: "Lumen Coffee", total: 11.50), "A receipt, with the total line: \(String(describing: receipt))")
let invoice = MailRouter.route(subject: "Tax invoice INV-2231", body: "Amount due: AUD 1,980.00 by 30 November.\nHosting AUD 1,800.00", fromName: "Billing", fromAddress: "billing@cloudhost.io")
check(invoice == .receipt(vendor: "Cloudhost", total: 1_980), "An invoice from a generic sender is named from the domain: \(String(describing: invoice))")
check(MailRouter.route(subject: "Invoice", body: "Please see attached.", fromName: "A", fromAddress: "a@b.co") == nil, "No amount, no receipt")
check(MailRouter.route(subject: "Quick question", body: "Are you free for a quick call on Tuesday?", fromName: "Priya", fromAddress: "priya@northwind.vc") == .meeting, "A meeting request")
check(MailRouter.route(subject: "Agreement for the pilot", body: "Attached is the agreement. Please sign when you can.", fromName: "Tom", fromAddress: "tom@acme.co") == .agreement, "An agreement to sign")
check(MailRouter.route(subject: "Lunch?", body: "Loved the demo, well done.", fromName: "Jess", fromAddress: "jess@studiowong.com") == nil, "Most mail is none of these")
check(MailRouter.amounts(in: "A$42 then 12.00 USD and $1,234.56") == [42, 12, 1_234.56], "Amounts written different ways")
check(MailRouter.total(in: "Item $5.00\nItem $90.00") == 90, "No total line: the largest amount")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
