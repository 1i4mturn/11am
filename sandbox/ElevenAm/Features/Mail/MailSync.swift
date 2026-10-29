import Foundation

extension MailMessage {
    init(parsed: ParsedMail, id: String, accountID: String) {
        let headers = parsed.headers
        let from = MailParser.address(headers["from"] ?? "Unknown sender")
        let precedence = headers["precedence"]?.lowercased() ?? ""
        let automatic = headers["auto-submitted"]?.lowercased() ?? "no"
        self.init(
            id: id,
            accountID: accountID,
            fromName: from.name,
            fromAddress: from.address,
            subject: MailParser.decodeWords(headers["subject"] ?? "(no subject)"),
            date: MailParser.date(headers["date"]) ?? .distantPast,
            body: String(parsed.body.prefix(20_000))
        )
        messageID = headers["message-id"]?.trimmingCharacters(in: .whitespaces) ?? ""
        inReplyTo = headers["in-reply-to"]?.trimmingCharacters(in: .whitespaces)
        references = headers["references"]?.trimmingCharacters(in: .whitespaces)
        replyTo = headers["reply-to"].map { MailParser.address($0).address }
        to = MailParser.addresses(headers["to"])
        cc = MailParser.addresses(headers["cc"])
        isBulk = headers["list-unsubscribe"] != nil || headers["list-id"] != nil
            || precedence.contains("bulk") || precedence.contains("list") || automatic.hasPrefix("auto-")
        unsubscribe = MailUnsubscribe.parse(headers["list-unsubscribe"], post: headers["list-unsubscribe-post"])
    }
}

enum MailAction: Sendable {
    case seen(Bool)
    case flagged(Bool)
    case answered
    case archive
    case delete
}

/// Everything that talks to an IMAP account: sync the inbox, read past flags on day one, carry out actions, send.
enum MailSync {
    struct Inbox: Sendable {
        var messages: [MailMessage]
        var uidValidity: UInt32
        var folders: IMAPSpecialFolders
    }

    static let headerFields = "FROM TO CC REPLY-TO SUBJECT DATE MESSAGE-ID IN-REPLY-TO REFERENCES LIST-ID LIST-UNSUBSCRIBE LIST-UNSUBSCRIBE-POST PRECEDENCE AUTO-SUBMITTED"

    /// Signs in. iCloud accepts the name part or the whole address, depending on the account; try both.
    static func connect(_ account: MailAccount, password: String) async throws -> IMAPClient {
        let client = IMAPClient(host: account.imapHost, port: account.imapPort, security: account.imapSecurity)
        do {
            try await client.login(username: account.imapUsername, password: password)
        } catch {
            guard account.provider == .icloud, account.imapUsername != account.address else {
                await client.logout()
                throw error
            }
            do {
                try await client.login(username: account.address, password: password)
            } catch {
                await client.logout()
                throw error
            }
        }
        return client
    }

    /// Checks the details work, and finds the folders that matter.
    static func test(_ account: MailAccount, password: String) async throws -> IMAPSpecialFolders {
        let client = try await connect(account, password: password)
        do {
            let folders = IMAPSpecialFolders(try await client.folders())
            await client.logout()
            return folders
        } catch {
            await client.logout()
            throw error
        }
    }

    /// The last few weeks of the inbox: headers and flags for all of it, the full text for the newest.
    /// `haveBodies` are UIDs already cached with their text, so they aren't downloaded again.
    static func inbox(_ account: MailAccount, password: String, haveBodies: Set<UInt32>, days: Int = 30) async throws -> Inbox {
        let client = try await connect(account, password: password)
        do {
            let folders = IMAPSpecialFolders(try await client.folders())
            let selected = try await client.select("INBOX")
            let since = IMAPClient.searchDate(Date().addingTimeInterval(-Double(days) * 86_400))
            let uids = Array(try await client.search("SINCE \(since)").suffix(300))
            let sameMailbox = account.uidValidity == selected.uidValidity

            var headers: [UInt32: IMAPClient.Fetched] = [:]
            for chunk in uids.chunks(of: 150) {
                for item in try await client.fetch(chunk, items: "(UID FLAGS INTERNALDATE BODY.PEEK[HEADER.FIELDS (\(headerFields))])") {
                    headers[item.uid] = item
                }
            }
            let wanted = uids.suffix(120).filter { !(sameMailbox && haveBodies.contains($0)) }
            var bodies: [UInt32: Data] = [:]
            for chunk in Array(wanted).chunks(of: 20) {
                for item in try await client.fetch(chunk, items: "(UID BODY.PEEK[]<0.49152>)") {
                    if let body = item.body { bodies[item.uid] = body }
                }
            }
            await client.logout()

            let messages = uids.reversed().compactMap { uid -> MailMessage? in
                guard let item = headers[uid] else { return nil }
                return MailSync.message(from: item, body: bodies[uid], account: account, validity: selected.uidValidity)
            }
            return Inbox(messages: messages, uidValidity: selected.uidValidity, folders: folders)
        } catch {
            await client.logout()
            throw error
        }
    }

    static func message(from item: IMAPClient.Fetched, body: Data?, account: MailAccount, validity: UInt32) -> MailMessage {
        let raw = body ?? item.header ?? Data()
        var message = MailMessage(parsed: MailParser.parse(String(decoding: raw, as: UTF8.self)), id: "\(account.id):\(validity):\(item.uid)", accountID: account.id)
        if body == nil { message.body = "" }
        message.uid = item.uid
        message.seen = item.flags.contains("\\seen")
        message.answered = item.flags.contains("\\answered")
        message.flagged = item.flags.contains("\\flagged")
        if message.date == .distantPast, let date = item.internalDate { message.date = date }
        return message
    }

