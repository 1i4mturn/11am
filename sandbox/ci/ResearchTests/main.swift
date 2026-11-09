import Foundation

// Checks James's research engine: the HTML tree, reader mode, what a page says about itself, search results,
// clippings and the browser button, names and dates, the five citation styles, citations in a document, and the
// checks on a sourced answer.

var failures = 0
func check(_ condition: Bool, _ name: String) {
    print(condition ? "PASS" : "FAIL", name)
    if !condition { failures += 1 }
}
func same(_ actual: String, _ expected: String, _ name: String) {
    if actual == expected {
        print("PASS", name)
    } else {
        print("FAIL", name)
        print("  expected: \(expected)")
        print("  actual:   \(actual)")
        failures += 1
    }
}

// MARK: HTML tree

let tree = HTMLTree.parse("<html><body><p class='lead' data-x=1 hidden>One &amp; two<p>Three&#8217;s &#x2014; four&nbsp;five<ul><li>a<li>b<ul><li>c</ul><li>d</ul><script>var x = '<p>not a paragraph</p>';</script><br/><img src=a.png alt=\"A &quot;pic&quot;\"></body></html>")
let paragraphs = tree.elements("p")
check(paragraphs.count == 2, "tree: an unclosed paragraph closes when the next opens")
check(paragraphs.first?.attributes["class"] == "lead" && paragraphs.first?.attributes["data-x"] == "1" && paragraphs.first?.attributes["hidden"] == "", "tree: quoted, unquoted and bare attributes")
same(paragraphs.first?.textContent ?? "", "One & two", "tree: entities in text")
check((paragraphs.last?.textContent ?? "").hasPrefix("Three\u{2019}s \u{2014} four\u{00A0}five"), "tree: numeric and named entities")
let outerList = tree.elements("ul").first
check(outerList?.children.filter { $0.tag == "li" }.count == 3, "tree: list items close each other, a nested list stays inside its item")
check(tree.elements("li").count == 4, "tree: four items in all")
check(!tree.textContent.contains("not a paragraph"), "tree: script stays out of the text")
check(tree.elements("p").allSatisfy { $0.parent?.tag != "script" }, "tree: markup in a script isn't parsed")
check(tree.first("img")?.attributes["alt"] == "A \"pic\"", "tree: void tags and entities in attributes")
check(HTMLTree.parse("<div><span>a</div>b</span>c").first("div")?.textContent == "a", "tree: a stray closing tag doesn't break the tree")
check(HTMLTree.parse("<!-- <p>hidden</p> --><p>shown</p>").elements("p").count == 1, "tree: comments skipped")
same(HTMLText.collapse("  a \n\t b  "), "a b", "text: collapse")
same(HTMLText.squeeze("  a \n b  "), " a b ", "text: squeeze keeps a space at each end")

// MARK: Reader mode on a news page

