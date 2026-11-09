import Foundation

/// Sample sources, an article to clip, a finished look-up and a cited document, for screenshots and first runs.
extension ResearchModel {
    static func sampleSources(accessed: Date = Date()) -> [CitationSource] {
        var news = CitationSource(title: "Interest rates hold steady as inflation eases", url: "https://example.com/news/rates", kind: .news,
                                  authors: [PersonName(given: "Jane", family: "Citizen"), PersonName(given: "Sam", family: "Lee")],
                                  container: "The Harbour Times", published: CiteDate(year: 2026, month: 11, day: 3), accessed: accessed,
                                  excerpt: "The Reserve Bank left the cash rate unchanged on Tuesday, saying inflation had eased faster than it expected. For a small business with a variable loan, repayments stay where they are for at least another month.")
        news.key = "citizen2026"
        var paper = CitationSource(title: "Cash flow habits of sole traders", url: "https://journals.example/jsb/45", kind: .journal,
                                   authors: [PersonName(given: "Thi", family: "Nguyen"), PersonName(given: "Alex", family: "Brown")],
                                   container: "Journal of Small Business", published: CiteDate(year: 2025, month: 6, day: 14), accessed: accessed,
                                   excerpt: "We surveyed 1,200 sole traders about how they manage cash, and found that most keep less than a month of costs in reserve.")
        paper.volume = "12"
        paper.issue = "3"
        paper.pages = "45–67"
        paper.doi = "10.1234/jsb.2025.045"
        paper.key = "nguyen2025"
        var counts = CitationSource(title: "Counts of Australian businesses", url: "https://www.abs.gov.au/counts", kind: .webpage,
                                    authors: [.organisation("Australian Bureau of Statistics")], container: "ABS", accessed: accessed,
                                    excerpt: "There were about 2.6 million actively trading businesses in the Australian economy.")
        counts.key = "absnd"
        var runway = CitationSource(title: "Runway (finance)", url: "https://en.wikipedia.org/wiki/Runway_(finance)", kind: .webpage,
                                    container: "Wikipedia", published: CiteDate(year: 2026, month: 10, day: 2), accessed: accessed,
                                    excerpt: "In finance, runway is the amount of time a company has before it runs out of money, at its current rate of spending.")
        runway.key = "runway2026"
        var book = CitationSource(title: "The solo operator's handbook", kind: .book, authors: [PersonName(given: "Priya", family: "Raman")],
                                  container: "Harbour Press", published: CiteDate(year: 2024), accessed: accessed)
        book.key = "raman2024"
        return [news, paper, counts, runway, book]
    }

    /// Fills the sources (keeping any you have) and shows a sample article in the browser.
    func loadSample() {
        for source in Self.sampleSources() where !library.contains(where: { $0.key == source.key }) {
            library.append(source)
        }
        saveLibrary()
        let url = URL(string: "https://example.com/news/rates")!
        sampleURL = url
        address = url.absoluteString
        webView.loadHTMLString(Self.sampleArticle, baseURL: url)
    }

    /// A finished look-up in the agent pane, with one sentence James couldn't source.
    func showSampleLookUp() {
        let sources = Self.sampleSources()
        let lookup = LookUp(question: "How much cash runway should a sole trader keep?")
        lookup.sources = [sources[3], sources[1], sources[0]]
        let run = BrainRun(prompt: lookup.question)
        run.text = """
        Runway is how long a business can keep paying its costs from the cash it has, at its current rate of spending [1]. A survey of 1,200 sole traders found most keep less than a month of costs in reserve [2]. With rates on hold, repayments on variable loans stay where they are for now, which gives owners room to build a buffer [3]. Most advisers suggest keeping three to six months of costs.

        Not covered: how much runway differs by industry.
        """
        run.providerLabel = "On this Mac"
        run.isLocal = true
        run.status = .done
        lookup.run = run
        lookup.review = SourcedAnswer.review(run.text, sourceCount: lookup.sources.count)
        lookup.stage = .done
        self.lookup = lookup
        onShowPane?()
    }

    /// A short document in Write with its citations and references in your style.
    func writeSampleDocument() {
        if library.isEmpty { loadSample() }
        let draft = """
        # Cash runway for sole traders

        Runway is how long a business can keep paying its costs from the cash it has [x](cite:runway2026). Most sole traders keep less than a month of costs in reserve [x](cite:nguyen2025), and there are about 2.6 million businesses chasing the same customers [x](cite:absnd).

        ## What changed this month

        The Reserve Bank left the cash rate on hold [x](cite:citizen2026), so repayments on variable loans stay where they are. That gives owners a month to plan.

        ## What to do

        - Work out a month of costs, including tax and super.
        - Keep three months aside before you take on staff.
        - Check it again each quarter, when the BAS is done.
        """
        write.addDocument(text: Citations.format(draft, sources: library, style: style).text)
    }

