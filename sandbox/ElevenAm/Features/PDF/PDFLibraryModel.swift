import AppKit
import Foundation
import PDFKit

/// A question asked across a collection: the excerpts Bolton read and the answer citing them.
struct CollectionAsk {
    var question: String
    var run: BrainRun
    var passages: [PDFPassage]
}

/// What Bolton pulled out of the open PDF, waiting for you to send it on.
struct PDFPullOutCard: Equatable {
    var kind: PDFKind
    var invoice: InvoiceFacts?
    var contract: ContractFacts?
}

/// A PDF's pages as text, kept while the file doesn't change.
struct CachedPages {
    var modified: Date
    var pages: [String]
}

extension PDFModel {
    // MARK: Collections

    func loadCollections() {
        collections = JSONStore.load([PDFCollection].self, from: "pdf-collections") ?? []
        selectedCollection = selectedCollection ?? collections.first?.id
    }

    func saveCollections() { JSONStore.save(collections, to: "pdf-collections") }

    var currentCollection: PDFCollection? { collections.first { $0.id == selectedCollection } }

    func newCollection(named name: String? = nil) {
        var title = name ?? "New collection"
        var number = 2
        while collections.contains(where: { $0.name == title }) {
            title = "\(name ?? "New collection") \(number)"
            number += 1
        }
        let collection = PDFCollection(name: title)
        collections.insert(collection, at: 0)
        selectedCollection = collection.id
        collectionAsk = nil
        saveCollections()
    }