let newsPage = """
<!doctype html>
<html lang="en"><head>
<title>Interest rates hold steady as inflation eases | The Harbour Times</title>
<meta property="og:site_name" content="The Harbour Times">
<meta property="og:title" content="Interest rates hold steady as inflation eases">
<meta property="og:type" content="article">
<meta name="description" content="The Reserve Bank kept the cash rate where it was.">
<meta property="article:published_time" content="2026-11-03T14:30:00+11:00">
<script type="application/ld+json">{"@context":"https://schema.org","@graph":[{"@type":"WebPage","name":"Page"},{"@type":"NewsArticle","headline":"Interest rates hold steady as inflation eases","datePublished":"2026-11-03T14:30:00+11:00","author":[{"@type":"Person","name":"Jane Citizen"},{"@type":"Person","name":"Sam Lee"}],"publisher":{"@type":"Organization","name":"The Harbour Times"}}]}</script>
<style>.x { color: red }</style>
</head><body>
<div class="cookie-banner">We use cookies. <button>Accept</button></div>
<header class="site-header"><nav><a href="/">Home</a> <a href="/business">Business</a></nav></header>
<main>
<article class="story">
<header><h1>Interest rates hold steady as inflation eases</h1><p class="byline">By Jane Citizen and Sam Lee</p><time datetime="2026-11-03">3 November 2026</time></header>
<p>The <a href="/rba">Reserve Bank</a> left the cash rate unchanged on Tuesday, saying inflation had eased faster than it expected, though rents and insurance were still rising.</p>
<figure><img src="/img/chart.png" alt="Chart of rates" width="800"><figcaption>The cash rate since 2020</figcaption></figure>
<p>Economists had expected the pause, and most now think the next move, whenever it comes, will be down rather than up, which would help households and small businesses alike.</p>
<h2>What it means</h2>
<p>For a small business with a variable loan, repayments stay where they are for at least another month, giving owners some room to plan, hire, or build a buffer of cash.</p>
<blockquote><p>We are not declaring victory yet, but the trend is clearly in the right direction.</p></blockquote>
<ul><li>First, check your loan's rate.</li><li>Second, talk to your <strong>accountant</strong>.</li></ul>
<p>Read the full statement on the bank's website, which sets out the board's reasoning in detail and the data it relied on.<sup><a href="#n1">[1]</a></sup></p>
<aside class="related"><h3>Related stories</h3><a href="/a">Housing prices</a></aside>
<div class="newsletter-signup"><p>Subscribe to our newsletter for the latest business news every morning.</p></div>
</article>
</main>
<footer><p>Copyright The Harbour Times</p></footer>
<script>var tracking = "<p>nope</p>";</script>
</body></html>
"""
let newsURL = URL(string: "https://example.com/news/rates")!
let article = ArticleReader.read(html: newsPage, url: newsURL)
same(article.details.title, "Interest rates hold steady as inflation eases", "reader: title from the page's own tags")
same(article.details.authors.map(\.full).joined(separator: "; "), "Jane Citizen; Sam Lee", "reader: authors from the page's linked data")
check(article.details.published == CiteDate(year: 2026, month: 11, day: 3), "reader: the published date")
same(article.details.site, "The Harbour Times", "reader: the site's name")
check(article.details.kind == .news, "reader: a news article")
let body = article.markdown
check(body.contains("The [Reserve Bank](https://example.com/rba) left the cash rate unchanged"), "reader: links made absolute")
check(body.contains("![Chart of rates](https://example.com/img/chart.png)"), "reader: pictures kept, with absolute addresses")
check(body.contains("*The cash rate since 2020*"), "reader: captions in italics")
check(body.contains("## What it means"), "reader: headings kept")
check(!body.contains("# Interest rates hold steady"), "reader: the title isn't repeated in the body")
check(body.contains("> We are not declaring victory yet"), "reader: quotes kept")
check(body.contains("- First, check your loan's rate.") && body.contains("- Second, talk to your **accountant**."), "reader: lists and bold kept")
check(!body.contains("Related stories") && !body.contains("Housing prices"), "reader: related links dropped")
check(!body.contains("Subscribe") && !body.contains("cookies") && !body.contains("Copyright"), "reader: banners, sign-ups and footers dropped")
check(!body.contains("Home") && !body.contains("tracking") && !body.contains("color: red"), "reader: menus, scripts and styles dropped")
check(!body.contains("[1]"), "reader: footnote markers dropped")
check(body.contains("data it relied on."), "reader: the last paragraph kept")
check(article.excerpt.hasPrefix("The Reserve Bank left the cash rate unchanged"), "reader: the excerpt is the first paragraph, without marks")
check(article.words > 100 && article.readingMinutes == 1, "reader: words and reading time")

