import Foundation

// Checks William's writing tools: comments that stay on their passage as the text changes, finding your own material
// for a draft, another document's shape, a summary put under the title, and long documents split for translating.

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

let now = Date(timeIntervalSince1970: 1_800_000_000)

// MARK: Comments

let text = "# Plan\n\nThe plan is good. We start in March.\n\nThe plan is late, though, and the budget is tight."
let ns = text as NSString
let second = ns.range(of: "The plan is late")
let lateRange = NSRange(location: second.location, length: "The plan".count)
let comment = DocAnchors.comment(on: lateRange, in: text, body: "Which plan? @William can you check the dates?", date: now)
same(comment?.quote, "The plan", "comment: the passage")
check(comment?.before.hasSuffix("We start in March.\n\n") == true, "comment: what came before it")
check(comment?.asksWilliam == true, "comment: asking William")
check(!DocAnchors.mentionsWilliam("@Williams can you") && DocAnchors.mentionsWilliam("ask @william."), "comment: @William, not @Williams")
check(DocAnchors.comment(on: NSRange(location: 3, length: 0), in: text, body: "x") == nil, "comment: nothing selected, no comment")

let edited = "# Plan\n\nIntro added here.\n\nThe plan is good. We start in March.\n\nThe plan is late, though, and the budget is tight."
let moved = comment.flatMap { DocAnchors.locate($0, in: edited) }
same(moved.map { (edited as NSString).substring(from: $0.location).hasPrefix("The plan is late") }, true, "comment: follows its passage when text is added above")
check(moved?.location != (edited as NSString).range(of: "The plan").location, "comment: the second 'The plan', not the first")
same(comment.flatMap { DocAnchors.locate($0, in: "# Plan\n\nAll rewritten.") }, nil, "comment: gone when the words are gone")
let single = DocAnchors.comment(on: ns.range(of: "budget is tight"), in: text, body: "Get numbers", date: now)!
same(DocAnchors.locate(single, in: "The budget is tight now.").map { $0.location }, 4, "comment: one place, found wherever it moved")
same(DocAnchors.excerpt(DocComment(quote: String(repeating: "word ", count: 30), before: "", body: "", author: "You", created: now), length: 20).count, 20, "comment: a short excerpt")

var resolved = single
resolved.resolved = true
var gone = single
gone.quote = "words that are gone"
let order = DocAnchors.ordered([resolved, gone, comment!], in: text)
same(order.map(\.quote), ["The plan", "words that are gone", "budget is tight"], "comments: open by position, then detached, then resolved")

// MARK: Your own material

same(MaterialFinder.terms("a proposal for Acme using last week's call notes and our pricing sheet"), ["proposal", "acme", "call", "pricing", "sheet"], "material: the words that matter")
same(MaterialFinder.window("last week's call"), 14 * 86_400, "material: last week looks back a fortnight")
check(MaterialFinder.window("our pricing") == nil, "material: no window without a time")
let day: TimeInterval = 86_400
let items = [
    DraftMaterial(id: "a", title: "Acme call, 3 Nov", kind: "Note", text: "Tom wants the pilot in December. Pricing came up: they'd pay per seat.", date: now - 3 * day),
    DraftMaterial(id: "b", title: "Pricing sheet 2026", kind: "Sheet", text: "Solo $12, Team $40 a month.", date: now - 10 * day),
    DraftMaterial(id: "c", title: "Acme proposal 2025", kind: "Document", text: "Our proposal for Acme last year: pricing per seat, a pilot in March.", date: now - 60 * day),
    DraftMaterial(id: "d", title: "Holiday plans", kind: "Note", text: "Japan in April.", date: now - 1 * day),
]
let request = "a proposal for Acme using last week's call notes and our pricing sheet"
same(MaterialFinder.rank(request, items, now: now).map(\.id), ["a", "b", "c"], "material: recent call notes and the pricing sheet before last year's proposal")
same(MaterialFinder.rank(request, items, now: now, limit: 2).map(\.id), ["a", "b"], "material: only as many as asked")
same(MaterialFinder.rank("acme proposal", items, now: now).first?.id, "c", "material: without a time, the best match wins")
same(MaterialFinder.rank("the and of", items, now: now).count, 0, "material: nothing to look for, nothing found")
let long = DraftMaterial(id: "l", title: "Long", kind: "Note", text: String(repeating: "filler words here. ", count: 200) + "The Kestrel budget is $40k." + String(repeating: " more filler.", count: 200), date: now)
let cut = MaterialFinder.excerpt(long, terms: ["kestrel"], length: 400)
check(cut.contains("Kestrel budget") && cut.hasPrefix("…") && cut.hasSuffix("…") && cut.count <= 402, "material: the excerpt is around the words that matter")

// MARK: The shape of a document

same(DocShape.outline("# Proposal\n\nIntro\n\n## Background\n\ntext\n\n### Detail\n\n## Price"), "# Proposal\n## Background\n### Detail\n## Price", "shape: another document's headings")
let summarised = DocShape.insertSummary("Short summary.", into: "# Title\n\nBody one.\n\n## Part\n\nMore.")
same(summarised, "# Title\n\n> **Summary:** Short summary.\n\nBody one.\n\n## Part\n\nMore.", "summary: under the title")
same(DocShape.insertSummary("Newer.\nSecond line.", into: summarised), "# Title\n\n> **Summary:** Newer.\n> Second line.\n\nBody one.\n\n## Part\n\nMore.", "summary: replaces the old one, body kept")
same(DocShape.insertSummary("Top.", into: "Just text."), "> **Summary:** Top.\n\nJust text.", "summary: at the top without a title")
same(DocShape.insertSummary("Tight.", into: "# Title\nBody."), "# Title\n\n> **Summary:** Tight.\n\nBody.", "summary: a blank line after the title")

let paragraphs = (1...10).map { "Paragraph \($0) " + String(repeating: "x", count: 990) }
let document = paragraphs.joined(separator: "\n\n")
let parts = DocShape.chunks(document, limit: 2_500)
check(parts.count == 5 && parts.allSatisfy { $0.count <= 2_500 }, "translate: long documents in parts that fit (\(parts.count))")
same(parts.joined(separator: "\n\n"), document, "translate: the parts make the whole")
same(DocShape.chunks("Short.", limit: 100), ["Short."], "translate: a short document is one part")

print(failures == 0 ? "All writing checks passed." : "\(failures) writing checks failed.")
exit(failures == 0 ? 0 : 1)
