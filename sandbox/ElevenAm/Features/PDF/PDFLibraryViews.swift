import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Collections

/// PDFs kept together to ask across, like Acrobat's PDF Spaces: every answer cites its file and page.
struct PDFCollectionsView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var pdf: PDFModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            list
                .frame(width: 200)
            if let collection = pdf.currentCollection {
                PDFCollectionDetail(collection: collection)
            } else {
                VStack(spacing: 12) {
                    AgentLogo(code: "bn", size: 40, color: theme.inkTertiary(scheme))
                    Text("Ask across a pile of PDFs")
                        .font(theme.display(22))
                        .foregroundStyle(theme.ink(scheme))
                    Text("Put the lease, the insurance and the contracts for one job together, then ask. Bolton answers from their pages and shows you each page it used.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.inkSecondary(scheme))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    Button("New collection") { pdf.newCollection() }
                        .buttonStyle(.vellumPrimary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .vellum(level: 2, radius: max(theme.radius - 2, 8))
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SectionLabel(text: "Collections")
                Spacer()
                Button { pdf.newCollection() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("New collection")
            }
            .padding(.bottom, 4)
            ForEach(pdf.collections) { collection in
                let selected = collection.id == pdf.selectedCollection
                Button {
                    pdf.selectedCollection = collection.id
                    pdf.collectionAsk = nil
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.inkTertiary(scheme))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(collection.name)
                                .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                                .foregroundStyle(theme.ink(scheme))
                                .lineLimit(1)
                            Text("\(collection.files.count) \(collection.files.count == 1 ? "PDF" : "PDFs")")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.inkTertiary(scheme))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selected ? theme.ink(scheme).opacity(scheme == .dark ? 0.14 : 0.07) : .clear)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Delete \u{201C}\(collection.name)\u{201D}") { pdf.deleteCollection(collection.id) }
                }
            }
            if pdf.collections.isEmpty {
                Text("None yet.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
            Spacer(minLength: 0)
            Text("The PDFs stay where they are. Bolton reads their text on this Mac, and sends only the pages that answer to the brain you've chosen.")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.inkTertiary(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .vellum(level: 2, radius: max(theme.radius - 2, 8))
    }
}

private struct PDFCollectionDetail: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var pdf: PDFModel
    @EnvironmentObject private var brain: Brain
    @Environment(\.colorScheme) private var scheme
    var collection: PDFCollection
    @State private var name = ""
    @State private var question = ""
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(theme.display(20))
                    .foregroundStyle(theme.ink(scheme))
                    .onSubmit { pdf.renameCollection(collection.id, to: name) }
                Spacer(minLength: 8)
                if let url = pdf.url, !collection.files.contains(url.path) {
                    Button("Add \u{201C}\(pdf.title)\u{201D}") { pdf.addFiles([url], to: collection.id) }
                        .buttonStyle(.vellumSecondary)
                        .lineLimit(1)
                }
                Button { pdf.addFilesPanel(to: collection.id) } label: { Label("Add PDFs…", systemImage: "plus") }
                    .buttonStyle(.vellumSecondary)
            }
            files
            let blank = pdf.filesWithoutText(collection)
            if !blank.isEmpty {
                Label("No text to search in \(blank.map { PDFCollection.name(of: $0) }.joined(separator: ", ")). Open \(blank.count == 1 ? "it" : "each") and make it searchable.",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.inkSecondary(scheme))
            }
            AskField(placeholder: "Ask across these PDFs", text: $question) { pdf.askCollection(question) }
                .disabled(collection.files.isEmpty || brain.isBusy)
            if let ask = pdf.collectionAsk {
                ScrollView {
                    PDFCollectionAnswer(ask: ask)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(collection.files.isEmpty
                     ? "Drop PDFs here, or add them, then ask a question."
                     : "Try \u{201C}When does anything need renewing?\u{201D} or \u{201C}What do these say about notice?\u{201D}")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkTertiary(scheme))
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .vellum(level: 2, radius: max(theme.radius - 2, 8))
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: max(theme.radius - 2, 8), style: .continuous)
                    .strokeBorder(theme.ink(scheme).opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    }
                }
                pdf.addFiles(urls, to: collection.id)
            }
            return true
        }
        .onAppear { name = collection.name }
        .onChange(of: collection.id) { _, _ in
            name = collection.name
            question = ""
        }
        .onChange(of: collection.name) { _, value in name = value }
    }

    private var files: some View {
        FlowLayout(spacing: 6) {
            ForEach(collection.files, id: \.self) { path in
                HStack(spacing: 5) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 11))
                    Text(PDFCollection.name(of: path))
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Button { pdf.removeFile(path, from: collection.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkTertiary(scheme))
                    .help("Take it out of the collection (the file stays)")
                }
                .foregroundStyle(theme.ink(scheme))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(theme.ink(scheme).opacity(scheme == .dark ? 0.12 : 0.06)))
                .onTapGesture(count: 2) { pdf.openPassage(PDFPassage(file: path, page: 1, text: "")) }
            }
        }
    }
}