// A page with no article tag: the paragraphs decide.
let blogPage = """
<html><head><title>Pricing for one-person businesses - Field Notes</title><meta name="author" content="Alex Brown"></head><body>
<div id="top"><a href="/">Field Notes</a></div>
<div class="layout">
<div class="sidebar"><ul><li><a href="/1">Older post one</a></li><li><a href="/2">Older post two</a></li><li><a href="/3">Older post three</a></li></ul></div>
<div class="post-content">
<div>Pricing is the decision most solo owners make once and never revisit, even though it shapes everything else, from cash flow to the clients they attract.</div>
<p>Start with what the work is worth to the client, not with what your hours cost you, and test the number, carefully, on the next three proposals you send.</p>
<p>If nobody pushes back, your price is too low. If everyone does, look at how you explain the value, before you look at the number itself.</p>
</div>
</div>
</body></html>
"""
let blog = ArticleReader.read(html: blogPage, url: URL(string: "https://fieldnotes.example/pricing"))
check(blog.markdown.contains("Pricing is the decision") && blog.markdown.contains("If nobody pushes back"), "reader: finds the post among divs")
check(!blog.markdown.contains("Older post"), "reader: leaves the sidebar out")
same(blog.details.title, "Pricing for one-person businesses", "reader: the site's name trimmed from the title")
same(blog.details.authors.first?.family ?? "", "Brown", "reader: the author tag")
same(blog.details.site, "fieldnotes.example", "reader: the host when there's no site name")
same(ArticleReader.trimSiteName("Runway (finance) - Wikipedia", site: "Wikipedia"), "Runway (finance)", "reader: Wikipedia's suffix")
same(ArticleReader.trimSiteName("Q&A: the 2026 budget - what it means - ABC News", site: "ABC News"), "Q&A: the 2026 budget - what it means", "reader: only the last part is the site")

// A journal article's scholar tags.
let journalPage = """
<html><head>
<meta name="citation_title" content="Cash flow habits of sole traders">
<meta name="citation_author" content="Nguyen, Thi">
<meta name="citation_author" content="Brown, Alex">
<meta name="citation_journal_title" content="Journal of Small Business">
<meta name="citation_publication_date" content="2025/06/14">
<meta name="citation_volume" content="12"><meta name="citation_issue" content="3">
<meta name="citation_firstpage" content="45"><meta name="citation_lastpage" content="67">
<meta name="citation_doi" content="doi:10.1234/jsb.2025.045">
</head><body><article><p>Abstract. We surveyed 1,200 sole traders about how they manage cash, and found that most keep less than a month of costs in reserve.</p></article></body></html>
"""
let journal = ArticleReader.read(html: journalPage, url: URL(string: "https://journals.example/jsb/45"))
check(journal.details.kind == .journal, "scholar tags: a journal article")
same(journal.details.authors.map { "\($0.family)|\($0.given)" }.joined(separator: " "), "Nguyen|Thi Brown|Alex", "scholar tags: authors, family name first")
check(journal.details.published == CiteDate(year: 2025, month: 6, day: 14), "scholar tags: the date")
same(journal.details.doi, "10.1234/jsb.2025.045", "scholar tags: the DOI without its prefix")
same("\(journal.details.volume)/\(journal.details.issue)/\(journal.details.pages)", "12/3/45–67", "scholar tags: volume, issue and pages")
same(journal.details.site, "Journal of Small Business", "scholar tags: the journal")

// MARK: Dates and names

check(CiteDate.parse("2026-11-03T14:30:00+11:00") == CiteDate(year: 2026, month: 11, day: 3), "dates: a timestamp")
check(CiteDate.parse("2025/6/14") == CiteDate(year: 2025, month: 6, day: 14), "dates: slashes")
check(CiteDate.parse("Posted 5th March 2024") == CiteDate(year: 2024, month: 3, day: 5), "dates: day month year")
check(CiteDate.parse("Mar. 5, 2024") == CiteDate(year: 2024, month: 3, day: 5), "dates: month day, year")
check(CiteDate.parse("Updated September 2023") == CiteDate(year: 2023, month: 9), "dates: month and year")
check(CiteDate.parse("Sept 2023") == CiteDate(year: 2023, month: 9), "dates: Sept")
check(CiteDate.parse("© 2019 Example") == CiteDate(year: 2019), "dates: a year alone")
check(CiteDate.parse("2024-13-40") == nil && CiteDate.parse("no date here") == nil, "dates: nonsense is nothing")
check(CiteDate(year: 2024, month: 3) < CiteDate(year: 2024, month: 3, day: 1), "dates: a month sorts before its days")