    /// The sample sources on a slide at the end of the open deck, and one cited on the slide before.
    func addSampleSourcesSlide() {
        if library.isEmpty { loadSample() }
        guard let decks, let deck = decks.deck else { return }
        let picked = library.filter { ["nguyen2025", "absnd", "citizen2026"].contains($0.key) }
        addSourcesSlide(picked)
        if let index = deck.slides.lastIndex(where: { $0.layout == .bullets || $0.layout == .chart }) {
            decks.showSlide(index)
            if let paper = picked.first(where: { $0.key == "nguyen2025" }) { citeOnSlide(paper) }
        }
        decks.showSlide((decks.deck?.slides.count ?? 1) - 1)
    }

    static let sampleArticle = """
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8">
    <title>Interest rates hold steady as inflation eases | The Harbour Times</title>
    <meta property="og:site_name" content="The Harbour Times">
    <meta property="og:title" content="Interest rates hold steady as inflation eases">
    <meta property="article:published_time" content="2026-11-03T14:30:00+11:00">
    <script type="application/ld+json">{"@context":"https://schema.org","@type":"NewsArticle","headline":"Interest rates hold steady as inflation eases","datePublished":"2026-11-03T14:30:00+11:00","author":[{"@type":"Person","name":"Jane Citizen"},{"@type":"Person","name":"Sam Lee"}],"publisher":{"@type":"Organization","name":"The Harbour Times"}}</script>
    <style>
    body { font: 17px/1.6 Georgia, serif; color: #1d1d1f; background: #fff; margin: 0; }
    .masthead { font: 600 13px -apple-system, system-ui; letter-spacing: 0.08em; text-transform: uppercase; padding: 14px 28px; border-bottom: 1px solid #e6e6e6; display: flex; gap: 22px; }
    .masthead b { margin-right: auto; letter-spacing: 0.02em; text-transform: none; font: 700 19px Georgia, serif; }
    .masthead span { color: #777; }
    article { max-width: 640px; margin: 34px auto; padding: 0 28px; }
    h1 { font-size: 36px; line-height: 1.15; margin: 0 0 10px; letter-spacing: -0.5px; }
    .byline { font: 13px -apple-system, system-ui; color: #666; margin-bottom: 26px; }
    figure { margin: 26px 0; } .chart { height: 150px; border-radius: 6px; background: linear-gradient(180deg, #f2f2f0, #e4e4e0); position: relative; overflow: hidden; }
    .chart i { position: absolute; bottom: 0; width: 9%; background: #1d1d1f; border-radius: 3px 3px 0 0; }
    figcaption { font: 12px -apple-system, system-ui; color: #777; margin-top: 6px; }
    blockquote { margin: 22px 0; padding-left: 18px; border-left: 3px solid #1d1d1f; font-style: italic; }
    aside { font: 13px -apple-system, system-ui; border-top: 1px solid #e6e6e6; margin-top: 30px; padding-top: 12px; color: #777; }
    .cookie { position: fixed; bottom: 0; left: 0; right: 0; background: #1d1d1f; color: #fff; font: 13px -apple-system, system-ui; padding: 10px 28px; }
    </style></head><body>
    <div class="masthead"><b>The Harbour Times</b><span>News</span><span>Business</span><span>Money</span><span>Opinion</span></div>
    <article>
    <h1>Interest rates hold steady as inflation eases</h1>
    <p class="byline">By Jane Citizen and Sam Lee · 3 November 2026</p>
    <p>The <a href="/rba">Reserve Bank</a> left the cash rate unchanged on Tuesday, saying inflation had eased faster than it expected, though rents and insurance were still rising.</p>
    <figure><div class="chart"><i style="left:4%;height:30%"></i><i style="left:16%;height:55%"></i><i style="left:28%;height:80%"></i><i style="left:40%;height:92%"></i><i style="left:52%;height:92%"></i><i style="left:64%;height:86%"></i><i style="left:76%;height:80%"></i><i style="left:88%;height:80%"></i></div><figcaption>The cash rate since 2020</figcaption></figure>
    <p>Economists had expected the pause, and most now think the next move, whenever it comes, will be down rather than up, which would help households and small businesses alike.</p>
    <h2>What it means</h2>
    <p>For a small business with a variable loan, repayments stay where they are for at least another month, giving owners some room to plan, hire, or build a buffer of cash.</p>
    <blockquote>We are not declaring victory yet, but the trend is clearly in the right direction.</blockquote>
    <aside>Related: Housing prices · What the budget means for you</aside>
    </article>
    <div class="cookie">We use cookies to make this site work.</div>
    </body></html>
    """
}
