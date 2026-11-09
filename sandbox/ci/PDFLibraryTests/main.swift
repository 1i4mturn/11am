import Foundation

// Checks Bolton's PDF extras: collections ranked and cited by file and page, a PDF's lines joined back into
// paragraphs, invoices and agreements pulled out for George and Notes, and tall web pages cut into pages.

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
calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

// MARK: Collections

let lease = [
    "Office lease\nBetween Harbour Properties Pty Ltd (the landlord) and 11am Labs Pty Ltd (the tenant).\nThe rent is $4,600 a month, paid in advance on the first of each month.",
    "Ending the lease\nEither party may end this lease by giving 60 days' notice in writing. The bond is four weeks' rent, $9,200, held until the tenant leaves.",
    "Repairs\nThe landlord fixes the building; the tenant fixes what the tenant breaks.",
]
let insurance = [
    "Contents insurance\nYour excess is $500 for each claim. We cover laptops and phones away from the office.",
    "Making a claim\nTell us within 30 days of the loss. Keep receipts for anything over $1,000.",
]
let pilot = ["Pilot agreement\nEither of us can end the pilot with 7 days' notice in writing. Invoices are due within 14 days."]
let passages = PageIndex.passages(file: "/Users/me/Documents/Office lease.pdf", pages: lease)
    + PageIndex.passages(file: "/Users/me/Documents/Contents insurance.pdf", pages: insurance)
    + PageIndex.passages(file: "/Users/me/Documents/Pilot agreement.pdf", pages: pilot)

same(passages.filter { $0.name == "Office lease" }.map(\.page), [1, 2, 3], "index: a passage a page for short pages")
same(passages.first?.label, "Office lease, p. 1", "index: labelled with the file and page")
same(PageIndex.terms("Notices ending the leases"), ["notice", "end", "lease"], "terms: stop words gone, words stemmed")
same(PageIndex.flatten("we agree-\nment is   here\nnow"), "we agreement is here now", "index: a word broken at a line's end, mended")

let notice = PageIndex.rank("How much notice do I need to give to end the lease?", passages)
same(notice.first?.label, "Office lease, p. 2", "rank: the page about ending the lease first")
check(notice.contains { $0.name == "Pilot agreement" }, "rank: the other agreement's notice found too")
check(!notice.contains { $0.label == "Office lease, p. 3" }, "rank: a page that doesn't mention it isn't")
same(PageIndex.rank("What is the excess on a claim?", passages).first?.label, "Contents insurance, p. 1", "rank: excess and claim together win")
same(PageIndex.rank("the and of what", passages).count, 0, "rank: nothing to look for, nothing found")
same(PageIndex.rank("lease", passages, limit: 1).count, 1, "rank: only as many as asked")
let bonds = PageIndex.passages(file: "/a/Bonds.pdf", pages: Array(repeating: "The bond is held in trust.", count: 6)) + passages
check(PageIndex.rank("bond", bonds, perFile: 4).filter { $0.name == "Bonds" }.count == 4, "rank: one file can't crowd out the rest")

let long = (1...40).map { "Sentence number \($0) says something about the lease and the rent." }.joined(separator: " ")
let pieces = PageIndex.passages(file: "/a/Long.pdf", pages: [long])
check(pieces.count > 1 && pieces.allSatisfy { $0.text.count <= 900 && $0.page == 1 }, "index: a long page in passages that fit (\(pieces.count))")
same(pieces.map(\.text).joined(separator: " "), long, "index: the passages make the page")

// MARK: Answers

let top = Array(notice.prefix(3))
let prompt = CollectionAnswer.prompt(question: "How much notice?", passages: top)
check(prompt.contains("[1] Office lease, p. 2") && prompt.contains("Question: How much notice?"), "answer: excerpts numbered with file and page")
let markers = CollectionAnswer.markers(in: "Sixty days [1]. Seven days [2, 3] and [4–5]. Not [x].")
same(markers.map { $0.numbers }, [[1], [2, 3], [4, 5]], "answer: markers and the excerpts they name")
let answer = "The lease needs 60 days' notice in writing [1]. The pilot needs seven [2]. Both want it in writing [1, 2]. See also [9]."
same(CollectionAnswer.cited(answer, passages: top).map(\.label), [top[0].label, top[1].label], "answer: cited pages in order, once each")
same(CollectionAnswer.plain("Sixty days' notice [1]. A bond too [1]. Unknown [9].", passages: top),
     "Sixty days' notice (Office lease, p. 2). A bond too (Office lease, p. 2). Unknown [9].", "answer: written out for pasting")

// MARK: A PDF's text as paragraphs

let page = """
Ending the pilot
Either of us can end the pilot at any time by giving the other side seven
days' notice in writing, and we will stop charging for seats from the day
the notice arrives. Work done before then is still paid for under the agree-
ment.
• Notice goes to the email address on the first page of this agreement.
• Seats stop the same day.
"""
same(PDFText.paragraphs(page), [
    "Ending the pilot",
    "Either of us can end the pilot at any time by giving the other side seven days' notice in writing, and we will stop charging for seats from the day the notice arrives. Work done before then is still paid for under the agreement.",
    "• Notice goes to the email address on the first page of this agreement.",
    "• Seats stop the same day.",
], "text: lines joined into paragraphs, a broken word mended, list items kept apart")
same(PDFText.markdown(title: "Pilot agreement", pages: ["Pilot agreement", page]).components(separatedBy: "\n\n").prefix(3).joined(separator: "|"),
     "# Pilot agreement|## Ending the pilot|Either of us can end the pilot at any time by giving the other side seven days' notice in writing, and we will stop charging for seats from the day the notice arrives. Work done before then is still paid for under the agreement.",
     "text: as Markdown with a title, the title line not repeated, a short line as a heading")