let smith = PersonName.parse("Smith, John Paul")
check(smith?.family == "Smith" && smith?.given == "John Paul" && smith?.initials == "J. P.", "names: family first, with initials")
let berg = PersonName.parse("Jean-Luc van der Berg")
check(berg?.family == "van der Berg" && berg?.initials == "J.-L.", "names: particles stay with the family name; hyphenated initials")
check(PersonName.parse("By Jane Citizen")?.family == "Citizen", "names: 'By' dropped")
check(PersonName.parse("Australian Bureau of Statistics")?.isOrganisation == true, "names: an organisation")
check(PersonName.parse("Martin Luther King Jr.")?.family == "King Jr.", "names: suffixes stay with the family name")
check(PersonName.parse("https://example.com/author/jane") == nil, "names: a link isn't a name")
same(PageDetails.splitNames("Jane Citizen and Sam Lee").joined(separator: "|"), "Jane Citizen|Sam Lee", "names: 'and' splits")
same(PageDetails.splitNames("Lee, Jane").joined(separator: "|"), "Lee, Jane", "names: a family-first name isn't split")

// MARK: Search results

let searchPage = """
<div class="results">
<div class="result results_links results_links_deep result--ad"><h2 class="result__title"><a class="result__a" href="https://duckduckgo.com/y.js?ad_provider=x&amp;u3=https%3A%2F%2Fads.example">Sponsored thing</a></h2><a class="result__snippet">Buy now</a></div>
<div class="result results_links results_links_deep web-result"><div class="links_main result__body"><h2 class="result__title"><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fen.wikipedia.org%2Fwiki%2FRunway_(finance)&amp;rut=abc">Runway (finance) - Wikipedia</a></h2><a class="result__snippet" href="x">In finance, <b>runway</b> is the amount of time a company has before it runs out of money.</a></div></div>
<div class="result results_links web-result"><h2 class="result__title"><a class="result__a" href="https://www.investopedia.com/runway">What Is Cash Runway?</a></h2><div class="result__snippet">How long cash lasts at the current burn.</div></div>
<div class="result web-result"><h2><a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fen.wikipedia.org%2Fwiki%2FRunway_(finance)">Duplicate</a></h2></div>
</div>
"""
let hits = SearchResults.duckDuckGo(searchPage)
check(hits.count == 2, "search: ads and repeats left out")
same(hits.first?.url ?? "", "https://en.wikipedia.org/wiki/Runway_(finance)", "search: the real address unwrapped")
same(hits.first?.title ?? "", "Runway (finance) - Wikipedia", "search: titles")
same(hits.first?.snippet ?? "", "In finance, runway is the amount of time a company has before it runs out of money.", "search: snippets")
same(hits.last?.host ?? "", "investopedia.com", "search: hosts without www")
check(SearchResults.url(for: "cash runway")?.absoluteString == "https://html.duckduckgo.com/html/?q=cash%20runway", "search: the address")

// MARK: Clippings and the browser button

let clipped = ClipNote.markdown(article, selection: "the trend is clearly\nin the right direction", clipped: ISO8601DateFormatter().date(from: "2026-11-09T01:00:00Z")!)
check(clipped.hasPrefix("# Interest rates hold steady as inflation eases\n"), "clip: the title first")
check(clipped.contains("*Clipped 9 November 2026 from* [The Harbour Times](https://example.com/news/rates) · by Jane Citizen and Sam Lee · 3 November 2026"), "clip: where it's from, who wrote it and when")
check(clipped.contains("> the trend is clearly\n> in the right direction"), "clip: the selection as a quote")
check(clipped.contains("## What it means") && clipped.hasSuffix("#clipping"), "clip: the article, then the tag")
let textClip = ClipNote.markdown(text: "A line worth keeping.\nAnd another.", from: "Safari", clipped: Date())
check(textClip.hasPrefix("# A line worth keeping.") && textClip.contains("> And another.") && textClip.contains("from* Safari"), "clip: text from another app")

let clipLink = ClipLink.clip(url: "https://example.com/a?b=1&c=2", title: "A & B", selection: "Some text")
check(clipLink.url.flatMap(ClipLink.parse) == clipLink, "link: a clip survives the round trip")
check(ClipLink.parse(URL(string: "elevenam://lookup?q=cash%20runway%20for%20sole%20traders")!) == .lookUp("cash runway for sole traders"), "link: look this up")
check(ClipLink.parse(URL(string: "elevenam://clip")!) == nil && ClipLink.parse(URL(string: "https://clip?url=x")!) == nil, "link: empty or foreign links ignored")
check(ClipLink.bookmarklet.hasPrefix("javascript:") && ClipLink.bookmarklet.contains("elevenam://clip?url=") && !ClipLink.bookmarklet.contains("\n"), "link: the browser button")

