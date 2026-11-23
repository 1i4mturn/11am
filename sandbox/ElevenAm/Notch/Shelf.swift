import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// The drop's shelf: files dragged up to the notch wait here, or go straight to an agent whose ring opens for them.
/// Files stay where they are on disk; the shelf only remembers where.
@MainActor
final class ShelfModel: ObservableObject {
    struct Item: Identifiable, Equatable {
        var url: URL
        var kind: ShelfKind
        var id: String { url.path }
    }

    /// What a hand-off did, shown in the drop for a moment.
    struct Handed: Identifiable, Equatable {
        var id = UUID()
        var agent: String
        var text: String
        var section: AppSection?
    }

    @Published private(set) var items: [Item] = []
    @Published var handed: Handed?
    weak var model: AppModel?
    /// Dropping a file on the 11 asks about it in the puck's note.
    var onAsk: ((URL) -> Void)?

    func load() {
        items = (JSONStore.load([String].self, from: "shelf") ?? []).compactMap(Self.item)
    }

    private func save() {
        JSONStore.save(items.map(\.url.path), to: "shelf")
    }

    static func item(_ path: String) -> Item? {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) else { return nil }
        let url = URL(fileURLWithPath: path)
        return Item(url: url, kind: ShelfKind.of(url, isFolder: isFolder.boolValue))
    }

    static func kinds(_ urls: [URL]) -> [ShelfKind] {
        urls.map { url in
            var isFolder: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
            return ShelfKind.of(url, isFolder: isFolder.boolValue)
        }
    }

    func add(_ urls: [URL]) {
        let paths = ShelfList.adding(urls.filter(\.isFileURL).map(\.path), to: items.map(\.url.path))
        items = paths.compactMap(Self.item)
        save()
    }

    func remove(_ item: Item) {
        items.removeAll { $0 == item }
        save()
    }

    func clear() {
        items = []
        save()
    }

    /// Who can take these files, and what they'd do: nil when the agent's ring stays closed.
    static func action(for urls: [URL], agent: String) -> ShelfAction? {
        ShelfRouting.action(agent: agent, kinds: kinds(urls))
    }

    /// Hands files to an agent. Files that came off the shelf leave it once they're dealt with.
    @discardableResult
    func hand(_ urls: [URL], to agent: String) -> Bool {
        guard let model, !urls.isEmpty, let action = Self.action(for: urls, agent: agent) else { return false }
        let name = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
        var section: AppSection?
        var text = ""
        switch action {
        case .ask:
            onAsk?(urls[0])
            text = "asking about \(name)"
        case .task:
            for url in urls {
                let origin = TaskOrigin(kind: .agent, monogram: "le", label: "From the shelf · \(url.lastPathComponent)", reference: "file:" + url.path)
                // Added plainly, then named, so a date in a file name doesn't become a due date.
                if let task = model.tasks.add("Look at the file", in: .inbox, origin: origin, select: false) {
                    model.tasks.update(task.id) { $0.title = "Look at \(url.deletingPathExtension().lastPathComponent)" }
                }
            }
            text = urls.count == 1 ? "added a task to look at \(name)" : "added \(urls.count) tasks, one for each file"
            section = .tasks
        case .email:
            model.mail.compose(attaching: urls)
            text = "a new email with \(name) attached"
            section = .mail
        case .write:
            model.write.importFiles(urls)
            text = "opened \(name) in Write"
            section = .write
        case .source:
            for url in urls { model.research.addSource(Self.source(from: url)) }
            model.research.tab = .sources
            text = urls.count == 1 ? "kept \(name) as a source" : "kept \(urls.count) sources"
            section = .research
        case .receipt:
            model.ledger.addReceiptFiles(urls)
            text = urls.count == 1 ? "reading \(name) for the receipt" : "reading \(urls.count) receipts"
            section = .money
        case .sheet:
            model.sheets.importURLs(urls)
            text = "opened \(name) in Sheets"
            section = .sheets
        case .deck:
            let url = urls[0]
            guard let markdown = try? DocImport.markdown(from: url), !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                handed = Handed(agent: "cr", text: "couldn't read \(name) to make a deck from it.", section: nil)
                return true
            }
            model.decks.newDeck(fromDocument: markdown, title: url.deletingPathExtension().lastPathComponent)
            text = "made a deck from \(name)"
            section = .decks
        case .photo:
            model.photo.open(urls[0])
            text = "opened \(name) in Photo"
            section = .photo
        case .video:
            model.video.add(urls)
            text = "added \(name) to Video"
            section = .video
        case .audio:
            model.audio.importFiles(urls)
            text = "added \(name) to Audio"
            section = .audio
        case .terminal:
            model.terminal.open(folder: urls[0])
            model.build.tab = .terminal
            text = "opened a terminal in \(urls[0].hasDirectoryPath ? name : urls[0].deletingLastPathComponent().lastPathComponent)"
            section = .build
        case .pdf:
            model.pdf.open(urls[0])
            text = "opened \(name) in PDF"
            section = .pdf
        case .files:
            model.browser.open(urls[0])
            text = "showing \(name) in Files"
            section = .files
        case .note:
            keepInNotes(urls, model: model)
            text = urls.count == 1 ? "kept \(name) in Notes" : "kept \(urls.count) files in a note"
            section = .notes
        }
        let shelved = Set(items.map(\.url.path))
        if urls.allSatisfy({ shelved.contains($0.path) }) {
            items.removeAll { item in urls.contains { $0.path == item.url.path } }
            save()
        }
        let code = AgentCode.brand(agent)
        if action != .ask { model.log(code, String(text.prefix(1)).uppercased() + String(text.dropFirst()) + ".") }
        if action.opensApp, let section {
            model.go(to: section)
            handed = nil
        } else {
            handed = Handed(agent: code, text: text, section: section)
        }
        return true
    }

    /// One note with the files attached: pictures show in it, anything else is a link. Very large files stay where they
    /// are and the note links to them.
    private func keepInNotes(_ urls: [URL], model: AppModel) {
        let title = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : "Files from the shelf"
        let note = model.notes.newNote(text: "# \(title)\n")
        var lines: [String] = []
        for url in urls {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let isImage = ShelfKind.of(extension: url.pathExtension) == .image
            if size <= 50 * 1_024 * 1_024, let data = try? Data(contentsOf: url), let source = model.notes.attach(data, named: url.lastPathComponent, to: note.id) {
                lines.append(isImage ? "![](\(source))" : "[\(url.lastPathComponent)](\(source))")
            } else {
                lines.append("[\(url.lastPathComponent)](\(url.absoluteString))")
            }
        }
        model.notes.update(note.id, text: "# \(title)\n\n" + lines.joined(separator: "\n") + "\n")
    }

    /// A file as a research source: the PDF's own title and author when it has them, and its text for James to read.
    static func source(from url: URL) -> CitationSource {
        var title = url.deletingPathExtension().lastPathComponent
        var authors: [PersonName] = []
        if let attributes = PDFDocument(url: url)?.documentAttributes {
            if let value = attributes[PDFDocumentAttribute.titleAttribute] as? String, !value.trimmingCharacters(in: .whitespaces).isEmpty {
                title = value
            }
            if let value = attributes[PDFDocumentAttribute.authorAttribute] as? String {
                authors = value.components(separatedBy: CharacterSet(charactersIn: ";,")).compactMap { PersonName.parse($0.trimmingCharacters(in: .whitespaces)) }
            }
        }
        return CitationSource(title: title, url: url.absoluteString, kind: .report, authors: authors, accessed: Date(),
                              excerpt: FileExcerpt.text(of: url, limit: 6_000))
    }
}