/// The answer with each [n] as a small number you can click, and the pages it used underneath.
private struct PDFCollectionAnswer: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var pdf: PDFModel
    @Environment(\.colorScheme) private var scheme
    var ask: CollectionAsk

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ask.question)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.ink(scheme))
            CitedText(run: ask.run, passages: ask.passages) { pdf.openPassage($0) }
            Sources(run: ask.run, passages: ask.passages)
        }
    }

    private struct CitedText: View {
        @EnvironmentObject private var theme: Theme
        @Environment(\.colorScheme) private var scheme
        @ObservedObject var run: BrainRun
        var passages: [PDFPassage]
        var open: (PDFPassage) -> Void

        var body: some View {
            switch run.status {
            case .failed(let message):
                Text("Bolton couldn't answer: \(message)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.inkSecondary(scheme))
            default:
                if run.text.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading \(passages.count) \(passages.count == 1 ? "passage" : "passages") from \(Set(passages.map(\.file)).count) PDFs…")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.inkTertiary(scheme))
                    }
                } else {
                    Text(attributed)
                        .font(.system(size: 13.5))
                        .lineSpacing(3)
                        .foregroundStyle(theme.ink(scheme))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .environment(\.openURL, OpenURLAction { url in
                            guard url.scheme == "bolton-cite", let number = Int(url.host ?? ""), passages.indices.contains(number - 1) else { return .systemAction }
                            open(passages[number - 1])
                            return .handled
                        })
                }
            }
        }

        private var attributed: AttributedString {
            let text = run.text
            let ns = text as NSString
            var result = AttributedString()
            var last = 0
            for marker in CollectionAnswer.markers(in: text) {
                result += AttributedString(ns.substring(with: NSRange(location: last, length: marker.range.location - last)))
                for number in marker.numbers {
                    var chip = AttributedString("\u{2009}\(number)\u{2009}")
                    chip[AttributeScopes.SwiftUIAttributes.FontAttribute.self] = Font.system(size: 10, weight: .bold).monospacedDigit()
                    chip[AttributeScopes.SwiftUIAttributes.BaselineOffsetAttribute.self] = 4
                    chip[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = Color.accentColor
                    if passages.indices.contains(number - 1) { chip.link = URL(string: "bolton-cite://\(number)") }
                    result += chip
                }
                last = marker.range.location + marker.range.length
            }
            result += AttributedString(ns.substring(from: last))
            return result
        }
    }

    private struct Sources: View {
        @EnvironmentObject private var theme: Theme
        @EnvironmentObject private var pdf: PDFModel
        @Environment(\.colorScheme) private var scheme
        @ObservedObject var run: BrainRun
        var passages: [PDFPassage]

        var body: some View {
            let cited = run.status == .done ? CollectionAnswer.cited(run.text, passages: passages) : []
            if !cited.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(text: "Pages it used")
                    ForEach(cited, id: \.self) { passage in
                        let number = (passages.firstIndex(of: passage) ?? 0) + 1
                        Button { pdf.openPassage(passage) } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(number)")
                                    .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 16, height: 16)
                                    .background(Circle().fill(Color.accentColor.opacity(0.14)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(passage.label)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(theme.ink(scheme))
                                    Text(passage.text)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(theme.inkSecondary(scheme))
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.inkTertiary(scheme))
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.ink(scheme).opacity(scheme == .dark ? 0.08 : 0.035)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Open \(passage.label)")
                    }
                    Button("Copy with sources") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(CollectionAnswer.plain(run.text, passages: passages), forType: .string)
                    }
                    .buttonStyle(.vellumSecondary)
                    .padding(.top, 2)
                }
            }
        }
    }
}

// MARK: - Pulling out