// MARK: Sources and citations

let accessed = ISO8601DateFormatter().date(from: "2026-11-09T01:00:00Z")!
var news = CitationSource(title: "Interest rates hold steady as inflation eases", url: "https://example.com/news/rates", kind: .news,
                          authors: [PersonName(given: "Jane", family: "Citizen"), PersonName(given: "Sam", family: "Lee")],
                          container: "The Harbour Times", published: CiteDate(year: 2026, month: 11, day: 3), accessed: accessed)
var paper = CitationSource(title: "Cash flow habits of sole traders", url: "https://journals.example/jsb/45", kind: .journal,
                           authors: [PersonName(given: "Thi", family: "Nguyen"), PersonName(given: "Alex", family: "Brown")],
                           container: "Journal of Small Business", published: CiteDate(year: 2025, month: 6, day: 14), accessed: accessed)
paper.volume = "12"
paper.issue = "3"
paper.pages = "45–67"
paper.doi = "10.1234/jsb.2025.045"
var bureau = CitationSource(title: "Counts of Australian businesses", url: "https://www.abs.gov.au/counts", kind: .webpage,
                         authors: [.organisation("Australian Bureau of Statistics")], container: "ABS", accessed: accessed)
news.key = Citations.key(for: news, existing: [])
paper.key = Citations.key(for: paper, existing: [news.key])
bureau.key = Citations.key(for: bureau, existing: [news.key, paper.key])
same("\(news.key) \(paper.key) \(bureau.key)", "citizen2026 nguyen2025 absnd", "keys: author and year; an organisation's initials")
same(Citations.key(for: news, existing: ["citizen2026"]), "citizen2026a", "keys: a letter when taken")

same(Citations.reference(news, style: .apa), "Citizen, J., & Lee, S. (2026, November 3). Interest rates hold steady as inflation eases. *The Harbour Times*. https://example.com/news/rates", "APA: news")
same(Citations.reference(paper, style: .apa), "Nguyen, T., & Brown, A. (2025). Cash flow habits of sole traders. *Journal of Small Business*, *12*(3), 45–67. https://doi.org/10.1234/jsb.2025.045", "APA: journal")
same(Citations.reference(bureau, style: .apa), "Australian Bureau of Statistics. (n.d.). *Counts of Australian businesses*. ABS. https://www.abs.gov.au/counts", "APA: an organisation's page with no date")
same(Citations.reference(news, style: .harvard), "Citizen, J. and Lee, S. (2026) \u{2018}Interest rates hold steady as inflation eases\u{2019}, *The Harbour Times*, 3 November. Available at: https://example.com/news/rates (Accessed: 9 November 2026).", "Harvard: news")
same(Citations.reference(paper, style: .harvard), "Nguyen, T. and Brown, A. (2025) \u{2018}Cash flow habits of sole traders\u{2019}, *Journal of Small Business*, 12(3), pp. 45–67. Available at: https://doi.org/10.1234/jsb.2025.045.", "Harvard: journal")
same(Citations.reference(bureau, style: .harvard), "Australian Bureau of Statistics (no date) *Counts of Australian businesses*. Available at: https://www.abs.gov.au/counts (Accessed: 9 November 2026).", "Harvard: no date")
same(Citations.reference(news, style: .mla), "Citizen, Jane, and Sam Lee. \u{201C}Interest rates hold steady as inflation eases.\u{201D} *The Harbour Times*, 3 Nov. 2026, example.com/news/rates.", "MLA: news")
same(Citations.reference(bureau, style: .mla), "Australian Bureau of Statistics. \u{201C}Counts of Australian businesses.\u{201D} *ABS*, abs.gov.au/counts. Accessed 9 Nov. 2026.", "MLA: accessed when there's no date")
same(Citations.reference(news, style: .chicago), "Citizen, Jane, and Sam Lee. 2026. \u{201C}Interest rates hold steady as inflation eases.\u{201D} *The Harbour Times*, November 3, 2026. https://example.com/news/rates.", "Chicago: news")
same(Citations.reference(paper, style: .chicago), "Nguyen, Thi, and Alex Brown. 2025. \u{201C}Cash flow habits of sole traders.\u{201D} *Journal of Small Business* 12 (3): 45–67. https://doi.org/10.1234/jsb.2025.045.", "Chicago: journal")
same(Citations.reference(news, style: .ieee), "J. Citizen and S. Lee, \u{201C}Interest rates hold steady as inflation eases,\u{201D} *The Harbour Times*, Nov. 3, 2026. Accessed: Nov. 9, 2026. [Online]. Available: https://example.com/news/rates", "IEEE: news")
same(Citations.reference(paper, style: .ieee), "T. Nguyen and A. Brown, \u{201C}Cash flow habits of sole traders,\u{201D} *Journal of Small Business*, vol. 12, no. 3, pp. 45–67, Jun. 14, 2025, doi: 10.1234/jsb.2025.045.", "IEEE: journal")

