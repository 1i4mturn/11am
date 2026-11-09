import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Bolton's PDF app: read and search, mark up and sign, fill in forms, reorganise pages, and change the file.
struct PDFAppView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var pdf: PDFModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    @State private var search = ""
    @State private var results: [PDFSelection] = []
    @State private var resultIndex = 0
    @State private var showingProtect = false
    @State private var showingSplit = false
    @State private var asking = UserDefaults.standard.bool(forKey: "pdfAsk")
    @State private var dropTargeted = false
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "pdf", subtitle: subtitle) {
                HStack(spacing: 8) {
                    if pdf.document != nil && !pdf.showsCollections { searchField.frame(width: 190) }
                    Button { pdf.showsCollections.toggle() } label: {
                        Label(pdf.showsCollections && pdf.document != nil ? "Back to \(pdf.title)" : "Collections",
                              systemImage: pdf.showsCollections && pdf.document != nil ? "chevron.left" : "books.vertical")
                            .lineLimit(1)
                    }
                    .buttonStyle(.vellumSecondary)
                    .help("Ask questions across a set of PDFs")
                    Button { pdf.openPanel() } label: { Label("Open", systemImage: "doc") }
                        .buttonStyle(.vellumSecondary)
                        .keyboardShortcut("o", modifiers: .command)
                    NewPDFMenu()
                    if pdf.document != nil && !pdf.showsCollections {
                        documentMenu
                        Button { pdf.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                            .buttonStyle(.vellumPrimary)
                            .keyboardShortcut("s", modifiers: .command)
                            .disabled(!pdf.isDirty && pdf.url != nil)
                    }
                }
            }

            if let notice = pdf.notice {
                PDFBanner(text: notice) { pdf.notice = nil }
                    .transition(.rise(theme.rise))
            }
            if pdf.document?.isLocked == true {
                HStack(spacing: 8) {
                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onSubmit { pdf.unlock(password) }
                    Button("Unlock") { pdf.unlock(password) }
                        .buttonStyle(.vellumPrimary)
                }
            }

            if pdf.showsCollections {
                PDFCollectionsView()
            } else if pdf.document == nil {
                EmptyPDF(dropTargeted: dropTargeted)
            } else {
                toolbar
                if pdf.redactionCount > 0 || pdf.tool == .redact {
                    RedactionBar()
                        .transition(.rise(theme.rise))
                }
                if pdf.mode == .read {
                    HStack(alignment: .top, spacing: 12) {
                        ThumbnailStrip(controller: pdf.view, revision: pdf.revision)
                            .frame(width: 112)
                        PDFCanvas()
                            .background {
                                RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous)
                                    .fill(theme.ink(scheme).opacity(scheme == .dark ? 0.25 : 0.04))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous))
                        if asking {
                            AskPDFPanel()
                                .frame(width: 260)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                } else {
                    PageGrid()
                }
            }
        }
        .padding(24)
        .animation(theme.spring, value: pdf.notice)
        .animation(theme.spring, value: asking)
        .animation(theme.spring, value: pdf.mode)
        .animation(theme.spring, value: pdf.showsCollections)
        .animation(theme.spring, value: pdf.redactionCount)
        .onChange(of: asking) { _, value in UserDefaults.standard.set(value, forKey: "pdfAsk") }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            Task { @MainActor in await openDropped(providers) }
            return true
        }
        .sheet(item: $pdf.placement) { placement in
            PlacementSheet(placement: placement)
                .environmentObject(pdf)
                .environmentObject(theme)
        }
        .sheet(isPresented: $pdf.editingSignature) {
            SignatureSheet()
                .environmentObject(pdf)
                .environmentObject(theme)
        }
        .sheet(isPresented: $showingProtect) {
            ProtectSheet()
                .environmentObject(pdf)
                .environmentObject(theme)
        }
        .sheet(isPresented: $showingSplit) {
            SplitSheet()
                .environmentObject(pdf)
                .environmentObject(theme)
        }
        .sheet(isPresented: $pdf.showsWebPage) {
            WebPagePDFSheet()
                .environmentObject(pdf)
                .environmentObject(theme)
        }
        .task(id: pdf.notice) {
            guard pdf.notice != nil, (try? await Task.sleep(for: .seconds(10))) != nil else { return }
            pdf.notice = nil
        }
    }

    private var subtitle: String {
        if pdf.showsCollections { return "Ask across a set of PDFs, with the page for every answer" }
        guard let document = pdf.document else { return "Read, mark up, sign, fill in and fix PDFs" }
        var parts = ["\(pdf.title)\(pdf.isDirty ? " · edited" : "")", "\(document.pageCount) \(document.pageCount == 1 ? "page" : "pages")"]
        if let url = pdf.url, let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(theme.inkTertiary(scheme))
            TextField("Find in PDF", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .onSubmit(find)
            if !results.isEmpty {
                Text("\(resultIndex + 1)/\(results.count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(theme.inkTertiary(scheme))
                Button { step(1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkSecondary(scheme))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background { Capsule().fill(theme.well(scheme)) }
        .overlay { Capsule().strokeBorder(theme.edge(scheme), lineWidth: 0.5) }
    }

    private func find() {
        guard let document = pdf.document, !search.isEmpty else {
            results = []
            pdf.view.highlightAll([])
            return
        }
        results = document.findString(search, withOptions: .caseInsensitive)
        resultIndex = 0
        pdf.view.highlightAll(results)
        if let first = results.first {
            pdf.mode = .read
            pdf.view.show(first)
        } else {
            pdf.notice = "\u{201C}\(search)\u{201D} isn't in this PDF."
        }
    }

    private func step(_ by: Int) {
        guard !results.isEmpty else { return }
        resultIndex = (resultIndex + by + results.count) % results.count
        pdf.view.show(results[resultIndex])
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            Picker("", selection: $pdf.mode) {
                ForEach(PDFMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.trailing, 8)
            if pdf.mode == .read {
                ForEach(PDFTool.allCases) { tool in
                    ToolButton(symbol: tool.symbol, help: tool.title, on: pdf.tool == tool) {
                        pdf.tool = tool
                        if tool == .sign && pdf.signature == nil { pdf.editingSignature = true }
                    }
                }
                Spacer(minLength: 8)
                ToolButton(symbol: "minus.magnifyingglass", help: "Zoom out") { pdf.view.zoomOut() }
                ToolButton(symbol: "plus.magnifyingglass", help: "Zoom in") { pdf.view.zoomIn() }
                Menu {
                    Picker("Pages", selection: $pdf.displayMode) {
                        Text("Single page").tag(PDFDisplayMode.singlePage)
                        Text("Continuous").tag(PDFDisplayMode.singlePageContinuous)
                        Text("Two pages").tag(PDFDisplayMode.twoUp)
                        Text("Two pages, continuous").tag(PDFDisplayMode.twoUpContinuous)
                    }
                    Button("Fit to width") { pdf.view.fit() }
                    if let outline = outlineItems, !outline.isEmpty {
                        Divider()
                        Section("Contents") {
                            ForEach(Array(outline.enumerated()), id: \.offset) { _, item in
                                Button(item.title) { pdf.view.go(to: item.page) }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(width: 28)
                .help("Page layout and contents")
                ToolButton(symbol: pdf.isSpeaking ? "speaker.slash" : "speaker.wave.2", help: pdf.isSpeaking ? "Stop reading" : "Read this page (or the selection) aloud",
                           on: pdf.isSpeaking) { pdf.readAloud() }
                ToolButton(symbol: "sparkle.magnifyingglass", help: "Ask Bolton about this PDF", on: asking) { asking.toggle() }
            } else {
                ToolButton(symbol: "rotate.left", help: "Rotate left") { pdf.rotate(-90) }
                ToolButton(symbol: "rotate.right", help: "Rotate right") { pdf.rotate(90) }
                ToolButton(symbol: "plus.square.on.square", help: "Duplicate") { pdf.duplicatePages() }
                ToolButton(symbol: "trash", help: "Delete") { pdf.deletePages() }
                Divider().frame(height: 16).padding(.horizontal, 4)
                Button("Insert…") { pdf.insertPanel() }
                    .buttonStyle(.vellumSecondary)
                Button("Save pages as…") { pdf.extractPages() }
                    .buttonStyle(.vellumSecondary)
                Button("Split…") { showingSplit = true }
                    .buttonStyle(.vellumSecondary)
                Spacer(minLength: 8)
                Text(pdf.selectedPages.isEmpty ? "Click to pick pages, ⌘-click for more, drag to reorder" : "\(pdf.selectedPages.count) picked")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .lineLimit(1)
            }
        }
    }

    /// The document's contents (bookmarks), two levels deep.
    private var outlineItems: [(title: String, page: Int)]? {
        guard let document = pdf.document, let root = document.outlineRoot else { return nil }
        var items: [(title: String, page: Int)] = []
        func visit(_ node: PDFOutline, depth: Int) {
            for index in 0..<node.numberOfChildren {
                guard let child = node.child(at: index) else { continue }
                if let page = child.destination?.page {
                    items.append((String(repeating: "   ", count: depth) + (child.label ?? "Untitled"), document.index(for: page)))
                }
                if depth < 1 { visit(child, depth: depth + 1) }
            }
        }
        visit(root, depth: 0)
        return items
    }

    private var documentMenu: some View {
        Menu {
            Button("Save a copy…") { pdf.saveAs() }
            Divider()
            Button("Compress…") { pdf.compress() }
            Button("Protect with a password…") { showingProtect = true }
            Button("Flatten marks and form answers…") { pdf.flatten() }
            Button("Remove hidden details (author, title)…") { pdf.removeMetadata() }
            Button("Make scanned pages searchable…") { pdf.makeSearchable() }
            Divider()
            Menu("Translate into") {
                ForEach(DocShape.languages, id: \.self) { language in
                    Button(language) { pdf.translate(to: language) }
                }
            }
            Button("Open the text in Write") { pdf.openInWrite() }
            if let collection = pdf.currentCollection, let url = pdf.url, !collection.files.contains(url.path) {
                Button("Add to \u{201C}\(collection.name)\u{201D}") { pdf.addFiles([url], to: collection.id) }
            }
            Divider()
            Button("Split into parts…") { showingSplit = true }
            Button("Change my signature…") { pdf.editingSignature = true }
            Button("Show in Finder") { if let url = pdf.url { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                .disabled(pdf.url == nil)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(theme.inkSecondary(scheme))
        .help("Compress, protect, flatten, clean up, split")
    }

    private func openDropped(_ providers: [NSItemProvider]) async {
        var urls: [URL] = []
        for provider in providers {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
               let fileURL = URL(dataRepresentation: url, relativeTo: nil) {
                urls.append(fileURL)
            }
        }
        guard !urls.isEmpty else { return }
        if urls.count == 1, urls[0].pathExtension.lowercased() == "pdf", pdf.document == nil || !pdf.isDirty {
            pdf.open(urls[0])
        } else if let document = pdf.document {
            do {
                try PDFEngine.insert(urls, into: document, at: document.pageCount)
                pdf.changed()
                pdf.notice = "Added \(urls.count) \(urls.count == 1 ? "file" : "files") at the end."
            } catch {
                pdf.notice = error.localizedDescription
            }
        } else if let first = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) {
            pdf.open(first)
        }
    }
}

private struct PDFBanner: View {
    @EnvironmentObject private var theme: Theme
    @Environment(\.colorScheme) private var scheme
    var text: String
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AgentLogo(code: "bn", size: 18, color: theme.inkSecondary(scheme))
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.ink(scheme))
                .lineLimit(2)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(theme.inkTertiary(scheme))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background { RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).fill(theme.well(scheme)) }
        .overlay { RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5) }
    }
}

private struct RedactionBar: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var pdf: PDFModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.fill").foregroundStyle(theme.ink(scheme))
            Text(pdf.redactionCount == 0
                 ? "Drag over anything to hide it. Nothing changes until you apply."
                 : "\(pdf.redactionCount) \(pdf.redactionCount == 1 ? "area" : "areas") marked. Applying removes what's underneath for good, in a copy, then checks it.")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.ink(scheme))
                .lineLimit(2)
            Spacer()
            if pdf.redactionCount > 0 {
                Button("Clear") { pdf.clearRedactions() }
                    .buttonStyle(.vellumSecondary)
                Button("Apply redactions…") { pdf.applyRedactions() }
                    .buttonStyle(.vellumPrimary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background { RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).fill(theme.well(scheme)) }
        .overlay { RoundedRectangle(cornerRadius: max(theme.radius - 4, 8), style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5) }
    }
}

private struct EmptyPDF: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var pdf: PDFModel
    @Environment(\.colorScheme) private var scheme
    var dropTargeted: Bool

    var body: some View {
        VStack(spacing: 16) {
            AgentLogo(code: "bn", size: 48, color: theme.inkTertiary(scheme))
            Text("Drop a PDF here")
                .font(theme.display(24))
                .foregroundStyle(theme.ink(scheme))
            Text("Read it, highlight and sign it, fill in its forms, move its pages around, or make it smaller, private or redacted. Nothing leaves this Mac unless you ask Bolton about it with a cloud brain.")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.inkSecondary(scheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            HStack(spacing: 8) {
                Button("Open a PDF…") { pdf.openPanel() }
                    .buttonStyle(.vellumPrimary)
                Button("A web page as a PDF…") { pdf.showsWebPage = true }
                    .buttonStyle(.vellumSecondary)
                Button("Try a sample agreement") { pdf.loadSample() }
                    .buttonStyle(.vellumSecondary)
            }
            if !pdf.recent.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(text: "Recent")
                    ForEach(pdf.recent.prefix(5), id: \.self) { url in
                        Button {
                            pdf.open(url)
                        } label: {
                            Label(url.deletingPathExtension().lastPathComponent, systemImage: "doc.richtext")
                                .font(.system(size: 12.5))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.ink(scheme))
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: max(theme.radius - 2, 8), style: .continuous)
                .strokeBorder(theme.ink(scheme).opacity(dropTargeted ? 0.5 : 0.15), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        }
    }
}

// MARK: The page view

final class MarkupPDFView: PDFView {
    var tool: PDFTool = .select
    var markColor: NSColor = .yellow
    var onMark: (() -> Void)?
    var onPlace: ((PDFTool, Int, CGPoint) -> Void)?
    var onSign: ((Int, CGPoint) -> Void)?
    var onRedact: ((CGRect, Int) -> Void)?
    private var activePage: PDFPage?
    private var points: [CGPoint] = []
    private var start: CGPoint?
    private var preview: PDFAnnotation?

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard let document, let page = page(for: location, nearest: true) else { return super.mouseDown(with: event) }
        let point = convert(location, to: page)
        let index = document.index(for: page)
        switch tool {
        case .select, .highlight, .underline, .strike:
            super.mouseDown(with: event)
        case .note, .text:
            onPlace?(tool, index, point)
        case .sign:
            onSign?(index, point)
        case .draw:
            activePage = page
            points = [point]
        case .redact:
            activePage = page
            start = point
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let page = activePage else { return super.mouseDragged(with: event) }
        let point = convert(convert(event.locationInWindow, from: nil), to: page)
        switch tool {
        case .draw:
            points.append(point)
            showPreview(ink(points), on: page)
        case .redact:
            if let start { showPreview(box(Self.rect(start, point)), on: page) }
        default:
            super.mouseDragged(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            activePage = nil
            start = nil
            points = []
        }
        switch tool {
        case .draw:
            guard let page = activePage else { return }
            removePreview()
            if points.count > 1 {
                page.addAnnotation(ink(points))
                onMark?()
            }
        case .redact:
            guard let page = activePage, let start, let document else { return }
            removePreview()
            let end = convert(convert(event.locationInWindow, from: nil), to: page)
            onRedact?(Self.rect(start, end), document.index(for: page))
        case .highlight, .underline, .strike:
            super.mouseUp(with: event)
            guard let selection = currentSelection, !(selection.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let type: PDFAnnotationSubtype = tool == .highlight ? .highlight : (tool == .underline ? .underline : .strikeOut)
            PDFEngine.markup(selection, type: type, color: markColor)
            clearSelection()
            onMark?()
        default:
            super.mouseUp(with: event)
        }
    }

    private static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func ink(_ points: [CGPoint]) -> PDFAnnotation {
        let xs = points.map(\.x), ys = points.map(\.y)
        let bounds = CGRect(x: (xs.min() ?? 0) - 4, y: (ys.min() ?? 0) - 4,
                            width: (xs.max() ?? 0) - (xs.min() ?? 0) + 8, height: (ys.max() ?? 0) - (ys.min() ?? 0) + 8)
        let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        let path = NSBezierPath()
        for (index, point) in points.enumerated() {
            let local = NSPoint(x: point.x - bounds.minX, y: point.y - bounds.minY)
            if index == 0 { path.move(to: local) } else { path.line(to: local) }
        }
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        annotation.add(path)
        annotation.color = markColor
        let border = PDFBorder()
        border.lineWidth = 2
        annotation.border = border
        return annotation
    }

    private func box(_ rect: CGRect) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: rect, forType: .square, withProperties: nil)
        annotation.color = NSColor(calibratedWhite: 0, alpha: 0.75)
        annotation.interiorColor = NSColor(calibratedWhite: 0, alpha: 0.35)
        return annotation
    }

    private func showPreview(_ annotation: PDFAnnotation, on page: PDFPage) {
        removePreview()
        page.addAnnotation(annotation)
        preview = annotation
    }

    private func removePreview() {
        if let preview { preview.page?.removeAnnotation(preview) }
        preview = nil
    }
}

private struct PDFCanvas: NSViewRepresentable {
    @EnvironmentObject private var pdf: PDFModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MarkupPDFView {
        let view = MarkupPDFView()
        view.autoScales = true
        view.displayMode = pdf.displayMode
        view.displaysPageBreaks = true
        view.backgroundColor = .clear
        view.pageShadowsEnabled = true
        view.document = pdf.document
        pdf.view.view = view
        let model = pdf
        view.onMark = { model.changed() }
        view.onPlace = { tool, page, point in model.placement = PDFPlacement(tool: tool, page: page, point: point) }
        view.onSign = { page, point in model.sign(page: page, at: point) }
        view.onRedact = { rect, page in model.addRedaction(rect, page: page) }
        context.coordinator.observer = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak view] _ in
            MainActor.assumeIsolated {
                guard let view, let page = view.currentPage, let document = view.document else { return }
                let index = document.index(for: page)
                if model.currentPage != index { model.currentPage = index }
            }
        }
        context.coordinator.revision = pdf.revision
        return view
    }

    func updateNSView(_ view: MarkupPDFView, context: Context) {
        pdf.view.view = view
        if view.document !== pdf.document {
            view.document = pdf.document
        } else if context.coordinator.revision != pdf.revision {
            view.layoutDocumentView()
        }
        context.coordinator.revision = pdf.revision
        if view.displayMode != pdf.displayMode { view.displayMode = pdf.displayMode }
        view.tool = pdf.tool
        view.markColor = pdf.markColor
    }

    final class Coordinator {
        var observer: NSObjectProtocol?
        var revision = 0

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}

private struct ThumbnailStrip: NSViewRepresentable {
    var controller: PDFViewController
    var revision: Int

    func makeNSView(context: Context) -> PDFThumbnailView {
        let strip = PDFThumbnailView()
        strip.thumbnailSize = CGSize(width: 84, height: 112)
        strip.backgroundColor = .clear
        strip.maximumNumberOfColumns = 1
        strip.pdfView = controller.view
        return strip
    }

    func updateNSView(_ strip: PDFThumbnailView, context: Context) {
        if strip.pdfView !== controller.view { strip.pdfView = controller.view }
        _ = revision
    }
}

// MARK: Pages

private struct PageGrid: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var pdf: PDFModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 18)], spacing: 18) {
                ForEach(0..<(pdf.document?.pageCount ?? 0), id: \.self) { index in
                    PageTile(index: index, revision: pdf.revision, selected: pdf.selectedPages.contains(index))
                        .onTapGesture(count: 2) {
                            pdf.mode = .read
                            pdf.selectedPages = []
                            DispatchQueue.main.async { pdf.view.go(to: index) }
                        }
                        .onTapGesture { pick(index) }
                        .draggable("\(index)")
                        .dropDestination(for: String.self) { items, _ in
                            let dragged = IndexSet(items.compactMap(Int.init))
                            guard !dragged.isEmpty, !dragged.contains(index) else { return false }
                            let moving = pdf.selectedPages.contains(dragged.first ?? -1) ? pdf.selectedPages : dragged
                            withAnimation(theme.spring) { pdf.movePages(moving, to: index > (moving.first ?? 0) ? index + 1 : index) }
                            return true
                        }
                }
            }
            .padding(6)
        }
        .scrollContentBackground(.hidden)
    }

    private func pick(_ index: Int) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if pdf.selectedPages.contains(index) { pdf.selectedPages.remove(index) } else { pdf.selectedPages.insert(index) }
        } else if flags.contains(.shift), let anchor = pdf.selectedPages.first {
            pdf.selectedPages = IndexSet(integersIn: min(anchor, index)...max(anchor, index))
        } else {
            pdf.selectedPages = pdf.selectedPages == IndexSet(integer: index) ? [] : IndexSet(integer: index)
        }
    }
}