check(PDFText.markdown(title: "T", pages: [page]).contains("\n\n- Seats stop the same day."), "text: bullets as Markdown list items")
check(!PDFText.isHeading("Onboarding $2,500") && !PDFText.isHeading("Signed for Acme Co: ______") && !PDFText.isHeading("Short and done."),
      "text: amounts, signature lines and sentences aren't headings")

// MARK: Invoices

let invoiceText = """
Tax Invoice
Northwind Design Studio
ABN 51 824 753 556
Invoice number: INV-0042
Invoice date: 3 November 2026
Bill to: 11am Labs Pty Ltd
Brand refresh, logo and type   $1,500.00
Subtotal $1,500.00
GST $150.00
Total due $1,650.00
Payment terms: 14 days
"""
same(PDFPullOut.kind(invoiceText), .invoice, "pull out: an invoice")
let facts = PDFPullOut.invoice(invoiceText, calendar: calendar)
same(facts.vendor, "Northwind Design Studio", "invoice: who it's from")
same(facts.number, "INV-0042", "invoice: its number")
same(facts.total, 165_000, "invoice: the total")
same(facts.gst, 15_000, "invoice: the GST")
same(facts.abn, "51 824 753 556", "invoice: the ABN")
same(facts.issued, day(2026, 11, 3), "invoice: the date")
same(facts.due, day(2026, 11, 17), "invoice: due 14 days later, from the payment terms")
let explicit = PDFPullOut.invoice("Invoice # 1187\nFrom: Pixel & Co\nDate: 1/11/2026\nDue date: 30/11/2026\nAmount due $880.00", calendar: calendar)
same(explicit.number, "1187", "invoice: a number after #")
same(explicit.due, day(2026, 11, 30), "invoice: a due date it states")
same(explicit.issued, day(2026, 11, 1), "invoice: the issue date isn't the due date")
same(PDFPullOut.number(in: "Tax Invoice\nNorthwind\nRef INV-77"), "INV-77", "invoice: a name starting No isn't a number")

// MARK: Agreements

let agreement = """
Pilot agreement
Between 11am Labs Pty Ltd ("we") and Acme Co ("you"), dated 9 November 2026.
1. The pilot
We give you access to 11am for 40 seats for 90 days, starting on Friday. You give us feedback every two weeks.
2. Fees
Item Amount
Pilot (40 seats, 90 days) $0
Onboarding $2,500
After the pilot, per seat per month $24
Invoices are due within 14 days. Account for payment: BSB 062-000, account 1234 5678.
4. Ending the pilot
Either of us can end the pilot with 7 days' notice in writing.
"""
same(PDFPullOut.kind(agreement), .contract, "pull out: an agreement, though it mentions invoices")
same(PDFPullOut.kind("Shopping list: eggs, milk, bread"), .other, "pull out: anything else")
let terms = PDFPullOut.contract(agreement, calendar: calendar)
same(terms.title, "Pilot agreement", "agreement: its title")
same(terms.parties, ["11am Labs Pty Ltd", "Acme Co"], "agreement: who it's between")
same(terms.dated, day(2026, 11, 9), "agreement: when")
same(terms.money, ["Pilot (40 seats, 90 days) $0", "Onboarding $2,500", "After the pilot, per seat per month $24"], "agreement: the money lines")
same(terms.times, ["We give you access to 11am for 40 seats for 90 days, starting on Friday.", "You give us feedback every two weeks.",
                   "Invoices are due within 14 days.", "Either of us can end the pilot with 7 days' notice in writing."], "agreement: the time limits")
let note = PDFPullOut.note(terms, file: "/Users/me/Acme pilot agreement.pdf", calendar: calendar)
check(note.hasPrefix("# Key facts: Pilot agreement\n") && note.contains("**Between:** 11am Labs Pty Ltd and Acme Co")
      && note.contains("**Dated:** 9 November 2026") && note.contains("## Time limits\n- We give you") && note.contains("Acme pilot agreement"),
      "agreement: a note for Notes")

// MARK: Web pages

same(WebPages.slices(height: 2_500, pageHeight: 1_000), [0...1_000, 1_000...2_000, 2_000...2_500], "web: cut into pages")
same(WebPages.slices(height: 2_500, pageHeight: 1_000, gaps: [950, 1_980]), [0...950, 950...1_950, 1_950...2_500], "web: cuts move up to a gap between lines")
same(WebPages.slices(height: 900, pageHeight: 1_000), [0...900], "web: a short page is one page")
same(WebPages.slices(height: 0, pageHeight: 1_000).count, 0, "web: nothing to cut")
var details = PageDetails()
details.title = "How to rest"
details.site = "The Example Times"
details.authors = [PersonName(given: "Ana", family: "Lopez")]
let article = ClippedArticle(url: "https://www.example.com/rest", details: details, markdown: "Sleep more.\n", excerpt: "", words: 2)
same(WebPages.markdown(article), "# How to rest\n\n*Ana Lopez · The Example Times*\n\nSleep more.", "web: the article with its title and source")

print(failures == 0 ? "All PDF checks passed." : "\(failures) PDF checks failed.")
exit(failures == 0 ? 0 : 1)