let library = [news, paper, bureau]
same(Citations.inText([news], style: .apa, numbers: [1], letters: [:]), "(Citizen & Lee, 2026)", "in text: APA")
same(Citations.inText([paper, news], style: .apa, numbers: [2, 1], letters: [:]), "(Nguyen & Brown, 2025; Citizen & Lee, 2026)", "in text: two sources at once")
same(Citations.inText([bureau], style: .harvard, numbers: [3], letters: [:]), "(Australian Bureau of Statistics, no date)", "in text: Harvard with no date")
same(Citations.inText([news], style: .mla, numbers: [1], letters: [:]), "(Citizen and Lee)", "in text: MLA has no year")
same(Citations.inText([news], style: .chicago, numbers: [1], letters: [:]), "(Citizen and Lee 2026)", "in text: Chicago")
same(Citations.inText([paper, news], style: .ieee, numbers: [2, 1], letters: [:]), "\\[1\\], \\[2\\]", "in text: IEEE numbers, escaped for Markdown")
var crowd = news
crowd.authors = [PersonName(given: "A", family: "One"), PersonName(given: "B", family: "Two"), PersonName(given: "C", family: "Three")]
same(Citations.inText([crowd], style: .apa, numbers: [1], letters: [:]), "(One et al., 2026)", "in text: et al. for three in APA")
same(Citations.inText([crowd], style: .harvard, numbers: [1], letters: [:]), "(One, Two and Three, 2026)", "in text: three named in Harvard")
var anonymous = bureau
anonymous.authors = []
same(Citations.inText([anonymous], style: .apa, numbers: [1], letters: [:]), "(*Counts of Australian businesses*, n.d.)", "in text: the title when there's no author")

let draft = """
# Rates note

Rates held this month [see](cite:citizen2026). Sole traders keep little cash [x](cite:nguyen2025,citizen2026).
There are about 2.6 million businesses [x](cite:absnd), and one more [?](cite:ghost2020).

## References

An old list that goes.

## Next steps

Keep going.
"""
let formatted = Citations.format(draft, sources: library, style: .apa)
check(formatted.text.contains("Rates held this month [(Citizen & Lee, 2026)](cite:citizen2026)."), "document: a citation rewritten in the style")
check(formatted.text.contains("[(Nguyen & Brown, 2025; Citizen & Lee, 2026)](cite:nguyen2025,citizen2026)"), "document: several sources in one citation")
check(formatted.text.contains("[(Australian Bureau of Statistics, n.d.)](cite:absnd)"), "document: an organisation")
check(!formatted.text.contains("An old list") && formatted.text.contains("## Next steps\n\nKeep going."), "document: the old reference list replaced, the rest kept")
check(formatted.text.hasSuffix("## References\n\n" + Citations.reference(bureau, style: .apa) + "\n\n" + Citations.reference(news, style: .apa) + "\n\n" + Citations.reference(paper, style: .apa) + "\n"), "document: references at the end, A to Z")
same(formatted.missing.joined(separator: ","), "ghost2020", "document: citations with no source are reported")
same(formatted.cited.map(\.key).joined(separator: ","), "absnd,citizen2026,nguyen2025", "document: what was cited")
check(Citations.format(formatted.text, sources: library, style: .apa).text == formatted.text, "document: formatting twice changes nothing")
let numbered = Citations.format(formatted.text, sources: library, style: .ieee)
check(numbered.text.contains("this month [\\[1\\]](cite:citizen2026)") && numbered.text.contains("[\\[1\\], \\[2\\]](cite:nguyen2025,citizen2026)") && numbered.text.contains("[\\[3\\]](cite:absnd)"), "document: IEEE numbers in order of first citation")
check(numbered.text.contains("## References\n\n1. J. Citizen and S. Lee") && numbered.text.contains("\n3. Australian Bureau of Statistics, "), "document: IEEE's numbered list")
check(!numbered.text.contains("(Citizen & Lee, 2026)"), "document: switching style rewrites every citation")
let mlaVersion = Citations.format(numbered.text, sources: library, style: .mla)
check(mlaVersion.text.contains("## Works Cited") && !mlaVersion.text.contains("## References"), "document: MLA's heading replaces the old one")
let plainText = Citations.plain(numbered.text)
check(plainText.contains("Rates held this month [1].") && !plainText.contains("cite:"), "document: citations as plain words for export")
same(Citations.markers(in: "a [\\[1\\]](cite:x) b").first?.keys.joined() ?? "", "x", "document: escaped brackets in a label")
same(Citations.marker(for: [news], style: .apa), "[(Citizen & Lee, 2026)](cite:citizen2026)", "document: what Cite inserts")