private struct PageTile: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var pdf: PDFModel
    @Environment(\.colorScheme) private var scheme
    var index: Int
    var revision: Int
    var selected: Bool
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle().fill(Color.white).aspectRatio(0.71, contentMode: .fit)
                }
            }
            .frame(height: 170)
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            .overlay {
                RoundedRectangle(cornerRadius: 3).strokeBorder(selected ? theme.ink(scheme) : Color.clear, lineWidth: 2.5)
                    .padding(-4)
            }
            Text("\(index + 1)")
                .font(.system(size: 11.5, weight: selected ? .bold : .regular).monospacedDigit())
                .foregroundStyle(selected ? theme.ink(scheme) : theme.inkSecondary(scheme))
        }
        .contentShape(Rectangle())
        .task(id: "\(revision)-\(index)") {
            image = pdf.document?.page(at: index)?.thumbnail(of: CGSize(width: 240, height: 340), for: .cropBox)
        }
    }
}

// MARK: Ask

private struct AskPDFPanel: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var pdf: PDFModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    @State private var question = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AgentLogo(code: "bn", size: 20)
                Text("Ask this PDF")
                    .font(theme.display(17))
                    .foregroundStyle(theme.ink(scheme))
            }
            FlowLayout(spacing: 6) {
                Button("Summary") { pdf.ask(.summary) }
                Button("Key points") { pdf.ask(.keyPoints) }
                Button("Dates, money, obligations") { pdf.ask(.details) }
                Button("For George or Notes") { pdf.pullOutDetails() }
                    .help("An invoice becomes a draft bill; an agreement's key facts become a note")
            }
            .buttonStyle(.vellumSecondary)
            .disabled(brain.isBusy)
            AskField(placeholder: "When can either side end it?", text: $question) {
                guard !question.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                pdf.ask(.question, question: question)
            }
            if let card = pdf.pullOut {
                ScrollView {
                    PDFPullOutView(card: card).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let run = pdf.askRun {
                ScrollView {
                    RunView(run: run).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Answers cite their pages. Bolton reads only this document's text.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .vellum(level: 3, radius: max(theme.radius - 2, 8))
    }
}

// MARK: Sheets

private struct PlacementSheet: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var pdf: PDFModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    var placement: PDFPlacement
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(placement.tool == .note ? "Sticky note" : "Text box")
                .font(theme.display(20))
                .foregroundStyle(theme.ink(scheme))
            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 110)
                .background { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.well(scheme)) }
                .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.edge(scheme), lineWidth: 0.5) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.vellumSecondary)
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    pdf.place(text, at: placement)
                    dismiss()
                }
                .buttonStyle(.vellumPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

/// Draw your signature with the trackpad or mouse, or type it. Kept on this Mac for next time.
private struct SignatureSheet: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var pdf: PDFModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var typing = false
    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var name = ""

    private let canvas = CGSize(width: 360, height: 140)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your signature")
                .font(theme.display(20))
                .foregroundStyle(theme.ink(scheme))
            Picker("", selection: $typing) {
                Text("Draw").tag(false)
                Text("Type").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if typing {
                TextField("Your name", text: $name)
                    .textFieldStyle(.roundedBorder)
                Text(name.isEmpty ? " " : name)
                    .font(.custom("SnellRoundhand-Bold", size: 34))
                    .foregroundStyle(Color(red: 0.05, green: 0.1, blue: 0.3))
                    .frame(width: canvas.width, height: 70)
                    .background(Color.white)
            } else {
                Canvas { context, _ in
                    for stroke in strokes + [current] where stroke.count > 1 {
                        var path = Path()
                        path.addLines(stroke)
                        context.stroke(path, with: .color(Color(red: 0.05, green: 0.1, blue: 0.3)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    }
                }
                .frame(width: canvas.width, height: canvas.height)
                .background(Color.white)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.black.opacity(0.15)).frame(height: 1).padding(.horizontal, 20).padding(.bottom, 30)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in current.append(value.location) }
                        .onEnded { _ in
                            if current.count > 1 { strokes.append(current) }
                            current = []
                        }
                )
                Text("Sign with your trackpad or mouse.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
            HStack {
                Button("Clear") {
                    strokes = []
                    name = ""
                }
                .buttonStyle(.vellumSecondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.vellumSecondary)
                    .keyboardShortcut(.cancelAction)
                Button("Use this signature") {
                    if typing {
                        pdf.signature = SavedSignature(typed: name.trimmingCharacters(in: .whitespaces))
                    } else {
                        pdf.signature = SavedSignature(strokes: strokes.map { $0.map { [Double($0.x), Double($0.y)] } },
                                                       width: Double(canvas.width), height: Double(canvas.height))
                    }
                    pdf.tool = .sign
                    pdf.notice = "Click where it goes."
                    dismiss()
                }
                .buttonStyle(.vellumPrimary)
                .disabled(typing ? name.trimmingCharacters(in: .whitespaces).isEmpty : strokes.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            if let saved = pdf.signature {
                typing = saved.typed != nil
                name = saved.typed ?? ""
                strokes = saved.points
            }
        }
    }
}

private struct ProtectSheet: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var pdf: PDFModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var again = ""
    @State private var printing = true
    @State private var copying = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Protect with a password")
                .font(theme.display(20))
                .foregroundStyle(theme.ink(scheme))
            Text("Saves a copy that needs the password to open. Keep it somewhere safe; it can't be recovered.")
                .font(.system(size: 12))
                .foregroundStyle(theme.inkSecondary(scheme))
                .fixedSize(horizontal: false, vertical: true)
            SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
            SecureField("Again", text: $again).textFieldStyle(.roundedBorder)
            Toggle("Allow printing", isOn: $printing)
            Toggle("Allow copying text", isOn: $copying)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.vellumSecondary)
                    .keyboardShortcut(.cancelAction)
                Button("Save protected copy…") {
                    dismiss()
                    let chosen = password
                    DispatchQueue.main.async { pdf.protect(password: chosen, allowPrinting: printing, allowCopying: copying) }
                }
                .buttonStyle(.vellumPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty || password != again)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

private struct SplitSheet: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var pdf: PDFModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var size = 1

    var body: some View {
        let total = pdf.document?.pageCount ?? 0
        VStack(alignment: .leading, spacing: 12) {
            Text("Split into parts")
                .font(theme.display(20))
                .foregroundStyle(theme.ink(scheme))
            Stepper("Every \(size) \(size == 1 ? "page" : "pages")", value: $size, in: 1...max(1, total))
            Text("Makes \(total == 0 ? 0 : (total + size - 1) / size) files.")
                .font(.system(size: 12))
                .foregroundStyle(theme.inkTertiary(scheme))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.vellumSecondary)
                    .keyboardShortcut(.cancelAction)
                Button("Split…") {
                    dismiss()
                    let chosen = size
                    DispatchQueue.main.async { pdf.split(every: chosen) }
                }
                .buttonStyle(.vellumPrimary)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
