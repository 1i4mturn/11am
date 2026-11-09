import AppKit
import PDFKit
import WebKit

/// Web pages as PDFs: the article alone, set like a William document, or the whole page as it looks, cut into A4 pages
/// between lines of text rather than through them.
@MainActor
enum WebPagePDF {
    struct Made {
        var document: PDFDocument
        var title: String
    }

    struct Failure: LocalizedError {
        var errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }

    static let a4 = CGSize(width: 595.28, height: 841.89)

    /// Reader view: James's article reader finds the article, William's PDF export sets it.
    static func article(_ url: URL) async throws -> Made {
        let html = try await ResearchModel.fetch(url)
        let article = ArticleReader.read(html: html, url: url)
        guard article.words >= 40 else { throw Failure("there's no article on it to keep. Try the whole page instead.") }
        var setup = PageSetup()
        setup.paper = .a4
        let data = DocPDF.data(WebPages.markdown(article), title: article.title, setup: setup, baseURL: url)
        guard let document = PDFDocument(data: data) else { throw Failure("the PDF didn't come out.") }
        return Made(document: document, title: article.title)
    }

    /// The page as Safari would print it on one long sheet, then cut into A4 pages.
    static func wholePage(_ url: URL) async throws -> Made {
        let loader = PageLoader()
        defer { loader.close() }
        try await loader.load(url)
        let web = loader.web
        let height = (try? await web.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") as? Double) ?? 0
        let tall = min(max(height, 800), 40_000)
        loader.resize(height: tall)
        try? await Task.sleep(nanoseconds: 400_000_000)
        let configuration = WKPDFConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: web.frame.width, height: tall)
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            web.createPDF(configuration: configuration) { result in continuation.resume(with: result) }
        }
        let title = (web.title?.isEmpty == false ? web.title : nil) ?? url.host ?? "Web page"
        guard let long = PDFDocument(data: data)?.page(at: 0), let document = paginate(long, title: title) else {
            throw Failure("the page didn't draw.")
        }
        return Made(document: document, title: title)
    }

    /// One tall page cut into A4 pages with a small margin, each cut just under a line of text when one is close.
    static func paginate(_ page: PDFPage, title: String) -> PDFDocument? {
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0, let source = page.pageRef else { return nil }
        let margin: CGFloat = 24
        let scale = (a4.width - margin * 2) / box.width
        let sliceHeight = (a4.height - margin * 2) / scale
        let slices = WebPages.slices(height: Double(box.height), pageHeight: Double(sliceHeight), gaps: lineBottoms(page, box: box))
        let data = NSMutableData()
        var media = CGRect(origin: .zero, size: a4)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &media, [kCGPDFContextTitle as String: title] as CFDictionary) else { return nil }
        for slice in slices {
            context.beginPDFPage(nil)
            context.saveGState()
            let shown = CGFloat(slice.upperBound - slice.lowerBound) * scale
            context.clip(to: CGRect(x: margin, y: a4.height - margin - shown, width: a4.width - margin * 2, height: shown))
            // The slice's top edge lands at the top margin.
            context.translateBy(x: margin, y: a4.height - margin)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -box.minX, y: -(box.maxY - CGFloat(slice.lowerBound)))
            context.drawPDFPage(source)
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        return PDFDocument(data: data as Data)
    }

    /// Just under each line of text, measured from the top, where a cut won't split a line.
    private static func lineBottoms(_ page: PDFPage, box: CGRect) -> [Double] {
        guard let lines = page.selection(for: box)?.selectionsByLine() else { return [] }
        return lines.prefix(4_000).map { Double(box.maxY - $0.bounds(for: page).minY) + 1 }
    }
}

/// Loads a page in a web view off screen and says when it's ready.
@MainActor
private final class PageLoader: NSObject, WKNavigationDelegate {
    let web: WKWebView
    private let window: NSWindow
    private var waiting: CheckedContinuation<Void, Error>?

    override init() {
        let frame = CGRect(x: 0, y: 0, width: 1_024, height: 1_400)
        web = WKWebView(frame: frame)
        window = NSWindow(contentRect: frame.offsetBy(dx: -30_000, dy: -30_000), styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        web.appearance = NSAppearance(named: .aqua)
        web.navigationDelegate = self
        window.contentView = web
    }

    func load(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            waiting = continuation
            web.load(URLRequest(url: url, timeoutInterval: 20))
        }
        // Late fonts and pictures.
        try? await Task.sleep(nanoseconds: 900_000_000)
    }

    func resize(height: Double) {
        window.setContentSize(CGSize(width: web.frame.width, height: height))
        web.setFrameSize(CGSize(width: web.frame.width, height: height))
    }

    func close() {
        web.stopLoading()
        window.close()
    }

    private func finish(_ error: Error?) {
        guard let waiting else { return }
        self.waiting = nil
        if let error { waiting.resume(throwing: error) } else { waiting.resume() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(nil) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(error) }
}
