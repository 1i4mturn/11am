import Foundation

enum MailLane: String, CaseIterable, Identifiable, Codable, Sendable {
    case needsYou, worthReading, fyi, noise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needsYou: return "Needs you"
        case .worthReading: return "Worth reading"
        case .fyi: return "FYI"
        case .noise: return "Noise"
        }
    }

    var index: Int { MailLane.allCases.firstIndex(of: self) ?? 0 }

    /// Reads lanes saved by earlier builds too ("later" became "worth reading").
    init?(stored: String) {
        if stored == "later" {
            self = .worthReading
        } else {
            self.init(rawValue: stored)
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MailLane(stored: raw) ?? .fyi
    }
}

/// How to unsubscribe, from the List-Unsubscribe headers.
struct MailUnsubscribe: Codable, Hashable, Sendable {
    var url: URL?
    var mailto: String?
    /// RFC 8058: a single POST unsubscribes, no web page.
    var oneClick = false

    static func parse(_ header: String?, post: String?) -> MailUnsubscribe? {
        guard let header else { return nil }
        var result = MailUnsubscribe()
        for part in header.split(separator: ",") {
            let value = part.trimmingCharacters(in: CharacterSet(charactersIn: " <>\t"))
            if value.lowercased().hasPrefix("mailto:") {
                result.mailto = String(value.dropFirst(7))
            } else if value.lowercased().hasPrefix("https://"), let url = URL(string: value) {
                result.url = url
            }
        }
        result.oneClick = result.url != nil && (post?.lowercased().contains("one-click") ?? false)
        return result.url == nil && result.mailto == nil ? nil : result
    }
}

struct MailMessage: Identifiable, Hashable, Codable, Sendable {
    /// Unique across accounts: account, mailbox and UID for IMAP; a path for files.
    var id: String
    var accountID: String
    var uid: UInt32?
    var messageID = ""
    var inReplyTo: String?
    var references: String?
    var fromName: String
    var fromAddress: String
    var replyTo: String?
    var to: [String] = []
    var cc: [String] = []
    var subject: String
    var date: Date
    var body: String
    var isBulk = false
    var unsubscribe: MailUnsubscribe?
    var seen = false
    var answered = false
    var flagged = false
    var lane: MailLane = .fyi
    /// Marc's one-line reason for the lane.
    var reason = ""

    var snippet: String {
        String(body.prefix(240)).replacingOccurrences(of: "\n", with: " ")
    }

    var senderKey: String { fromAddress.lowercased() }

    var senderDomain: String {
        senderKey.split(separator: "@").last.map(String.init) ?? senderKey
    }
}

enum MailProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case icloud, gmail, fastmail, yahoo, outlook, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icloud: return "iCloud"
        case .gmail: return "Gmail or Google Workspace"
        case .fastmail: return "Fastmail"
        case .yahoo: return "Yahoo"
        case .outlook: return "Outlook or Microsoft 365"
        case .other: return "Other (IMAP)"
        }
    }

    var imapHost: String {
        switch self {
        case .icloud: return "imap.mail.me.com"
        case .gmail: return "imap.gmail.com"
        case .fastmail: return "imap.fastmail.com"
        case .yahoo: return "imap.mail.yahoo.com"
        case .outlook: return "outlook.office365.com"
        case .other: return ""
        }
    }

    var smtpHost: String {
        switch self {
        case .icloud: return "smtp.mail.me.com"
        case .gmail: return "smtp.gmail.com"
        case .fastmail: return "smtp.fastmail.com"
        case .yahoo: return "smtp.mail.yahoo.com"
        case .outlook: return "smtp.office365.com"
        case .other: return ""
        }
    }

    var smtpPort: Int { self == .icloud || self == .outlook ? 587 : 465 }

    var smtpSecurity: MailSecurity { smtpPort == 587 ? .startTLS : .tls }

    /// Gmail and Microsoft file sent mail themselves; the others need a copy appended to Sent.
    var savesSentItself: Bool { self == .gmail || self == .outlook }

    /// Microsoft switched off app passwords; those accounts need Microsoft sign-in.
    /// Microsoft switched off app passwords; these accounts sign in with Microsoft instead.
    var needsMicrosoftSignIn: Bool { self == .outlook }

    var passwordHelp: String {
        switch self {
        case .icloud: return "Use an app-specific password: account.apple.com › Sign-In and Security › App-Specific Passwords."
        case .gmail: return "Use an app password (needs 2-Step Verification): myaccount.google.com/apppasswords."
        case .fastmail: return "Use an app password: Settings › Privacy & Security › Manage app passwords, with IMAP and SMTP access."
        case .yahoo: return "Use an app password: Account Security › Generate app password."
        case .outlook: return "Sign in with Microsoft. It needs a free app registration with Microsoft, once."
        case .other: return "Your provider's IMAP and SMTP details, and an app password if it offers one."
        }
    }

    var passwordPage: URL? {
        switch self {
        case .icloud: return URL(string: "https://account.apple.com/account/manage")
        case .gmail: return URL(string: "https://myaccount.google.com/apppasswords")
        case .fastmail: return URL(string: "https://app.fastmail.com/settings/security/integrations")
        case .yahoo: return URL(string: "https://login.yahoo.com/account/security")
        case .outlook, .other: return nil
        }
    }

    /// iCloud's IMAP login is the name part of the address; everyone else uses the whole address.
    func imapUsername(for address: String) -> String {
        if self == .icloud, let name = address.split(separator: "@").first, address.lowercased().hasSuffix("@icloud.com") || address.lowercased().hasSuffix("@me.com") || address.lowercased().hasSuffix("@mac.com") {
            return String(name)
        }
        return address
    }

    static func guess(for address: String) -> MailProvider {
        let domain = address.lowercased().split(separator: "@").last.map(String.init) ?? ""
        switch domain {
        case "icloud.com", "me.com", "mac.com": return .icloud
        case "gmail.com", "googlemail.com": return .gmail
        case "fastmail.com", "fastmail.fm": return .fastmail
        case "yahoo.com", "yahoo.com.au", "ymail.com": return .yahoo
        case "outlook.com", "hotmail.com", "live.com", "msn.com", "outlook.com.au", "hotmail.com.au": return .outlook
        default: return .other
        }
    }
}