/// What Bolton read in the open PDF, with where it can go.
struct PDFPullOutView: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var pdf: PDFModel
    @Environment(\.colorScheme) private var scheme
    var card: PDFPullOutCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(heading)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.ink(scheme))
                Spacer()
                Button { pdf.pullOut = nil } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkTertiary(scheme))
            }
            switch card.kind {
            case .invoice:
                if let facts = card.invoice { invoice(facts) }
            case .contract:
                if let facts = card.contract { contract(facts) }
            case .other:
                Text("This doesn't read like an invoice or an agreement. Ask Bolton about it instead.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkSecondary(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.ink(scheme).opacity(scheme == .dark ? 0.08 : 0.04)))
    }

    private var heading: String {
        switch card.kind {
        case .invoice: return "An invoice, for George"
        case .contract: return "An agreement, for Notes"
        case .other: return "Nothing to pull out"
        }
    }

    private func row(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(theme.inkTertiary(scheme))
                .frame(width: 58, alignment: .leading)
            Text(value ?? "Not found")
                .font(.system(size: 12, weight: value == nil ? .regular : .medium))
                .foregroundStyle(value == nil ? theme.inkTertiary(scheme) : theme.ink(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func date(_ value: Date?) -> String? { value?.formatted(.dateTime.day().month(.abbreviated).year()) }

    private func invoice(_ facts: InvoiceFacts) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            row("From", facts.vendor)
            row("Invoice", facts.number)
            row("Dated", date(facts.issued))
            row("Due", date(facts.due))
            row("Total", facts.total.map { LedgerMoney.text($0) })
            row("GST", facts.gst.map { LedgerMoney.text($0) })
            if let abn = facts.abn { row("ABN", abn) }
            Button("Make a draft bill for George") { pdf.makeDraftBill() }
                .buttonStyle(.vellumPrimary)
                .disabled(facts.total == nil || pdf.ledger == nil)
                .padding(.top, 4)
            Text("It waits in Money › Bills for you to check and approve, with this PDF kept as its receipt.")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.inkTertiary(scheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func contract(_ facts: ContractFacts) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Between", facts.parties.isEmpty ? nil : facts.parties.joined(separator: " and "))
            row("Dated", date(facts.dated))
            if !facts.money.isEmpty { list("Money", facts.money) }
            if !facts.times.isEmpty { list("Time limits", facts.times) }
            Button("Save key facts to Notes") { pdf.saveKeyFacts() }
                .buttonStyle(.vellumPrimary)
                .disabled(pdf.notes == nil)
                .padding(.top, 4)
        }
    }

    private func list(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(theme.inkTertiary(scheme))
                .padding(.top, 2)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("•").foregroundStyle(theme.inkTertiary(scheme))
                    Text(item)
                        .foregroundStyle(theme.ink(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11.5))
            }
        }
    }
}

// MARK: - New PDFs

/// A web page as a PDF: the article alone, or the whole page as it looks.
struct WebPagePDFSheet: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var pdf: PDFModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var wholePage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("A web page as a PDF")
                .font(theme.display(20))
                .foregroundStyle(theme.ink(scheme))
            TextField("https://", text: $address)
                .textFieldStyle(.roundedBorder)
                .onSubmit(make)
            Picker("", selection: $wholePage) {
                Text("Just the article").tag(false)
                Text("The whole page, as it looks").tag(true)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            Text(wholePage
                 ? "Everything on the page, cut into A4 pages between lines of text. Links don't come with it."
                 : "James's reader keeps the article and drops the menus, ads and pop-ups; William sets it like a document, with where it came from under the title.")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.inkTertiary(scheme))
                .fixedSize(horizontal: false, vertical: true)
            if let making = pdf.making {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(making).font(.system(size: 12)).foregroundStyle(theme.inkSecondary(scheme))
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Make the PDF", action: make)
                    .buttonStyle(.vellumPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || pdf.making != nil)
            }
        }
        .padding(22)
        .frame(width: 440)
        .onAppear {
            if let copied = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
               copied.hasPrefix("http"), !copied.contains(" ") {
                address = copied
            }
        }
    }

    private func make() {
        guard pdf.making == nil else { return }
        pdf.makeFromWebPage(address, wholePage: wholePage)
    }
}

/// New PDFs from a web page, from PDFs and pictures, or from a William document.
struct NewPDFMenu: View {
    @EnvironmentObject private var theme: Theme
    @EnvironmentObject private var pdf: PDFModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Menu {
            Button("A web page…") { pdf.showsWebPage = true }
            Button("PDFs and pictures, combined…") { pdf.combinePanel() }
            if let documents = pdf.write?.documents, !documents.isEmpty {
                Section("A Write document") {
                    ForEach(documents.prefix(12)) { document in
                        Button(document.title) { pdf.makeFromWrite(document) }
                    }
                }
            }
        } label: {
            Label("New", systemImage: "plus")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .foregroundStyle(theme.inkSecondary(scheme))
        .help("Make a PDF from a web page, from PDFs and pictures, or from a Write document")
    }
}