/// The readable text of a file, for asking about it: a PDF's pages, a document through the importers, plain text.
enum FileExcerpt {
    static func text(of url: URL, limit: Int = 12_000) -> String {
        switch ShelfKind.of(extension: url.pathExtension) {
        case .pdf:
            guard let document = PDFDocument(url: url) else { return "" }
            var text = ""
            for index in 0..<document.pageCount {
                text += (document.page(at: index)?.string ?? "") + "\n"
                if text.count > limit { break }
            }
            return String(text.prefix(limit))
        case .document:
            let markdown = (try? DocImport.markdown(from: url)) ?? ""
            return String(markdown.prefix(limit))
        case .code, .sheet, .calendar, .other:
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
            return String(text.prefix(limit))
        default:
            return ""
        }
    }
}

// MARK: - Views

/// A file on the shelf: its kind in Courier, its name, and a ×. Drag it to an agent or out to any app; click to open it.
struct ShelfChip: View {
    @EnvironmentObject private var shelf: ShelfModel
    var item: ShelfModel.Item

    var body: some View {
        HStack(spacing: 6) {
            Text(item.kind.rawValue)
                .font(BrandFont.label(11))
                .opacity(0.8)
            Text(ShelfList.chipName(item.url.lastPathComponent))
                .font(BrandFont.body(13, weight: .medium))
                .lineLimit(1)
            Button {
                shelf.remove(item)
            } label: {
                Text("×").font(BrandFont.body(15)).frame(width: 16, height: 16).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Take it off the shelf (the file stays where it is)")
        }
        .foregroundStyle(.white)
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 32)
        .background(Capsule().fill(BrandTokens.sheetInk))
        .contentShape(Capsule())
        .onTapGesture { NSWorkspace.shared.open(item.url) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .help(item.url.path)
    }
}

/// The shelf in the open drop, when it holds anything.
struct ShelfRow: View {
    @EnvironmentObject private var shelf: ShelfModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("shelf · \(shelf.items.count)")
                    .font(BrandFont.label(12))
                Spacer()
                Button("clear") { shelf.clear() }
                    .buttonStyle(.plain)
                    .font(BrandFont.label(12))
                    .underline()
                    .help("Empty the shelf (the files stay where they are)")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(shelf.items) { item in ShelfChip(item: item) }
                }
            }
            .frame(height: 34)
        }
        .foregroundStyle(.white)
    }
}