enum MailSecurity: String, Codable, Sendable {
    /// TLS from the first byte (IMAP 993, SMTP 465).
    case tls
    /// Plain, then upgraded before anything private is sent (SMTP 587).
    case startTLS
    /// Only for the protocol tests against a local fake server.
    case plainForTesting
}

struct MailAccount: Identifiable, Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// Reads, sorts, archives and sends through the provider.
        case imap
        /// Read-only, through Apple Mail's copy on this Mac.
        case appleMail
        /// Read-only, from an exported mailbox or .eml files.
        case file
        /// The built-in sample inbox.
        case sample
    }

    var id = UUID().uuidString
    var kind: Kind = .imap
    var name: String
    var address: String
    var provider: MailProvider = .other
    var imapHost = ""
    var imapPort = 993
    var imapSecurity: MailSecurity = .tls
    var imapUsername = ""
    var smtpHost = ""
    var smtpPort = 465
    var smtpSecurity: MailSecurity = .tls
    var smtpUsername = ""
    var saveSentCopy = true
    var colorIndex = 0
    var lastSync: Date?
    var historyImported = false
    /// Apple Mail's folder for this account, for `.appleMail`.
    var folderPath: String?
    /// Found on the first sync, from the server's special-use flags.
    var archiveFolder: String?
    var trashFolder: String?
    var sentFolder: String?
    var uidValidity: UInt32?
    /// Set for Outlook and Microsoft 365: signs in with Microsoft (the refresh token is in the Keychain).
    var microsoft: MicrosoftApp?

    var canSend: Bool { kind == .imap }
    var canChangeServer: Bool { kind == .imap }

    /// The account's letter in the unified inbox.
    var initial: String { String(name.prefix(1)).uppercased() }

    static func imap(provider: MailProvider, name: String, address: String) -> MailAccount {
        MailAccount(
            kind: .imap, name: name, address: address, provider: provider,
            imapHost: provider.imapHost, imapPort: 993, imapUsername: provider.imapUsername(for: address),
            smtpHost: provider.smtpHost, smtpPort: provider.smtpPort, smtpSecurity: provider.smtpSecurity,
            smtpUsername: address, saveSentCopy: !provider.savesSentItself
        )
    }

    var keychainKey: String { "mail-\(id)" }
}

/// Mail domains shared by millions of people; a domain match there says nothing about who someone is.
enum MailDomains {
    static let shared: Set<String> = [
        "gmail.com", "googlemail.com", "icloud.com", "me.com", "mac.com", "outlook.com", "hotmail.com", "live.com",
        "msn.com", "yahoo.com", "ymail.com", "yahoo.com.au", "bigpond.com", "bigpond.net.au", "optusnet.com.au",
        "proton.me", "protonmail.com", "fastmail.com", "aol.com", "gmx.com", "hey.com", "outlook.com.au", "hotmail.com.au",
    ]
}