    func renameCollection(_ id: UUID, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].name = clean
        saveCollections()
    }

    func deleteCollection(_ id: UUID) {
        collections.removeAll { $0.id == id }
        if selectedCollection == id {
            selectedCollection = collections.first?.id
            collectionAsk = nil
        }
        saveCollections()
    }

    /// PDFs into a collection, each once. Anything that isn't a PDF is left out.
    func addFiles(_ urls: [URL], to id: UUID) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }.map(\.path)
        let new = pdfs.filter { !collections[index].files.contains($0) }
        collections[index].files += new
        saveCollections()
        if pdfs.count < urls.count { notice = "Only PDFs go in a collection; the other files were left out." }
        collectionAsk = nil
    }

    func addFilesPanel(to id: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.message = "Choose PDFs to ask questions across."
        guard panel.runModal() == .OK else { return }
        addFiles(panel.urls, to: id)
    }

    func removeFile(_ path: String, from id: UUID) {
        guard let index = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[index].files.removeAll { $0 == path }
        saveCollections()
        collectionAsk = nil
    }

    /// Each page's text, read once while the file is unchanged.
    func pages(of path: String) -> [String] {
        let modified = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
        if let cached = pageCache[path], cached.modified == modified { return cached.pages }
        guard let document = PDFDocument(url: URL(fileURLWithPath: path)), !document.isLocked else { return [] }
        let pages = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
        pageCache[path] = CachedPages(modified: modified, pages: pages)
        return pages
    }

    /// Files in the collection with no text to search (scans not yet made searchable, or locked).
    func filesWithoutText(_ collection: PDFCollection) -> [String] {
        collection.files.filter { path in !pages(of: path).contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    }

    /// Bolton finds the pages that answer it across every PDF in the collection, then answers citing each one.
    func askCollection(_ question: String) {
        let clean = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let collection = currentCollection else { return }
        guard !collection.files.isEmpty else {
            notice = "Add some PDFs to \u{201C}\(collection.name)\u{201D} first."
            return
        }
        let passages = collection.files.flatMap { PageIndex.passages(file: $0, pages: pages(of: $0)) }
        guard !passages.isEmpty else {
            notice = "There's no text in these PDFs yet. Open each one and make it searchable (in the ••• menu)."
            return
        }
        let found = PageIndex.rank(clean, passages)
        guard !found.isEmpty else {
            notice = "Nothing in \u{201C}\(collection.name)\u{201D} mentions that. Try the words the documents would use."
            return
        }
        let run = brain.run(BrainRequest(system: CollectionAnswer.system, prompt: CollectionAnswer.prompt(question: clean, passages: found), weight: .deep))
        collectionAsk = CollectionAsk(question: clean, run: run, passages: found)
    }

    /// Opens a cited page, with its first words selected when PDFKit can find them.
    func openPassage(_ passage: PDFPassage) {
        let target = URL(fileURLWithPath: passage.file)
        guard FileManager.default.fileExists(atPath: passage.file) else {
            notice = "\(passage.name) isn't where it was. Take it out of the collection and add it again."
            return
        }
        if url != target {
            if isDirty {
                notice = "Save \(title) first, then open the page."
                return
            }
            open(target)
        }
        showsCollections = false
        mode = .read
        let index = passage.page - 1
        currentPage = index
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, let document = self.document else { return }
            self.view.go(to: index)
            let words = passage.text.split(separator: " ").prefix(5).joined(separator: " ")
            guard !words.isEmpty else { return }
            if let found = document.findString(words, withOptions: .caseInsensitive)
                .first(where: { selection in selection.pages.first.map { document.index(for: $0) } == index }) {
                self.view.show(found)
            }
        }
    }

    // MARK: Pulling out what matters

    private var documentText: String {
        guard let document else { return "" }
        return (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
    }

    /// Reads the open PDF as an invoice (for George) or an agreement (for Notes).
    func pullOutDetails() {
        let text = documentText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            notice = "There's no text in this PDF yet. Make it searchable first (it's in the ••• menu)."
            return
        }
        let calendar = ledger?.book.calendar ?? .current
        switch PDFPullOut.kind(text) {
        case .invoice: pullOut = PDFPullOutCard(kind: .invoice, invoice: PDFPullOut.invoice(text, calendar: calendar))
        case .contract: pullOut = PDFPullOutCard(kind: .contract, contract: PDFPullOut.contract(text, calendar: calendar))
        case .other: pullOut = PDFPullOutCard(kind: .other)
        }
    }

    /// George's draft bill from the invoice, with the PDF kept as its receipt.
    func makeDraftBill() {
        guard let facts = pullOut?.invoice, let ledger else { return }
        guard (facts.total ?? 0) > 0 else {
            notice = "Bolton couldn't read a total from this invoice. Add the bill in Money by hand."
            return
        }
        ledger.draftBill(from: facts, file: url, name: title)
        pullOut = nil
        onOpen?(.money)
    }

    /// The agreement's key facts as a note in Notes.
    func saveKeyFacts() {
        guard let facts = pullOut?.contract, let notes else { return }
        let calendar = ledger?.book.calendar ?? .current
        notes.newNote(text: PDFPullOut.note(facts, file: url?.path ?? title + ".pdf", calendar: calendar), folder: "")
        pullOut = nil
        onOpen?(.notes)
    }

    // MARK: To William

    private var pageTexts: [String] {
        guard let document else { return [] }
        return (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
    }

    /// William translates the PDF's text into a new document, a part at a time, in your voice.
    func translate(to language: String) {
        guard let write else { return }
        let pages = pageTexts
        guard pages.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            notice = "There's no text in this PDF to translate yet. Make it searchable first (it's in the ••• menu)."
            return
        }
        write.translate(text: PDFText.markdown(title: title, pages: pages), title: title, to: language)
        onOpen?(.write)
    }

    /// The PDF's text as a William document, to edit and export again.
    func openInWrite() {
        guard let write else { return }
        let pages = pageTexts
        guard pages.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            notice = "There's no text in this PDF yet. Make it searchable first (it's in the ••• menu)."
            return
        }
        write.addDocument(text: PDFText.markdown(title: title, pages: pages))
        write.notice = "\u{201C}\(title)\u{201D} as a document. The layout is William's now; the PDF is untouched."
        onOpen?(.write)
    }

    // MARK: New PDFs

    /// A William document as a PDF, set the way Write exports it.
    func makeFromWrite(_ document: WriteDocument) {
        guard let write else { return }
        let data = write.data(for: .pdf, document: document)
        guard let made = PDFDocument(data: data) else {
            notice = "Couldn't make a PDF of \u{201C}\(document.title)\u{201D}."
            return
        }
        adopt(made, name: document.title, notice: "\u{201C}\(document.title)\u{201D} as a PDF, \(made.pageCount) \(made.pageCount == 1 ? "page" : "pages"). Save to keep it.")
    }

    /// A web page as a PDF: just the article (set like a document), or the whole page as it looks, cut into A4 pages.
    func makeFromWebPage(_ address: String, wholePage: Bool) {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), let host = url.host, host.contains(".") || host == "localhost" else {
            notice = "That doesn't look like a web address."
            return
        }
        making = "Fetching \(host)…"
        Task { @MainActor [weak self] in
            do {
                let made: WebPagePDF.Made
                if wholePage {
                    made = try await WebPagePDF.wholePage(url)
                } else {
                    made = try await WebPagePDF.article(url)
                }
                guard let self else { return }
                self.making = nil
                self.showsWebPage = false
                self.adopt(made.document, name: made.title,
                           notice: "\u{201C}\(made.title)\u{201D} as a PDF, \(made.document.pageCount) \(made.document.pageCount == 1 ? "page" : "pages"). Save to keep it.")
            } catch {
                self?.making = nil
                self?.notice = "Couldn't make a PDF of that page: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Samples

    /// For screenshots: a collection of three PDFs with an answer that cites them.
    func loadCollectionSample() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("11am sample collection", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var setup = PageSetup()
        setup.paper = .a4
        let files: [(String, String)] = [
            ("Office lease", """
            # Office lease

            Between **Harbour Properties Pty Ltd** (the landlord) and **11am Labs Pty Ltd** (the tenant), for Suite 4, 18 Mary Street, Surry Hills.

            ## Rent
            The rent is $4,600 a month, paid in advance on the first of each month. It goes up by 3% on each anniversary of the start date.

            ## Ending the lease
            The term is two years. Either party may end this lease by giving 60 days' notice in writing. If you leave before the end of the term, you pay the rent until a new tenant moves in, up to three months.

            ## Bond
            The bond is four weeks' rent, $4,246, held by the NSW Rental Bond Board until you leave.
            """),
            ("Contents insurance", """
            # Contents insurance

            Policy for 11am Labs Pty Ltd. Your excess is $500 for each claim.

            ## What's covered
            Laptops, phones and cameras, in the office and away from it, up to $40,000 in total. Furniture and fit-out in the office up to $25,000.

            ## Making a claim
            Tell us within 30 days of the loss. Keep receipts for anything over $1,000. If you move office, tell us within 14 days or the cover stops.
            """),
            ("Acme pilot agreement", """
            # Pilot agreement

            Between **11am Labs Pty Ltd** ("we") and **Acme Co** ("you").

            ## The pilot
            We give you access to 11am for 40 seats for 90 days. Either of us can end the pilot with 7 days' notice in writing.

            ## Fees
            Onboarding is $2,500. After the pilot, seats are $24 per seat per month, invoiced monthly and due within 14 days.
            """),
        ]
        var paths: [String] = []
        for (name, markdown) in files {
            let destination = folder.appendingPathComponent(name + ".pdf")
            try? DocPDF.data(markdown, title: name, setup: setup, baseURL: nil).write(to: destination)
            paths.append(destination.path)
        }
        collections.removeAll { $0.name == "Moving office" }
        var collection = PDFCollection(name: "Moving office")
        collection.files = paths
        collections.insert(collection, at: 0)
        selectedCollection = collection.id
        showsCollections = true
        let question = "If we move office, how much notice do we need to give, and what happens to the insurance?"
        let all = paths.flatMap { PageIndex.passages(file: $0, pages: pages(of: $0)) }
        func passage(_ name: String, _ words: String) -> PDFPassage? { all.first { $0.name == name && $0.text.contains(words) } }
        let lease = passage("Office lease", "60 days"), bond = passage("Office lease", "Bond Board")
        var passages = [lease, passage("Contents insurance", "move office")].compactMap { $0 }
        if let bond, bond != lease { passages.append(bond) }
        let bondMarker = bond != nil && bond != lease ? "[3]" : "[1]"
        let run = BrainRun(prompt: question)
        run.text = "The lease needs 60 days' notice in writing. The term is two years, so leaving early means paying rent until a new tenant moves in, for up to three months [1]. "
            + "Tell the insurer within 14 days of moving, or the cover stops [2]. "
            + "The $4,246 bond comes back from the Rental Bond Board when you leave \(bondMarker)."
        run.providerLabel = "On this Mac"
        run.status = .done
        collectionAsk = CollectionAsk(question: question, run: run, passages: passages)
    }

    /// For screenshots: the sample agreement with its key facts pulled out.
    func loadPullOutSample() {
        loadSample()
        pullOutDetails()
    }
}
