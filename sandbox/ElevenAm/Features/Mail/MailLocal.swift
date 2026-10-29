import Foundation

enum MailLoadError: Error, Equatable {
    case noAccess, notFound, empty

    var message: String {
        switch self {
        case .noAccess:
            return "11am needs Full Disk Access to read Apple Mail's local copy of your mail. Turn it on in System Settings › Privacy & Security › Full Disk Access, then try again. Nothing leaves your Mac."
        case .notFound:
            return "Apple Mail hasn't downloaded any mail on this Mac yet. Add an account in Mail, or open an exported mailbox file instead."
        case .empty:
            return "No messages could be read from that. Try a .mbox exported from Mail (Mailbox › Export Mailbox…) or some .eml files."
        }
    }
}

/// Mail already on this Mac: each Apple Mail account (including Outlook and Microsoft 365, which Apple Mail signs in to),
/// or exported files. Read-only, no logins, nothing uploaded.
enum MailLocal {
    struct Loaded: Sendable {
        var account: MailAccount
        var messages: [MailMessage]
        /// Older mail, as flags only, for Marc's day-one learning.
        var history: [MailRecord]
    }

    static func appleMail(recent: Int = 200, older: Int = 1_500) -> Result<[Loaded], MailLoadError> {
        let fileManager = FileManager.default
        let root = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mail")
        let versions: [URL]
        do {
            versions = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("V") }
        } catch {
            // ~/Library/Mail is protected: without Full Disk Access the listing fails.
            return .failure(fileManager.fileExists(atPath: root.path) ? .noAccess : .notFound)
        }
        guard let store = versions.max(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
        else { return .failure(.notFound) }

        let folders = ((try? fileManager.contentsOfDirectory(at: store, includingPropertiesForKeys: nil)) ?? [])
            .filter { fileManager.fileExists(atPath: $0.appendingPathComponent("INBOX.mbox").path) }
        var loaded: [Loaded] = []
        for (index, folder) in folders.enumerated() {
            let files = emlxFiles(in: folder.appendingPathComponent("INBOX.mbox"))
            guard !files.isEmpty else { continue }
            var account = MailAccount(kind: .appleMail, name: "Apple Mail", address: "")
            account.id = "applemail-\(folder.lastPathComponent)"
            account.folderPath = folder.path
            account.colorIndex = index

            var messages: [MailMessage] = []
            var recipients: [String: Int] = [:]
            for url in files.prefix(recent) {
                guard let data = try? Data(contentsOf: url), let parsed = MailParser.parseEmlx(data) else { continue }
                var message = MailMessage(parsed: parsed, id: url.path, accountID: account.id)
                if let flags = MailParser.emlxFlags(data) {
                    message.seen = flags.read
                    message.answered = flags.answered
                    message.flagged = flags.flagged
                }
                for address in message.to { recipients[address, default: 0] += 1 }
                messages.append(message)
            }
            // The address this account receives at is the one most of its mail goes to.
            account.address = recipients.max { $0.value < $1.value }?.key ?? ""
            account.provider = MailProvider.guess(for: account.address)
            account.name = name(for: account)
            let mine: Set<String> = account.address.isEmpty ? [] : [account.address]

            var history: [MailRecord] = []
            let cutoff = Date().addingTimeInterval(-180 * 86_400)
            for url in files.dropFirst(recent).prefix(older) {
                guard let data = try? Data(contentsOf: url), let flags = MailParser.emlxFlags(data),
                      let parsed = MailParser.parseEmlx(data, headersOnly: true) else { continue }
                let message = MailMessage(parsed: parsed, id: url.path, accountID: account.id)
                guard message.date > cutoff, !mine.contains(message.senderKey) else { continue }
                var record = MailRecord(message: message, traits: MailTriage.traits(of: message, myAddresses: mine))
                record.id = "history:\(url.path)"
                record.fromHistory = true
                record.opened = flags.read
                record.replied = flags.answered
                record.flagged = flags.flagged
                record.ignored = !flags.read && message.date < Date().addingTimeInterval(-3 * 86_400)
                history.append(record)
            }
            loaded.append(Loaded(account: account, messages: messages, history: history))
        }
        return loaded.isEmpty ? .failure(.notFound) : .success(loaded)
    }

    private static func emlxFiles(in inbox: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let walker = fileManager.enumerator(at: inbox, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return [] }
        var found: [(url: URL, date: Date)] = []
        for case let url as URL in walker where url.pathExtension == "emlx" {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            found.append((url, date))
        }
        return found.sorted { $0.date > $1.date }.map(\.url)
    }

    private static func name(for account: MailAccount) -> String {
        switch account.provider {
        case .icloud: return "iCloud"
        case .gmail: return "Gmail"
        case .outlook: return "Outlook"
        case .yahoo: return "Yahoo"
        case .fastmail: return "Fastmail"
        case .other:
            let domain = account.address.split(separator: "@").last.map(String.init) ?? "Mail"
            return domain.split(separator: ".").first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? domain
        }
    }

    static func files(_ urls: [URL], limit: Int = 300) -> Result<Loaded, MailLoadError> {
        var account = MailAccount(kind: .file, name: "Mailbox file", address: "")
        account.id = "file"
        var list: [MailMessage] = []
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if ext == "eml" || ext == "emlx" {
                guard let data = try? Data(contentsOf: url) else { continue }
                let parsed = ext == "emlx" ? MailParser.parseEmlx(data) : MailParser.parse(String(decoding: data, as: UTF8.self))
                if let parsed { list.append(MailMessage(parsed: parsed, id: url.path, accountID: account.id)) }
                continue
            }
            // Mail exports a mailbox as a folder (Inbox.mbox) holding a file called "mbox".
            var isFolder: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
            let file = isFolder.boolValue ? url.appendingPathComponent("mbox") : url
            guard let text = readTail(of: file, maxBytes: 40_000_000) else { continue }
            for (index, parsed) in MailParser.messages(inMbox: text, limit: limit).enumerated() {
                list.append(MailMessage(parsed: parsed, id: "\(url.path)#\(index)", accountID: account.id))
            }
        }
        guard !list.isEmpty else { return .failure(.empty) }
        var recipients: [String: Int] = [:]
        for message in list { for address in message.to { recipients[address, default: 0] += 1 } }
        account.address = recipients.max { $0.value < $1.value }?.key ?? ""
        return .success(Loaded(account: account, messages: Array(list.sorted { $0.date > $1.date }.prefix(limit)), history: []))
    }

    /// Reads at most the last `maxBytes` of a file, so a huge mailbox never fills an 8 GB Mac's memory.
    private static func readTail(of url: URL, maxBytes: UInt64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > maxBytes ? size - maxBytes : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        // Starting mid-file: skip ahead to the first whole message.
        if start > 0, let boundary = text.range(of: "\nFrom ") {
            return String(text[text.index(after: boundary.lowerBound)...])
        }
        return text
    }
}
