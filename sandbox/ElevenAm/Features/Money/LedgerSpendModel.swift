import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers
import Vision

// Receipts, expense claims, budgets and George's checks in the app. Receipts are copied into Money's own folder and read on
// this Mac: a PDF's text, or a photo's words recognised by macOS.

extension LedgerModel {
    var receiptsFolder: URL { JSONStore.folder.appendingPathComponent("Receipts", isDirectory: true) }

    func receiptURL(_ receipt: LedgerReceipt) -> URL? {
        receipt.file.isEmpty ? nil : receiptsFolder.appendingPathComponent(receipt.file)
    }

    // MARK: Adding receipts

    func chooseReceipts() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.pdf, .image, .plainText]
        panel.message = "Choose receipts: PDFs, photos or scans. George reads them and matches them to the bank."
        guard panel.runModal() == .OK else { return }
        addReceiptFiles(panel.urls)
    }

    /// Reads each file, keeps a copy, and matches it to its bank line when George is sure.
    func addReceiptFiles(_ urls: [URL], toLine line: UUID? = nil) {
        let files = urls.filter { !$0.hasDirectoryPath }
        guard !files.isEmpty else { return }
        notice = files.count == 1 ? "Reading \(files[0].lastPathComponent)…" : "Reading \(files.count) receipts…"
        Task { @MainActor [weak self] in
            guard let self else { return }
            var added = 0, matched = 0, unread: [String] = []
            for url in files {
                let text = await Self.text(of: url)
                let reading = ReceiptReader.read(text, calendar: self.book.calendar)
                guard let stored = self.store(url) else {
                    unread.append(url.lastPathComponent)
                    continue
                }
                let fallbackDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                var receipt = LedgerReceipt(file: stored, vendor: reading.vendor ?? url.deletingPathExtension().lastPathComponent,
                                            date: reading.date ?? fallbackDate, total: reading.total ?? 0, gst: reading.gst)
                receipt.abn = reading.abn ?? ""
                receipt.bankLine = line
                if reading.total == nil { unread.append(url.lastPathComponent) }
                var id: UUID?
                self.change { id = $0.addReceipt(receipt) }
                added += 1
                if let id, self.book.receipt(id)?.bankLine != nil { matched += 1 }
            }
            var parts: [String] = []
            if added > 0 { parts.append("Kept \(added) \(added == 1 ? "receipt" : "receipts")\(matched > 0 ? ", \(matched) matched to the bank" : "").") }
            if !unread.isEmpty { parts.append("Couldn't read a total from \(unread.joined(separator: ", ")); type it in.") }
            self.notice = parts.joined(separator: " ")
            self.tab = .spend
        }
    }

    /// Copies a file into the receipts folder under a name of its own.
    private func store(_ url: URL) -> String? {
        try? FileManager.default.createDirectory(at: receiptsFolder, withIntermediateDirectories: true)
        let name = UUID().uuidString + (url.pathExtension.isEmpty ? "" : "." + url.pathExtension.lowercased())
        do {
            try FileManager.default.copyItem(at: url, to: receiptsFolder.appendingPathComponent(name))
            return name
        } catch {
            return nil
        }
    }

    /// A PDF's own text (or its pages recognised, if it's a scan), a photo's recognised text, or a text file.
    static func text(of url: URL) async -> String {
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        if type?.conforms(to: .pdf) == true, let document = PDFDocument(url: url) {
            let text = document.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 { return text }
            var pages: [String] = []
            for index in 0..<min(document.pageCount, 3) {
                guard let page = document.page(at: index) else { continue }
                let image = page.thumbnail(of: CGSize(width: 1_700, height: 2_200), for: .mediaBox)
                if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) { pages.append(await recognise(cg)) }
            }
            return pages.joined(separator: "\n")
        }
        if type?.conforms(to: .image) == true, let image = NSImage(contentsOf: url), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return await recognise(cg)
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Words in an image, read on this Mac, top to bottom.
    nonisolated static func recognise(_ image: CGImage) async -> String {
        await Task.detached(priority: .userInitiated) { () -> String in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-AU", "en-US"]
            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
            } catch {
                return ""
            }
            let lines = (request.results ?? [])
                .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
                .compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
    }

    /// Marc found a receipt in your mail: kept with its email text, and matched when the payment's in the bank.
    func addMailReceipt(vendor: String, total: Cents, date: Date, subject: String, body: String) {
        try? FileManager.default.createDirectory(at: receiptsFolder, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".txt"
        try? "\(subject)\n\n\(body)".write(to: receiptsFolder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        let reading = ReceiptReader.read(body, calendar: book.calendar)
        var receipt = LedgerReceipt(file: name, vendor: vendor, date: date, total: total, gst: reading.gst, source: .mail)
        receipt.abn = reading.abn ?? ""
        var id: UUID?
        change { id = $0.addReceipt(receipt) }
        tab = .spend
        let line = id.flatMap { book.receipt($0)?.bankLine }.flatMap { lineID in book.bank.first { $0.id == lineID } }
        notice = line.map { "Kept the receipt from \(vendor) and matched it to the bank line on \($0.date.formatted(.dateTime.day().month(.abbreviated)))." }
            ?? "Kept the receipt from \(vendor) for \(LedgerMoney.text(total)). George matches it when the payment shows up in the bank."
    }

    // MARK: Changing receipts

    func updateReceipt(_ receipt: LedgerReceipt) {
        change { book in
            if let index = book.receipts.firstIndex(where: { $0.id == receipt.id }) { book.receipts[index] = receipt }
        }
    }

    func attachReceipt(_ id: UUID, to line: UUID) { change { $0.attachReceipt(id, toLine: line) } }

    func detachReceipt(_ id: UUID) { change { $0.detachReceipt(id) } }

    func deleteReceipt(_ id: UUID) {
        if let receipt = book.receipt(id), let url = receiptURL(receipt) { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        change { $0.deleteReceipt(id) }
    }

    func matchReceipts() {
        var count = 0
        change { count = $0.matchReceipts() }
        notice = count == 0 ? "Nothing more George is sure of. Match the rest by hand." : "Matched \(count) \(count == 1 ? "receipt" : "receipts")."
    }

    func openReceipt(_ receipt: LedgerReceipt) {
        guard let url = receiptURL(receipt), FileManager.default.fileExists(atPath: url.path) else {
            notice = "There's no file kept for that receipt."
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// "I have it": a receipt for a purchase that needs one, attached to that bank line.
    func addReceipt(for line: BankLine) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .image, .plainText]
        panel.message = "Choose the receipt for \(line.description) (\(LedgerMoney.text(-line.amount)))."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addReceiptFiles([url], toLine: line.id)
    }

    // MARK: Expense claims

    /// Who claims: you, by your Mac's name, or whoever claimed last time.
    var claimant: UUID {
        if let last = book.claims.first, book.contact(last.contact) != nil { return last.contact }
        let name = NSFullUserName().isEmpty ? "You" : NSFullUserName()
        if let found = book.contacts.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return found.id }
        return addContact(named: name)
    }

    /// Unmatched receipts you paid for yourself, onto a claim to be paid back.
    func claim(_ receiptIDs: [UUID]) {
        let chosen = receiptIDs.compactMap { book.receipt($0) }.filter { !$0.isMatched && $0.total > 0 }
        guard !chosen.isEmpty else {
            notice = "Pick receipts that aren't matched yet."
            return
        }
        let person = claimant
        let items = chosen.map { receipt in
            let rule = book.rules[LedgerBook.payeeKey(receipt.vendor)]
            return ClaimItem(description: receipt.vendor, total: receipt.total, account: rule?.account ?? "429", gst: rule?.gst ?? .gst,
                             date: receipt.date, receipt: receipt.id)
        }
        var made: UUID?
        let date = today
        change { made = try $0.makeClaim(items, by: person, date: date) }
        guard let made, let claim = book.invoice(made) else { return }
        notice = "\(claim.number) for \(LedgerMoney.text(claim.total)) is in Bills, owed to \(book.contact(person)?.name ?? "you"). Pay it back like any bill."
    }

    // MARK: Budgets

    func setBudget(_ code: String, monthly: Cents) {
        change { $0.setBudget(code, monthly: monthly) }
    }

    /// A first budget from the last year's figures.
    func startBudgetsFromLastYear() {
        let suggested = book.suggestedBudgets(before: today)
        guard !suggested.isEmpty else {
            notice = "There isn't a year of figures to start from yet. Type the monthly amounts in."
            return
        }
        change { book in
            for (code, monthly) in suggested where book.budgets[code] == nil { book.setBudget(code, monthly: monthly) }
        }
        notice = "Budgets started from the last year's monthly averages. Change any you like."
    }

    /// Receipts, claims, budgets and checks, for George's answers.
    var moneyOutFacts: String {
        let yearStart = book.financialYearStart(for: today)
        let missing = book.missingReceipts(from: yearStart, to: today)
        let unmatched = book.receipts.filter { !$0.isMatched }.count
        var lines = ["Receipts kept: \(book.receipts.count), \(unmatched) not matched to the bank yet."]
        if !missing.isEmpty {
            lines.append("\(missing.count) purchases over $82.50 have no tax invoice kept, with \(LedgerMoney.text(book.gstWaitingOnReceipts(from: yearStart, to: today))) of GST credits claimed on them this financial year.")
        }
        if book.owedOnClaims > 0 { lines.append("Owed to you on expense claims: \(LedgerMoney.text(book.owedOnClaims)).") }
        let rows = book.budgetReport(from: yearStart, to: today).filter { $0.budget != 0 }
        let worst = rows.filter { $0.variance < 0 }.sorted { $0.variance < $1.variance }.prefix(3)
        if !worst.isEmpty {
            lines.append("Furthest over budget this year: " + worst.map { "\($0.account.name) by \(LedgerMoney.text(-$0.variance))" }.joined(separator: ", ") + ".")
        }
        let found = checks
        if !found.isEmpty { lines.append("George's checks: " + found.map(\.title).joined(separator: "; ") + ".") }
        return lines.joined(separator: "\n")
    }

    // MARK: George's checks

    var checks: [LedgerCheck] { book.checks(on: today) }

    func dismiss(_ check: LedgerCheck) {
        change { $0.dismissCheck(check.id) }
    }

    /// Goes to what a check is about.
    func open(_ check: LedgerCheck) {
        switch check.kind {
        case .duplicateBill:
            tab = .bills
            selectedInvoice = check.reference
        case .unusualAmount, .staleBankLines:
            if let line = book.bank.first(where: { $0.id == check.reference }) { bankAccount = line.account }
            tab = .bank
        case .gstOnWages:
            tab = .bank
        case .missingReceipts:
            tab = .spend
        }
    }
}