/// While a file is dragged over the drop: an open ring to keep it on the shelf.
struct ShelfStrip: View {
    @EnvironmentObject private var shelf: ShelfModel
    @EnvironmentObject private var state: NotchState

    private var targeted: Bool { state.dragTarget == "shelf" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(targeted ? "let go to keep it on the shelf" : "or keep it on the shelf")
                .font(BrandFont.label(12))
            if !shelf.items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(shelf.items) { item in ShelfChip(item: item) }
                    }
                }
                .frame(height: 34)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: BrandTokens.radiusNotice, style: .continuous)
                .fill(targeted ? BrandTokens.sheetInk : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: BrandTokens.radiusNotice, style: .continuous)
                .strokeBorder(Color.white, lineWidth: BrandTokens.ruleOpen)
        }
        .onDrop(of: [.fileURL], delegate: ShelfDropDelegate(target: "shelf", state: state, accepts: { true }, perform: { urls in
            shelf.add(urls)
        }))
    }
}

/// One drop target in the drop: an agent's circle or the shelf. Marks itself while a file hovers, and reads the files
/// once they're let go.
struct ShelfDropDelegate: DropDelegate {
    var target: String
    var state: NotchState
    var accepts: @MainActor () -> Bool
    var perform: @MainActor ([URL]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL]) && MainActor.assumeIsolated { accepts() }
    }

    func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated { state.dragTarget = target }
    }

    func dropExited(info: DropInfo) {
        MainActor.assumeIsolated {
            if state.dragTarget == target { state.dragTarget = nil }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: MainActor.assumeIsolated { accepts() } ? .copy : .forbidden)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard MainActor.assumeIsolated({ accepts() }) else { return false }
        let providers = info.itemProviders(for: [.fileURL])
        let fallback = MainActor.assumeIsolated { state.dragURLs }
        FileDrops.urls(from: providers) { urls in
            perform(urls.isEmpty ? fallback : urls)
            state.dropped()
        }
        return true
    }
}

// MARK: - Samples

/// Sample files for screenshots and the first look: a receipt and an agreement as PDFs, a board update, a photo.
enum SampleShelf {
    static func make() -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("11am-shelf-sample", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let receipt = folder.appendingPathComponent("Officeworks receipt.pdf")
        let agreement = folder.appendingPathComponent("Acme pilot agreement.pdf")
        let update = folder.appendingPathComponent("Board update.md")
        let photo = folder.appendingPathComponent("Lake Eildon.jpg")
        pdf("""
        OFFICEWORKS
        Tax invoice · ABN 36 004 763 526
        12 November 2026

        Printer paper A4 x5        42.50
        Whiteboard markers         18.50
        Desk lamp                  25.90

        TOTAL                      86.90
        GST included                7.90
        """, to: receipt)
        pdf("""
        Pilot agreement

        Between Acme Pty Ltd and 11am Labs.
        The pilot runs from 1 December 2026 for eight weeks.
        Fee: $12,000 plus GST, invoiced at the start, payable in 14 days.
        Either side can end the pilot with 7 days' notice in writing.
        """, to: agreement)
        try? "# Board update\n\nRevenue is up 18% on last quarter.\n\n- Acme pilot signed\n- Two hires in January\n- Runway 19 months\n"
            .write(to: update, atomically: true, encoding: .utf8)
        image(to: photo)
        return [receipt, agreement, update, photo]
    }

    private static func pdf(_ text: String, to url: URL) {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)])
            .draw(in: CGRect(x: 60, y: 60, width: 475, height: 720))
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
    }

    private static func image(to url: URL) {
        let size = NSSize(width: 1200, height: 800)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(colors: [NSColor(white: 0.85, alpha: 1), NSColor(white: 0.35, alpha: 1)])?.draw(in: NSRect(origin: .zero, size: size), angle: 90)
        NSColor(white: 0.15, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: size.width, height: 260)).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return }
        try? jpeg.write(to: url)
    }
}