    /// Day one: what you've already done with six months of mail (opened, answered, flagged, left unread),
    /// and who you write to, from the Sent folder. Only headers and flags are read.
    static func history(_ account: MailAccount, password: String, myAddresses: Set<String>, skipping recent: Set<String>) async throws -> (records: [MailRecord], sentTo: [String: Int]) {
        let client = try await connect(account, password: password)
        do {
            let folders = IMAPSpecialFolders(try await client.folders())
            let since = IMAPClient.searchDate(Date().addingTimeInterval(-180 * 86_400))
            var seenIDs = recent
            var records: [MailRecord] = []
            let mailboxes = ["INBOX", account.provider == .gmail ? folders.all : folders.archive].compactMap { $0 }
            for mailbox in mailboxes {
                guard (try? await client.select(mailbox, readOnly: true)) != nil else { continue }
                let uids = Array(try await client.search("SINCE \(since)").suffix(1_500))
                for chunk in uids.chunks(of: 250) {
                    for item in try await client.fetch(chunk, items: "(UID FLAGS INTERNALDATE BODY.PEEK[HEADER.FIELDS (\(headerFields))])") {
                        let mail = MailSync.message(from: item, body: nil, account: account, validity: 0)
                        let key = mail.messageID.isEmpty ? "\(mailbox):\(item.uid)" : mail.messageID
                        guard !seenIDs.contains(key), !myAddresses.contains(mail.senderKey) else { continue }
                        seenIDs.insert(key)
                        var record = MailRecord(message: mail, traits: MailTriage.traits(of: mail, myAddresses: myAddresses))
                        record.id = "history:\(account.id):\(key)"
                        record.fromHistory = true
                        record.opened = mail.seen
                        record.replied = mail.answered
                        record.flagged = mail.flagged
                        record.ignored = !mail.seen && mail.date < Date().addingTimeInterval(-3 * 86_400)
                        records.append(record)
                    }
                }
            }
            var sentTo: [String: Int] = [:]
            if let sent = folders.sent, (try? await client.select(sent, readOnly: true)) != nil {
                let uids = Array(try await client.search("SINCE \(since)").suffix(1_000))
                for chunk in uids.chunks(of: 250) {
                    for item in try await client.fetch(chunk, items: "(UID BODY.PEEK[HEADER.FIELDS (TO CC)])") {
                        let headers = MailParser.parse(String(decoding: item.header ?? Data(), as: UTF8.self)).headers
                        for address in MailParser.addresses(headers["to"]) + MailParser.addresses(headers["cc"]) where !myAddresses.contains(address) {
                            sentTo[address, default: 0] += 1
                        }
                    }
                }
            }
            await client.logout()
            return (records, sentTo)
        } catch {
            await client.logout()
            throw error
        }
    }

    /// Archive, delete, read, flag or mark answered, on the server. Refuses if the inbox was rebuilt since the UIDs were read.
    static func perform(_ action: MailAction, uids: [UInt32], validity: UInt32, account: MailAccount, password: String) async throws {
        let client = try await connect(account, password: password)
        do {
            let selected = try await client.select("INBOX")
            guard selected.uidValidity == validity else {
                throw MailError("The inbox changed on the server. Sync, then try again.")
            }
            switch action {
            case .seen(let on): try await client.store(uids, flags: ["\\Seen"], add: on)
            case .flagged(let on): try await client.store(uids, flags: ["\\Flagged"], add: on)
            case .answered: try await client.store(uids, flags: ["\\Answered"], add: true)
            case .archive:
                guard let target = account.archiveFolder else { throw MailError("\(account.name) has no Archive folder.") }
                try await client.move(uids, to: target)
            case .delete:
                guard let trash = account.trashFolder else { throw MailError("\(account.name) has no Trash folder.") }
                try await client.move(uids, to: trash)
            }
            await client.logout()
        } catch {
            await client.logout()
            throw error
        }
    }

    /// Sends, files a copy in Sent where the provider doesn't, and marks the original as answered.
    static func send(_ mail: OutgoingMail, account: MailAccount, password: String, original: (uid: UInt32, validity: UInt32)?) async throws {
        try await SMTPClient.send(mail, host: account.smtpHost, port: account.smtpPort, security: account.smtpSecurity,
                                  username: account.smtpUsername.isEmpty ? account.address : account.smtpUsername, password: password)
        guard (account.saveSentCopy && account.sentFolder != nil) || original != nil,
              let client = try? await connect(account, password: password) else { return }
        if account.saveSentCopy, let sent = account.sentFolder {
            try? await client.append(mail.rfc5322(), to: sent, flags: ["\\Seen"])
        }
        if let original, let selected = try? await client.select("INBOX"), selected.uidValidity == original.validity {
            try? await client.store([original.uid], flags: ["\\Answered"], add: true)
        }
        await client.logout()
    }

    /// RFC 8058 one-click unsubscribe: a single POST, no web page, no tracking.
    static func oneClickUnsubscribe(_ url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("List-Unsubscribe=One-Click".utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            throw MailError("The sender's unsubscribe page answered \(http.statusCode).")
        }
    }
}

extension Array {
    func chunks(of size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