var second = news
second.id = UUID()
second.title = "Banks pass on the pause"
second.key = "citizen2026a"
let lettered = Citations.format("A [x](cite:citizen2026). B [x](cite:citizen2026a).", sources: [news, second], style: .apa)
check(lettered.text.contains("A [(Citizen & Lee, 2026b)](cite:citizen2026)") && lettered.text.contains("B [(Citizen & Lee, 2026a)](cite:citizen2026a)"), "document: same authors and year get letters, by title")
check(lettered.text.contains("(2026a, November 3). Banks pass on the pause."), "document: the letter in the reference too")

// Sources saved before citations existed still load.
let oldJSON = #"[{"id":"7C1E2D3A-0000-4000-8000-000000000001","title":"Vellum","url":"https://en.wikipedia.org/wiki/Vellum","excerpt":"Vellum is…","added":"2026-01-02T03:04:05Z"}]"#
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
let old = try? decoder.decode([CitationSource].self, from: Data(oldJSON.utf8))
check(old?.first?.title == "Vellum" && old?.first?.kind == .webpage && old?.first?.accessed == ISO8601DateFormatter().date(from: "2026-01-02T03:04:05Z"), "sources: the old format loads")
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
let again = (try? encoder.encode(library)).flatMap { try? decoder.decode([CitationSource].self, from: $0) }
check(again == library, "sources: save and load")
same(bureau.host, "abs.gov.au", "sources: the host")
same(paper.link, "https://doi.org/10.1234/jsb.2025.045", "sources: the DOI is the link")

// MARK: Sourced answers

check(SourcedAnswer.citedNumbers("A [1]. B [2, 3]. C [4–5]. D [1].") == [1, 2, 3, 4, 5], "answers: every citation, once, in order")
let answer = """
Cash runway is how long a business can keep paying its costs from the cash it has [1]. Most sole traders keep less than a month in reserve [2].
The median business holds exactly forty-two days of costs at any given time. A good buffer is three months [4].
Not covered: how runway differs by industry.
"""
let review = SourcedAnswer.review(answer, sourceCount: 3)
check(review.cited == [1, 2], "answers: what's cited")
check(review.unknown == [4], "answers: a number with no source")
check(review.unsourced == ["The median business holds exactly forty-two days of costs at any given time."], "answers: a claim with no citation is flagged")
check(SourcedAnswer.sentences("It grew. [2] Then it fell [3]. Done.") == ["It grew. [2]", "Then it fell [3].", "Done."], "answers: a citation after the full stop stays with its sentence")
let prompt = SourcedAnswer.prompt(question: "What is runway?", sources: [.init(title: "Runway", url: "https://a", text: String(repeating: "x", count: 20_000))])
check(prompt.contains("[1] Runway (https://a)") && prompt.count < 10_000, "answers: sources numbered and trimmed to fit")

print(failures == 0 ? "All research checks passed." : "\(failures) research checks failed.")
exit(failures == 0 ? 0 : 1)
